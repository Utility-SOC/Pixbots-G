use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};
use pixbots_core::broadphase::{self, Index, Shot, Target};

type VDict = Dictionary<Variant, Variant>;

// Ports Projectile.gd's per-tick hit detection off Godot's own Area2D
// broadphase (one live physics-server body per projectile, tracked/updated
// every tick regardless of whether anything's actually nearby) into a single
// batched Rust call - see ProjectileManager.gd's own header, which already
// flagged this as the planned "Phase 3" follow-up to the flight-math port in
// projectile_flight.rs. This module does ONLY hit detection: it returns
// (projectile, target) overlap pairs, nothing else. Everything about what a
// hit actually DOES (damage, status effects, pierce, lightning re-target,
// poison-mine detonation) stays in Projectile._handle_hit(), completely
// unchanged - this is purely "who touched whom this tick," same division of
// labor as ProjectileFlight is purely "where does this projectile go."
//
// Dedup (a projectile shouldn't re-hit the same target every tick it stays
// overlapping) is NOT this module's job either - Projectile.gd's existing
// _handled_targets dict already owns that, same as it does for the old
// Area2D signal path. This just reports raw overlaps every tick.
//
// Grid-bucket spatial hash (2026-08-03 - real playtest evidence, not a
// guess: a 34-enemy/495-live-shot stress video showed collision pairs
// staying near zero, confirming the OLD flat O(n_projectiles x n_targets)
// double loop, not resolution, was the real cost at that volume). Same
// HashMap<(i64,i64), Vec<usize>> idiom hexgrid_sim.rs already uses for its
// fixed hex grid, adapted to coarse continuous-space cells: targets are
// bucketed by position once per call, and each projectile only tests
// candidates from the cells its swept segment's bounding box (expanded by
// radius) actually overlaps, instead of every live target. Correctness
// verified against the flat-loop GDScript fallback via
// ProjectileBroadphaseParityCheck.gd (unchanged - the spatial hash is an
// implementation detail behind the same query_hits signature and result
// contract, not a behavior change).

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ProjectileBroadphaseRs {
    base: Base<RefCounted>,
    // Obstacles never move, so they are bucketed once (set_static_targets) and reused by every query_hits_packed call
    // instead of being re-marshalled and re-bucketed every physics tick.
    statics: Index,
}

#[godot_api]
impl IRefCounted for ProjectileBroadphaseRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base, statics: Index::default() }
    }
}

fn get_f(d: &VDict, k: &str) -> f64 {
    d.get(k).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0)
}

fn get_i(d: &VDict, k: &str) -> i64 {
    d.get(k).and_then(|v| v.try_to::<i64>().ok()).unwrap_or(0)
}

fn get_vec2(d: &VDict, k: &str) -> (f32, f32) {
    let v: Vector2 = d.get(k).and_then(|v| v.try_to().ok()).unwrap_or(Vector2::ZERO);
    (v.x, v.y)
}

#[godot_api]
impl ProjectileBroadphaseRs {
    // `targets`: one Dictionary per live hit-target this tick - id, pos (Vector2), radius, layer (collision_layer bits).
    // `projectiles`: one per projectile that moved - id, prev, curr (Vector2), radius, mask (collision_mask bits).
    // Returns {"projectile_id", "target_id"} pair Dictionaries, one per overlap. The maths is pixbots_core::broadphase.
    #[func]
    fn query_hits(&self, targets: Array<Variant>, projectiles: Array<Variant>) -> Array<Variant> {
        let targets: Vec<Target> = targets
            .iter_shared()
            .filter_map(|v| {
                let d: VDict = v.try_to().ok()?;
                Some(Target { id: get_i(&d, "id"), pos: get_vec2(&d, "pos"), radius: get_f(&d, "radius"), layer: get_i(&d, "layer") })
            })
            .collect();
        let shots: Vec<Shot> = projectiles
            .iter_shared()
            .filter_map(|v| {
                let d: VDict = v.try_to().ok()?;
                Some(Shot { id: get_i(&d, "id"), prev: get_vec2(&d, "prev"), curr: get_vec2(&d, "curr"), radius: get_f(&d, "radius"), mask: get_i(&d, "mask") })
            })
            .collect();
        let mut results: Array<Variant> = Array::new();
        for (pid, tid) in broadphase::query(&Index::default(), &Index::new(targets), &shots) {
            let mut pair = VDict::new();
            pair.set("projectile_id", pid);
            pair.set("target_id", tid);
            results.push(&pair.to_variant());
        }
        results
    }

    #[func]
    fn set_static_targets(&mut self, ids: PackedInt64Array, pos: PackedVector2Array, radii: PackedFloat64Array, layers: PackedInt64Array) {
        let (ids, pos, radii, layers) = (ids.as_slice(), pos.as_slice(), radii.as_slice(), layers.as_slice());
        let n = ids.len().min(pos.len()).min(radii.len()).min(layers.len());
        let targets = (0..n).map(|i| Target { id: ids[i], pos: (pos[i].x, pos[i].y), radius: radii[i], layer: layers[i] }).collect();
        self.statics = Index::new(targets);
    }

    // Same hit test as query_hits, but dynamic targets and projectiles come in as parallel packed arrays and the retained
    // static targets are included automatically. Returns flat [projectile_id, target_id, ...].
    #[func]
    fn query_hits_packed(
        &self,
        t_ids: PackedInt64Array,
        t_pos: PackedVector2Array,
        t_radii: PackedFloat64Array,
        t_layers: PackedInt64Array,
        p_ids: PackedInt64Array,
        p_prev: PackedVector2Array,
        p_curr: PackedVector2Array,
        p_radii: PackedFloat64Array,
        p_masks: PackedInt64Array,
    ) -> PackedInt64Array {
        let (t_ids, t_pos, t_radii, t_layers) = (t_ids.as_slice(), t_pos.as_slice(), t_radii.as_slice(), t_layers.as_slice());
        let tn = t_ids.len().min(t_pos.len()).min(t_radii.len()).min(t_layers.len());
        let dynamic = Index::new((0..tn).map(|i| Target { id: t_ids[i], pos: (t_pos[i].x, t_pos[i].y), radius: t_radii[i], layer: t_layers[i] }).collect());
        let (p_ids, p_prev, p_curr, p_radii, p_masks) =
            (p_ids.as_slice(), p_prev.as_slice(), p_curr.as_slice(), p_radii.as_slice(), p_masks.as_slice());
        let pn = p_ids.len().min(p_prev.len()).min(p_curr.len()).min(p_radii.len()).min(p_masks.len());
        let shots: Vec<Shot> = (0..pn)
            .map(|j| Shot { id: p_ids[j], prev: (p_prev[j].x, p_prev[j].y), curr: (p_curr[j].x, p_curr[j].y), radius: p_radii[j], mask: p_masks[j] })
            .collect();
        let mut out: Vec<i64> = Vec::new();
        for (pid, tid) in broadphase::query(&self.statics, &dynamic, &shots) {
            out.push(pid);
            out.push(tid);
        }
        PackedInt64Array::from(out.as_slice())
    }
}

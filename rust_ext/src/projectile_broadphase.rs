use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};
use std::collections::HashMap;

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
    // Obstacles never move, so they are bucketed once (set_static_targets)
    // and reused by every query_hits_packed call instead of being
    // re-marshalled and re-bucketed every physics tick.
    static_targets: Vec<Target>,
    static_buckets: HashMap<(i64, i64), Vec<usize>>,
    static_max_radius: f64,
}

#[godot_api]
impl IRefCounted for ProjectileBroadphaseRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            static_targets: Vec::new(),
            static_buckets: HashMap::new(),
            static_max_radius: 0.0,
        }
    }
}

fn get_f(d: &VDict, k: &str) -> f64 {
    d.get(k).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0)
}

fn get_i(d: &VDict, k: &str) -> i64 {
    d.get(k).and_then(|v| v.try_to::<i64>().ok()).unwrap_or(0)
}

fn get_vec2(d: &VDict, k: &str) -> Vector2 {
    d.get(k).and_then(|v| v.try_to().ok()).unwrap_or(Vector2::ZERO)
}

struct Target {
    id: i64,
    pos: Vector2,
    radius: f64,
    layer: i64,
}

struct Projectile {
    id: i64,
    prev: Vector2,
    curr: Vector2,
    radius: f64,
    mask: i64,
}

// Bucket cell size in world pixels - large enough that most cells hold a
// handful of targets rather than dozens (keeping per-cell test cost low),
// small enough that a projectile's expanded bounding box doesn't sweep in
// huge swaths of empty cells for a normal-speed shot. Tuned against this
// game's actual scale (PartHitbox/obstacle radii in the tens of pixels,
// play areas in the thousands) - not a hard physical constant, fine to
// retune later if profiling on a real wave suggests a better value.
const CELL_SIZE: f64 = 150.0;

fn cell_of(pos: Vector2) -> (i64, i64) {
    cell_of_f64(pos.x as f64, pos.y as f64)
}

fn cell_of_f64(x: f64, y: f64) -> (i64, i64) {
    ((x / CELL_SIZE).floor() as i64, (y / CELL_SIZE).floor() as i64)
}

// Closest distance from `point` to the segment [a, b] - the same swept-shape
// idea Projectile.gd's old _sweep_for_tunneled_hits used (a moving rectangle
// approximated here as a moving circle, consistent with the existing
// rectangle-approximates-the-sprite precision level already accepted
// elsewhere in this codebase's hit detection).
fn point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> f64 {
    let ab = b - a;
    let len_sq = ab.length_squared() as f64;
    if len_sq <= 1e-9 {
        return (point - a).length() as f64;
    }
    let t = (((point - a).dot(ab)) as f64 / len_sq).clamp(0.0, 1.0);
    let closest = a + ab * (t as f32);
    (point - closest).length() as f64
}

#[godot_api]
impl ProjectileBroadphaseRs {
    // `targets`: one Dictionary per live hit-target (PartHitbox part or
    // obstacle/husk) this tick - keys: id (i64), pos (Vector2), radius
    // (f64), layer (i64, collision_layer bits).
    // `projectiles`: one Dictionary per projectile that moved this tick -
    // keys: id (i64), prev (Vector2), curr (Vector2), radius (f64), mask
    // (i64, collision_mask bits).
    // Returns: flat Array of {"projectile_id": i64, "target_id": i64} pair
    // Dictionaries, one per overlap found this tick (unordered, may contain
    // multiple targets for the same pierce-capable projectile).
    #[func]
    fn query_hits(&self, targets: Array<Variant>, projectiles: Array<Variant>) -> Array<Variant> {
        let targets: Vec<Target> = targets
            .iter_shared()
            .filter_map(|v| {
                let d: VDict = v.try_to().ok()?;
                Some(Target {
                    id: get_i(&d, "id"),
                    pos: get_vec2(&d, "pos"),
                    radius: get_f(&d, "radius"),
                    layer: get_i(&d, "layer"),
                })
            })
            .collect();

        let projectiles: Vec<Projectile> = projectiles
            .iter_shared()
            .filter_map(|v| {
                let d: VDict = v.try_to().ok()?;
                Some(Projectile {
                    id: get_i(&d, "id"),
                    prev: get_vec2(&d, "prev"),
                    curr: get_vec2(&d, "curr"),
                    radius: get_f(&d, "radius"),
                    mask: get_i(&d, "mask"),
                })
            })
            .collect();

        // Bucket targets by position once (O(T)), track the largest target
        // radius seen so every projectile's query margin is guaranteed wide
        // enough to not miss a legitimate overlap near a cell boundary.
        let mut buckets: HashMap<(i64, i64), Vec<usize>> = HashMap::with_capacity(targets.len());
        let mut max_target_radius: f64 = 0.0;
        for (i, t) in targets.iter().enumerate() {
            buckets.entry(cell_of(t.pos)).or_default().push(i);
            if t.radius > max_target_radius {
                max_target_radius = t.radius;
            }
        }

        let mut results: Array<Variant> = Array::new();
        for p in &projectiles {
            if buckets.is_empty() {
                continue;
            }
            // Swept segment's bounding box, expanded by both radii - any
            // target that could possibly overlap this projectile's path
            // this tick has its bucket cell inside this range. A target can
            // only ever live in its OWN single bucket (bucketed once above,
            // by its own position), so iterating every cell in range never
            // double-tests the same target even though the range itself can
            // span several cells.
            let margin = p.radius + max_target_radius;
            let min_x = (p.prev.x.min(p.curr.x) as f64) - margin;
            let max_x = (p.prev.x.max(p.curr.x) as f64) + margin;
            let min_y = (p.prev.y.min(p.curr.y) as f64) - margin;
            let max_y = (p.prev.y.max(p.curr.y) as f64) + margin;

            let (min_cx, min_cy) = cell_of_f64(min_x, min_y);
            let (max_cx, max_cy) = cell_of_f64(max_x, max_y);

            for cx in min_cx..=max_cx {
                for cy in min_cy..=max_cy {
                    let Some(indices) = buckets.get(&(cx, cy)) else {
                        continue;
                    };
                    for &ti in indices {
                        let t = &targets[ti];
                        if (t.layer & p.mask) == 0 {
                            continue;
                        }
                        let dist = point_segment_distance(t.pos, p.prev, p.curr);
                        if dist <= t.radius + p.radius {
                            let mut pair = VDict::new();
                            pair.set("projectile_id", p.id);
                            pair.set("target_id", t.id);
                            results.push(&pair.to_variant());
                        }
                    }
                }
            }
        }
        results
    }

    #[func]
    fn set_static_targets(
        &mut self,
        ids: PackedInt64Array,
        pos: PackedVector2Array,
        radii: PackedFloat64Array,
        layers: PackedInt64Array,
    ) {
        let (ids, pos, radii, layers) = (ids.as_slice(), pos.as_slice(), radii.as_slice(), layers.as_slice());
        let n = ids.len().min(pos.len()).min(radii.len()).min(layers.len());
        self.static_targets.clear();
        self.static_buckets.clear();
        self.static_max_radius = 0.0;
        for i in 0..n {
            let t = Target { id: ids[i], pos: pos[i], radius: radii[i], layer: layers[i] };
            self.static_buckets.entry(cell_of(t.pos)).or_default().push(i);
            if t.radius > self.static_max_radius {
                self.static_max_radius = t.radius;
            }
            self.static_targets.push(t);
        }
    }

    // Same hit test as query_hits, but dynamic targets and projectiles come
    // in as parallel packed arrays and the retained static targets are
    // included automatically. Returns flat [projectile_id, target_id, ...].
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
        let mut dyn_targets: Vec<Target> = Vec::with_capacity(tn);
        let mut dyn_buckets: HashMap<(i64, i64), Vec<usize>> = HashMap::with_capacity(tn);
        let mut max_r = self.static_max_radius;
        for i in 0..tn {
            let t = Target { id: t_ids[i], pos: t_pos[i], radius: t_radii[i], layer: t_layers[i] };
            dyn_buckets.entry(cell_of(t.pos)).or_default().push(i);
            if t.radius > max_r {
                max_r = t.radius;
            }
            dyn_targets.push(t);
        }

        let (p_ids, p_prev, p_curr, p_radii, p_masks) =
            (p_ids.as_slice(), p_prev.as_slice(), p_curr.as_slice(), p_radii.as_slice(), p_masks.as_slice());
        let pn = p_ids.len().min(p_prev.len()).min(p_curr.len()).min(p_radii.len()).min(p_masks.len());
        let mut out: Vec<i64> = Vec::new();
        if dyn_targets.is_empty() && self.static_targets.is_empty() {
            return PackedInt64Array::new();
        }
        for j in 0..pn {
            let (prev, curr, radius, mask) = (p_prev[j], p_curr[j], p_radii[j], p_masks[j]);
            let margin = radius + max_r;
            let min_x = (prev.x.min(curr.x) as f64) - margin;
            let max_x = (prev.x.max(curr.x) as f64) + margin;
            let min_y = (prev.y.min(curr.y) as f64) - margin;
            let max_y = (prev.y.max(curr.y) as f64) + margin;
            let (min_cx, min_cy) = cell_of_f64(min_x, min_y);
            let (max_cx, max_cy) = cell_of_f64(max_x, max_y);
            for cx in min_cx..=max_cx {
                for cy in min_cy..=max_cy {
                    for (buckets, targets) in [(&dyn_buckets, &dyn_targets), (&self.static_buckets, &self.static_targets)] {
                        let Some(indices) = buckets.get(&(cx, cy)) else { continue };
                        for &ti in indices {
                            let t = &targets[ti];
                            if (t.layer & mask) == 0 {
                                continue;
                            }
                            if point_segment_distance(t.pos, prev, curr) <= t.radius + radius {
                                out.push(p_ids[j]);
                                out.push(t.id);
                            }
                        }
                    }
                }
            }
        }
        PackedInt64Array::from(out.as_slice())
    }
}

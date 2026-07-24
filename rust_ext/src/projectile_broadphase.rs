use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};

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
// MVP: flat O(n_projectiles x n_targets) double loop, no spatial
// partitioning. At realistic scale (~300 projectiles x ~300-900 targets)
// that's on the order of the same per-tick workload hexgrid_sim.rs's
// simulate_grid() already handles fine - a grid-bucket spatial hash (same
// HashMap<(i64,i64), Vec<..>> idiom hexgrid_sim.rs uses for its fixed hex
// grid, adapted to coarse continuous-space cells) is a drop-in optimization
// behind the same query_hits signature if profiling ever says it's needed,
// but shouldn't be built until it is.

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ProjectileBroadphaseRs {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for ProjectileBroadphaseRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

fn get_f(d: &VDict, k: &str) -> f64 {
    d.get(k).map(|v| v.to::<f64>()).unwrap_or(0.0)
}

fn get_i(d: &VDict, k: &str) -> i64 {
    d.get(k).map(|v| v.to::<i64>()).unwrap_or(0)
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

        let mut results: Array<Variant> = Array::new();
        for p in &projectiles {
            for t in &targets {
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
        results
    }
}

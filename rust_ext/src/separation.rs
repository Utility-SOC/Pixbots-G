use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};
use std::collections::HashMap;

type VDict = Dictionary<Variant, Variant>;

// Batches Mech._compute_separation() across every eligible enemy mech into
// ONE call per batch cadence (SeparationBatcher.gd, mirroring
// ProjectileManager.gd's register/collect/one-call pattern) instead of each
// mech independently issuing its own PhysicsShapeQueryParameters2D circle
// query on its own staggered timer. Two real wins over the old per-mech
// physics query, not just fewer FFI calls:
//   1. No physics-server round-trip at all - every non-player, non-boss
//      mech lives on collision_layer 4 AND is in the "enemy" group in the
//      same _ready() block (Mech.gd), so EntityCache.get_group("enemy")
//      is an equivalent, already-cached population source. This trades an
//      exact shape-query for a point-distance approximation (mech bodies
//      are ~40px-wide rectangles, not points) - a reasonable trade for a
//      steering heuristic, same precision level already accepted elsewhere
//      in this codebase's hit detection, but NOT a byte-identical parity
//      guarantee the way the projectile-broadphase spatial hash was.
//   2. Grid-bucket spatial hash (same idiom as hexgrid_sim.rs/
//      projectile_broadphase.rs) instead of relying on the physics
//      server's own broadphase - for the worst case this matters most in
//      (a dense cluster around the player), neighbor lookup stays cheap
//      instead of degrading toward all-pairs.
//
// Batched once per SeparationBatcher's own interval (matches Mech.
// SEPARATION_QUERY_INTERVAL, 0.2s) for ALL eligible mechs at once, rather
// than staggering individual mechs' queries across ticks - now that it's
// one efficient batched call instead of N separate physics-server calls,
// there's no "thundering herd" concern left to stagger against.

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct SeparationRs {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for SeparationRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

fn get_i(d: &VDict, k: &str) -> i64 {
    d.get(k).and_then(|v| v.try_to::<i64>().ok()).unwrap_or(0)
}

fn get_vec2(d: &VDict, k: &str) -> Vector2 {
    d.get(k).and_then(|v| v.try_to().ok()).unwrap_or(Vector2::ZERO)
}

fn cell_of(pos: Vector2, cell_size: f64) -> (i64, i64) {
    (
        ((pos.x as f64) / cell_size).floor() as i64,
        ((pos.y as f64) / cell_size).floor() as i64,
    )
}

#[godot_api]
impl SeparationRs {
    // `mechs`: one Dictionary per eligible mech this batch - keys: id
    // (i64, instance id), pos (Vector2).
    // `radius`: separation radius (same meaning as Mech.SEPARATION_RADIUS).
    // Returns: one Dictionary per mech, same order - keys: id (i64), push
    // (Vector2) - identical formula to the old _compute_separation(): each
    // neighbor within `radius` contributes a unit vector away from it,
    // weighted by (1 - distance/radius), averaged over however many
    // neighbors were found (zero neighbors -> Vector2.ZERO).
    #[func]
    fn batch_compute_separation(&self, mechs: Array<Variant>, radius: f64) -> Array<Variant> {
        let entries: Vec<(i64, Vector2)> = mechs
            .iter_shared()
            .filter_map(|v| {
                let d: VDict = v.try_to().ok()?;
                Some((get_i(&d, "id"), get_vec2(&d, "pos")))
            })
            .collect();

        // Cell size matched to the separation radius itself - a neighbor
        // within `radius` can only ever be in the same cell or one of the
        // 8 adjacent ones.
        let cell_size = radius.max(1.0);
        let mut buckets: HashMap<(i64, i64), Vec<usize>> = HashMap::with_capacity(entries.len());
        for (i, (_, pos)) in entries.iter().enumerate() {
            buckets.entry(cell_of(*pos, cell_size)).or_default().push(i);
        }

        let mut results: Array<Variant> = Array::new();
        for (i, (id, pos)) in entries.iter().enumerate() {
            let (cx, cy) = cell_of(*pos, cell_size);
            let mut push = Vector2::ZERO;
            let mut count = 0i64;
            for dx in -1..=1 {
                for dy in -1..=1 {
                    let Some(indices) = buckets.get(&(cx + dx, cy + dy)) else {
                        continue;
                    };
                    for &j in indices {
                        if j == i {
                            continue;
                        }
                        let other_pos = entries[j].1;
                        let away = *pos - other_pos;
                        let d = away.length() as f64;
                        if d > 0.001 && d < radius {
                            push += away.normalized() * (1.0 - d / radius) as f32;
                            count += 1;
                        }
                    }
                }
            }
            if count > 0 {
                push /= count as f32;
            }
            let mut out: VDict = Dictionary::new();
            let _ = out.insert("id", *id);
            let _ = out.insert("push", push);
            results.push(&out.to_variant());
        }
        results
    }
}

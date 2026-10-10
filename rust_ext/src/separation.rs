use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};

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

#[godot_api]
impl SeparationRs {
    // `mechs`: one Dictionary per eligible mech this batch - keys: id (i64), pos (Vector2). `radius`: separation radius
    // (Mech.SEPARATION_RADIUS). Returns one {id, push} Dictionary per mech, same order. The maths is
    // pixbots_core::separation (native tests); this only marshals.
    #[func]
    fn batch_compute_separation(&self, mechs: Array<Variant>, radius: f64) -> Array<Variant> {
        let entries: Vec<(i64, (f32, f32))> = mechs
            .iter_shared()
            .filter_map(|v| {
                let d: VDict = v.try_to().ok()?;
                let p = get_vec2(&d, "pos");
                Some((get_i(&d, "id"), (p.x, p.y)))
            })
            .collect();
        let mut results: Array<Variant> = Array::new();
        for (id, (px, py)) in pixbots_core::separation::compute(&entries, radius) {
            let mut out: VDict = Dictionary::new();
            let _ = out.insert("id", id);
            let _ = out.insert("push", Vector2::new(px, py));
            results.push(&out.to_variant());
        }
        results
    }
}

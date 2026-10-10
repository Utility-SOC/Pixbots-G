use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};
use pixbots_core::solid_grid::SolidGrid;

type VDict = Dictionary<Variant, Variant>;

// Phase 1 of the AI-tactics Rust-cutover plan (see
// C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md). Backs
// SolidGridBatcher.gd, which replaces the direct per-mech
// PhysicsRayQueryParameters2D calls in SightAndSearch.gd (sight check,
// search-leg avoidance) and BossBrain.gd (_pick_retreat_dir) with one
// batched grid-marched line-of-sight test per cadence.
//
// This is a deliberate BEHAVIOR CHANGE, not a pure parity port: those real
// raycasts all passed collision_mask=1 (Env/map-boundary layer only) -
// confirmed by reading every PhysicsRayQueryParameters2D.create call site in
// the codebase - so trees/boulders/ruins (layer 32, "Obstacles") never
// actually blocked sight/search-avoidance/retreat-picking before this. The
// user explicitly chose to fix that alongside the port (2026-08-03 planning
// session) rather than faithfully replicate the boundary-only quirk, so this
// grid now marks every MapGenerator.obstacles cell as solid and mechs
// genuinely can't see/path through solid terrain anymore.
//
// Grid-marched via Amanatides & Woo's DDA algorithm (the standard
// grid-traversal method for this exact problem - step from cell to cell
// along the line, testing solidity, without the aliasing gaps a naive
// fixed-step sampler can produce at shallow angles). Endpoints themselves
// are never tested (only cells strictly between start and end) so a mech
// standing on/adjacent to obstacle-cell geometry, or a target inside one,
// doesn't spuriously block its own sight line.

// The DDA march itself lives in pixbots_core::solid_grid (native unit tests); this file only marshals Godot data.

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct SolidGridRs {
    base: Base<RefCounted>,
    grid: SolidGrid,
}

#[godot_api]
impl IRefCounted for SolidGridRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base, grid: SolidGrid { tile_size: 32.0, ..SolidGrid::default() } }
    }
}

fn get_vec2(d: &VDict, k: &str) -> Vector2 {
    d.get(k).and_then(|v| v.try_to().ok()).unwrap_or(Vector2::ZERO)
}

#[godot_api]
impl SolidGridRs {
    // Called by SolidGridBatcher.gd only when the obstacle-solidity snapshot is invalidated, not every batch tick.
    #[func]
    fn set_grid(&mut self, solidity: PackedByteArray, width: i32, height: i32, tile_size: f64) {
        self.grid = SolidGrid::new(solidity.to_vec(), width, height, tile_size);
    }

    // `queries`: one Dictionary per line test (keys from/to, world-space Vector2). One bool per query: true = clear.
    #[func]
    fn batch_line_of_sight(&self, queries: Array<Variant>) -> Array<Variant> {
        let mut results: Array<Variant> = Array::new();
        for q in queries.iter_shared() {
            let Ok(d) = q.try_to::<VDict>() else {
                results.push(&true.to_variant());
                continue;
            };
            let (from, to) = (get_vec2(&d, "from"), get_vec2(&d, "to"));
            results.push(&self.grid.line_of_sight((from.x, from.y), (to.x, to.y)).to_variant());
        }
        results
    }

    // Distance along each from->to probe before a solid cell (the full length when never blocked).
    #[func]
    fn batch_probe_clearance(&self, queries: Array<Variant>) -> PackedFloat64Array {
        let mut results = PackedFloat64Array::new();
        for q in queries.iter_shared() {
            let Ok(d) = q.try_to::<VDict>() else {
                results.push(0.0);
                continue;
            };
            let (from, to) = (get_vec2(&d, "from"), get_vec2(&d, "to"));
            results.push(self.grid.clearance((from.x, from.y), (to.x, to.y)));
        }
        results
    }
}

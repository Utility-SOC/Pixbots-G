use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};

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

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct SolidGridRs {
    base: Base<RefCounted>,
    solidity: Vec<u8>,
    width: i32,
    height: i32,
    tile_size: f64,
}

#[godot_api]
impl IRefCounted for SolidGridRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base, solidity: Vec::new(), width: 0, height: 0, tile_size: 32.0 }
    }
}

fn get_vec2(d: &VDict, k: &str) -> Vector2 {
    d.get(k).and_then(|v| v.try_to().ok()).unwrap_or(Vector2::ZERO)
}

#[godot_api]
impl SolidGridRs {
    // Called by SolidGridBatcher.gd only when MapGenerator's obstacle-solidity
    // snapshot is actually invalidated (piggybacks on the same
    // _flow_field_timer trigger obstacle-destruction scripts already zero) -
    // not every batch tick, so the ~100KB-per-400x250-map buffer isn't
    // re-marshalled across the FFI boundary on every query call.
    #[func]
    fn set_grid(&mut self, solidity: PackedByteArray, width: i32, height: i32, tile_size: f64) {
        self.solidity = solidity.to_vec();
        self.width = width;
        self.height = height;
        self.tile_size = tile_size;
    }

    fn is_solid_cell(&self, cx: i32, cy: i32) -> bool {
        if cx < 0 || cy < 0 || cx >= self.width || cy >= self.height {
            return false; // outside the flattened window - no data, assume open (matches "outside the flow field's bounded window falls back to straight-line" convention elsewhere)
        }
        self.solidity[(cy * self.width + cx) as usize] != 0
    }

    // `queries`: one Dictionary per line test - keys: from (Vector2), to
    // (Vector2), both world-space. Returns one bool per query, same order -
    // true = clear line of sight, false = blocked by a solid cell.
    #[func]
    fn batch_line_of_sight(&self, queries: Array<Variant>) -> Array<Variant> {
        let mut results: Array<Variant> = Array::new();
        for q in queries.iter_shared() {
            let Ok(d) = q.try_to::<VDict>() else {
                results.push(&true.to_variant());
                continue;
            };
            let from = get_vec2(&d, "from");
            let to = get_vec2(&d, "to");
            results.push(&(self.march(from, to).is_none()).to_variant());
        }
        results
    }

    // Phase 4 (BossBrain._pick_retreat_dir) candidate - unlike
    // batch_line_of_sight's boolean, this returns how FAR along each
    // from->to segment the ray gets before hitting a solid cell (world
    // units, capped at the segment's own length if never blocked) -
    // matches _pick_retreat_dir's real raycast semantics exactly
    // (`clearance = probe_dist if result.is_empty() else
    // mech.global_position.distance_to(result.position)`), just against
    // the grid-cell boundary the ray first enters rather than the real
    // collision shape's exact surface (same disclosed grid-vs-physics
    // approximation tier as batch_line_of_sight).
    //
    // `queries`: one Dictionary per probe - keys: from (Vector2), to
    // (Vector2). Returns one f64 per query, same order.
    #[func]
    fn batch_probe_clearance(&self, queries: Array<Variant>) -> PackedFloat64Array {
        let mut results = PackedFloat64Array::new();
        for q in queries.iter_shared() {
            let Ok(d) = q.try_to::<VDict>() else {
                results.push(0.0);
                continue;
            };
            let from = get_vec2(&d, "from");
            let to = get_vec2(&d, "to");
            let full_len = (to - from).length() as f64;
            let clearance = match self.march(from, to) {
                Some(t) => t * full_len,
                None => full_len,
            };
            results.push(clearance);
        }
        results
    }

    // Shared DDA core (Amanatides & Woo) for both queries above. Returns
    // `Some(t)` - the 0..1 parametrization along from->to at which the
    // first solid cell was entered - or `None` if the ray reaches the
    // destination cell clear. Endpoints themselves are never tested (only
    // cells strictly between start and end), so a mech standing on/adjacent
    // to obstacle-cell geometry - or a target inside one - doesn't
    // spuriously block its own line.
    fn march(&self, from: Vector2, to: Vector2) -> Option<f64> {
        if self.solidity.is_empty() || self.tile_size <= 0.0 {
            return None; // grid not yet built - fail open, matches get_flow_direction's own "no data" fallback
        }
        let ts = self.tile_size;
        let (x0, y0) = (from.x as f64 / ts, from.y as f64 / ts);
        let (x1, y1) = (to.x as f64 / ts, to.y as f64 / ts);

        let mut cx = x0.floor() as i32;
        let cy0 = y0.floor() as i32;
        let end_cx = x1.floor() as i32;
        let end_cy = y1.floor() as i32;

        let dx = x1 - x0;
        let dy = y1 - y0;
        let step_x: i32 = if dx > 0.0 { 1 } else if dx < 0.0 { -1 } else { 0 };
        let step_y: i32 = if dy > 0.0 { 1 } else if dy < 0.0 { -1 } else { 0 };

        // Distance (in units of t, the 0..1 parametrization of the segment)
        // to cross one full cell along each axis.
        let t_delta_x = if dx != 0.0 { (1.0 / dx).abs() } else { f64::INFINITY };
        let t_delta_y = if dy != 0.0 { (1.0 / dy).abs() } else { f64::INFINITY };

        let mut t_max_x = if step_x > 0 {
            ((cx as f64 + 1.0) - x0) * t_delta_x
        } else if step_x < 0 {
            (x0 - cx as f64) * t_delta_x
        } else {
            f64::INFINITY
        };
        let mut cy = cy0;
        let mut t_max_y = if step_y > 0 {
            ((cy as f64 + 1.0) - y0) * t_delta_y
        } else if step_y < 0 {
            (y0 - cy as f64) * t_delta_y
        } else {
            f64::INFINITY
        };

        // Cap iterations at the Manhattan cell distance (+2 for rounding
        // slop) - guarantees termination regardless of float edge cases,
        // same defensive bound every other grid-march in this codebase
        // (hexgrid_sim's BFS, MapGenerator's own flow-field BFS) implicitly
        // gets from its queue running dry.
        let max_steps = ((end_cx - cx).abs() + (end_cy - cy).abs() + 2) as i64;

        for _ in 0..max_steps {
            if cx == end_cx && cy == end_cy {
                break; // reached the destination cell - never test it, matches the "endpoints aren't tested" contract above
            }
            let t_here;
            if t_max_x < t_max_y {
                cx += step_x;
                t_here = t_max_x;
                t_max_x += t_delta_x;
            } else {
                cy += step_y;
                t_here = t_max_y;
                t_max_y += t_delta_y;
            }
            if cx == end_cx && cy == end_cy {
                break;
            }
            if self.is_solid_cell(cx, cy) {
                return Some(t_here.clamp(0.0, 1.0));
            }
        }
        None
    }
}

use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};
use pixbots_core::flow_field::FlowGrid;

// Phase 3 of the AI-tactics Rust-cutover plan (see
// C:\Users\Utility\.claude\plans\effervescent-drifting-kazoo.md). Ports
// MapGenerator._rebuild_flow_field's bounded BFS - Phase 0's real
// instrumentation measured this at ~6.8-7.6ms per rebuild on a 0.4s cadence,
// a genuine periodic stutter, the number that justified this phase.
//
// Unlike Phase 1/2 (soft heuristics, disclosed approximations accepted),
// this is navigation-affecting and REQUIRES byte-identical parity with the
// GDScript BFS it replaces - verified via FlowFieldParityCheck.gd, not just
// an approximate agreement.
//
// Deliberately NOT sharing SolidGridRs's (Phase 1) solidity buffer:
// astar_grid (which the old GDScript BFS queries via is_point_solid) marks
// BOTH obstacles.has(cell) AND terrain==WATER as solid
// (MapGenerator._build_navigation), whereas SolidGridRs's LOS buffer is
// obstacles-only - reusing it here would silently make water passable for
// flow-field routing, an undiscussed behavior change. This keeps its own
// separate solidity buffer using the union definition that matches
// astar_grid exactly.

// The BFS lives in pixbots_core::flow_field (native unit tests); this file only marshals Godot data.

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct FlowFieldRs {
    base: Base<RefCounted>,
    grid: FlowGrid,
}

#[godot_api]
impl IRefCounted for FlowFieldRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base, grid: FlowGrid::default() }
    }
}

#[godot_api]
impl FlowFieldRs {
    // Called by MapGenerator only when its obstacle-solidity snapshot is invalidated.
    #[func]
    fn set_grid(&mut self, solidity: PackedByteArray, width: i32, height: i32) {
        self.grid = FlowGrid::new(solidity.to_vec(), width, height);
    }

    // Array of {cell: Vector2i, dir: Vector2}: one entry per reached cell that has an improving neighbour
    // (the target maps to Vector2.ZERO), matching the GDScript flow_field exactly.
    #[func]
    fn rebuild(&self, target_x: i32, target_y: i32, radius: i32) -> Array<Variant> {
        let mut results: Array<Variant> = Array::new();
        for ((cx, cy), (dx, dy)) in self.grid.rebuild(target_x, target_y, radius) {
            let mut out: Dictionary<Variant, Variant> = Dictionary::new();
            let _ = out.insert("cell", Vector2i::new(cx, cy));
            let dir = if dx == 0 && dy == 0 { Vector2::ZERO } else { Vector2::new(dx as f32, dy as f32).normalized() };
            let _ = out.insert("dir", dir);
            results.push(&out.to_variant());
        }
        results
    }
}

use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};

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

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct FlowFieldRs {
    base: Base<RefCounted>,
    solidity: Vec<u8>,
    width: i32,
    height: i32,
}

#[godot_api]
impl IRefCounted for FlowFieldRs {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base, solidity: Vec::new(), width: 0, height: 0 }
    }
}

// Same order as MapGenerator._FLOW_NEIGHBOR_OFFSETS - the direction-
// extraction pass's tie-break ("first neighbor found with a strictly lower
// distance wins") depends on iterating in this exact order for
// byte-identical parity.
const NEIGHBOR_OFFSETS: [(i32, i32); 8] = [
    (1, 0), (-1, 0), (0, 1), (0, -1),
    (1, 1), (1, -1), (-1, 1), (-1, -1),
];

#[godot_api]
impl FlowFieldRs {
    // Called by MapGenerator only when its obstacle-solidity snapshot is
    // invalidated (same obstacles.size()-change piggyback Phase 1's
    // SolidGridBatcher uses) - water never changes after generation, so
    // this buffer is otherwise stable for the whole match.
    #[func]
    fn set_grid(&mut self, solidity: PackedByteArray, width: i32, height: i32) {
        self.solidity = solidity.to_vec();
        self.width = width;
        self.height = height;
    }

    // Bounds-unsafe by design, matching a real invariant: every caller
    // (both the BFS neighbor loop and the target-cell check) only ever
    // queries cells already known to be inside [0,width)x[0,height) via a
    // prior clamp/bounds check, same as the GDScript original never calls
    // astar_grid.is_point_solid() out of region either.
    fn is_solid(&self, x: i32, y: i32) -> bool {
        self.solidity[(y * self.width + x) as usize] != 0
    }

    // Returns Array of {cell: Vector2i, dir: Vector2} - one entry per cell
    // the BFS actually reached (matching GDScript's flow_field.keys()
    // exactly): target_cell maps to Vector2.ZERO, every other reached cell
    // maps to its normalized step direction. A reached cell with no
    // improving neighbor is silently omitted, matching the GDScript's own
    // `if best_dir != Vector2i.ZERO: flow_field[cell] = ...` guard.
    #[func]
    fn rebuild(&self, target_x: i32, target_y: i32, radius: i32) -> Array<Variant> {
        let mut results: Array<Variant> = Array::new();
        if self.solidity.is_empty() {
            return results; // no grid built yet
        }
        if target_x < 0 || target_y < 0 || target_x >= self.width || target_y >= self.height {
            return results;
        }
        if self.is_solid(target_x, target_y) {
            return results; // target inside a solid cell - empty field, matches the GDScript early return
        }

        let min_x = (target_x - radius).max(0);
        let max_x = (target_x + radius).min(self.width - 1);
        let min_y = (target_y - radius).max(0);
        let max_y = (target_y + radius).min(self.height - 1);

        let win_w = (max_x - min_x + 1) as usize;
        let win_h = (max_y - min_y + 1) as usize;
        let mut dist: Vec<i32> = vec![-1; win_w * win_h];
        let idx = |x: i32, y: i32| -> usize { ((y - min_y) as usize) * win_w + (x - min_x) as usize };

        dist[idx(target_x, target_y)] = 0;
        let mut queue: Vec<(i32, i32)> = Vec::with_capacity(win_w * win_h);
        queue.push((target_x, target_y));
        let mut head = 0usize;
        while head < queue.len() {
            let (cx, cy) = queue[head];
            head += 1;
            let cur_dist = dist[idx(cx, cy)];
            for &(dx, dy) in NEIGHBOR_OFFSETS.iter() {
                let nx = cx + dx;
                let ny = cy + dy;
                if nx < min_x || nx > max_x || ny < min_y || ny > max_y {
                    continue;
                }
                let ni = idx(nx, ny);
                if dist[ni] != -1 || self.is_solid(nx, ny) {
                    continue;
                }
                dist[ni] = cur_dist + 1;
                queue.push((nx, ny));
            }
        }

        // Pass 2: direction extraction, same tie-break order as GDScript.
        for &(cx, cy) in queue.iter() {
            let mut out: Dictionary<Variant, Variant> = Dictionary::new();
            let _ = out.insert("cell", Vector2i::new(cx, cy));
            if cx == target_x && cy == target_y {
                let _ = out.insert("dir", Vector2::ZERO);
                results.push(&out.to_variant());
                continue;
            }
            let best_dist_here = dist[idx(cx, cy)];
            let mut best_dist = best_dist_here;
            let mut best_dir: Option<(i32, i32)> = None;
            for &(dx, dy) in NEIGHBOR_OFFSETS.iter() {
                let nx = cx + dx;
                let ny = cy + dy;
                if nx < min_x || nx > max_x || ny < min_y || ny > max_y {
                    continue;
                }
                let nd = dist[idx(nx, ny)];
                if nd != -1 && nd < best_dist {
                    best_dist = nd;
                    best_dir = Some((dx, dy));
                }
            }
            if let Some((dx, dy)) = best_dir {
                let v = Vector2::new(dx as f32, dy as f32).normalized();
                let _ = out.insert("dir", v);
                results.push(&out.to_variant());
            }
        }
        results
    }
}

//! Bounded flow-field BFS toward a target cell over a flat solidity buffer (8-neighbour, window of `radius` cells).
//!
//! Navigation-affecting, so byte-identical to the GDScript BFS it replaced: the neighbour order below is the tie-break
//! for the direction pass ("first neighbour with a strictly lower distance wins").

pub const NEIGHBOR_OFFSETS: [(i32, i32); 8] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];

#[derive(Default, Clone)]
pub struct FlowGrid {
    pub solidity: Vec<u8>,
    pub width: i32,
    pub height: i32,
}

impl FlowGrid {
    pub fn new(solidity: Vec<u8>, width: i32, height: i32) -> Self {
        Self { solidity, width, height }
    }

    fn is_solid(&self, x: i32, y: i32) -> bool {
        self.solidity[(y * self.width + x) as usize] != 0
    }

    /// One `(cell, step)` per reached cell with an improving neighbour, in BFS order. The target maps to (0, 0).
    /// Normalising the integer step into a unit vector is the caller's job.
    pub fn rebuild(&self, target_x: i32, target_y: i32, radius: i32) -> Vec<((i32, i32), (i32, i32))> {
        let mut results = Vec::new();
        if self.solidity.is_empty() {
            return results;
        }
        if target_x < 0 || target_y < 0 || target_x >= self.width || target_y >= self.height {
            return results;
        }
        if self.is_solid(target_x, target_y) {
            return results;
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

        for &(cx, cy) in queue.iter() {
            if cx == target_x && cy == target_y {
                results.push(((cx, cy), (0, 0)));
                continue;
            }
            let mut best_dist = dist[idx(cx, cy)];
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
            if let Some(d) = best_dir {
                results.push(((cx, cy), d));
            }
        }
        results
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn open(w: i32, h: i32) -> FlowGrid {
        FlowGrid::new(vec![0; (w * h) as usize], w, h)
    }

    #[test]
    fn target_maps_to_zero_and_neighbours_point_at_it() {
        let g = open(5, 5);
        let f = g.rebuild(2, 2, 10);
        assert_eq!(f[0], ((2, 2), (0, 0)));
        let east = f.iter().find(|(c, _)| *c == (3, 2)).unwrap();
        assert_eq!(east.1, (-1, 0));
    }

    #[test]
    fn solid_target_gives_an_empty_field() {
        let mut g = open(5, 5);
        g.solidity[2 * 5 + 2] = 1;
        assert!(g.rebuild(2, 2, 10).is_empty());
    }

    #[test]
    fn out_of_range_target_gives_an_empty_field() {
        assert!(open(5, 5).rebuild(9, 9, 10).is_empty());
        assert!(FlowGrid::default().rebuild(0, 0, 10).is_empty());
    }

    #[test]
    fn walls_are_routed_around() {
        // Wall at x=2 except a gap at y=4; target (4,0): the cell (0,0) must head toward the gap side (down), not into the wall.
        let mut g = open(5, 5);
        for y in 0..4 {
            g.solidity[(y * 5 + 2) as usize] = 1;
        }
        let f = g.rebuild(4, 0, 10);
        let c = f.iter().find(|(c, _)| *c == (0, 0)).unwrap();
        assert!(c.1 .1 > 0, "expected a step toward the gap, got {:?}", c.1);
    }

    #[test]
    fn radius_limits_the_window() {
        let f = open(20, 20).rebuild(10, 10, 2);
        assert!(f.iter().all(|((x, y), _)| (x - 10).abs() <= 2 && (y - 10).abs() <= 2));
        assert!(f.len() > 1);
    }
}

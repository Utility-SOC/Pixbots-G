//! Grid-marched line of sight (Amanatides & Woo DDA) over a flat solidity buffer.
//!
//! Endpoints are never tested (only cells strictly between start and end), so a body standing on or beside solid
//! geometry, or a target inside it, does not block its own line. Outside the buffer is open, and an empty grid fails open.

#[derive(Default, Clone)]
pub struct SolidGrid {
    pub solidity: Vec<u8>,
    pub width: i32,
    pub height: i32,
    pub tile_size: f64,
}

impl SolidGrid {
    pub fn new(solidity: Vec<u8>, width: i32, height: i32, tile_size: f64) -> Self {
        Self { solidity, width, height, tile_size }
    }

    fn is_solid_cell(&self, cx: i32, cy: i32) -> bool {
        if cx < 0 || cy < 0 || cx >= self.width || cy >= self.height {
            return false;
        }
        self.solidity[(cy * self.width + cx) as usize] != 0
    }

    /// `Some(t)`: the 0..1 parameter along from->to at which the first solid cell was entered. `None`: clear.
    pub fn march(&self, from: (f32, f32), to: (f32, f32)) -> Option<f64> {
        if self.solidity.is_empty() || self.tile_size <= 0.0 {
            return None;
        }
        let ts = self.tile_size;
        let (x0, y0) = (from.0 as f64 / ts, from.1 as f64 / ts);
        let (x1, y1) = (to.0 as f64 / ts, to.1 as f64 / ts);

        let mut cx = x0.floor() as i32;
        let cy0 = y0.floor() as i32;
        let end_cx = x1.floor() as i32;
        let end_cy = y1.floor() as i32;

        let dx = x1 - x0;
        let dy = y1 - y0;
        let step_x: i32 = if dx > 0.0 { 1 } else if dx < 0.0 { -1 } else { 0 };
        let step_y: i32 = if dy > 0.0 { 1 } else if dy < 0.0 { -1 } else { 0 };

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

        // Manhattan cell distance (+2 for rounding slop) guarantees termination whatever the float edge cases.
        let max_steps = ((end_cx - cx).abs() + (end_cy - cy).abs() + 2) as i64;

        for _ in 0..max_steps {
            if cx == end_cx && cy == end_cy {
                break;
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

    pub fn line_of_sight(&self, from: (f32, f32), to: (f32, f32)) -> bool {
        self.march(from, to).is_none()
    }

    /// Distance along from->to before the first solid cell (the full length when never blocked).
    pub fn clearance(&self, from: (f32, f32), to: (f32, f32)) -> f64 {
        let dx = (to.0 - from.0) as f64;
        let dy = (to.1 - from.1) as f64;
        let full_len = (dx * dx + dy * dy).sqrt();
        match self.march(from, to) {
            Some(t) => t * full_len,
            None => full_len,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // 10x10 cells of 32 px, a vertical wall at x = 5 for rows 0..9.
    fn walled() -> SolidGrid {
        let mut s = vec![0u8; 100];
        for y in 0..10 {
            s[y * 10 + 5] = 1;
        }
        SolidGrid::new(s, 10, 10, 32.0)
    }

    #[test]
    fn wall_blocks_sight_across_it() {
        let g = walled();
        assert!(!g.line_of_sight((16.0, 16.0), (300.0, 16.0)));
    }

    #[test]
    fn open_side_has_sight() {
        let g = walled();
        assert!(g.line_of_sight((16.0, 16.0), (100.0, 100.0)));
    }

    #[test]
    fn clearance_stops_at_the_wall() {
        let g = walled();
        let c = g.clearance((16.0, 16.0), (300.0, 16.0));
        assert!((c - (5.0 * 32.0 - 16.0)).abs() < 1.0, "clearance {}", c);
    }

    #[test]
    fn endpoints_inside_solid_do_not_block() {
        let g = walled();
        assert!(g.line_of_sight((5.0 * 32.0 + 4.0, 16.0), (5.0 * 32.0 + 20.0, 16.0)));
    }

    #[test]
    fn empty_grid_fails_open() {
        assert!(SolidGrid::default().line_of_sight((0.0, 0.0), (500.0, 500.0)));
    }

    #[test]
    fn outside_the_buffer_is_open() {
        let g = walled();
        assert!(g.line_of_sight((-500.0, 16.0), (-100.0, 16.0)));
    }
}

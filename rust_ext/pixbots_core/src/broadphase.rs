//! Projectile hit broadphase: reports (projectile, target) overlaps for the swept segment each projectile travelled this
//! tick. Targets are bucketed into a coarse grid once per call (statics once ever), and each projectile only tests the
//! cells its segment's bounding box (grown by both radii) touches. A moving circle approximates the sprite.
//! What a hit DOES (damage, pierce, dedup) is the caller's business; this only answers "who touched whom".

use std::collections::HashMap;

/// Bucket cell size in world pixels: big enough that cells hold a handful of targets, small enough that a normal shot's
/// box does not sweep huge empty areas. Tuned to the game's scale (radii in the tens of px, maps in the thousands).
pub const CELL_SIZE: f64 = 150.0;

#[derive(Clone, Copy, Debug)]
pub struct Target {
    pub id: i64,
    pub pos: (f32, f32),
    pub radius: f64,
    pub layer: i64,
}

#[derive(Clone, Copy, Debug)]
pub struct Shot {
    pub id: i64,
    pub prev: (f32, f32),
    pub curr: (f32, f32),
    pub radius: f64,
    pub mask: i64,
}

fn cell_of_f64(x: f64, y: f64) -> (i64, i64) {
    ((x / CELL_SIZE).floor() as i64, (y / CELL_SIZE).floor() as i64)
}

/// Closest distance from `p` to the segment [a, b], in f32 like the engine's Vector2 maths.
fn point_segment_distance(p: (f32, f32), a: (f32, f32), b: (f32, f32)) -> f64 {
    let (abx, aby) = (b.0 - a.0, b.1 - a.1);
    let len_sq = (abx * abx + aby * aby) as f64;
    let (pax, pay) = (p.0 - a.0, p.1 - a.1);
    if len_sq <= 1e-9 {
        return ((pax * pax + pay * pay).sqrt()) as f64;
    }
    let t = (((pax * abx + pay * aby) as f64) / len_sq).clamp(0.0, 1.0) as f32;
    let (cx, cy) = (a.0 + abx * t, a.1 + aby * t);
    let (dx, dy) = (p.0 - cx, p.1 - cy);
    ((dx * dx + dy * dy).sqrt()) as f64
}

/// A bucketed target set. Build once for things that never move (obstacles), per call for the rest.
#[derive(Default, Clone)]
pub struct Index {
    pub targets: Vec<Target>,
    buckets: HashMap<(i64, i64), Vec<usize>>,
    pub max_radius: f64,
}

impl Index {
    pub fn new(targets: Vec<Target>) -> Self {
        let mut buckets: HashMap<(i64, i64), Vec<usize>> = HashMap::with_capacity(targets.len());
        let mut max_radius: f64 = 0.0;
        for (i, t) in targets.iter().enumerate() {
            buckets.entry(cell_of_f64(t.pos.0 as f64, t.pos.1 as f64)).or_default().push(i);
            if t.radius > max_radius {
                max_radius = t.radius;
            }
        }
        Self { targets, buckets, max_radius }
    }

    pub fn is_empty(&self) -> bool {
        self.targets.is_empty()
    }
}

/// Overlap pairs `(projectile_id, target_id)`. Within a cell the dynamic index is tested before the static one.
pub fn query(statics: &Index, dynamic: &Index, shots: &[Shot]) -> Vec<(i64, i64)> {
    let mut out = Vec::new();
    if dynamic.is_empty() && statics.is_empty() {
        return out;
    }
    let max_r = dynamic.max_radius.max(statics.max_radius);
    for s in shots {
        let margin = s.radius + max_r;
        let min_x = (s.prev.0.min(s.curr.0) as f64) - margin;
        let max_x = (s.prev.0.max(s.curr.0) as f64) + margin;
        let min_y = (s.prev.1.min(s.curr.1) as f64) - margin;
        let max_y = (s.prev.1.max(s.curr.1) as f64) + margin;
        let (min_cx, min_cy) = cell_of_f64(min_x, min_y);
        let (max_cx, max_cy) = cell_of_f64(max_x, max_y);
        for cx in min_cx..=max_cx {
            for cy in min_cy..=max_cy {
                for idx in [dynamic, statics] {
                    let Some(indices) = idx.buckets.get(&(cx, cy)) else { continue };
                    for &ti in indices {
                        let t = &idx.targets[ti];
                        if (t.layer & s.mask) == 0 {
                            continue;
                        }
                        if point_segment_distance(t.pos, s.prev, s.curr) <= t.radius + s.radius {
                            out.push((s.id, t.id));
                        }
                    }
                }
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn target(id: i64, x: f32, y: f32, radius: f64, layer: i64) -> Target {
        Target { id, pos: (x, y), radius, layer }
    }
    fn shot(id: i64, from: (f32, f32), to: (f32, f32), radius: f64, mask: i64) -> Shot {
        Shot { id, prev: from, curr: to, radius, mask }
    }

    #[test]
    fn a_shot_overlapping_a_target_reports_the_pair() {
        let d = Index::new(vec![target(10, 100.0, 0.0, 20.0, 4)]);
        let hits = query(&Index::default(), &d, &[shot(1, (0.0, 0.0), (90.0, 0.0), 5.0, 4)]);
        assert_eq!(hits, vec![(1, 10)]);
    }

    #[test]
    fn a_fast_shot_does_not_tunnel_through_a_thin_target() {
        // Moves 400 px in one tick, straight through a 10 px target at x = 200.
        let d = Index::new(vec![target(7, 200.0, 0.0, 10.0, 1)]);
        let hits = query(&Index::default(), &d, &[shot(1, (0.0, 0.0), (400.0, 0.0), 2.0, 1)]);
        assert_eq!(hits, vec![(1, 7)]);
    }

    #[test]
    fn layer_mask_filters_targets() {
        let d = Index::new(vec![target(10, 50.0, 0.0, 20.0, 8)]);
        assert!(query(&Index::default(), &d, &[shot(1, (0.0, 0.0), (60.0, 0.0), 5.0, 4)]).is_empty());
    }

    #[test]
    fn a_miss_reports_nothing() {
        let d = Index::new(vec![target(10, 100.0, 300.0, 20.0, 4)]);
        assert!(query(&Index::default(), &d, &[shot(1, (0.0, 0.0), (200.0, 0.0), 5.0, 4)]).is_empty());
    }

    #[test]
    fn statics_and_dynamics_are_both_searched() {
        let s = Index::new(vec![target(1, 100.0, 0.0, 10.0, 1)]);
        let d = Index::new(vec![target(2, 100.0, 5.0, 10.0, 1)]);
        let hits = query(&s, &d, &[shot(9, (0.0, 0.0), (150.0, 0.0), 3.0, 1)]);
        assert_eq!(hits, vec![(9, 2), (9, 1)]); // dynamic first within a cell
    }

    #[test]
    fn a_target_across_a_cell_boundary_is_still_found() {
        // Target centre sits just past x = 150 (next cell); the shot ends before it but its radius reaches in.
        let d = Index::new(vec![target(3, 151.0, 0.0, 20.0, 1)]);
        let hits = query(&Index::default(), &d, &[shot(1, (0.0, 0.0), (140.0, 0.0), 5.0, 1)]);
        assert_eq!(hits, vec![(1, 3)]);
    }

    #[test]
    fn stationary_shot_uses_point_distance() {
        let d = Index::new(vec![target(3, 10.0, 0.0, 6.0, 1)]);
        assert_eq!(query(&Index::default(), &d, &[shot(1, (0.0, 0.0), (0.0, 0.0), 5.0, 1)]), vec![(1, 3)]);
        assert!(query(&Index::default(), &d, &[shot(1, (0.0, 0.0), (0.0, 0.0), 2.0, 1)]).is_empty());
    }

    #[test]
    fn nothing_to_hit_is_fast_and_empty() {
        assert!(query(&Index::default(), &Index::default(), &[shot(1, (0.0, 0.0), (1.0, 1.0), 1.0, 1)]).is_empty());
    }
}

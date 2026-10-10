//! Crowd separation: each neighbour within `radius` pushes a body directly away, weighted by (1 - d/radius), averaged
//! over the neighbours found. A grid-bucket spatial hash (cell = radius) keeps a dense cluster from degrading to all-pairs.
//! Positions are f32 like the engine's Vector2, the distance test is f64 like the GDScript original.

use std::collections::HashMap;

fn cell_of(x: f32, y: f32, cell_size: f64) -> (i64, i64) {
    (((x as f64) / cell_size).floor() as i64, ((y as f64) / cell_size).floor() as i64)
}

/// One push vector per entry, same order. `entries`: (id, (x, y)).
pub fn compute(entries: &[(i64, (f32, f32))], radius: f64) -> Vec<(i64, (f32, f32))> {
    let cell_size = radius.max(1.0);
    let mut buckets: HashMap<(i64, i64), Vec<usize>> = HashMap::with_capacity(entries.len());
    for (i, (_, pos)) in entries.iter().enumerate() {
        buckets.entry(cell_of(pos.0, pos.1, cell_size)).or_default().push(i);
    }

    let mut results = Vec::with_capacity(entries.len());
    for (i, (id, pos)) in entries.iter().enumerate() {
        let (cx, cy) = cell_of(pos.0, pos.1, cell_size);
        let (mut px, mut py) = (0.0f32, 0.0f32);
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
                    let other = entries[j].1;
                    let (ax, ay) = (pos.0 - other.0, pos.1 - other.1);
                    let len = (ax * ax + ay * ay).sqrt();
                    let d = len as f64;
                    if d > 0.001 && d < radius {
                        let w = (1.0 - d / radius) as f32;
                        px += ax / len * w;
                        py += ay / len * w;
                        count += 1;
                    }
                }
            }
        }
        if count > 0 {
            px /= count as f32;
            py /= count as f32;
        }
        results.push((*id, (px, py)));
    }
    results
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn two_bodies_push_apart_equally() {
        let r = compute(&[(1, (0.0, 0.0)), (2, (10.0, 0.0))], 40.0);
        assert!(r[0].1 .0 < 0.0 && r[1].1 .0 > 0.0);
        assert!((r[0].1 .0 + r[1].1 .0).abs() < 1e-6);
        assert_eq!(r[0].1 .1, 0.0);
    }

    #[test]
    fn closer_pushes_harder() {
        let near = compute(&[(1, (0.0, 0.0)), (2, (5.0, 0.0))], 40.0)[0].1 .0.abs();
        let far = compute(&[(1, (0.0, 0.0)), (2, (30.0, 0.0))], 40.0)[0].1 .0.abs();
        assert!(near > far);
    }

    #[test]
    fn outside_the_radius_or_alone_is_zero() {
        assert_eq!(compute(&[(1, (0.0, 0.0)), (2, (100.0, 0.0))], 40.0)[0].1, (0.0, 0.0));
        assert_eq!(compute(&[(7, (3.0, 3.0))], 40.0)[0], (7, (0.0, 0.0)));
    }

    #[test]
    fn neighbours_in_adjacent_cells_are_found() {
        // x = 39 and x = 41 straddle a cell boundary at radius 40 but are 2 apart.
        let r = compute(&[(1, (39.0, 0.0)), (2, (41.0, 0.0))], 40.0);
        assert!(r[0].1 .0 < 0.0);
    }

    #[test]
    fn coincident_bodies_do_not_produce_nan() {
        let r = compute(&[(1, (5.0, 5.0)), (2, (5.0, 5.0))], 40.0);
        assert!(r[0].1 .0.is_finite() && r[0].1 .1.is_finite());
    }
}

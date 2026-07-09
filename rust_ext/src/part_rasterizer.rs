use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};

// Port of scripts/visuals/MechPartRenderer.gd's finish()/_rasterize_polygon/
// _rasterize_line/_add_outline - identified as the actual hot path behind
// the enemy-spawn stutter (nested 32x32 point-in-polygon/distance-to-segment
// loops, x6 parts x several fill/line regions each, once per spawned mech -
// NOT the generate_procedural_shape() workload the original Rust POC
// targeted, which only runs for loot/Black Market, not enemy spawns).
//
// Whole rasterization batch happens in one native call and returns a single
// PackedByteArray of RGBA8 pixel data, matching Image.create()'s layout -
// GDScript just needs to build an Image/ImageTexture from the returned
// bytes instead of running the pixel loops itself. Batching into one call
// matters: per-pixel FFI round-trips would eat the whole native-speed win.

const CELL_SIZE: f32 = 3.0;
const GRID_RADIUS: i32 = 16;
const GRID_DIM: i32 = GRID_RADIUS * 2;

fn cell_to_local(gx: i32, gy: i32) -> Vector2 {
    Vector2::new((gx - GRID_RADIUS) as f32 + 0.5, (gy - GRID_RADIUS) as f32 + 0.5) * CELL_SIZE
}

// Ray-casting point-in-polygon - matches Geometry2D.is_point_in_polygon for
// the simple, non-self-intersecting polygons this renderer ever builds.
fn point_in_polygon(p: Vector2, poly: &[Vector2]) -> bool {
    let n = poly.len();
    if n < 3 {
        return false;
    }
    let mut inside = false;
    let mut j = n - 1;
    for i in 0..n {
        let vi = poly[i];
        let vj = poly[j];
        if (vi.y > p.y) != (vj.y > p.y) {
            let x_cross = (vj.x - vi.x) * (p.y - vi.y) / (vj.y - vi.y) + vi.x;
            if p.x < x_cross {
                inside = !inside;
            }
        }
        j = i;
    }
    inside
}

fn distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> f32 {
    let ab = b - a;
    let len_sq = ab.length_squared();
    if len_sq <= 0.0001 {
        return p.distance_to(a);
    }
    let t = ((p - a).dot(ab) / len_sq).clamp(0.0, 1.0);
    p.distance_to(a + ab * t)
}

fn color_to_bytes(c: Color) -> [u8; 4] {
    [
        (c.r.clamp(0.0, 1.0) * 255.0).round() as u8,
        (c.g.clamp(0.0, 1.0) * 255.0).round() as u8,
        (c.b.clamp(0.0, 1.0) * 255.0).round() as u8,
        (c.a.clamp(0.0, 1.0) * 255.0).round() as u8,
    ]
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct PartRasterizer {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for PartRasterizer {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl PartRasterizer {
    // fill_regions / line_regions are passed straight through from
    // MechPartRenderer's own _fill_regions/_line_regions arrays (same
    // Dictionary shape: {polygon, color} / {a, b, color, width}) so the
    // GDScript call site barely changes. outline_color matches the constant
    // in _add_outline(). Returns GRID_DIM*GRID_DIM*4 bytes of RGBA8 pixel
    // data, row-major, matching Image.create(GRID_DIM, GRID_DIM, false,
    // Image.FORMAT_RGBA8)'s layout.
    #[func]
    fn rasterize(
        &self,
        fill_regions: Array<Dictionary>,
        line_regions: Array<Dictionary>,
        outline_color: Color,
    ) -> PackedByteArray {
        let dim = GRID_DIM as usize;
        let mut pixels: Vec<Color> = vec![Color::from_rgba(0.0, 0.0, 0.0, 0.0); dim * dim];

        for region in fill_regions.iter_shared() {
            let polygon: PackedVector2Array = region.get("polygon").unwrap_or_default().to();
            let color: Color = region.get("color").unwrap_or_default().to();
            let poly_slice = polygon.as_slice();
            if poly_slice.len() < 3 {
                continue;
            }
            for gy in 0..GRID_DIM {
                for gx in 0..GRID_DIM {
                    let p = cell_to_local(gx, gy);
                    if point_in_polygon(p, poly_slice) {
                        pixels[(gy as usize) * dim + (gx as usize)] = color;
                    }
                }
            }
        }

        for line in line_regions.iter_shared() {
            let a: Vector2 = line.get("a").unwrap_or_default().to();
            let b: Vector2 = line.get("b").unwrap_or_default().to();
            let color: Color = line.get("color").unwrap_or_default().to();
            let width: f32 = line.get("width").map(|v| v.to()).unwrap_or(1.5);
            let half_w = (CELL_SIZE * 0.5).max(width * 0.5);
            for gy in 0..GRID_DIM {
                for gx in 0..GRID_DIM {
                    let p = cell_to_local(gx, gy);
                    if distance_to_segment(p, a, b) <= half_w {
                        pixels[(gy as usize) * dim + (gx as usize)] = color;
                    }
                }
            }
        }

        // Outline: any transparent cell orthogonally adjacent to an opaque one.
        let mut edge_cells: Vec<usize> = Vec::new();
        for gy in 0..GRID_DIM {
            for gx in 0..GRID_DIM {
                let idx = (gy as usize) * dim + (gx as usize);
                if pixels[idx].a > 0.0 {
                    continue;
                }
                let mut touches = false;
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = gx + dx;
                    let ny = gy + dy;
                    if nx < 0 || ny < 0 || nx >= GRID_DIM || ny >= GRID_DIM {
                        continue;
                    }
                    let nidx = (ny as usize) * dim + (nx as usize);
                    if pixels[nidx].a > 0.0 {
                        touches = true;
                        break;
                    }
                }
                if touches {
                    edge_cells.push(idx);
                }
            }
        }
        for idx in edge_cells {
            pixels[idx] = outline_color;
        }

        let mut bytes: Vec<u8> = Vec::with_capacity(dim * dim * 4);
        for c in pixels.iter() {
            bytes.extend_from_slice(&color_to_bytes(*c));
        }
        PackedByteArray::from(bytes.as_slice())
    }

    // Same workload as above but self-contained (builds its own synthetic
    // regions) so it can be benchmarked in isolation, matching a typical
    // real part: 3 fills + 1 line + outline.
    #[func]
    fn run_benchmark(&self, iterations: i64) -> Dictionary {
        let poly = PackedVector2Array::from(vec![
            Vector2::new(-15.0, -20.0),
            Vector2::new(15.0, -20.0),
            Vector2::new(18.0, 0.0),
            Vector2::new(12.0, 20.0),
            Vector2::new(-12.0, 20.0),
            Vector2::new(-18.0, 0.0),
        ]);
        let mut fill_regions: Array<Dictionary> = Array::new();
        for (dx, alpha) in [(0.0, 1.0), (2.0, 0.6), (-2.0, 0.8)] {
            let mut shifted = PackedVector2Array::new();
            for p in poly.as_slice() {
                shifted.push(Vector2::new(p.x + dx, p.y));
            }
            let mut d = Dictionary::new();
            d.set("polygon", shifted);
            d.set("color", Color::from_rgba(0.6, 0.7, 0.9, alpha));
            fill_regions.push(&d);
        }
        let mut line_regions: Array<Dictionary> = Array::new();
        let mut d = Dictionary::new();
        d.set("a", Vector2::new(-15.0, -20.0));
        d.set("b", Vector2::new(15.0, 20.0));
        d.set("color", Color::from_rgba(1.0, 1.0, 1.0, 1.0));
        d.set("width", 1.5f32);
        line_regions.push(&d);
        let outline = Color::from_rgba(0.05, 0.05, 0.08, 1.0);

        let start = std::time::Instant::now();
        for _ in 0..iterations {
            let _ = self.rasterize(fill_regions.clone(), line_regions.clone(), outline);
        }
        let elapsed = start.elapsed();
        let us_per_part = elapsed.as_secs_f64() * 1_000_000.0 / (iterations as f64);

        let mut result = Dictionary::new();
        result.set("elapsed_sec", elapsed.as_secs_f64());
        result.set("us_per_part", us_per_part);
        result.set("iterations", iterations);
        result
    }
}

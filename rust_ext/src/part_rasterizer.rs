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

// Kept in sync by hand with scripts/visuals/MechPartRenderer.gd's CELL_SIZE/
// LIGHT_DIR/SHADE_STRENGTH constants (light_dir() below mirrors LIGHT_DIR) -
// this is the accelerated mirror of that GDScript reference implementation,
// not an independent design.
const CELL_SIZE: f32 = 4.5;
const GRID_RADIUS: i32 = 16;
const GRID_DIM: i32 = GRID_RADIUS * 2;
const SHADE_STRENGTH: f32 = 0.3;

// fn, not a Vector2 const, since Vector2::new isn't guaranteed const-evaluable.
fn light_dir() -> Vector2 {
    Vector2::new(-0.55, -0.85)
}

// gdext 0.5's Dictionary is generic over key/value type now - VDict is the
// untyped (Variant/Variant) form matching the old Dictionary-of-anything API.
type VDict = Dictionary<Variant, Variant>;

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

// Matches Godot's Color.lightened()/darkened() exactly (move each channel
// toward white/black by `amount`) - see MechPartRenderer.gd's
// _rasterize_polygon comment for why this per-shape gradient exists instead
// of per-edge bevel detection.
fn lightened(c: Color, amount: f32) -> Color {
    Color::from_rgba(
        c.r + (1.0 - c.r) * amount,
        c.g + (1.0 - c.g) * amount,
        c.b + (1.0 - c.b) * amount,
        c.a,
    )
}

fn darkened(c: Color, amount: f32) -> Color {
    Color::from_rgba(c.r * (1.0 - amount), c.g * (1.0 - amount), c.b * (1.0 - amount), c.a)
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

// Matches Godot's own Image::set_pixel byte conversion (C++ float->int cast,
// i.e. truncation, not rounding) - confirmed by a byte-for-byte comparison
// against the GDScript rasterizer catching a mismatch here (0.05*255=12.75:
// GDScript produced 12, an earlier .round()-based version here produced 13).
fn color_to_bytes(c: Color) -> [u8; 4] {
    [
        (c.r.clamp(0.0, 1.0) * 255.0) as u8,
        (c.g.clamp(0.0, 1.0) * 255.0) as u8,
        (c.b.clamp(0.0, 1.0) * 255.0) as u8,
        (c.a.clamp(0.0, 1.0) * 255.0) as u8,
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
    // GDScript call site barely changes. Untyped Array<Variant>, not
    // Array<Dictionary> - MechPartRenderer's fields are plain `var x: Array`,
    // and Godot's typed-array marshalling requires the GDScript-side array
    // to be explicitly `Array[Dictionary]` to bind to a Rust-typed
    // Array<Dictionary> parameter; converting each element from Variant here
    // instead avoids having to retype those fields (used elsewhere too).
    // outline_color matches the constant in _add_outline(). Returns
    // GRID_DIM*GRID_DIM*4 bytes of RGBA8 pixel data, row-major, matching
    // Image.create(GRID_DIM, GRID_DIM, false, Image.FORMAT_RGBA8)'s layout.
    #[func]
    fn rasterize(
        &self,
        fill_regions: Array<Variant>,
        line_regions: Array<Variant>,
        outline_color: Color,
    ) -> PackedByteArray {
        let dim = GRID_DIM as usize;
        let mut pixels: Vec<Color> = vec![Color::from_rgba(0.0, 0.0, 0.0, 0.0); dim * dim];

        for region_variant in fill_regions.iter_shared() {
            let region: VDict = region_variant.to();
            let polygon: PackedVector2Array = region.get("polygon").unwrap_or_default().to();
            let color: Color = region.get("color").unwrap_or_default().to();
            let poly_slice = polygon.as_slice();
            if poly_slice.len() < 3 {
                continue;
            }

            let light = light_dir().normalized();
            let mut min_p = Vector2::new(f32::INFINITY, f32::INFINITY);
            let mut max_p = Vector2::new(f32::NEG_INFINITY, f32::NEG_INFINITY);
            for p in poly_slice {
                min_p.x = min_p.x.min(p.x);
                min_p.y = min_p.y.min(p.y);
                max_p.x = max_p.x.max(p.x);
                max_p.y = max_p.y.max(p.y);
            }
            let center = (min_p + max_p) * 0.5;
            let half_extent = ((max_p - min_p).length() * 0.5).max(1.0);

            for gy in 0..GRID_DIM {
                for gx in 0..GRID_DIM {
                    let p = cell_to_local(gx, gy);
                    if point_in_polygon(p, poly_slice) {
                        let t = (((p - center).dot(light)) / half_extent).clamp(-1.0, 1.0);
                        let shaded = if t > 0.0 {
                            lightened(color, SHADE_STRENGTH * t)
                        } else {
                            darkened(color, SHADE_STRENGTH * -t)
                        };
                        pixels[(gy as usize) * dim + (gx as usize)] = shaded;
                    }
                }
            }
        }

        for line_variant in line_regions.iter_shared() {
            let line: VDict = line_variant.to();
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
    fn run_benchmark(&self, iterations: i64) -> VDict {
        let poly = PackedVector2Array::from(vec![
            Vector2::new(-15.0, -20.0),
            Vector2::new(15.0, -20.0),
            Vector2::new(18.0, 0.0),
            Vector2::new(12.0, 20.0),
            Vector2::new(-12.0, 20.0),
            Vector2::new(-18.0, 0.0),
        ]);
        let mut fill_regions: Array<Variant> = Array::new();
        for (dx, alpha) in [(0.0, 1.0), (2.0, 0.6), (-2.0, 0.8)] {
            let mut shifted = PackedVector2Array::new();
            for p in poly.as_slice() {
                shifted.push(Vector2::new(p.x + dx, p.y));
            }
            let mut d = VDict::new();
            d.set("polygon", &shifted);
            d.set("color", Color::from_rgba(0.6, 0.7, 0.9, alpha));
            fill_regions.push(&d.to_variant());
        }
        let mut line_regions: Array<Variant> = Array::new();
        let mut d = VDict::new();
        d.set("a", Vector2::new(-15.0, -20.0));
        d.set("b", Vector2::new(15.0, 20.0));
        d.set("color", Color::from_rgba(1.0, 1.0, 1.0, 1.0));
        d.set("width", 1.5f32);
        line_regions.push(&d.to_variant());
        let outline = Color::from_rgba(0.05, 0.05, 0.08, 1.0);

        let start = std::time::Instant::now();
        for _ in 0..iterations {
            let _ = self.rasterize(fill_regions.clone(), line_regions.clone(), outline);
        }
        let elapsed = start.elapsed();
        let us_per_part = elapsed.as_secs_f64() * 1_000_000.0 / (iterations as f64);

        let mut result = VDict::new();
        result.set("elapsed_sec", elapsed.as_secs_f64());
        result.set("us_per_part", us_per_part);
        result.set("iterations", iterations);
        result
    }
}

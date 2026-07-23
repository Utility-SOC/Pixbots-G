use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};

// Port of scripts/core/MapGenerator.gd's _build_terrain_chunk/
// _paint_textured_tile/_get_textured_pixel_color/_get_biome_color -
// identified as the single largest confirmed map-load cost: a 400x250 tile
// Normal map paints every tile as a 4x4 grid of "fat pixel" blocks (~1.6
// million Image.fill_rect calls total, each with its own per-block color
// roll), all synchronous in MapGenerator._ready() with zero frame-yielding.
// Same batching shape as part_rasterizer.rs: one native call computes a
// whole chunk's RGBA8 pixel buffer and hands back raw bytes, so GDScript
// builds the chunk's Image/Sprite2D from one Image.create_from_data() call
// instead of running the per-block fill_rect loop itself.
//
// Texture speckling here is cosmetic noise (not gameplay-affecting, and a
// fresh map reseeds every generation anyway) - so unlike part_rasterizer.rs
// there's no requirement for this module's RNG draws to line up bit-for-bit
// with GDScript's randf() sequence. It only needs to reproduce the same
// PALETTE/threshold logic per biome/map_type so a Rust-painted map reads
// identically to a GDScript-painted one at a glance.

// Small, fast, non-cryptographic PRNG (xorshift32) - plenty for cosmetic
// per-pixel-block noise, and avoids pulling in an external `rand` crate for
// a tiny extension that otherwise has zero dependencies beyond `godot`.
struct Rng(u32);

impl Rng {
    fn new(seed: u32) -> Self {
        Rng(if seed == 0 { 0x9E3779B9 } else { seed })
    }

    fn next_u32(&mut self) -> u32 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.0 = x;
        x
    }

    // [0.0, 1.0), matching GDScript's randf() range.
    fn randf(&mut self) -> f32 {
        (self.next_u32() as f64 / (u32::MAX as f64 + 1.0)) as f32
    }
}

// Matches Godot's Color.lightened()/darkened()/lerp() exactly - see
// part_rasterizer.rs's lightened()/darkened() (same math, duplicated here
// rather than shared since these are small leaf modules with no shared-utils
// convention in this crate yet).
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

fn lerp_color(from: Color, to: Color, weight: f32) -> Color {
    Color::from_rgba(
        from.r + (to.r - from.r) * weight,
        from.g + (to.g - from.g) * weight,
        from.b + (to.b - from.b) * weight,
        from.a + (to.a - from.a) * weight,
    )
}

// Matches Godot's own Image::set_pixel byte conversion (truncating cast, not
// rounding) - see part_rasterizer.rs's color_to_bytes for the same note.
fn color_to_bytes(c: Color) -> [u8; 4] {
    [
        (c.r.clamp(0.0, 1.0) * 255.0) as u8,
        (c.g.clamp(0.0, 1.0) * 255.0) as u8,
        (c.b.clamp(0.0, 1.0) * 255.0) as u8,
        (c.a.clamp(0.0, 1.0) * 255.0) as u8,
    ]
}

fn fill_rect(pixels: &mut [Color], img_w: i32, img_h: i32, x: i32, y: i32, w: i32, h: i32, color: Color) {
    let x0 = x.max(0);
    let y0 = y.max(0);
    let x1 = (x + w).min(img_w);
    let y1 = (y + h).min(img_h);
    if x1 <= x0 || y1 <= y0 {
        return;
    }
    for py in y0..y1 {
        let row = (py as usize) * (img_w as usize);
        for px in x0..x1 {
            pixels[row + (px as usize)] = color;
        }
    }
}

// BiomeType enum order, kept in sync by hand with MapGenerator.gd's
// `enum BiomeType { GRASSLAND, WATER, DESERT, FOREST, TUNDRA, VOLCANO,
// DUNGEON }` (0..6) - same "accelerated mirror of the GDScript reference
// implementation" relationship as part_rasterizer.rs's CELL_SIZE/LIGHT_DIR.
const BIOME_GRASSLAND: i32 = 0;
const BIOME_WATER: i32 = 1;
const BIOME_DESERT: i32 = 2;
const BIOME_FOREST: i32 = 3;
const BIOME_TUNDRA: i32 = 4;
const BIOME_VOLCANO: i32 = 5;
const BIOME_DUNGEON: i32 = 6;

const GROUND_PIXEL_SIZE: i32 = 8;

// fn, not a Color const, since Color::from_rgba isn't guaranteed
// const-evaluable (same reasoning as part_rasterizer.rs's light_dir()).
fn corn_color() -> Color {
    Color::from_rgba(0.55, 0.62, 0.18, 1.0)
}

// gdext 0.5's Dictionary is generic over key/value type - VDict is the
// untyped (Variant/Variant) form, matching part_rasterizer.rs's alias.
type VDict = Dictionary<Variant, Variant>;

fn biome_color(map_type: &str, biome: i32) -> Color {
    if map_type == "Tabletop" && biome == BIOME_DESERT {
        return Color::from_rgba(0.52, 0.24, 0.16, 1.0);
    }
    if map_type == "FightShovel" && biome == BIOME_DESERT {
        return Color::from_rgba(0.62, 0.53, 0.36, 1.0);
    }
    match biome {
        BIOME_GRASSLAND => Color::from_rgba(0.4, 0.8, 0.4, 1.0),
        BIOME_WATER => Color::from_rgba(0.2, 0.4, 0.9, 1.0),
        BIOME_DESERT => Color::from_rgba(0.9, 0.8, 0.5, 1.0),
        BIOME_FOREST => Color::from_rgba(0.1, 0.5, 0.2, 1.0),
        BIOME_TUNDRA => Color::from_rgba(0.8, 0.9, 0.9, 1.0),
        BIOME_VOLCANO => Color::from_rgba(0.3, 0.1, 0.1, 1.0),
        BIOME_DUNGEON => Color::from_rgba(0.15, 0.1, 0.2, 1.0),
        _ => Color::from_rgba(0.0, 0.0, 0.0, 1.0),
    }
}

fn textured_pixel_color(rng: &mut Rng, map_type: &str, base: Color, biome: i32) -> Color {
    if map_type == "Tabletop" {
        let flock_roll = rng.randf();
        if flock_roll < 0.14 {
            return darkened(base, 0.15 + rng.randf() * 0.2);
        } else if flock_roll < 0.22 {
            return lerp_color(Color::from_rgba(0.42, 0.33, 0.26, 1.0), base, 0.4);
        } else if flock_roll < 0.27 {
            return lightened(base, 0.12 + rng.randf() * 0.1);
        }
        return darkened(base, rng.randf() * 0.06);
    }
    if map_type == "FightShovel" {
        let dust_roll = rng.randf();
        if dust_roll < 0.10 {
            return darkened(base, 0.25 + rng.randf() * 0.2);
        } else if dust_roll < 0.24 {
            return lightened(base, 0.14 + rng.randf() * 0.12);
        } else if dust_roll < 0.30 {
            return lerp_color(Color::from_rgba(0.7, 0.63, 0.5, 1.0), base, 0.35);
        }
        return darkened(base, rng.randf() * 0.05);
    }
    match biome {
        BIOME_GRASSLAND => {
            let roll = rng.randf();
            if roll < 0.22 {
                darkened(base, 0.18 + rng.randf() * 0.15)
            } else if roll < 0.34 {
                lightened(base, 0.1)
            } else {
                darkened(base, rng.randf() * 0.05)
            }
        }
        BIOME_FOREST => {
            if rng.randf() < 0.28 {
                darkened(base, 0.2 + rng.randf() * 0.15)
            } else {
                darkened(base, rng.randf() * 0.08)
            }
        }
        BIOME_DESERT => {
            let roll2 = rng.randf();
            if roll2 < 0.15 {
                darkened(base, 0.08 + rng.randf() * 0.1)
            } else if roll2 < 0.25 {
                lightened(base, 0.12)
            } else {
                darkened(base, rng.randf() * 0.04)
            }
        }
        BIOME_TUNDRA => {
            if rng.randf() < 0.12 {
                darkened(base, 0.04 + rng.randf() * 0.06)
            } else {
                lightened(base, rng.randf() * 0.05)
            }
        }
        BIOME_VOLCANO => {
            if rng.randf() < 0.15 {
                lightened(base, 0.1 + rng.randf() * 0.2)
            } else {
                darkened(base, rng.randf() * 0.1)
            }
        }
        BIOME_DUNGEON => {
            if rng.randf() < 0.2 {
                darkened(base, 0.15 + rng.randf() * 0.15)
            } else {
                darkened(base, rng.randf() * 0.06)
            }
        }
        BIOME_WATER => {
            if rng.randf() < 0.15 {
                lightened(base, 0.08 + rng.randf() * 0.1)
            } else {
                darkened(base, rng.randf() * 0.04)
            }
        }
        _ => base,
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct TerrainRasterizer {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for TerrainRasterizer {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl TerrainRasterizer {
    // biomes/obstacle_names/corn_mask are flat, row-major, chunk_w_tiles x
    // chunk_h_tiles arrays - MapGenerator.gd builds these straight from its
    // own terrain/obstacles/corn_field_cells data (see _build_terrain_chunk's
    // call site) rather than this module touching any live Godot Node, same
    // "Rust gets flat data, GDScript owns the scene tree" split as
    // RustGridSim/hexgrid_sim.rs. Returns
    // (chunk_w_tiles*tile_size)*(chunk_h_tiles*tile_size)*4 bytes of RGBA8
    // pixel data, row-major, matching Image.create()'s layout - wall-strip
    // painting and Image/Sprite2D/ImageTexture creation stay in GDScript
    // (real Godot resources, not something Rust can touch).
    #[func]
    fn rasterize_chunk(
        &self,
        biomes: PackedInt32Array,
        obstacle_names: PackedStringArray,
        corn_mask: PackedByteArray,
        chunk_w_tiles: i32,
        chunk_h_tiles: i32,
        tile_size: i32,
        map_type: GString,
        seed: i64,
    ) -> PackedByteArray {
        let map_type_str = map_type.to_string();
        let img_w = (chunk_w_tiles * tile_size).max(0);
        let img_h = (chunk_h_tiles * tile_size).max(0);
        let mut pixels: Vec<Color> =
            vec![Color::from_rgba(0.0, 0.0, 0.0, 0.0); (img_w as usize) * (img_h as usize)];
        let mut rng = Rng::new((seed as u32) ^ 0x9E3779B9);

        let blocks_per_side = (tile_size / GROUND_PIXEL_SIZE).max(1);
        let biomes_slice = biomes.as_slice();
        let obstacles_slice = obstacle_names.as_slice();
        let corn_slice = corn_mask.as_slice();
        let tiles_per_row = chunk_w_tiles as usize;

        for ty in 0..chunk_h_tiles {
            for tx in 0..chunk_w_tiles {
                let idx = (ty as usize) * tiles_per_row + (tx as usize);
                let biome = biomes_slice.get(idx).copied().unwrap_or(BIOME_GRASSLAND);
                let obstacle_name = obstacles_slice
                    .get(idx)
                    .map(|s| s.to_string())
                    .unwrap_or_default();
                let is_corn = map_type_str == "FightShovel"
                    && corn_slice.get(idx).copied().unwrap_or(0) != 0;

                let local_x = tx * tile_size;
                let local_y = ty * tile_size;

                let base = if is_corn {
                    corn_color()
                } else {
                    biome_color(&map_type_str, biome)
                };

                for by in 0..blocks_per_side {
                    for bx in 0..blocks_per_side {
                        let color = if is_corn {
                            let mut c = if bx % 2 == 0 {
                                lightened(base, 0.15)
                            } else {
                                darkened(base, 0.12)
                            };
                            if rng.randf() < 0.08 {
                                c = Color::from_rgba(0.85, 0.72, 0.25, 1.0);
                            }
                            c
                        } else {
                            textured_pixel_color(&mut rng, &map_type_str, base, biome)
                        };
                        fill_rect(
                            &mut pixels,
                            img_w,
                            img_h,
                            local_x + bx * GROUND_PIXEL_SIZE,
                            local_y + by * GROUND_PIXEL_SIZE,
                            GROUND_PIXEL_SIZE,
                            GROUND_PIXEL_SIZE,
                            color,
                        );
                    }
                }

                // Trees, RuinParts, and the DestructibleObstacle-backed flat
                // types (Boulder/Cactus/IceBoulder/LavaRock/StoneWall) have
                // real scene nodes drawing them now - only the remaining
                // flat/indestructible types (Tractor, Fence) get a painted
                // square baked into the static terrain texture, matching
                // _build_terrain_chunk's own guard.
                let is_destructible_flat = matches!(
                    obstacle_name.as_str(),
                    "Boulder" | "Cactus" | "IceBoulder" | "LavaRock" | "StoneWall"
                );
                if !obstacle_name.is_empty() && obstacle_name != "Tree" && obstacle_name != "RuinPart" && !is_destructible_flat {
                    if obstacle_name == "Tractor" {
                        let obs_color = Color::from_rgba(0.55, 0.28, 0.12, 1.0);
                        fill_rect(&mut pixels, img_w, img_h, local_x + 8, local_y + 8, tile_size - 16, tile_size - 16, obs_color);
                        let wheel = Color::from_rgba(0.15, 0.13, 0.12, 1.0);
                        fill_rect(&mut pixels, img_w, img_h, local_x + 6, local_y + tile_size - 12, 8, 8, wheel);
                        fill_rect(&mut pixels, img_w, img_h, local_x + tile_size - 14, local_y + tile_size - 12, 8, 8, wheel);
                    } else {
                        let obs_color = Color::from_rgba(0.2, 0.2, 0.2, 1.0);
                        fill_rect(&mut pixels, img_w, img_h, local_x + 8, local_y + 8, tile_size - 16, tile_size - 16, obs_color);
                    }
                }
            }
        }

        let mut bytes: Vec<u8> = Vec::with_capacity((img_w as usize) * (img_h as usize) * 4);
        for c in pixels.iter() {
            bytes.extend_from_slice(&color_to_bytes(*c));
        }
        PackedByteArray::from(bytes.as_slice())
    }

    // Isolated-workload benchmark (matches part_rasterizer.rs's
    // run_benchmark) - one synthetic 50x50-tile chunk (CHUNK_TILES from
    // MapGenerator.gd), Normal-map-shaped (no obstacles/corn), so the cost
    // of the real hot path (the fat-pixel block loop) can be measured without
    // needing a live MapGenerator/terrain grid.
    #[func]
    fn run_benchmark(&self, iterations: i64) -> VDict {
        let chunk_tiles: i32 = 50;
        let tile_size: i32 = 32;
        let mut biomes = PackedInt32Array::new();
        let mut obstacle_names = PackedStringArray::new();
        let mut corn_mask = PackedByteArray::new();
        for i in 0..(chunk_tiles * chunk_tiles) {
            biomes.push((i % 7) as i32);
            obstacle_names.push("");
            corn_mask.push(0);
        }

        let start = std::time::Instant::now();
        for i in 0..iterations {
            let _ = self.rasterize_chunk(
                biomes.clone(),
                obstacle_names.clone(),
                corn_mask.clone(),
                chunk_tiles,
                chunk_tiles,
                tile_size,
                GString::from("Normal"),
                i,
            );
        }
        let elapsed = start.elapsed();
        let us_per_chunk = elapsed.as_secs_f64() * 1_000_000.0 / (iterations as f64);

        let mut result = VDict::new();
        result.set("elapsed_sec", elapsed.as_secs_f64());
        result.set("us_per_chunk", us_per_chunk);
        result.set("iterations", iterations);
        result
    }
}

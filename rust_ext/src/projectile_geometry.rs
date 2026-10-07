use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};

type VDict = Dictionary<Variant, Variant>;

// Geometry builder for ProjectileBatchPool's FLAT atlas renderer (2026-10-07).
//
// ProjectileBatchPool._draw_atlas used to queue, per live shot, 10-15 textured quads (soft glow disc, comet
// trail, two body quads, up to two orbiting echoes or six vortex-helix quads, element dots, three sparks), each
// as draw_set_transform + draw_texture_rect_region from GDScript: ~100 ms of every second at ~600 shots on the
// HD 4000. This module builds ALL of those quads in one pass and returns plain triangle-array buffers
// (points / vertex colours / uvs / indices), which GDScript submits with one canvas_item_add_triangle_array per
// chunk. Same quads, same transforms, same colours as the GDScript path (kept as the fallback and as the parity
// reference - see ProjectileGeometryParityCheck.gd and the image diff in ProjectileGeometryImageDiff.gd).
//
// Transform note: Godot 4's draw_set_transform(pos, rot, scale) builds Transform2D(rot, scale, 0, pos), the usual
// translate * rotate * scale: the scale acts in the shape's LOCAL axes, so a beam (sx != sy) stretches along its own
// direction. (Verified against the engine by ProjectileGeometryImageDiff; an earlier draft that scaled in world axes
// visibly mis-drew every beam.)
//
// Only the FLAT render mode is handled here; the cosmetic Pie / Blend / Starburst / Rings modes stay in GDScript.
// Spark positions use a per-shot hash precomputed in GDScript at spawn (Godot's hash() is not reproduced here).

const MAX_QUADS_PER_CHUNK: usize = 14000; // 56,000 vertices, safely under a 16-bit index limit if one applies

#[derive(Default)]
struct Chunk {
    points: Vec<Vector2>,
    colors: Vec<Color>,
    uvs: Vec<Vector2>,
    indices: Vec<i32>,
    quads: usize,
}

#[derive(Clone, Copy, Default)]
struct Consts {
    glow_base_radius: f64,
    glow_scale_mult: f64,
    glow_alpha_mult: f64,
    trail_offset_px: f64,
    trail_scale_mult: f64,
    trail_alpha_mult: f64,
    echo_orbit_radius: f64,
    echo_orbit_speed: f64,
    echo_scale_mult: f64,
    vortex_helix_speed: f64,
    vortex_helix_radius: f64,
    extra_ring_units: f64,
    spark_count: i64,
    spark_min_dist: f64,
    spark_max_dist: f64,
    spark_jitter_perp: f64,
    spark_base_radius: f64,
    spark_alpha_mult: f64,
    spark_refresh: f64,
    cell_beam: usize,
    cell_disc: usize,
    cell_comet_fire: usize,
    cell_comet_kinetic: usize,
    syn_fire: i64,
    syn_kinetic: i64,
    syn_vortex: i64,
    syn_pierce: i64,
    no_synergy: i64,
    helix0: usize,
    helix1: usize,
    helix2: usize,
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ProjectileGeometry {
    base: Base<RefCounted>,
    c: Consts,
    units: Vec<[f32; 4]>, // atlas cell destination rects (x, y, w, h) in world units
    px: Vec<[f32; 4]>,    // atlas cell source rects in texels
    atlas_w: f32,
    atlas_h: f32,
    echo_colors: Vec<Color>,
    vortex_color: Color,
    count: usize,
    chunks: Vec<Chunk>,
    // Snapshot taken by load_a() (the binding layer limits a method's argument count, so build() is split in two).
    s_alive: Vec<u8>,
    s_syn: Vec<u8>,
    s_dir: Vec<Vector2>,
    s_pos: Vec<Vector2>,
    s_off: Vec<Vector2>,
    s_scale: Vec<f32>,
    s_color: Vec<Color>,
}

#[godot_api]
impl IRefCounted for ProjectileGeometry {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            c: Consts::default(),
            units: Vec::new(),
            px: Vec::new(),
            atlas_w: 1.0,
            atlas_h: 1.0,
            echo_colors: Vec::new(),
            vortex_color: Color::WHITE,
            count: 0,
            chunks: Vec::new(),
            s_alive: Vec::new(),
            s_syn: Vec::new(),
            s_dir: Vec::new(),
            s_pos: Vec::new(),
            s_off: Vec::new(),
            s_scale: Vec::new(),
            s_color: Vec::new(),
        }
    }
}

fn get_f(d: &VDict, k: &str) -> f64 {
    d.get(k).and_then(|v| v.try_to::<f64>().ok()).unwrap_or(0.0)
}

fn get_i(d: &VDict, k: &str) -> i64 {
    d.get(k).and_then(|v| v.try_to::<i64>().ok()).unwrap_or(0)
}

fn rects_from_flat(flat: &[f32]) -> Vec<[f32; 4]> {
    flat.chunks_exact(4).map(|c| [c[0], c[1], c[2], c[3]]).collect()
}

#[godot_api]
impl ProjectileGeometry {
    /// consts: scalar tuning constants and atlas cell ids (see ProjectileBatchPool._ensure_geometry).
    /// units / px: four floats per atlas cell. atlas_size: texture size in texels.
    #[func]
    fn configure(
        &mut self,
        consts: VDict,
        units: PackedFloat32Array,
        px: PackedFloat32Array,
        atlas_size: Vector2,
        echo_colors: PackedColorArray,
        vortex_color: Color,
    ) {
        self.c = Consts {
            glow_base_radius: get_f(&consts, "glow_base_radius"),
            glow_scale_mult: get_f(&consts, "glow_scale_mult"),
            glow_alpha_mult: get_f(&consts, "glow_alpha_mult"),
            trail_offset_px: get_f(&consts, "trail_offset_px"),
            trail_scale_mult: get_f(&consts, "trail_scale_mult"),
            trail_alpha_mult: get_f(&consts, "trail_alpha_mult"),
            echo_orbit_radius: get_f(&consts, "echo_orbit_radius"),
            echo_orbit_speed: get_f(&consts, "echo_orbit_speed"),
            echo_scale_mult: get_f(&consts, "echo_scale_mult"),
            vortex_helix_speed: get_f(&consts, "vortex_helix_speed"),
            vortex_helix_radius: get_f(&consts, "vortex_helix_radius"),
            extra_ring_units: get_f(&consts, "extra_ring_units"),
            spark_count: get_i(&consts, "spark_count"),
            spark_min_dist: get_f(&consts, "spark_min_dist"),
            spark_max_dist: get_f(&consts, "spark_max_dist"),
            spark_jitter_perp: get_f(&consts, "spark_jitter_perp"),
            spark_base_radius: get_f(&consts, "spark_base_radius"),
            spark_alpha_mult: get_f(&consts, "spark_alpha_mult"),
            spark_refresh: get_f(&consts, "spark_refresh"),
            cell_beam: get_i(&consts, "cell_beam") as usize,
            cell_disc: get_i(&consts, "cell_disc") as usize,
            cell_comet_fire: get_i(&consts, "cell_comet_fire") as usize,
            cell_comet_kinetic: get_i(&consts, "cell_comet_kinetic") as usize,
            syn_fire: get_i(&consts, "syn_fire"),
            syn_kinetic: get_i(&consts, "syn_kinetic"),
            syn_vortex: get_i(&consts, "syn_vortex"),
            syn_pierce: get_i(&consts, "syn_pierce"),
            no_synergy: get_i(&consts, "no_synergy"),
            helix0: get_i(&consts, "helix0") as usize,
            helix1: get_i(&consts, "helix1") as usize,
            helix2: get_i(&consts, "helix2") as usize,
        };
        self.units = rects_from_flat(units.as_slice());
        self.px = rects_from_flat(px.as_slice());
        self.atlas_w = atlas_size.x.max(1.0);
        self.atlas_h = atlas_size.y.max(1.0);
        self.echo_colors = echo_colors.as_slice().to_vec();
        self.vortex_color = vortex_color;
    }

    /// How many slots (highest active index + 1) the next build() should scan.
    #[func]
    fn set_count(&mut self, n: i64) {
        self.count = n.max(0) as usize;
    }

    /// Step 1 of 2: snapshot the per-slot arrays that describe where each shot is (first `count` slots only).
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn load_a(
        &mut self,
        alive: PackedByteArray,
        syn: PackedByteArray,
        direction: PackedVector2Array,
        position: PackedVector2Array,
        visual_offset: PackedVector2Array,
        scale: PackedFloat32Array,
        color: PackedColorArray,
    ) {
        let n = self.count.min(alive.len());
        self.s_alive = alive.as_slice()[..n].to_vec();
        self.s_syn = syn.as_slice()[..n].to_vec();
        self.s_dir = direction.as_slice()[..n].to_vec();
        self.s_pos = position.as_slice()[..n].to_vec();
        self.s_off = visual_offset.as_slice()[..n].to_vec();
        self.s_scale = scale.as_slice()[..n].to_vec();
        self.s_color = color.as_slice()[..n].to_vec();
    }

    /// Step 2 of 2: builds every quad for the live shots. Returns the number of quads. Arrays are indexed by pool slot.
    #[func]
    #[allow(clippy::too_many_arguments)]
    fn build(
        &mut self,
        elapsed: PackedFloat32Array,
        lifetime: PackedFloat32Array,
        is_beam: PackedByteArray,
        speed: PackedFloat32Array,
        sec1: PackedByteArray,
        sec2: PackedByteArray,
        extra_mask: PackedInt32Array,
        spark_hash: PackedInt64Array,
    ) -> i64 {
        let (elapsed, lifetime, is_beam, speed) = (elapsed.as_slice(), lifetime.as_slice(), is_beam.as_slice(), speed.as_slice());
        let (sec1, sec2, extra_mask, spark_hash) = (sec1.as_slice(), sec2.as_slice(), extra_mask.as_slice(), spark_hash.as_slice());
        let alive = std::mem::take(&mut self.s_alive);
        let syn = std::mem::take(&mut self.s_syn);
        let direction = std::mem::take(&mut self.s_dir);
        let position = std::mem::take(&mut self.s_pos);
        let visual_offset = std::mem::take(&mut self.s_off);
        let scale = std::mem::take(&mut self.s_scale);
        let color = std::mem::take(&mut self.s_color);

        self.chunks.clear();
        self.chunks.push(Chunk::default());
        let n = alive.len();
        let c = self.c;
        let total_quads: i64;

        for i in 0..n {
            if alive[i] == 0 {
                continue;
            }
            let syn_i = syn[i] as i64;
            if syn_i >= 10 {
                continue;
            }
            let dir = direction[i];
            let rot = (dir.y as f64).atan2(dir.x as f64);
            let rp = position[i] + visual_offset[i];
            let sc = scale[i] as f64;
            let mut col = color[i];
            let life = lifetime[i] as f64;
            let el = elapsed[i] as f64;
            let a = 1.0 - if life > 0.0 { (el / life).clamp(0.0, 1.0) } else { 0.0 };
            col.a = a as f32;
            let beam = is_beam[i] == 1;

            if !beam {
                let mut gc = col;
                gc.a = (a * c.glow_alpha_mult) as f32;
                let gs = c.glow_base_radius * sc * c.glow_scale_mult / 8.0;
                self.quad(c.cell_disc, rp, 0.0, gs, gs, gc);
            }

            let mut tc = col;
            tc.a = (a * c.trail_alpha_mult) as f32;
            let trail_cell = if syn_i == c.syn_fire {
                c.cell_comet_fire
            } else if syn_i == c.syn_kinetic {
                c.cell_comet_kinetic
            } else {
                syn_i as usize
            };
            let trail_pos = rp - dir * (c.trail_offset_px as f32);
            self.quad(trail_cell, trail_pos, rot, sc * c.trail_scale_mult, sc * c.trail_scale_mult, tc);

            let body = if beam { c.cell_beam } else { syn_i as usize };
            let sx = sc * if beam { ((speed[i] as f64) / 500.0).clamp(1.0, 3.0) } else { 1.0 };
            self.quad(body, rp, rot, sx, sc, col);
            self.quad(body, rp, rot, sx * 0.5, sc * 0.5, col);

            if syn_i == c.syn_vortex {
                let mut vc = self.vortex_color;
                vc.a = a as f32;
                let third = std::f64::consts::TAU / 3.0;
                let channels = [c.helix0, c.helix1, c.helix2];
                for orb in 0..3 {
                    let ang = el * c.vortex_helix_speed + (orb as f64) * third;
                    let op = rp + Vector2::new(ang.cos() as f32, ang.sin() as f32) * (c.vortex_helix_radius as f32);
                    let cell = channels[orb];
                    self.quad(cell, op, rot, sc * c.echo_scale_mult, sc * c.echo_scale_mult, vc);
                    self.quad(cell, op, rot, sc * c.echo_scale_mult * 0.5, sc * c.echo_scale_mult * 0.5, vc);
                }
            } else {
                let s1 = sec1[i] as i64;
                if s1 != c.no_synergy && s1 >= 0 && (s1 as usize) < self.echo_colors.len() {
                    let (ec, ep);
                    if s1 == c.syn_pierce {
                        ec = Color::from_rgba(1.0, 1.0, 1.0, (a * 0.8) as f32);
                        ep = rp;
                    } else {
                        let mut e = self.echo_colors[s1 as usize];
                        e.a = a as f32;
                        ec = e;
                        let ang1 = el * c.echo_orbit_speed;
                        ep = rp + Vector2::new(ang1.cos() as f32, ang1.sin() as f32) * (c.echo_orbit_radius as f32);
                    }
                    self.quad(s1 as usize, ep, rot, sc * c.echo_scale_mult, sc * c.echo_scale_mult, ec);
                    self.quad(s1 as usize, ep, rot, sc * c.echo_scale_mult * 0.5, sc * c.echo_scale_mult * 0.5, ec);
                }
                let s2 = sec2[i] as i64;
                if s2 != c.no_synergy && s2 >= 0 && (s2 as usize) < self.echo_colors.len() {
                    let (ec2, ep2);
                    if s2 == c.syn_pierce {
                        ec2 = Color::from_rgba(1.0, 1.0, 1.0, (a * 0.8) as f32);
                        ep2 = rp;
                    } else {
                        let mut e = self.echo_colors[s2 as usize];
                        e.a = a as f32;
                        ec2 = e;
                        let ang2 = el * c.echo_orbit_speed + std::f64::consts::PI;
                        ep2 = rp + Vector2::new(ang2.cos() as f32, ang2.sin() as f32) * (c.echo_orbit_radius as f32);
                    }
                    let cell2 = if s2 == c.syn_fire {
                        c.cell_comet_fire
                    } else if s2 == c.syn_kinetic {
                        c.cell_comet_kinetic
                    } else {
                        s2 as usize
                    };
                    self.quad(cell2, ep2, rot, sc * c.echo_scale_mult, sc * c.echo_scale_mult, ec2);
                }
            }

            let xm = extra_mask[i];
            if xm != 0 && !beam {
                let mut n_extra = 0;
                for e in 1..10 {
                    if xm & (1 << e) != 0 {
                        n_extra += 1;
                    }
                }
                let ring_r = c.extra_ring_units.max(7.0 * sc);
                let dot = 0.32 * 1.0_f64.max(sc.sqrt());
                let mut k_extra = 0;
                for e in 1..10usize {
                    if xm & (1 << e) != 0 {
                        let ang_e = el * 3.4 + std::f64::consts::TAU * (k_extra as f64) / (n_extra as f64);
                        if e < self.echo_colors.len() {
                            let mut dc = self.echo_colors[e];
                            dc.a = (a * 0.95) as f32;
                            let p = rp + Vector2::new(ang_e.cos() as f32, ang_e.sin() as f32) * (ring_r as f32);
                            self.quad(c.cell_disc, p, 0.0, dot, dot, dc);
                        }
                        k_extra += 1;
                    }
                }
            }

            if !beam {
                let ortho = Vector2::new(-dir.y, dir.x);
                let bucket = (el / c.spark_refresh) as i64;
                let gen_hash = spark_hash[i];
                for sk in 0..c.spark_count {
                    let seed = gen_hash ^ (sk * 7919) ^ bucket;
                    let trail_t = ((seed.wrapping_abs() % 1000) as f64) / 1000.0;
                    let perp_t = (((seed ^ 0x5bd1e995).wrapping_abs() % 2000) as f64) / 1000.0 - 1.0;
                    let dist = c.spark_min_dist + trail_t * (c.spark_max_dist - c.spark_min_dist);
                    let mut spc = col;
                    spc.a = (a * c.spark_alpha_mult * (1.0 - trail_t * 0.5)) as f32;
                    let ss = c.spark_base_radius * sc / 8.0;
                    let sp = rp - dir * (dist as f32) + ortho * ((perp_t * c.spark_jitter_perp) as f32);
                    self.quad(c.cell_disc, sp, 0.0, ss, ss, spc);
                }
            }
        }
        total_quads = self.chunks.iter().map(|ch| ch.quads as i64).sum();
        total_quads
    }

    #[func]
    fn chunk_count(&self) -> i64 {
        self.chunks.iter().filter(|c| c.quads > 0).count() as i64
    }

    #[func]
    fn chunk_points(&self, i: i64) -> PackedVector2Array {
        PackedVector2Array::from(self.chunks[i as usize].points.as_slice())
    }

    #[func]
    fn chunk_colors(&self, i: i64) -> PackedColorArray {
        PackedColorArray::from(self.chunks[i as usize].colors.as_slice())
    }

    #[func]
    fn chunk_uvs(&self, i: i64) -> PackedVector2Array {
        PackedVector2Array::from(self.chunks[i as usize].uvs.as_slice())
    }

    #[func]
    fn chunk_indices(&self, i: i64) -> PackedInt32Array {
        PackedInt32Array::from(self.chunks[i as usize].indices.as_slice())
    }
}

impl ProjectileGeometry {
    /// One textured quad: atlas `cell` drawn at `pos` with rotation `rot` and scale (sx, sy), tinted `col`.
    fn quad(&mut self, cell: usize, pos: Vector2, rot: f64, sx: f64, sy: f64, col: Color) {
        if cell >= self.units.len() || cell >= self.px.len() {
            return;
        }
        let u = self.units[cell];
        let p = self.px[cell];
        let (sr, cr) = rot.sin_cos();
        // Transform2D(rot, scale, 0, pos): column0 = (cos*sx, sin*sx), column1 = (-sin*sy, cos*sy).
        let c0 = Vector2::new((cr * sx) as f32, (sr * sx) as f32);
        let c1 = Vector2::new((-sr * sy) as f32, (cr * sy) as f32);
        let corners = [
            (u[0], u[1], p[0], p[1]),
            (u[0] + u[2], u[1], p[0] + p[2], p[1]),
            (u[0] + u[2], u[1] + u[3], p[0] + p[2], p[1] + p[3]),
            (u[0], u[1] + u[3], p[0], p[1] + p[3]),
        ];
        if self.chunks.last().map(|c| c.quads >= MAX_QUADS_PER_CHUNK).unwrap_or(true) {
            self.chunks.push(Chunk::default());
        }
        let (aw, ah) = (self.atlas_w, self.atlas_h);
        let ch = self.chunks.last_mut().unwrap();
        let base = ch.points.len() as i32;
        for (dx, dy, tx, ty) in corners {
            ch.points.push(pos + c0 * dx + c1 * dy);
            ch.colors.push(col);
            ch.uvs.push(Vector2::new(tx / aw, ty / ah));
        }
        ch.indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
        ch.quads += 1;
    }
}

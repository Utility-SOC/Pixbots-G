//! Projectile quad geometry: turns the projectile pool's per-slot state arrays into textured-quad triangle buffers.
//!
//! This is the maths that ProjectileBatchPool._draw_atlas used to run in GDScript (10-15 `draw_texture_rect_region`
//! calls per shot). It is a pure function of its inputs: slices in, `Chunk` buffers out, no engine types.
//!
//! Transform convention (matches Godot 4's `draw_set_transform(pos, rot, scale)` = Transform2D(rot, scale, 0, pos)):
//! x axis = (cos r * sx, sin r * sx), y axis = (-sin r * sy, cos r * sy), i.e. translate * rotate * scale, so a stretched
//! shape (a beam, sx != sy) stretches along its own direction.

use std::f64::consts::{PI, TAU};
use std::ops::{Add, Mul, Sub};

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct V2 {
    pub x: f32,
    pub y: f32,
}

impl V2 {
    pub const fn new(x: f32, y: f32) -> Self {
        Self { x, y }
    }
}
impl Add for V2 {
    type Output = V2;
    fn add(self, o: V2) -> V2 {
        V2::new(self.x + o.x, self.y + o.y)
    }
}
impl Sub for V2 {
    type Output = V2;
    fn sub(self, o: V2) -> V2 {
        V2::new(self.x - o.x, self.y - o.y)
    }
}
impl Mul<f32> for V2 {
    type Output = V2;
    fn mul(self, s: f32) -> V2 {
        V2::new(self.x * s, self.y * s)
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgba {
    pub r: f32,
    pub g: f32,
    pub b: f32,
    pub a: f32,
}

impl Rgba {
    pub const WHITE: Rgba = Rgba { r: 1.0, g: 1.0, b: 1.0, a: 1.0 };
    pub const fn new(r: f32, g: f32, b: f32, a: f32) -> Self {
        Self { r, g, b, a }
    }
}

/// Tuning constants and atlas cell ids (all supplied by the caller; see ProjectileBatchPool._ensure_geometry).
#[derive(Clone, Copy, Debug, Default)]
pub struct Consts {
    pub glow_base_radius: f64,
    pub glow_scale_mult: f64,
    pub glow_alpha_mult: f64,
    pub trail_offset_px: f64,
    pub trail_scale_mult: f64,
    pub trail_alpha_mult: f64,
    pub echo_orbit_radius: f64,
    pub echo_orbit_speed: f64,
    pub echo_scale_mult: f64,
    pub vortex_helix_speed: f64,
    pub vortex_helix_radius: f64,
    pub extra_ring_units: f64,
    pub spark_count: i64,
    pub spark_min_dist: f64,
    pub spark_max_dist: f64,
    pub spark_jitter_perp: f64,
    pub spark_base_radius: f64,
    pub spark_alpha_mult: f64,
    pub spark_refresh: f64,
    pub cell_beam: usize,
    pub cell_disc: usize,
    pub cell_comet_fire: usize,
    pub cell_comet_kinetic: usize,
    pub syn_fire: i64,
    pub syn_kinetic: i64,
    pub syn_vortex: i64,
    pub syn_pierce: i64,
    pub no_synergy: i64,
    pub helix: [usize; 3],
}

/// Atlas layout: per cell a destination rect in world units and a source rect in texels, both (x, y, w, h).
#[derive(Clone, Debug, Default)]
pub struct Atlas {
    pub units: Vec<[f32; 4]>,
    pub px: Vec<[f32; 4]>,
    pub width: f32,
    pub height: f32,
    pub echo_colors: Vec<Rgba>,
    pub vortex_color: Rgba,
}

impl Default for Rgba {
    fn default() -> Self {
        Rgba::WHITE
    }
}

/// The pool's per-slot state, indexed by slot. All slices cover the same `len()` slots.
pub struct ShotArrays<'a> {
    pub alive: &'a [u8],
    pub syn: &'a [u8],
    pub direction: &'a [V2],
    pub position: &'a [V2],
    pub visual_offset: &'a [V2],
    pub scale: &'a [f32],
    pub color: &'a [Rgba],
    pub elapsed: &'a [f32],
    pub lifetime: &'a [f32],
    pub is_beam: &'a [u8],
    pub speed: &'a [f32],
    pub sec1: &'a [u8],
    pub sec2: &'a [u8],
    pub extra_mask: &'a [i32],
    pub spark_hash: &'a [i64],
}

/// One draw batch of up to `MAX_QUADS_PER_CHUNK` quads (4 vertices, 6 indices each).
#[derive(Default, Debug)]
pub struct Chunk {
    pub points: Vec<V2>,
    pub colors: Vec<Rgba>,
    pub uvs: Vec<V2>,
    pub indices: Vec<i32>,
    pub quads: usize,
}

/// 56,000 vertices per chunk: comfortably below a 16-bit index limit if the renderer has one.
pub const MAX_QUADS_PER_CHUNK: usize = 14000;

#[derive(Default)]
pub struct GeometryBuilder {
    pub consts: Consts,
    pub atlas: Atlas,
    pub chunks: Vec<Chunk>,
}

impl GeometryBuilder {
    /// Builds every quad for the first `count` slots; returns the total number of quads.
    pub fn build(&mut self, shots: &ShotArrays, count: usize) -> usize {
        self.chunks.clear();
        self.chunks.push(Chunk::default());
        let n = count.min(shots.alive.len());
        let c = self.consts;

        for i in 0..n {
            if shots.alive[i] == 0 {
                continue;
            }
            let syn_i = shots.syn[i] as i64;
            if syn_i >= 10 {
                continue;
            }
            let dir = shots.direction[i];
            let rot = (dir.y as f64).atan2(dir.x as f64);
            let rp = shots.position[i] + shots.visual_offset[i];
            let sc = shots.scale[i] as f64;
            let mut col = shots.color[i];
            let life = shots.lifetime[i] as f64;
            let el = shots.elapsed[i] as f64;
            let a = 1.0 - if life > 0.0 { (el / life).clamp(0.0, 1.0) } else { 0.0 };
            col.a = a as f32;
            let beam = shots.is_beam[i] == 1;

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
            let sx = sc * if beam { ((shots.speed[i] as f64) / 500.0).clamp(1.0, 3.0) } else { 1.0 };
            self.quad(body, rp, rot, sx, sc, col);
            self.quad(body, rp, rot, sx * 0.5, sc * 0.5, col);

            if syn_i == c.syn_vortex {
                let mut vc = self.atlas.vortex_color;
                vc.a = a as f32;
                let third = TAU / 3.0;
                for orb in 0..3 {
                    let ang = el * c.vortex_helix_speed + (orb as f64) * third;
                    let op = rp + V2::new(ang.cos() as f32, ang.sin() as f32) * (c.vortex_helix_radius as f32);
                    let cell = c.helix[orb];
                    self.quad(cell, op, rot, sc * c.echo_scale_mult, sc * c.echo_scale_mult, vc);
                    self.quad(cell, op, rot, sc * c.echo_scale_mult * 0.5, sc * c.echo_scale_mult * 0.5, vc);
                }
            } else {
                let s1 = shots.sec1[i] as i64;
                if s1 != c.no_synergy && s1 >= 0 && (s1 as usize) < self.atlas.echo_colors.len() {
                    let (ec, ep);
                    if s1 == c.syn_pierce {
                        ec = Rgba::new(1.0, 1.0, 1.0, (a * 0.8) as f32);
                        ep = rp;
                    } else {
                        let mut e = self.atlas.echo_colors[s1 as usize];
                        e.a = a as f32;
                        ec = e;
                        let ang1 = el * c.echo_orbit_speed;
                        ep = rp + V2::new(ang1.cos() as f32, ang1.sin() as f32) * (c.echo_orbit_radius as f32);
                    }
                    self.quad(s1 as usize, ep, rot, sc * c.echo_scale_mult, sc * c.echo_scale_mult, ec);
                    self.quad(s1 as usize, ep, rot, sc * c.echo_scale_mult * 0.5, sc * c.echo_scale_mult * 0.5, ec);
                }
                let s2 = shots.sec2[i] as i64;
                if s2 != c.no_synergy && s2 >= 0 && (s2 as usize) < self.atlas.echo_colors.len() {
                    let (ec2, ep2);
                    if s2 == c.syn_pierce {
                        ec2 = Rgba::new(1.0, 1.0, 1.0, (a * 0.8) as f32);
                        ep2 = rp;
                    } else {
                        let mut e = self.atlas.echo_colors[s2 as usize];
                        e.a = a as f32;
                        ec2 = e;
                        let ang2 = el * c.echo_orbit_speed + PI;
                        ep2 = rp + V2::new(ang2.cos() as f32, ang2.sin() as f32) * (c.echo_orbit_radius as f32);
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

            let xm = shots.extra_mask[i];
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
                        let ang_e = el * 3.4 + TAU * (k_extra as f64) / (n_extra as f64);
                        if e < self.atlas.echo_colors.len() {
                            let mut dc = self.atlas.echo_colors[e];
                            dc.a = (a * 0.95) as f32;
                            let p = rp + V2::new(ang_e.cos() as f32, ang_e.sin() as f32) * (ring_r as f32);
                            self.quad(c.cell_disc, p, 0.0, dot, dot, dc);
                        }
                        k_extra += 1;
                    }
                }
            }

            if !beam {
                let ortho = V2::new(-dir.y, dir.x);
                let bucket = (el / c.spark_refresh) as i64;
                let gen_hash = shots.spark_hash[i];
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
        self.chunks.iter().map(|ch| ch.quads).sum()
    }

    /// One textured quad: atlas `cell` drawn at `pos` with rotation `rot` and scale (sx, sy), tinted `col`.
    fn quad(&mut self, cell: usize, pos: V2, rot: f64, sx: f64, sy: f64, col: Rgba) {
        if cell >= self.atlas.units.len() || cell >= self.atlas.px.len() {
            return;
        }
        let u = self.atlas.units[cell];
        let p = self.atlas.px[cell];
        let (sr, cr) = rot.sin_cos();
        let c0 = V2::new((cr * sx) as f32, (sr * sx) as f32);
        let c1 = V2::new((-sr * sy) as f32, (cr * sy) as f32);
        let corners = [
            (u[0], u[1], p[0], p[1]),
            (u[0] + u[2], u[1], p[0] + p[2], p[1]),
            (u[0] + u[2], u[1] + u[3], p[0] + p[2], p[1] + p[3]),
            (u[0], u[1] + u[3], p[0], p[1] + p[3]),
        ];
        if self.chunks.last().map(|c| c.quads >= MAX_QUADS_PER_CHUNK).unwrap_or(true) {
            self.chunks.push(Chunk::default());
        }
        let (aw, ah) = (self.atlas.width.max(1.0), self.atlas.height.max(1.0));
        let ch = self.chunks.last_mut().unwrap();
        let base = ch.points.len() as i32;
        for (dx, dy, tx, ty) in corners {
            ch.points.push(pos + c0 * dx + c1 * dy);
            ch.colors.push(col);
            ch.uvs.push(V2::new(tx / aw, ty / ah));
        }
        ch.indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
        ch.quads += 1;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const DISC: usize = 11;
    const BEAM: usize = 10;

    fn test_consts() -> Consts {
        Consts {
            glow_base_radius: 7.0,
            glow_scale_mult: 1.8,
            glow_alpha_mult: 0.22,
            trail_offset_px: 14.0,
            trail_scale_mult: 0.55,
            trail_alpha_mult: 0.35,
            echo_orbit_radius: 16.0,
            echo_orbit_speed: 8.0,
            echo_scale_mult: 0.4,
            vortex_helix_speed: 15.0,
            vortex_helix_radius: 8.0,
            extra_ring_units: 13.0,
            spark_count: 3,
            spark_min_dist: 10.0,
            spark_max_dist: 28.0,
            spark_jitter_perp: 6.0,
            spark_base_radius: 1.6,
            spark_alpha_mult: 0.6,
            spark_refresh: 0.06,
            cell_beam: BEAM,
            cell_disc: DISC,
            cell_comet_fire: 12,
            cell_comet_kinetic: 13,
            syn_fire: 1,
            syn_kinetic: 7,
            syn_vortex: 4,
            syn_pierce: 8,
            no_synergy: 255,
            helix: [0, 6, 8],
        }
    }

    fn test_atlas() -> Atlas {
        // 14 cells; cell i is a 28x28 world-unit square at texel (i*30, 0), 30x30 texels, in a 512x64 atlas.
        let units = (0..14).map(|_| [-14.0, -14.0, 28.0, 28.0]).collect();
        let px = (0..14).map(|i| [i as f32 * 30.0, 0.0, 30.0, 30.0]).collect();
        Atlas {
            units,
            px,
            width: 512.0,
            height: 64.0,
            echo_colors: (0..10).map(|i| Rgba::new(i as f32 / 10.0, 0.5, 0.5, 1.0)).collect(),
            vortex_color: Rgba::new(0.3, 0.2, 0.9, 1.0),
        }
    }

    /// Owned per-slot arrays for tests, with a helper to borrow them as ShotArrays.
    struct Shots {
        alive: Vec<u8>,
        syn: Vec<u8>,
        direction: Vec<V2>,
        position: Vec<V2>,
        visual_offset: Vec<V2>,
        scale: Vec<f32>,
        color: Vec<Rgba>,
        elapsed: Vec<f32>,
        lifetime: Vec<f32>,
        is_beam: Vec<u8>,
        speed: Vec<f32>,
        sec1: Vec<u8>,
        sec2: Vec<u8>,
        extra_mask: Vec<i32>,
        spark_hash: Vec<i64>,
    }

    impl Shots {
        fn new() -> Self {
            Shots { alive: vec![], syn: vec![], direction: vec![], position: vec![], visual_offset: vec![], scale: vec![], color: vec![],
                elapsed: vec![], lifetime: vec![], is_beam: vec![], speed: vec![], sec1: vec![], sec2: vec![], extra_mask: vec![], spark_hash: vec![] }
        }
        fn push(&mut self, syn: u8, dir: V2, pos: V2, scale: f32, beam: bool, sec1: u8, sec2: u8, extra: i32) {
            self.alive.push(1);
            self.syn.push(syn);
            self.direction.push(dir);
            self.position.push(pos);
            self.visual_offset.push(V2::default());
            self.scale.push(scale);
            self.color.push(Rgba::new(1.0, 0.5, 0.25, 1.0));
            self.elapsed.push(0.5);
            self.lifetime.push(2.0);
            self.is_beam.push(beam as u8);
            self.speed.push(800.0);
            self.sec1.push(sec1);
            self.sec2.push(sec2);
            self.extra_mask.push(extra);
            self.spark_hash.push(123456789);
        }
        fn arrays(&self) -> ShotArrays<'_> {
            ShotArrays { alive: &self.alive, syn: &self.syn, direction: &self.direction, position: &self.position,
                visual_offset: &self.visual_offset, scale: &self.scale, color: &self.color, elapsed: &self.elapsed,
                lifetime: &self.lifetime, is_beam: &self.is_beam, speed: &self.speed, sec1: &self.sec1, sec2: &self.sec2,
                extra_mask: &self.extra_mask, spark_hash: &self.spark_hash }
        }
    }

    fn builder() -> GeometryBuilder {
        GeometryBuilder { consts: test_consts(), atlas: test_atlas(), chunks: vec![] }
    }

    #[test]
    fn plain_shot_is_glow_trail_two_bodies_and_three_sparks() {
        let mut s = Shots::new();
        s.push(2, V2::new(1.0, 0.0), V2::new(100.0, 50.0), 1.0, false, 255, 255, 0);
        let mut b = builder();
        assert_eq!(b.build(&s.arrays(), 1), 7); // glow + trail + 2 body + 3 sparks
    }

    #[test]
    fn beam_has_no_glow_and_no_sparks() {
        let mut s = Shots::new();
        s.push(3, V2::new(1.0, 0.0), V2::new(0.0, 0.0), 2.0, true, 255, 255, 0);
        let mut b = builder();
        assert_eq!(b.build(&s.arrays(), 1), 3); // trail + 2 body
    }

    #[test]
    fn vortex_gets_a_six_quad_helix_instead_of_echoes() {
        let mut s = Shots::new();
        s.push(4, V2::new(0.0, 1.0), V2::new(0.0, 0.0), 1.0, false, 6, 8, 0); // secondaries ignored for vortex
        let mut b = builder();
        assert_eq!(b.build(&s.arrays(), 1), 7 + 6); // plain shot + helix
    }

    #[test]
    fn echoes_and_extra_dots_add_up() {
        let mut s = Shots::new();
        // two secondaries (2 quads + 1 quad) and three extra-element dots (bits 2, 5, 9)
        s.push(1, V2::new(1.0, 0.0), V2::new(0.0, 0.0), 1.0, false, 3, 7, (1 << 2) | (1 << 5) | (1 << 9));
        let mut b = builder();
        assert_eq!(b.build(&s.arrays(), 1), 7 + 3 + 3);
    }

    #[test]
    fn dead_and_out_of_range_slots_are_skipped() {
        let mut s = Shots::new();
        s.push(2, V2::new(1.0, 0.0), V2::new(0.0, 0.0), 1.0, false, 255, 255, 0);
        s.alive[0] = 0;
        s.push(10, V2::new(1.0, 0.0), V2::new(0.0, 0.0), 1.0, false, 255, 255, 0); // synergy id out of range
        s.push(2, V2::new(1.0, 0.0), V2::new(0.0, 0.0), 1.0, false, 255, 255, 0);
        let mut b = builder();
        assert_eq!(b.build(&s.arrays(), 3), 7); // only the third slot
        assert_eq!(b.build(&s.arrays(), 2), 0); // count limits the scan
    }

    #[test]
    fn body_quad_is_rotated_scaled_and_uv_mapped() {
        // A body quad (index 2 in a plain shot's emission order: glow, trail, body) for a shot facing +y.
        let mut s = Shots::new();
        s.push(2, V2::new(0.0, 1.0), V2::new(10.0, 20.0), 2.0, false, 255, 255, 0);
        let mut b = builder();
        b.build(&s.arrays(), 1);
        let ch = &b.chunks[0];
        let q = 2; // glow = 0, trail = 1, body = 2
        // rot = +90 degrees, scale (2, 2): corner (-14,-14) -> pos + R*S*(-14,-14) = (10,20) + (28, -28)
        let p0 = ch.points[q * 4];
        assert!((p0.x - 38.0).abs() < 1e-3 && (p0.y - (-8.0)).abs() < 1e-3, "got {:?}", p0);
        // uv of corner 0 is the source rect origin: cell 2 -> texel (60, 0) in a 512x64 atlas
        let uv0 = ch.uvs[q * 4];
        assert!((uv0.x - 60.0 / 512.0).abs() < 1e-6 && uv0.y.abs() < 1e-6);
        // far corner uv: (90, 30)
        let uv2 = ch.uvs[q * 4 + 2];
        assert!((uv2.x - 90.0 / 512.0).abs() < 1e-6 && (uv2.y - 30.0 / 64.0).abs() < 1e-6);
    }

    #[test]
    fn beam_scale_stretches_along_its_own_direction() {
        // A beam facing +y with speed 1000 -> sx = 2 * clamp(2, 1, 3) = 4, sy = 2: it must be LONGER along +y than along x.
        let mut s = Shots::new();
        s.push(3, V2::new(0.0, 1.0), V2::new(0.0, 0.0), 2.0, true, 255, 255, 0);
        s.speed[0] = 1000.0;
        let mut b = builder();
        b.build(&s.arrays(), 1);
        let ch = &b.chunks[0];
        let q = 1; // trail = 0, body = 1 (no glow for a beam)
        let (mut min_x, mut max_x, mut min_y, mut max_y) = (f32::MAX, f32::MIN, f32::MAX, f32::MIN);
        for k in 0..4 {
            let p = ch.points[q * 4 + k];
            min_x = min_x.min(p.x);
            max_x = max_x.max(p.x);
            min_y = min_y.min(p.y);
            max_y = max_y.max(p.y);
        }
        assert!((max_y - min_y) > (max_x - min_x) * 1.9, "extent y {} x {}", max_y - min_y, max_x - min_x);
    }

    #[test]
    fn alpha_fades_with_age_and_glow_trail_use_their_multipliers() {
        let mut s = Shots::new();
        s.push(2, V2::new(1.0, 0.0), V2::new(0.0, 0.0), 1.0, false, 255, 255, 0);
        s.elapsed[0] = 1.0; // half of a 2 s life -> a = 0.5
        let mut b = builder();
        b.build(&s.arrays(), 1);
        let ch = &b.chunks[0];
        assert!((ch.colors[0].a - 0.5 * 0.22).abs() < 1e-6, "glow alpha {}", ch.colors[0].a);
        assert!((ch.colors[4].a - 0.5 * 0.35).abs() < 1e-6, "trail alpha {}", ch.colors[4].a);
        assert!((ch.colors[8].a - 0.5).abs() < 1e-6, "body alpha {}", ch.colors[8].a);
    }

    #[test]
    fn many_shots_split_into_chunks_under_the_vertex_limit() {
        let mut s = Shots::new();
        for _ in 0..2500 {
            s.push(2, V2::new(1.0, 0.0), V2::new(0.0, 0.0), 1.0, false, 255, 255, 0);
        }
        let mut b = builder();
        let quads = b.build(&s.arrays(), 2500);
        assert_eq!(quads, 2500 * 7);
        assert!(b.chunks.len() >= 2);
        for ch in &b.chunks {
            assert!(ch.points.len() <= 4 * MAX_QUADS_PER_CHUNK);
            assert_eq!(ch.indices.len(), ch.quads * 6);
            assert_eq!(ch.points.len(), ch.quads * 4);
            // every index stays inside its own chunk
            assert!(ch.indices.iter().all(|&i| (i as usize) < ch.points.len()));
        }
    }

    #[test]
    fn sparks_are_deterministic_for_a_given_hash_and_time_bucket() {
        let mut s = Shots::new();
        s.push(2, V2::new(1.0, 0.0), V2::new(0.0, 0.0), 1.0, false, 255, 255, 0);
        let mut b1 = builder();
        let mut b2 = builder();
        b1.build(&s.arrays(), 1);
        b2.build(&s.arrays(), 1);
        assert_eq!(b1.chunks[0].points, b2.chunks[0].points);
        // a different spawn hash moves the sparks (quads 4..7)
        s.spark_hash[0] = 987654321;
        let mut b3 = builder();
        b3.build(&s.arrays(), 1);
        assert_ne!(b1.chunks[0].points[16..28], b3.chunks[0].points[16..28]);
    }
}

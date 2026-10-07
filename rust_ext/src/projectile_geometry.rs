use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};
use pixbots_core::geometry::{Atlas, Consts, GeometryBuilder, Rgba, ShotArrays, V2};

type VDict = Dictionary<Variant, Variant>;

// Godot binding for pixbots_core::geometry (2026-10-07). All of the maths lives in the engine-agnostic core crate (pure
// std, unit-tested with `cargo test -p pixbots_core`); this file only converts Godot packed arrays to core slices and
// the resulting triangle buffers back to packed arrays. ProjectileBatchPool.gd drives it (see _ensure_geometry /
// _draw_atlas_rust) and keeps its GDScript draw path as the fallback and parity reference
// (ProjectileGeometryParityCheck.gd quad by quad, ProjectileGeometryImageDiff.gd pixel by pixel).

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct ProjectileGeometry {
    base: Base<RefCounted>,
    builder: GeometryBuilder,
    count: usize,
    // Snapshot taken by load_a() (the binding layer limits a method's argument count, so build() is split in two).
    s_alive: Vec<u8>,
    s_syn: Vec<u8>,
    s_dir: Vec<V2>,
    s_pos: Vec<V2>,
    s_off: Vec<V2>,
    s_scale: Vec<f32>,
    s_color: Vec<Rgba>,
}

#[godot_api]
impl IRefCounted for ProjectileGeometry {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            builder: GeometryBuilder::default(),
            count: 0,
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

fn v2s(src: &[Vector2]) -> Vec<V2> {
    src.iter().map(|v| V2::new(v.x, v.y)).collect()
}

fn colors(src: &[Color]) -> Vec<Rgba> {
    src.iter().map(|c| Rgba::new(c.r, c.g, c.b, c.a)).collect()
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
        self.builder.consts = Consts {
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
            helix: [
                get_i(&consts, "helix0") as usize,
                get_i(&consts, "helix1") as usize,
                get_i(&consts, "helix2") as usize,
            ],
        };
        self.builder.atlas = Atlas {
            units: rects_from_flat(units.as_slice()),
            px: rects_from_flat(px.as_slice()),
            width: atlas_size.x.max(1.0),
            height: atlas_size.y.max(1.0),
            echo_colors: colors(echo_colors.as_slice()),
            vortex_color: Rgba::new(vortex_color.r, vortex_color.g, vortex_color.b, vortex_color.a),
        };
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
        self.s_dir = v2s(&direction.as_slice()[..n]);
        self.s_pos = v2s(&position.as_slice()[..n]);
        self.s_off = v2s(&visual_offset.as_slice()[..n]);
        self.s_scale = scale.as_slice()[..n].to_vec();
        self.s_color = colors(&color.as_slice()[..n]);
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
        let shots = ShotArrays {
            alive: &self.s_alive,
            syn: &self.s_syn,
            direction: &self.s_dir,
            position: &self.s_pos,
            visual_offset: &self.s_off,
            scale: &self.s_scale,
            color: &self.s_color,
            elapsed: elapsed.as_slice(),
            lifetime: lifetime.as_slice(),
            is_beam: is_beam.as_slice(),
            speed: speed.as_slice(),
            sec1: sec1.as_slice(),
            sec2: sec2.as_slice(),
            extra_mask: extra_mask.as_slice(),
            spark_hash: spark_hash.as_slice(),
        };
        let n = self.s_alive.len().min(self.count);
        self.builder.build(&shots, n) as i64
    }

    #[func]
    fn chunk_count(&self) -> i64 {
        self.builder.chunks.iter().filter(|c| c.quads > 0).count() as i64
    }

    #[func]
    fn chunk_points(&self, i: i64) -> PackedVector2Array {
        let v: Vec<Vector2> = self.builder.chunks[i as usize].points.iter().map(|p| Vector2::new(p.x, p.y)).collect();
        PackedVector2Array::from(v.as_slice())
    }

    #[func]
    fn chunk_colors(&self, i: i64) -> PackedColorArray {
        let v: Vec<Color> = self.builder.chunks[i as usize].colors.iter().map(|c| Color::from_rgba(c.r, c.g, c.b, c.a)).collect();
        PackedColorArray::from(v.as_slice())
    }

    #[func]
    fn chunk_uvs(&self, i: i64) -> PackedVector2Array {
        let v: Vec<Vector2> = self.builder.chunks[i as usize].uvs.iter().map(|p| Vector2::new(p.x, p.y)).collect();
        PackedVector2Array::from(v.as_slice())
    }

    #[func]
    fn chunk_indices(&self, i: i64) -> PackedInt32Array {
        PackedInt32Array::from(self.builder.chunks[i as usize].indices.as_slice())
    }
}

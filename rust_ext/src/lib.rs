use godot::prelude::*;

struct RustExt;

#[gdextension]
unsafe impl ExtensionLibrary for RustExt {}

mod hexmath;
mod part_rasterizer;
mod projectile_flight;
mod projectile_broadphase;
mod hexgrid_sim;
mod terrain_rasterizer;
mod procedural_shape;

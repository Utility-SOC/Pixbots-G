use godot::prelude::*;

struct RustExt;

#[gdextension]
unsafe impl ExtensionLibrary for RustExt {}

mod hexmath;
mod part_rasterizer;

use godot::prelude::*;
use godot::classes::{IRefCounted, RefCounted};

// STUB - the seed of the `pixbots_core` split (FEATURE_ROADMAP: Pixelbots 2
// convention). This will become the engine-agnostic energy-grid simulation:
// the compute half of Mech._recalculate_grid/_simulate_grid, taking a pure
// data description of every component's hex grid and returning the
// precalculated weapon packets combat fires from. Both PB1 (via this gdext
// binding) and PB2 (whatever engine) link the same core once it's real.
//
// Planned API shape (mirrors the GDScript sim's semantics 1:1):
//   simulate(components: Array<Dictionary>) -> Dictionary
//     in:  per component: slot_type, tiles [{q, r, tile_type, rarity,
//          level, faces/params...}], fixed_sinks, links between components
//     out: { "weapons": [{slot_type, mount_qr, packet: {magnitude,
//            synergies, charge_required, traversal_steps, bank_*}, step}],
//          "shield": {...}, "mobility": {...}, "per_tile_flow": [...] }
//
// Porting order (each verified against the GDScript sim byte-for-byte,
// same discipline as part_rasterizer's correctness check):
//   1. BFS packet routing + per-tile process_energy transfer functions
//   2. merge-by-traversal-step at mounts (the sync-deviation rules)
//   3. accumulator bank / siphon model
//   4. cross-component link transfers (torso -> peripheral feeds)
//
// Until then this class exists so the FFI surface, registration, and
// call sites can be built and tested; is_implemented() lets GDScript
// feature-gate cleanly.

#[derive(GodotClass)]
#[class(init, base=RefCounted)]
pub struct HexGridSim {
    _base: Base<RefCounted>,
}

#[godot_api]
impl HexGridSim {
    /// Stub: always false until the port lands. GDScript callers must
    /// check this and fall back to Mech._simulate_grid.
    #[func]
    fn is_implemented(&self) -> bool {
        false
    }

    /// Stub: returns an empty Dictionary. See the module comment for the
    /// contracted in/out shape the real implementation will honor.
    #[func]
    fn simulate(&self, _components: VariantArray) -> Dictionary<Variant, Variant> {
        Dictionary::new()
    }
}

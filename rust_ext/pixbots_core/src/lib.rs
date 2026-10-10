//! pixbots_core: the engine-agnostic part of Pixbots (see docs/RUST_MIGRATION_ROADMAP.md, Phase 1).
//!
//! Rules for this crate: `std` only, no Godot types, data in and out as plain slices / Vecs. Anything that has to
//! survive a change of engine or shell belongs here; `rust_ext` (the GDExtension) only converts Godot arrays to these
//! types and back.

pub mod flow_field;
pub mod geometry;
pub mod hex;
pub mod hexgrid_sim;
pub mod solid_grid;

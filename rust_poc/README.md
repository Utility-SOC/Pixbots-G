# Rust hybrid-architecture proof-of-concept

Not wired into the game. This is a research artifact from evaluating whether
porting hot-path math (HexGrid coordinates, procedural component-shape
generation) to Rust via GDExtension is worth the toolchain investment.

## What's here

- `hexgrid.rs` - standalone Rust port of `scripts/core/HexCoord.gd`'s
  coordinate math and `scripts/core/ComponentEquipment.gd`'s
  `generate_procedural_shape()` shape-growth algorithm. Builds with plain
  `rustc` (no Cargo/dependencies needed) and runs a benchmark on exit.
- `../scripts/debug/RustBenchComparison.gd` - the identical algorithm in
  GDScript, for an in-engine apples-to-apples timing number. Not wired into
  any menu; attach to a Node in an empty scene and run it (F6).

## Results so far

Measured in the dev sandbox (Linux, no GPU/display) - Rust vs. a Python port
of the same algorithm as an interpreted-language stand-in (Python isn't
GDScript, but is a reasonable proxy for dynamic-language overhead):

| Workload | Rust | Python | Speedup |
|---|---|---|---|
| Generate 100,000 component shapes | 2.44 us/shape | 69.62 us/shape | ~28x |
| 5,000,000 neighbor+distance ops | 1.66 ns/op | 396.86 ns/op | ~239x |

Both languages produced the same average hex count per shape (45.9) and an
identical checksum on the deterministic math loop (6,666,667), confirming
the ported logic is faithful to the original.

**Update - real in-engine GDScript number obtained** (Windows dev machine,
`godot --headless` running `RustBenchComparison.gd` directly, not the editor
GUI):

| Workload | GDScript (real) | Rust | Speedup |
|---|---|---|---|
| Generate 100,000 component shapes | 58.33 us/shape | 2.44 us/shape | ~24x |
| 5,000,000 neighbor+distance ops | 370.97 ns/op | 1.66 ns/op | ~223x |

Very close to the Python stand-in's numbers (as predicted), and the ~24x/
~223x speedups confirm the Python-based estimate wasn't optimistic - this is
a real, meaningful win for this specific algorithm shape.

**Important correction (found while investigating a separate enemy-spawn
stutter report):** `generate_procedural_shape()` - the function this POC
ported - is only used for **loot drops and Black Market offers**
(`LootManager.gd`, `GarageMenu.gd`'s Black Market), NOT for enemy starter
components. Enemy spawns use a different, simpler, non-recursive function
(`ComponentEquipment.gd`'s `generate_shape()`) that isn't the same
algorithmic shape as what's benchmarked here. **This POC's numbers do not
represent the enemy-spawn hot path.** See `../rust_ext/` (the real
GDExtension, not this standalone POC) for what's actually being ported for
that: a tight nested-loop pixel rasterizer in `MechPartRenderer.gd`,
identified as the real per-mech cost via direct code tracing.

This POC (and its Rust number above) remains valid evidence that porting
*is* worth it in general for this kind of allocation-heavy, branchy,
dynamically-typed-language-penalized workload - just not proof that this
*specific* function needed it.

## The real blocker: cross-compilation — RESOLVED

Rust (stable-x86_64-pc-windows-msvc, via rustup) is now installed directly
on the Windows dev machine, with a working MSVC linker (Visual Studio Build
Tools already present) - confirmed via a `cargo new` + `cargo run`
hello-world round trip. No cross-compilation needed. See `../rust_ext/` for
the real GDExtension crate (not this standalone POC folder, which remains a
reference artifact).

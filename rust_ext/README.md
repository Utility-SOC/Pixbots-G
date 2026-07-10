# rust_ext — the real GDExtension (not the rust_poc/ research artifact)

Wired into the game. `MechPartRenderer.gd`'s `finish()` calls into this when
available, falling back to the pure-GDScript rasterizer if the DLL isn't
built yet (fresh checkout, nobody's run `cargo build` here).

## Why this exists

`../rust_poc/` was the original research spike — it ported
`ComponentEquipment.gd`'s `generate_procedural_shape()` (used for loot/Black
Market drops) and proved Rust-via-GDExtension is worth the toolchain
investment in general. But when investigating a real enemy-spawn stutter
report, direct code tracing found `generate_procedural_shape()` **isn't**
actually in the enemy-spawn path at all — enemies use a different, cheaper,
non-recursive shape function. The real per-mech cost turned out to be
`MechPartRenderer.gd`'s pixel rasterization: `Geometry2D.is_point_in_polygon`
and point-to-segment distance tests run in a nested 32×32 loop, once per
fill/line region, once per body part (torso/2 arms/2 legs/head), once per
spawned mech. A squad of 3-5 enemies spawning at once (already staggered
one-squad-per-beat, see `Main._spawn_wave_async`) means 18-30 of these full
per-part bakes happening synchronously in one frame - that's the actual
stutter.

## What's here

- `src/hexmath.rs` — `HexMathBench`, a pipeline-validation class (same
  neighbor+distance workload as `rust_poc/hexgrid.rs` /
  `scripts/debug/RustBenchComparison.gd`). Not used by the game; exists to
  prove the whole GDExtension round trip (compiles → `.gdextension` loads →
  GDScript calls in → correct results out) works, with a checksum assert
  against the known-correct value, before trusting the rasterizer port.
- `src/part_rasterizer.rs` — `PartRasterizer`, the actual game-facing class.
  `rasterize(fill_regions, line_regions, outline_color) -> PackedByteArray`
  takes the exact same region data `MechPartRenderer`'s own
  `_fill_regions`/`_line_regions` arrays hold (untyped `Array` of
  `{polygon, color}` / `{a, b, color, width}` Dictionaries — kept untyped
  deliberately so `MechPartRenderer.gd`'s fields didn't need to change) and
  returns raw RGBA8 pixel bytes in `Image.create()`'s exact layout, so
  GDScript just builds an `Image`/`ImageTexture` from the bytes instead of
  running the pixel loops itself. The whole bake happens in one native call
  — batching matters here, since per-pixel FFI round-trips would eat the
  entire native-speed win.

## Results (this machine, Godot 4.6.3, headless)

| Workload | GDScript (real) | Rust debug | Rust release |
|---|---|---|---|
| Part rasterization (`PartRasterizer.rasterize`, matches `MechPartRenderer.finish()`) | 1690.64 us/part | ~430 us/part | **25-28 us/part (~60-67x)** |
| Neighbor+distance math (`HexMathBench`, pipeline validation only) | 370.97 ns/op | ~15 ns/op | **1.68-1.69 ns/op** (matches `rust_poc/hexgrid.rs`'s standalone 1.66 ns/op almost exactly) |

**Verified byte-for-byte correct**, not just "doesn't crash" — see
`scripts/debug/RasterizerCorrectnessCheck.gd`, which runs identical input
through both the GDScript and Rust rasterizers and diffs every byte. Caught
and fixed one real bug this way: the Rust color→byte conversion used
`.round()`, but Godot's own `Image::set_pixel` truncates (C++ float→int
cast) — a 396/4096-byte mismatch on the first attempt, traced to exactly
that (`0.05 * 255 = 12.75` → GDScript's 12 vs. the old rounding code's 13),
fixed in `part_rasterizer.rs`'s `color_to_bytes()`.

A typical mech has 6 parts: ~10.1ms of GDScript rasterization per mech vs.
~0.15-0.17ms in Rust. A 5-mech squad spawn beat goes from ~50ms (multiple
dropped frames at 60fps) to well under 1ms.

## Building

```
cd rust_ext
cargo build           # writes target/debug/rust_ext.dll
cargo build --release # writes target/release/rust_ext.dll
```

Godot picks whichever `.gdextension` path matches how the *Godot binary
itself* was built - running via the editor or `godot --headless` (an
official, non-exported build) always loads the `windows.debug.x86_64` path,
**regardless of whether you built the Rust side in debug or release**. The
release path only gets used once the game is actually exported. If you want
to benchmark the release build in-editor, temporarily copy
`target/release/rust_ext.dll` over `target/debug/rust_ext.dll` (that's how
the release numbers above were captured), then restore the real debug build
afterward for normal iteration (better compile times, debug info).

### Known issue: intermittent build failure on Windows

`cargo build` can fail with `The process cannot access the file because it
is being used by another process. (os error 32)` on a `.rmeta` file deep in
a dependency, even on a clean `cargo clean`. Root cause found here: Godot's
own filesystem watcher (left running from an editor/project scan) races
cargo's file writes if you've recently had the Godot editor open on this
project. Workarounds, in order of preference:
1. Just retry `cargo build` a couple of times — it's a race, not a
   deterministic failure, and often clears on its own.
2. If it keeps failing, build with an out-of-tree target dir and copy the
   result in:
   ```
   CARGO_TARGET_DIR=/some/path/outside/the/project cargo build --release
   cp /some/path/outside/the/project/release/rust_ext.dll target/release/
   ```

## Validation / correctness scripts

Both in `scripts/debug/`, same "attach to a Node, run it" pattern as
`RustBenchComparison.gd` (or run headless: `godot --headless
scripts/debug/<name>.tscn`):
- `RustExtValidation.gd` — loads both Rust classes, checksums the math,
  prints benchmark numbers.
- `RasterizerCorrectnessCheck.gd` — byte-diffs GDScript vs. Rust rasterizer
  output on identical input.
- `RasterizerBenchComparison.gd` — GDScript-only timing for
  `MechPartRenderer.finish()`'s actual code path (not synthetic), for a
  clean before/after number.

All three are debug-only tooling, safe to delete once you trust the
extension, same as `RustBenchComparison.gd`.

## What's NOT ported (yet)

`AutoEquipSolver.solve()` (called 3x per spawned enemy) and
`Mech._simulate_grid()` (up to ~7x per spawned mech, each capped at 100
routing steps) were both traced during the same investigation and found to
be smaller, more linear workloads than the rasterizer — real but not the
dominant cost. Candidates for a future pass if the rasterizer port alone
doesn't fully resolve the spawn stutter in practice, but not done here.

# Roadmap: moving Pixbots off Godot to pure Rust (DRAFT)

Status: draft for discussion, written 2026-10-06. Nothing here is started. Numbers come from the
repo and from the 2026-10-06 profiling session; assumptions are marked **(assumed)**.

## Why consider it

- Wave-34 bench (60 enemies) runs 25-40 fps on the i5-3340M / HD 4000 while scripts account for only
  ~100-150 ms of each second. A `perf` sample put **79% of main-thread CPU inside the Godot binary**
  (engine C++, which includes the GDScript VM), 8% libc malloc/free, ~1% the Vulkan driver, 2.5% our Rust.
  So the cost is engine/interpreter overhead we cannot reach from a script.
- Disabling collision on ~half of the 3,069 map StaticBody2Ds (keeping those near the player) lifted
  the bench by roughly +9 to +21 fps in repeated A/B runs. Godot's 2D physics cost scales with body
  count in a way a purpose-built grid would not.
- The Vulkan device-lost crashes (Mesa Ivy Bridge, "incomplete" support) are a driver problem that
  Godot's Forward+ makes us hit; we control little of that path.
- The game's differentiators (evolving AI, hex energy grids, shared gene pool) are already data and
  algorithms, not scene-tree features. 4.2k lines of Rust already carry the hot ones.
- Pixelbots 2 (3D) wants the same simulation core.

## Why not (yet)

- 89k lines of GDScript (59k excluding `scripts/debug`), 296 scenes. The Garage UI alone is ~13k lines.
- Godot gives us editor, import pipeline, audio, input, UI, scenes for free.
- Rendering in Rust still lands on the same HD 4000 / Mesa stack. wgpu on Vulkan would meet the same
  driver bugs; its GL backend is the escape hatch but must be proven on this machine first.
- One developer. A rewrite that stalls feature work is the usual way these die.

## Principle: strangler, not rewrite

Keep the game shippable at every step. Move *state and simulation* into Rust first, leave Godot as a
thin renderer/input/UI shell, then decide on replacing the shell with evidence in hand. Each phase
ends with something playable and a bench number.

## Phase 0: finish measuring (days)

Gate for everything else. Do not commit to the migration until this says the overhead is intrinsic.
- Name the engine hot spots: `perf` with symbols (Godot built with symbols, or an official debug
  template if one exists) and/or a headless GDScript sampler in BenchGame. CLI only.
- Finish the A/B set: physics step vs scene tree vs canvas draw (static-body, enemy-collision,
  node-count cuts).
- Record a fixed benchmark table (wave 12/34, 60 swarm) as the migration scoreboard.
- Cheap Godot-side wins to bank first: collapse static map bodies (merge into a few TileMap/polygon
  bodies or replace with the Rust `solid_grid`), cut per-bot node count (~23k nodes at wave 34).

Exit criteria: >50% of frame cost attributed; decision recorded here.

## Phase 1: simulation core crate (weeks)

Create `pixbots_core` (plain Rust lib, no Godot types) and have `rust_ext` become a thin binding to it.
- Already Rust: flow field, hex grid sim, separation, projectile flight/broadphase, proximity query,
  rasterizers. Move them behind the core crate API unchanged.
- Choose the data model: ECS (`hecs` or `bevy_ecs`, standalone) vs hand-rolled SoA. **(assumed)** ECS,
  because bots, drones, projectiles, hazards and status effects are many small entity types.
- Spatial index in Rust (uniform grid / sparse hash) for static map + dynamic bodies; becomes the
  replacement for Godot 2D physics queries. Deterministic, seedable (daily seed, replays, shared AI).
- Deterministic RNG plumbing and a fixed-timestep loop; core is headless-testable in `cargo test`.

Exit: Godot calls one `step(dt)` for projectiles + spatial queries; bench improves; checks still pass.

## Phase 2: mechs, AI and movement in Rust (1-2 months)

- Port `Mech` movement/steering (the `move_and_slide` replacement) onto the Rust spatial index.
- Port AI: SquadTactics, TacticGenome, PlayerModel, StockBuildEvolution, SquadDirector (~6k lines in
  `scripts/ai`, plus the logic in `scripts/core`). These are pure logic and port well. Keep the JSON
  save/gene-card formats byte-compatible so shared AI and run cards keep working.
- Port AutoEquipSolver / SolverRefiner (already partly Rust via `hexgrid_sim`).
- Port loot, status effects, hazards, boss brains.
- Godot side shrinks to: read snapshot arrays, draw sprites, feed input.

Exit: a full wave plays with the GDScript sim disabled; Godot is purely a view.

## Phase 3: choose the shell (decision point)

Evaluate with real numbers on the HD 4000, in this order of preference:
1. Keep Godot for rendering/UI/audio indefinitely, with Rust owning the sim (cheapest; may already
   be good enough after Phase 2).
2. Rust renderer via `wgpu` (or `bevy_render`) on its GL backend, with sprite batching we control.
3. Software/blit path for the pixel-art viewport (the game is 8px "fat pixels"; a CPU-composited
   low-res framebuffer scaled by the GPU is a real option on weak hardware).
Pick one only after a throwaway spike renders 80 mechs + 500 projectiles at target fps here.

## Phase 4: UI and tools (largest cost, only if Phase 3 leaves Godot)

- Garage (hex grid editor, power-flow overlay, War Room, panels): ~13k lines. `egui` is the practical
  Rust choice; budget it as its own project. Accessibility and controller support need rechecking.
- Replace editor-authored content: 296 scenes become data files (RON/JSON) plus code.
- Cutscenes/tutorial (`MazeTutorial`, 9+ cutscene JSONs) are already data driven.

## Phase 5: audio, saves, platform

- Audio: `ProceduralSynth`/`MusicGenome` to `cpal` + a small synth (e.g. `fundsp`); note music
  generation is already a CPU hog on this dual-core, so make it a core-pinned worker.
- Saves/imports: keep the allow-listed JSON validation from `docs/IMPORT_SECURITY.md`; port to `serde`
  with schema caps. This is an easy place to get *safer*.
- Packaging for Linux first (current launcher auto-pulls from GitHub; keep an equivalent).

## Phase 6: cutover and 3D

Remove the GDScript sim, freeze the Godot project as a reference, then reuse `pixbots_core` for
Pixelbots 2 (see `PIXELBOTS_2_HEX_TO_CUBE_MAPPING.md`).

## Risks

| Risk | Mitigation |
|---|---|
| Stall: no new features for months | Phases end playable; feature work continues on the Godot shell |
| Same Mesa/HD 4000 bugs under wgpu | Phase 3 spike on this machine before committing; GL backend |
| Save/gene-card compatibility breaks shared AI | Golden-file tests against current exports before each port |
| Loss of editor ergonomics | Keep Godot as the view until Phase 4 is justified |
| Solo bus factor | Core crate has docs + `cargo test` coverage mirroring the existing `*Check` scenes |

## Suggested first three tasks

1. Phase 0 profile with symbols, then bank the static-body and node-count wins in Godot.
2. Spin out `pixbots_core` from `rust_ext` (no behavior change) and add a headless bench.
3. Prototype the Rust spatial index replacing static `StaticBody2D`s for enemy movement, and compare
   against the `--nostatic` numbers.

## Open questions for the owner

- Is the goal speed on weak hardware, independence from Godot, or Pixelbots 2 reuse? They weight the
  phases differently.
- Acceptable timeline, and is feature work paused during any phase?
- Is dropping the Godot editor for level/UI authoring acceptable?

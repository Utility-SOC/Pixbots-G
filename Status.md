# PixBots-G: Master Status Document (Active Work & Backlog)

This document tracks the active implementation targets, backlog, and design expansions for PixBots-G. (All shipped and completed features have been cleared from this tracker - see the short "Recently Shipped" section at the bottom only for orientation context.)

---

## 1. Lore & Vision Context
**The Core Fantasy:** You are playing *PixBots*, a wildly popular tabletop miniatures game at Frank's local hobby shop. The scale is 20mm miniatures fighting on a 4x8ft tabletop mat (1mm = 5px, 1 inch = 127px).
**The Goal:** Survive as many waves as possible against Frank's proprietary AI Director, which evolves and breeds new rival profiles to counter your strategies.

**Story (Canon):** The shop runs a standing competition: defeat the AI and earn merchandise. The Black Market is the shop's glass case; the War Room is your opponent studying your plays.

**Open worldbuilding thread (not yet authored, direction only):** hints that the world outside the shop is a dystopian collapse Frank never comments on directly - see STORY_SCRIPT.md's "Worldbuilding thread: dystopian hints" section for seed ideas (Neighborhood Watch sweeps for unauthorized electronics/thermal signatures/unregistered materials) and the "The Eye" challenge concept below that gives it a first concrete gameplay hook.

**Standing design rulings (locked):**
- Purely procedural 2D visuals; sprite PNGs are optional *overrides*, never requirements.
- Every Champion Card PNG carries the full buildout (ghost + blueprint duality).
- Explosions are payload-only (no flight identity). Skill trees are QoL, not power.
- Corporate Sponsorships bias loot via **weights, never hard filters** - no build path can be bricked.
- Pixelbots 2 (godot-3d) shares gameplay rules via Node-free RefCounted/static classes, targeting an engine-agnostic `pixbots_core` Rust crate long-term.

---

## 1a. Pixelbots 2: The 3D Vision (captured 2026-07-20, not active work)

This is the actual long-term destination the `pixbots_core` split above is aimed at. Recorded here as durable design intent, not a task queue - **PB1 stays the priority**, and PB1 only picks up changes from this vision when they're cheap/natural to do anyway (e.g. work already being done for other reasons that happens to also serve PB2). Nothing below should be read as "go build this now."

**The core idea:** the hex grid isn't 2D forever - it's the 2D unfolding of a **3D cube grid**. Each hex a player places today is a face-projection of a cube; when the game goes 3D, that same build data describes a genuine 3D voxel structure. Garage UX changes accordingly: selecting a limb zooms the camera into a 3D model of that limb, and the player sees/edits columns and rows of cubes directly on the model - build logic and rules stay hex-based (so PB1's balance, routing, and solver code ports largely as-is), but the *view* is a real 3D shape, not a flat schematic.

**Why this is exciting, in the user's own words:** the hex-grid shape rules already produce "weird long limbed" torsos and asymmetric builds in 2D - wrapped up into 3D cube volumes, those same shapes read as genuinely strange, cool silhouettes rather than just an odd flat outline. The build-in-hex/view-in-3D duality is the whole hook: familiar hex-grid engineering, alien-looking robots.

**What this implies architecturally (informs, doesn't mandate, PB1 work):**
- The hex-grid simulation (packet routing, tile process_energy, capture/store semantics - i.e. everything `hexgrid_sim.rs`/`RustGridSim.gd` now cover) is exactly the "gameplay rules" layer meant to become the engine-agnostic `pixbots_core` crate. Every tile ported to Rust in PB1 is (long-term) a tile PB2 doesn't have to re-implement - this is the concrete throughline from "port tiles to Rust for PB1 performance" to "build the PB2 foundation." They're the same work, not competing priorities.
- Shape-generation code (`ComponentEquipment.generate_shape`/`generate_procedural_shape`) is the other natural PB2 seed - it already reasons about hex geometry as pure data (no Godot Node coupling in the algorithm itself), which is what a cube-projection layer would need to consume.
- The engine question is open: Godot supports 3D natively (no engine swap forced), but a 3D-heavy sequel is also the natural point to revisit whether Godot remains the right fit vs. something with more mature 3D tooling - not a decision to make now, just flagged as a real fork in the road when PB2 actually starts.

**Explicit non-goal for PB1:** PB1 does not need a 3D renderer, a cube-projection layer, or any camera/zoom-into-limb UX. Its job is only to keep the simulation/shape-generation layers clean and engine-agnostic where that's low-cost, so the eventual extraction is easier.

**Axial-to-cube axis mapping (raised 2026-07-27, purely conceptual, not to-do yet):** the user's own framing of "rolling up" a hex line into a line of cubes - a single straight line of hexes stays a straight line of cubes, but the existing "weird long-limbed dog-leg" shapes (already produced by the current hex shape-generation budget/spoke rules) would read as genuinely strange 3D silhouettes once every bend becomes a real turn in 3D space rather than a flat direction change. Tentative axis idea floated: hex E/W -> world X, NE/SW -> world Y, SE/NW -> world Z (an axial-to-cube-diagonal mapping, since a 2D hex grid has 3 natural axes/6 directions, matching a cube's 3 axes/6 faces one-to-one) - plausible on its own terms but genuinely untested; needs real validation once PB2 work actually starts, not now.

**Brush-based paint, not a single color (raised 2026-08-05):** PB1 shipped a Paint Rack this session - pick one flat color from a curated palette, applied uniformly to the whole mech (see Recently Shipped). The user wants PB2's real 3D bot model to go further: an actual brush tool the player paints directly onto the model with, not a single-swatch picker. Purely conceptual for now - no work needed on PB1's side; the existing paint_color field/Paint Rack stays exactly as it is until PB2 actually starts.

---

## 2. Execution Queue (reconciled 2026-10-09)

**Rule:** Rust ports outrank features. Lanes (Gameplay G, Polish P, Architecture A) run round-robin, one item per lane per round. **Engine-coupling cut comes first** so every later port and rework lands on clean seams. Each A item ends playable with a bench number (wave 12 / wave 34 / 60 swarm, HD 4000) and a `cargo test`-able core (`docs/RUST_MIGRATION_ROADMAP.md`). Design detail lives in specs, not here: `docs/ELEMENTAL_REWORK_SPEC.md`.

### Prerequisites (A lane, do before any port or Ice/Vortex build)
1. **Golden fixtures:** seeded wave runs, hex-grid energy results, solver outputs, gene-card/save exports captured as checked-in JSON from the GDScript build. Record the bench table first.
2. **Engine-coupling cut:** split `Mech.gd` (4,945 lines) so sim state and per-tick logic are node-free; route the ~25 files that call physics/collision APIs through one thin interface (this is also the future spatial-index seam); keep presentation/audio out of sim code.
3. **RNG policy (see below):** one injected seeded RNG with named streams for sim; sim clock instead of wall-clock ticks (~36 files).
4. Pin and version the save / gene-card / run-card / `stats.json` schemas.

**RNG policy:** gameplay-affecting randomness (~58 files use unseeded `randf/randi/shuffle/pick_random`; ~23 use `RandomNumberGenerator`) all moves to one injected seeded source, split into named streams (combat, loot, AI, map, vortex-wander) so adding a roll in one place does not shift the others. Purely cosmetic randomness (particles, jitter, audio variation) may stay unseeded and cheap. Fewer approaches = fewer error paths; the only reason to keep a second approach is that it is visual-only.

### Round 0: low-hanging fruit (started 2026-10-09)
- **A:** prerequisites 1-2 above. *In progress.* Done 2026-10-09: `scripts/core/SimPhysics.gd` (move / segment_blocked / circle_colliders, pass-through to Godot) and `Mech.gd` routed through it (5 call sites; mech checks pass). All live ray and shape queries (Mech, Projectile, BossBrain, SightAndSearch, MineEmitter, OilSlickHazard) now go through it; remaining direct use is only `move_and_slide` ownership, collision-layer setup and the superseded `_find_homing_target` reference. Golden fixtures done (2026-10-09): `SolverGoldenCheck` (8 seeded solver cases), `EnergyGoldenCheck` (13 grids through the Rust sim), `SaveGoldenCheck` (component serialization + round trip); fixtures in `scripts/debug/golden/`, re-bless with `PIXBOTS_UPDATE_GOLDEN=1` only after a deliberate change. Schema versioning: saves/loadouts already carry version numbers (`SAVE_FORMAT_VERSION` = 6) and the loader is `has()`-guarded; the fixtures pin the format. RNG: `scripts/core/SimRng.gd` has named seeded streams (combat, loot, ai, spawn, tile, map, solver; plus `pick`/`shuffle`), unseeded by default so play is unchanged. ~190 gameplay-affecting calls in 25 files migrated (Mech, Projectile, BossBrain, SightAndSearch, loot, Main spawns, all ai evolution/director code, tile sync roll, solver); visual/audio/cosmetic randomness deliberately left global. Map generation is deliberately NOT migrated: `MapGenerator` already seeds the global RNG for its generation window (`map_seed`, daily seed), and a seeded `RandomNumberGenerator` produces different floats than the seeded global one (ints match), so converting would change what existing daily seeds generate. Wave composition is not seeded (docs/DAILY_SEED.md). `Mech.gd` split done for the pure-logic groups (4,945 -> ~3,140 lines): `MechLoadoutBuilder` (loadout/stock builds), `MechDamage` (damage, shields, part damage, status), `MechGridSim` (grid/energy sim, weapon-mount/capability collection); each helper holds `mech`, `Mech.gd` keeps one-line wrappers so no caller changed, and `scripts` tools: the extraction script pattern is in the commit history. The movement / AI-tick / lifecycle code (`_physics_process`, AI tactics, flee/mosey, ramming; ~3,100 lines) is deliberately left in `Mech.gd`: it is the Rust Phase 2 port target and will be replaced by a Rust state/step rather than refactored (a `mech.`-prefixed helper would slow the hottest function for no lasting benefit). Remaining optional: gene-card/profile export fixtures; a seeded whole-wave run fixture (needs a deterministic spawn/AI path, i.e. the Rust step loop).
  - **Prerequisites status (2026-10-09): items 1-4 complete** (fixtures, coupling cut incl. physics seam + Mech split, RNG policy, schema pinned). The Architecture lane can now start item 1 (hexmath/solid_grid/flow_field into `pixbots_core`).
  - **Bench is noisy:** back-to-back wave-34 runs of identical code gave 129 and 60 fps (node counts 7.8k vs 12.9k, so the workload itself varies). Do not trust single runs; the Rust port needs a fixed-workload bench (seeded, fixed enemy count) before it can be scored. Full check suite after the migration: 250 pass; pre-existing issues: `MapStructureCheck` fails on the committed code too (Volcano builds 0 walls), `MapLayoutCheck` takes ~83 s; several perf checks only print numbers.
  - **Bug found and fixed by the fixtures (2026-10-09):** `AutoEquipSolver._replay_plan` (used on every repeat topology-cache hit) built a Directional Conduit wherever the fresh solve had synthesized a Splitter the inventory lacked, silently dropping branches on second-and-later builds with the same key. It now rebuilds the recorded tile type; `SolverGoldenCheck` asserts replay equals fresh.
  - **Bench baseline (2026-10-09, i5-3340M/HD 4000, windowed, 40 s, forward_plus):** wave 12: 122.6 fps avg (p95 11.9 ms); wave 34: 63.9 fps avg (p95 49.3 ms, 48 enemies). **Noise warning:** later wave-12 reruns of the same code ranged 57-76 fps (load/thermal on a dual-core), with or without the facade. Compare only interleaved A/B runs, several repeats, never a single number against an older one.
- **G:** DONE 2026-10-09: Explosive blast scale cap 5.0 -> 20.0 (4x max diameter; `Projectile.BLAST_SCALE_MAX`, puddle cap raised to match). The Elite Four unlock gate was already built (`SquadDirector._eligible_rival_pool_keys`), so it is not a task.
- **P:** DONE 2026-10-09: overload marking now flags only the choke tile (reflected excess no longer marks the tile it flows back into; `Packet.reflected` in Rust and `EnergyPacket.reflected`). Not yet covered by a dedicated regression check (existing Mythic overcharge check passes). BGM ducking, pooled weapon SFX and scorch decals were already shipped 2026-10-05 (`SfxManager.gd`), so they are removed from the Polish lane.

### Lane contents (top item per lane each round)
**A (Rust):** (after prerequisites)
1. `hexmath`, `solid_grid`, `flow_field` into `pixbots_core`.
2. Rust spatial index replacing ~3,069 `StaticBody2D`s (A/B: +9 to +21 fps).
3. Per-tick mech movement/steering, status effects, hazards (the measured per-enemy cost).
4. `hexgrid_sim`, `separation`, projectile flight/broadphase into core; deterministic `step(dt)` + headless bench.
5. AI tactics port with golden-file tests; AutoEquipSolver port after its G rework.
6. wgpu GL spike on the HD 4000; data-driven Map/Campaign Editor (design-only).

**G:**
0. **Solver rework, stage 1 done 2026-10-09** (owner chose: fix accidental saturation, then build deliberate stable loops). Found with the new mech-level scoreboard `scripts/debug/SolverBenchDiag` (and `EnemyBuildImpactDiag`): (a) `_try_reattach` could route a dropped branch through its own orphaned subtree, closing a cycle between adjacent Splitters, so a solved torso saturated by itself; fixed (orphan subtree blocked), guarded by `EnergyGoldenCheck` "routing tree is acyclic". (b) Accessory Return faces were aimed by tree reasoning that fails for Reflectors/conduits entered from the side; now each of the 6 directions is tested with a real packet in the Rust sim (`_test_return_faces`) and only non-saturating, widest-reaching ones are used. Effect: accidental cycles used to put the 150,000 cap into mounts on rich player inventories; clean trees now deliver far less there (scoreboard gain_sum 34819 -> 14849 with refine; the old number was runaway energy). Enemy builds barely change (mean delivered per bot 71/149/241 vs 105/188/151 at rarity 1/2/3). Note: nearly all enemy bots report `sim_saturated` even on the old solver, so saturation alone is not a defect signal. **Stage 2 (2026-10-09, partly done):** (1) *Real bug fixed:* `ComponentLinkTile.clear_pending()` clears only `pending_packets`, not `pending_transfer_packets`, so any trial sim on a torso (the refiner, `_test_return_faces`) left queued transfers that the NEXT real `_recalculate_grid` forwarded again: the first recalculation after an Auto-Equip scored ~7x too high (278 vs 37.5 steady state) and could have deployed an inflated mech. New `HexGridComponent.clear_sim_residue()` is used by the refiner and solver; the refiner also now resets the sticky `sim_saturated`/overload flags per trial (`reset_flow()`). (2) *Deliberate loops:* `SolverRefiner._loop_pass` swaps a spare Splitter in (faces: forward + a dead-end side corridor), optionally with spare Amplifiers in the corridor (a packet sent into an empty corridor bounces off the grid edge with 5% loss per hex, so a loop needs no wiring); kept only if the sim score rises and the grid neither saturates nor overloads. `SolverLoopCheck` guards it. (3) *`MechRefiner`* (opt-in, mech-level): tunes Head/Backpack conditioner elements against the whole-mech score; only helps when those parts have configurable tiles (+42% on one rich case, +3% geomean overall). (4) Head/Backpack-first solve order: best-of-both-orders is worth ~+10% geomean on player inventories and ~0 on enemy spawns, so it is NOT adopted yet. **Honest scoreboard (steady state, `SolverBenchDiag`, geomean gain; refine on):** original solver 221, after stage 1 fixes 54, +loops/refiner 55-57. The original's lead came from accidental loops that saturated to the 150,000 cap; stable loops (lap gain < 1) only recover ~5-10%. DECIDED 2026-10-09 (bounded overcharge loops, default ON, Settings > Visuals toggle `SaveManager.overcharge_loops`; refiner clamps each mount to NORMAL_MAGNITUDE_CAP and keeps max 3 loops). Was: DECISION NEEDED from owner: whether to reintroduce deliberate cap-hitting "overcharge" loops (bounded, deterministic) or accept the lower clean power.
1. Smarter AutoEquipSolver (remaining stage 2 above): loops, mixed synergies, head/backpack as reactor boosters/conditioners (spec).
2. War Room upgrades incl. confidence display for build culling (culls after ~3 trials).
3. ~~Ice embrittlement + shatter~~ DONE 2026-10-09 (`scripts/core/IceEffects.gd`, `IceEffectsCheck`; numbers marked (tune) need a balance pass; enemies use FLOW_REF 200 as actuator flow).
4. Vortex pin / gravity-well mine / bezier wander (spec); Mythic remediation tile (spec).
5. Enemy use of terrain; remaining map scope (set pieces, map types, biome identity).
6. Elemental balance pass (`docs/ELEMENTAL_BALANCE_OPTIONS.md`), Guard `energy_for_max` calibration. Heat stays on hold.
7. Feature batch after the Rust ports: Bot League spectating, Tactical Puzzles, Wager Waves, Shop Cat, shop-framing UI.

**P:**
1. Tween panel transitions; garage conduit shader; drop-pod overlay.
2. Synergy Codex for biome interactions.
3. Phase 5 visual identity (build-driven player mech look).
4. Menu diorama (art); cutscene authoring (men in black) when the owner supplies beats.

### Watch items
Vulkan device-lost crashes on HD 4000 (resolved after 3 clean long sessions); near-peer difficulty (evolution rewards player/ally damage and kills).

### Parked (do not build unless re-raised)
Heat; Kinetic firing enhancement; transparent filler / circuit-logic tiles; Frank's Challenge modifiers ("The Eye"); VORTEX/VAMPIRIC corpse statues; Mythic Anchor; Pilot Skill Tree; superweapons; Modding 3-4; Expedition Map and niche tables; RTS spinoff; Multiplayer (GodotSteam); Pixelbots 2 (section 1a).

---

## 3. Active Work (reconciled against the code, 2026-10-05)

### Recently landed (2026-10-05 stretch, details in README changelog and `docs/ENEMY_POOL.md`)
- Projectile batch renderer is the default; mine/emitter traits, element-gateway roles (poison = turrets/mines, explosion = AoE, kinetic = sniping, ice = CC), missile impacts follow composition (blast, kinetic sword, chain lightning, poison turrets, burning ground).
- Enemy bot pool built behind a loading screen on every garage return; uncapped per-wave microcore energy scaling; rarity unlock waves [0,10,25,75,120].
- Haul-at-risk economy (40% lost per life, everything on game over) with an uncapped streak drop bonus; HUD wording reworked.
- Component viability guarantee (every dropped part is wired and routable); enemy-role starter torsos fixed.
- Music: equal-power crossfade (no silence dips), background prebake with disk cache, seeded `MusicGenome` that adds orchestral layers per 8 waves (cap generation 4).
- Maps: boulders and stone walls absorb non-weak hits and stop piercing shots; cacti, ice and lava rock stay destructible.
- Status visuals (frozen tint, paralysis jolts), sword asterisk visual, bench draw-call tracing, physics catch-up cap.

### 2026-10-06 additions
- Stability: three Vulkan device losses (HD 4000, Garage open at waves 28-37) led to a 410 MB ground texture being cut to ~40 MB, GPU memory logging, an auto safe-visuals tier after unclean exits, and Phase 8 (optimization) on the roadmap. Not proven to be the crash cause; watch the next logs.
- Fixed: spawn watchdog restarting waves every 10 s; ground z-order hiding decals/vents/rings/shallow tint.
- Maps: Phase 2 mostly landed (see docs/ROADMAP.md).

### Queued
Superseded by the lane-based queue in Section 2 (reconciled 2026-10-08). Phase 2 maps is mostly landed; only enemy terrain use, set pieces, more map types and biome identity remain.

### Owner decisions (2026-10-07), details in docs/OPEN_QUESTIONS.md
- **Resistance tiles shipped:** Stun Guard (concussed), Shock Guard (paralyzed), Freeze Guard (frozen). Energy-fed sinks; strength is proportional to the energy routed in (cap 90%); the cost is a cell, mass and that energy. Freeze Guard later becomes a heat sink.
- **Ice rework: superseded 2026-10-09 by embrittlement + shatter; see `docs/ELEMENTAL_REWORK_SPEC.md`.**
- **Vortex rework: superseded 2026-10-09 by pin / gravity-well mine / bezier wander; see `docs/ELEMENTAL_REWORK_SPEC.md`.**
- **Rust migration takes precedence over most feature work** (speed on weak hardware and Pixelbots 2 reuse; ideally leave Godot for the 3D sequel): see docs/RUST_MIGRATION_ROADMAP.md.
- **Balance before Heat.** Weak-GPU visuals tier switches on automatically but is switchable in Settings. Garage overload marking: mark only the chokepoints. Enemy use of terrain is the next map step. Pixelbots 2 tile columns: porcupine.
- **Story thread (cutscenes to author, spread across the game):** strange men dressed all in black, hexagon bodies like Frank's but with different proportions, come in and demand data.

### Gameplay & Balance
- **Kinetic firing-mechanics enhancement (2026-07-27, deferred):** the user disagrees it needs work ("Kinetic owns range"). Not an active want; do not build unless re-raised.
- **Heat as a system (2026-07-26, on hold as of 2026-10-05):** candidate cost axis for the calcified meta; zero design done. Explicitly held.
  - **Design sketch (owner, 2026-10-07):** heat gets a SECOND, much simpler plumbing layer: not literally under the hex grid and not the full hex map. **Heat pipes** need to be contiguous (so some components need heat-pipe setups), **heat sinks do not**, and non-contiguous bits are "not a disaster". The Freeze defence tile later becomes a **heat sink fed with x+ heat**; until heat exists, the Stun / Shock / Freeze resistance tiles are plain tiles whose resistance **costs grid capacity**.
- **Owner notes on Vortex and Ice (2026-10-07):** Vortex is worth packing because it pulls enemies into a spot where they can be wrecked; if it could **suck and hold** instead of only flinging, it would be stronger. Ice is "worse than lightning in every way"; the owner is open to options (see the options write-up in the session notes / README changelog once chosen).
- **Elemental meta is calcified (2026-07-27, partly addressed):** Lightning/Explosive/Kinetic/Pierce dominate; Vortex, Poison and Ice rarely worth packing. The 2026-10 gateway work gave Poison and Explosion real roles, but Vortex and Ice still need a balance pass. Options to be written up before any change. Infuser loops are fine for now.
- **Synergy Effects:** per-element status marks are shipped (frozen/paralyzed now have visuals; vortex needs none). Still open: deepen lingering VORTEX and VAMPIRIC effects (bleed/immobilize with corpse statues).
- **Anchor tile:** base-rarity Anchor is what makes self-fired Vortex controllable; Mythic tier is the remaining gap (full 2026-07-27 analysis in `docs/STATUS_ARCHIVE.md` section D).
- **Player mech visual identity gap (2026-07-27):** the player mech is hard-coded to one "player" look regardless of build, and component silhouettes are fixed at creation. Part of Phase 5.
- **Scout torso shape:** a tall lean silhouette shipped 2026-08-11 (scout/jammer/anti-missile share it). The originally requested leg-shaped 3-wide torso is NOT built; it must keep the 6-neighbour core hub and spoke-tip link guarantee.
- **Near-peer difficulty watch:** evolution rewards player/ally damage and killing blows; watch whether it needs a counterweight.
- **HUD & UX:** popup budget, unified menu keys and HUD legibility are shipped. Open: extend the Synergy Codex to biome interactions.
- **Elite Four rival tier:** wired as of the 2026-10-02 code check; still needs an unlock gate (all 15 Regulars beaten once) and real moddable-roster work; story beats deferred by the user (2026-08-05).
- **More transparent filler hex tiles / circuit-logic tiles (2026-07-22/27, design only), Frank's Challenge modifiers (flat damage reduction enemy, "The Eye" per-projectile damage gating) (design only).**

### AAA Polish Roadmap (user-proposed 2026-08-05)
- **Done:** GPUParticles2D migration; tabletop diorama shader; HitstopManager autoload; camera kick (`CameraShake.gd` spring); WorldEnvironment glow wired into the pixel viewport (`AAAPolishPhase1Check`).
- **Not built (verified 2026-10-05):** BGM ducking under heavy impacts (no compressor/sidechain anywhere); pooled/layered weapon SFX (no weapon audio pool); MultiMesh scorch decals (the only MultiMesh user is the projectile renderer); `Tween` panel transitions as a general pattern; energy-conduit scrolling shader in the garage; drop-pod transition (the garage is an overlay, so do it as an overlay animation, not async scene loading); hobby-shop diorama menu background (art task).

### Future Expansions
- **Synchronous Online Multiplayer (GodotSteam):** P2P lobbies, state-sync with client prediction; modes 1v1, 2v2, co-op wave survival, asymmetric 2v1 point-buy.
- **Expedition Map (2026-08-05, supersedes the branching-bracket idea), "Shovelfight 1920" and high-fantasy niche tables (explicitly roadmap-not-to-do), Bot Garage (multiple tables running different rule sets):** full text in `docs/STATUS_ARCHIVE.md` section D.
- **Pilot Skill Tree** (QoL, not power); **Deployables & Superweapons** (mines and turrets now exist as missile/poison traits; multi-hex superweapons do not); **Modding Phases 3-4**; **Cutscene content** (framework shipped, story beats unauthored).

---

## 4. History
Everything shipped, measured-and-reverted, or closed before 2026-10-05 lives in `docs/STATUS_ARCHIVE.md` (execution-queue write-ups, 2026-08 performance audits, and the Recently Shipped log). The README changelog is the running record from here on.

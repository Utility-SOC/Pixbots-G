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

## 2. Execution Queue (in order)

Garage QoL first (felt immediately), then small gameplay wins, then progression systems, then the big engine lift, then the feature batch.
1. **Data-driven tiles, late-game progression (Overclocking, Chip Splicing, Nemesis Bounties), Rust projectile/AI-tactics ports** - all shipped, reverted after measurement, or closed. Full write-ups in `docs/STATUS_ARCHIVE.md` section A.
2. **Feature batch (greenfield, verified 2026-10-05: no code exists):** Bot League auto-pilot spectating (via Frank's exhibition table), Tactical Puzzle Challenges (chess-style JSON scenarios), Wager Waves, Shop Cat, shop-framing UI pass. Champion Card art compositing is shipped.
   - **Possible RTS spinoff seed (2026-08-05, speculative):** the Bot League auto-pilot AI could be the foundation of a separate RTS on the same combat sim. Not a commitment.
3. **Data-driven Map/Campaign Editor + Multiplayer** (2026-07-27, design-only): a standalone editor that reads the game's own schema live (as `TileStatsRegistry` and `res://tiles/<TileType>/stats.json` already decouple balance data) rather than hardcoding a duplicate. Multiplayer (GodotSteam) is tracked under Future Expansions.

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

### Queued (agreed with the user, in order)
1. Smarter AutoEquipSolver (priority; enemy builds use its output too). 2. War Room upgrades, including confidence display for the AI's build culling (it culls builds after about 3 trials, so luck can delete good ones). 3. Phase 2 maps (terrain effects, zone gameplay, biome identity, more map types, set pieces). 4. Phase 3 audio and feel (ducking, pooled weapon audio, hitstop/camera audit, scorch decals). 5. Phase 5 visual identity. 6. Elemental balance options write-up (describe first, Heat on hold).

### Gameplay & Balance
- **Kinetic firing-mechanics enhancement (2026-07-27, deferred):** the user disagrees it needs work ("Kinetic owns range"). Not an active want; do not build unless re-raised.
- **Heat as a system (2026-07-26, on hold as of 2026-10-05):** candidate cost axis for the calcified meta; zero design done. Explicitly held.
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

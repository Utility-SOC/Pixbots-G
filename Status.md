# PixBots-G: Master Status Document (Active Work & Backlog)

This document tracks the active implementation targets, backlog, and design expansions for PixBots-G. (All shipped and completed features have been cleared from this tracker - see the short "Recently Shipped" section at the bottom only for orientation context.)

---

## 1. Lore & Vision Context
**The Core Fantasy:** You are playing *PixBots*, a wildly popular tabletop miniatures game at Evan's local hobby shop. The scale is 20mm miniatures fighting on a 4x8ft tabletop mat (1mm = 5px, 1 inch = 127px).
**The Goal:** Survive as many waves as possible against Evan's proprietary AI Director, which evolves and breeds new rival profiles to counter your strategies.

**Story (Canon):** The shop runs a standing competition: defeat the AI and earn merchandise. The Black Market is the shop's glass case; the War Room is your opponent studying your plays.

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

---

## 2. Execution Queue (in order)

Garage QoL first (felt immediately), then small gameplay wins, then progression systems, then the big engine lift, then the feature batch.

1. **Data-driven tiles** - shipped. Every one of the 24 tile scripts now reads its balance numbers (weight, charge/damage multipliers, per-rarity power/duration/interval curves) from `res://tiles/<TileType>/stats.json` via the new `TileStatsRegistry` autoload, falling back to the original hardcoded value if a file/key is missing - purely additive, verified byte-identical to prior behavior via `DataDrivenTilesCheck.gd` across all 24 types and all 5 rarities. Optional sprite PNG override per tile folder is a natural next step (not yet wired) for the full custom-tile-mod staging; procedural visuals remain the default per the locked ruling either way.
2. **Late-game progression** (in order):
   - *Overclocking (prestige):* at max component level, safely un-equips Mod Chips back to inventory, drops Chip Capacity until re-upgraded; grants permanent mass reduction or +1 hex.
   - *Chip Splicing:* merge two Mythic chips into one "Corrupted" dual-effect chip carrying a severe drawback from a large pool.
   - *Nemesis Bounties:* the Director breeds a boss from the player's own genetics (BossEvolution) to counter their build; drops unique inverted-synergy Nemesis Parts.
3. **Corporate Sponsorships** - post-max-level alignment with an in-universe manufacturer; biases loot via weights (see locked ruling) and adds tech constraints. **Each brand carries its own unique hex tiles** (ruled 2026-07-14) - design discussion pending before implementation starts.
4. **Rust projectile physics port (Phase 3)** - the real win: eliminate per-projectile Area2D nodes entirely (Rust-side spatial hash + batched sweeps in `rust_ext`), feeding the `pixbots_core` extraction. Already landed toward this: ProjectileFlight batched flight math, `hexgrid_sim.rs` stub, and the GDScript saturation tiers (consolidation + visual LOD + popup budget) that relieve the immediate pressure.
5. **Feature batch:** Bot League auto-pilot spectating (entered via Evan's exhibition table), Tactical Puzzle Challenges (Evan's chess-style JSON scenarios, restricted parts, strict timers), Shop events (wager waves first; Shop Cat flagship later), shop-framing UI paradigm pass across all menus. Champion Card art compositing the real mech sprite: shipped.

---

## 3. Backlog & Improvements

### Bugs & Code Health
- **God-Class Aftercare (done):** `Mech.gd` audited at ~3000 lines. The 5 pre-existing splits (`BossBrain`, `StatusEffectRunner`, `PlayerController`, `MagnetSystem`, `SightAndSearch`) were confirmed genuinely lazy-constructed and cleanly delegated - never the problem. All three "equippable ability" cuts are done: `CloakSystem` (`b3adf92`), `JammerModuleSystem` (`fedc6ae`), `HealBeaconSystem` (`4c17922`) - each verified with zero regressions across the full check suite. The former 394-line `_recalculate_grid` was also broken up: unlike the ability cuts, it's the central orchestrator touching ~25 fields across every other subsystem and is called externally from `GarageSimulationRunner.gd`/`GarageTestRange.gd`/several debug checks, so moving it to a new composed file would've relocated risk rather than reduced it. Instead it stayed on `Mech` as a pure extract-method split into `_reset_grid_state`/`_compute_mass_and_stat_modifiers`/`_simulate_energy_flow`/`_collect_weapon_mounts_and_tile_capabilities`/`_finalize_grid_state` - zero behavior change, verified across 24 regression checks (Cloak/Jammer/HealBeacon/TestRange/SimTimeline/GarageEditFix/TileConfig/all Jammer variants/MagnetRepel/Synergy/WaveScaling/TileRarity/Mortar/Blueprint/FleeThreshold/SearchEscalation/DirectorTells/RustExt/Rasterizer/MapConnectivity), all passing. The **damage/combat pipeline** (`apply_damage`/`apply_part_damage`/shield mitigation/disable rolls, ~366 lines) was audited last and found already healthy: it's 8 well-named, appropriately-sized private helpers (12-75 lines each), not one monolith. `apply_damage` has 24 external callers and `_show_floating_text`/`elemental_resistances`/`recent_damage_log` are accessed by name from SquadDirector/Main/BossBrain/Drone/HealBeaconSystem/PlayerController - moving any of it to a composed file would add an indirection hop with zero reduction in Mech's public surface. Left as-is; no extraction warranted. Tech-debt pass complete.
- **Consolidation-first mode:** per direction given 2026-07-16, no new features until this pass and a general stability sweep are done.
- **Spatial Hashing:** Largely superseded by `EntityCache` + the saturation tiers; the remaining need (projectile broadphase) folds into queue item 4.

### Gameplay & Balance Improvements
- **Boss Variety:** Stop scaling up Brawlers. Use role-specific bosses or genuine boss-only kits.
- **Synergy Effects:** Signature status marks per element are shipped; deepen the lingering effects for VORTEX and VAMPIRIC (bleed/immobilize interactions with corpse statues).
- **Near-peer difficulty watch:** evolution now earns premiums for player/ally damage and killing blows - watch whether it needs a counterweight (rubber-banding, bounty rewards for the player) as it sharpens.
- **HUD & UX:** damage-number noise (popup budget shipped), unify menu keys (shipped), HUD legibility (shipped). Extend Synergy Codex to cover biome interactions still open.
- **Scout torso shape:** a Scout-role torso should be leg-shaped - 3 hexes wide, variable length (matching the existing leg silhouette code) - rather than the current symmetric-disc torso shared by every role. Note: the recent torso-link-reachability fix deliberately removed the OLD scout/brawler torso thinning (it broke peripheral-link routing); this is a from-scratch replacement silhouette, not a revert, and must keep the 6-neighbor core hub + spoke-tip link placement guarantee that fix added.
- **War Room "recent deaths" panel:** show the last 5 bots that killed the player (name/role/build snapshot) when entering the War Room FROM THE GARAGE specifically (i.e. after a death sent you there, not just any War Room visit) - lets the player study exactly what beat them. Needs: a small rolling death-log (SaveManager or WarRoomSnapshot-adjacent), populated wherever the player's death is currently attributed (see Mech._log_incoming_damage/resolve_attacker_label), and a new UI section in WarRoomMenu.gd gated on garage-entry context.

### Future Expansions
- **Synchronous Online Multiplayer (GodotSteam):** P2P lobby punch-through using GodotSteam (no dedicated servers required).
  - *Network Model:* State-sync/Server-Authoritative with Client Prediction (since the combat/mat phase is explicitly non-deterministic by design; only the Garage hex-routing is deterministic).
  - *Game Modes:* 1v1 duels, 2v2 brawls, 1+1 / 2+2 Co-op wave survival.
  - *Asymmetric PvP (2v1):* A point-buy system for components before the match where the solo player receives twice the point budget as the duo players.
- **Expedition Map:** Slay-the-Spire style branching Tournament Bracket/Shop Campaign.
- **Pilot Skill Tree:** Earn XP for permanent QoL/utility passives across runs (QoL, not power, per ruling).
- **Deployables & Superweapons:** Proximity mines, turrets, massive multi-hex superweapons (e.g. AoE shield domes).
- **Modding (Phases 3-4):** Custom bot types and custom tile scripts extending `HexTile` (staged by queue item 1).
- **Cutscene content:** the framework is shipped and data-driven (`config/cutscenes/`) - actual story beats and real sprite PNGs are authoring work, gated on STORY_SCRIPT.md.

---

## 4. Recently Shipped (orientation only - cleared from tracking)
- Easy-wins batch: starter inventory rarity curve (no more free Legendaries), Ambusher decloak reveal burst + targetable Heal Beacons (disable-priority), HUD text outlines + unified menu keys (WarRoomMenu now uses real InputMap actions like everything else), Champion Card sprite portrait (real in-engine MechRenderer render composited above the existing hex-schematic blueprint via a throwaway SubViewport rig)
- Data-driven tiles: all 24 tile types + `TileStatsRegistry` autoload, `res://tiles/<TileType>/stats.json` per type, zero behavior change (verified)
- Simulation Timeline Scrubber + Packet Inspector: deterministic re-run-to-step-N replay (no state buffering - Resonator/Splitter/Catalyst mutable state resets via HexTile.reset_simulation_state before each replay), drag-to-scrub HSlider synced to live auto-play, click-a-tile packet inspector showing current output + last-5-packet history per direction
- Garage Test Range: live-fire any armed mount's real combat packet at a target dummy in a private physics world (SubViewport + own World2D) - real projectiles, patterns, damage numbers, shots/avg readout
- Tile config batch (`1300fb6`): Resonator per-path Sync Dropoff, Mythic Splitter output ratios, Catalyst gated injection (magnitude + cadence gates), Accumulator auto-dump thresholds - all in the click-a-tile config popup, all save-persistent
- Wild-bot flee thresholds: skittish roles break off and go wild (squad + wave accounting stay honest, wounds regen while loitering, director recruits them back)
- Saturation perf tiers: volley consolidation, projectile visual LOD, damage-popup budget (`d65ab79`)
- Drone sortie leash fix (1000/2000px), near-peer AI fitness premiums, Mythic boss torso hex-budget fix (`d65ab79`)
- Pixel-art cutscene framework + sample Evan beat (`6bc1b63`)
- Power-scaled jammer fields + minimap jammer secrecy swirl (`3f3df78`)
- Unlimited named save slots for builds and parts (`fa26417`)
- Earlier: Scrap Shop, captured loadouts, Lance Mount, recon/Chinook drones, lightning blink identity, mortars with true direct-fire payloads, strategic zoom, demo builds, module keybinds, obstacle corridor carving.

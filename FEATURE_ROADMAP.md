# Pixbots-G: Feature Roadmap & Design Decisions

Master document combining the two feature reviews (original 7-feature list + 11 follow-up items) with Natalia's design decisions, grounded in a full read of the codebase. Companion to `GAME_IMPROVEMENT_SUGGESTIONS.md` (which covers bugs/polish; this covers new features).

**Key architectural fact that shapes everything below:** the energy grid is NOT simulated live during combat. `Mech._recalculate_grid()` runs a BFS once per loadout change; combat fires on charge timers with precomputed packets. Features are scoped to respect that unless explicitly noted.

---

## Decision Log (locked in)

| Decision | Ruling |
|---|---|
| Heat system | **Lightweight derived-heat version.** Per-packet/per-tick live simulation is too expensive. Heat is computed from the existing static grid sim (see spec below). |
| Elevation | **No true z-levels.** At most, shading-based hills/dips (visual + optional minor speed modifier). Undecided if even that is worth it in 2D — revisit after the tabletop reskin lands. |
| Mythic Magnet | Attract/Repel toggle **joins** the existing rarity-filter ability (both active). Mythic is supposed to be gamebreaking. |
| Piercing "cut in half" instant kill | Exempt: **bosses, Commanders, Piercing Jammers, and any unit inside a Piercing Jammer's aura.** AI should detect over-reliance on pierce executions and counter automatically (see AI section). |
| Jumpjets + water | If a mech has jumpjets and **spawns on (or is on) water, jumpjets immediately turn on and stay on** — no drowning while jumpjet energy holds. |
| Miner Gun Builder content | `mod_guide_text.txt` deleted (scraped blog content from another game — inspiration only, not to be shipped). |
| Modding | Phased; synergies stay a fixed enum with moddable *parameters* (see Modding section). |
| Canonical tabletop scale (REVISED) | **Pixbots are 20mm miniatures.** A ~100px mech sprite = 20mm, so **1mm = 5px, 1 inch = 127px**. A 4x8ft table = ~381x190 tiles; the "Tabletop" map type ships at **384x192** - nearly classic-map size, matching the game's pace. Governs section 6 melee/mass tuning and feature-2 terrain sizing. Blue outer walls = the firring strips. (Supersedes the old 4-7"/18px estimate.) |
| Tile destruction permanence | **RULED + SHIPPED: no permanent destruction.** Combat damage soft-disables tiles (auto-reboot) or, on grave hits, fries them (`power_lost`) - fried tiles stay dead until repaired in the Garage for scrap. power_lost now persists in saves (no quit-reload healing). |
| Map rotation | **Tabletop is in the per-run rotation now (double-weighted).** Long-term, EVERY map becomes a themed tabletop mat - biomes are mat prints, not "real terrain". |
| Tutorial voice | **Evan**, owner of the local game shop. PixBots Corp sponsors trainer/tournament tables at shops to grow the game; it caught on like wildfire - every kid has a pixbot or two. The player's was a birthday gift; they're learning on Evan's trainer. Claude drafts, Natalia edits. |
| Visual pipeline (2026-07-10) | **Stays purely procedural 2D** - shaded-primitive layer + module vocabulary, NOT the 3D-to-2D "Dead Cells" pipeline (rejected: needs modeled assets, viewport-bake management for 80 mechs, obsoletes the Rust rasterizer). 3D-to-2D is filed next to the Bevy option as escalation-only. |
| Card PNGs (2026-07-10) | **Every exported card PNG carries the full player buildout** in its iTXt payload - one PNG serves both purposes: fight it (Traveling Champion ghost) or import it as a Blueprint (build it in your own Garage, parts permitting). |
| Fourth-review feature batch (2026-07-10) | **Approved:** Bot League auto-pilot spectating, Blueprint Cards, obstacle demolition (obstacles get HP + element weaknesses; EXPLOSION/ramming carve paths, with baseline connectivity corridors still guaranteed), Director "tells" (pre/post-wave intel lines from real telemetry), remote-payload weapons (indirect-fire missile racks that deliver AoE at a targeted point with travel time + telegraph). **Also approved from Gemini's third review:** Corporate Sponsorships (as loot WEIGHTS, never hard filters), Tactical Puzzle Challenges, shop-event wave modifiers ("wager waves" first, Shop Cat as the later flagship event). **Skill tree ruling:** QoL/utility unlocks (rerolls, slots, intel, repair discounts), NOT combat-power passives - protects near-peer scaling. **Expedition Map:** build it AS the Tournament arc when its turn comes. **Passed on:** daily seed challenges. |
| Playtest rulings (2026-07-10 evening) | Part layering: **backpack < limbs < torso < head**. **Mismatch grunts approved** - per-part surplus colors converging to role colors by ~wave 50. Indirect fire ships NOW as the Mythic mount's **"Mortar" pattern**; the dedicated MissileRackTile stays a stub until the weapon-variety pass. **Bot League enters via the shop** (Evan's exhibition table), and ALL menus progressively adopt the shop framing. Champion Card art gets the real mech sprite next time that file is touched. |
| Pixelbots 2 (3D sequel) | `godot-3d` folder is its start: same game systems in 3D with perspectives. Convention adopted NOW in PB1: gameplay rules live in RefCounted/static classes with no Node/drawing dependencies; renderers only read state. Long-term: extract the sim into an engine-agnostic `pixbots_core` Rust crate (see Rust section). |

---

## Lightweight Thermal Management (v1 spec)

No live packet economy. Heat is a scalar per component (or per mech to start), derived from data the static sim already produces:

- **Heat generation:** `heat_rate = f(total adjacent-accumulator bank charge, charge_required, packet magnitude at mounts)` — all known at `_recalculate_grid()` time. Combat just integrates one float per frame.
- **Venting on fire:** each weapon discharge vents heat proportional to volley size. Design note: since firing cools, heat only punishes *sitting on a charged bank without releasing it* — that's the intended tension (hoarding a mega-volley is risky), not a fire-rate limiter.
- **Ice cooling:** if the grid's dominant stored synergy is ICE (already computable via `EnergyPacket.get_dominant_synergy()` on the simulated packets), heat_rate is reduced or negative. Ice Accumulator + Catalyst = a legitimate full solution to heat.
- **Volatility thresholds** (checked against the heat scalar + dominant stored synergy):
  - LIGHTNING over threshold → periodic arc damage to tiles adjacent to the accumulator (reuse `HexTile.take_damage`, which already has disable/reboot logic).
  - VORTEX over threshold → visual packet-warp only (renderer effect, no sim change).
  - KINETIC / PIERCE / RAW → no volatility (as designed).
- **Overheat consequence:** disable the hottest accumulator via the existing `is_disabled` machinery rather than inventing new failure states.
- **Tiered capacity (64/…/512/1024) & Mythic threshold slider:** deferred to the live-packet rework, IF it ever happens. In v1, "capacity" maps onto the existing bank-charge scaling instead. Do not build packet counting for v1.
- **Proportional, not flat:** all heat effects (generation rate, vent amounts, volatility severity) scale proportionally with total stored bank charge — a Legendary bank runs proportionally hotter, vents proportionally more per shot, and arcs proportionally harder than a Common one. No flat per-tier constants.

Cost: a few floats per mech per frame. Gets ~80% of the feel for ~10% of the rewrite.

---

## Original Feature List — status & scope

### 1. Grid & Heat Thermodynamics
Superseded by the lightweight spec above. Full live-packet accumulators (siphoning 10% of passing packets, real packet counts) remain a possible far-future rework — do not start it until the derived-heat version proves the fantasy is fun.

### 2. Tabletop-Themed Environments
- **Aesthetic reskin:** *(unclear if the specific foam-mat palette/terrain-bit sprite pass landed - the Tabletop map type itself exists and is in the per-run rotation double-weighted, but the visual reskin detail is unconfirmed. Worth a quick look before assuming either way.)*
- ~~**Destructible pillars/blockades**~~ (Done — obstacle demolition shipped: obstacles have HP + element weaknesses, EXPLOSION/ramming carve paths, with guaranteed baseline connectivity corridors.)
- **Elevation:** shading-fake only, if at all (see Decision Log). No LoS/projectile/pathfinding height logic. *(Deferred indefinitely by design, not a real backlog item.)*
- ~~**Oil slicks / water hazards**~~ (Done — oil slick hazards shipped alongside water divers.)

### 3. Directional Damage & Grid Sabotage
- **Shield protection: already done** — `_apply_shield_mitigation()` fully absorbs part damage while shields hold.
- **Angle-based tile hits:** replace the random-tile pick in `apply_part_damage()` with impact-point → hex mapping via `PartHitbox`. *(Still open - medium; no evidence this has shipped.)*
- ~~**Permanent destruction:** deliberate change from the current disable/reboot model. Decide "destroyed for the run" vs "until repair" before building.~~ (Resolved via the Decision Log: **ruled against, shipped the other way** — no permanent destruction. Combat damage disables tiles (auto-reboot) or, on grave hits, fries them (`power_lost`) until repaired for scrap in the Garage. `power_lost` persists in saves.)
- **Cascading failures:** per-component sims are already isolated; arm-loss disabling its mounts falls out of the `ComponentLink` structure. *(Unclear if formally verified/tested as intended - the plumbing exists, worth a quick playtest check rather than assuming.)*
- **Armor stat:** new; fits naturally as a tradeoff inside `ComponentEquipment`'s procedural shape budget. *(Still open - medium.)*

### 4. Evolving AI & Squad Tactics
Largely already built (`SquadDirector`, `SquadTemplateMutator`, `SolverProfile` — templates, weighted selection, mutation, fitness culling, reactive counter-profiles).
- ~~**New: Commanders**~~ (Done — the `commander` role exists with a Command Suite backpack stacking up to 5 support modules, and now always includes a Drone Bay by default.)
- **New: config borrowing from successful past buildouts** — medium; fitness signal already exists. *(Still open.)*
- ~~**Prerequisite:** instantiate `SquadProfileManager`~~ (Done — `SquadDirector.gd` instantiates it; template/profile learning persists across restarts via `user://ai_profiles/`.)
- ~~**New: pierce-execution counterplay.**~~ (Done — kill-method tracking + Piercing Jammer up-weighting on over-reliance is built, alongside the full pierce cut-in-half execution system with its exemption list.)

### 5. Upgrade Paths, Infusion & Black Market
- ~~**Scrap economy first**~~ (Done — 5+ spend sites in `GarageMenu.gd`: upgrades, repair, infusion, rarity tier-up, Black Market.)
- **Manual hex placement on upgrade:** a Garage editor mode on top of `GarageGridRenderer` + `ComponentEquipment.generate_procedural_shape` foundations. *(Done per the "Feature 5 phase 2" status note below — manual-hex component upgrades shipped.)*
- **Modifier infusion:** *(Done per the same status note — extraction/stacking-infusion shipped, chip system exists.)*
- **Mythic toggles:** ship 3–4 per patch. *(Batch 1 done per the status note below: Core native element, Catalyst invert, Weapon Mount patterns, Magnet repel, Jumpjet blink, Amplifier focus. Resonator sync and Conduit valve modes remain open, blocked on the melee/mass pillar's parent-system decisions.)*
- ~~**Black Market**~~ (Done — 10-min deterministic rotation, forbidden-tile drawbacks.)

### 6. Melee Actuators & Mass Physics
*(Status update: this is no longer "zero code exists" — weight/mass/ramming groundwork landed in the second-review pass. Every tile has weight, movement speed scales with total mass, ramming damage is `mass × speed`, and pierce cut-in-half executions exist with the full exemption list (bosses/Commanders/Piercing Jammers/aura) plus the AI counter-play from §4. What's still genuinely unbuilt is dedicated Melee Actuator weapon behavior itself — see `mythic_mode` on `ActuatorTile.gd`, which has "Schools" defined but the underlying melee-weapon mount mode is still blocked on this pillar's own remaining scope.)*
- ~~Weight value on every tile; mass-based movement rebalance~~ (Done.)
- ~~Ramming = contact damage from `mass × speed`~~ (Done.)
- Shield-element ram synergies (`dominant_shield_synergy` exists) — *(unclear if wired into ramming specifically, worth a quick check.)*
- ~~**Piercing cut-in-half:** percentage chance, with the exemption list~~ (Done.)
- **Dedicated Melee Actuator weapon mode** — *(still the real open item here - large, was scoped "build last" for a reason.)*

### 7. Elemental VFX & Instant Arcing
- `LightningChain` already arcs instantly between enemies; remove the flying bolt sprite for lightning-dominant shots, flash impact VFX directly. Modest.
- **Style note:** "photorealistic" contradicts the pixel aesthetic feature 2 preserves — stylized-but-instant jagged polylines instead.
- **Proportional synergy blending:** `Projectile.gd` already blends speed/scale/lifetime/trails/color by synergy *ratios*; the remaining work is converting the threshold-gated movement behaviors (vortex spiral, lightning jitter) to weighted composition. Incremental, not a new system.

---

## Follow-up Items

- ~~**Minimap + UI audit**~~ (Done — `MinimapOverlay.gd`, U-key toggle, resizable/zoomable/movable, feeds from existing node groups.)
- **Synergy threshold effects (remaining 8):** impact statuses today are only frozen/burning; projectile-side threshold checks already exist to hang new ones off. Vampiric corpse-obstacle is the only one adding a new system (corpse collision bodies — watch perf at 80 enemies). Lightning→paralyze and Vampiric→bleed/immobilize already spec'd. *(Still open - medium.)*
- ~~**Cloak redesign**~~ (Done — `Mech.gd` has `CLOAK_SHADER_CODE`, a real screen-UV distortion effect replacing the old alpha fade.)
- ~~**War Room UI**~~ (Done — template weights/fitness/lineage, a "YOUR MECH" power-estimate card, procedural rival/AI designation names.)
- ~~**Persistent/shareable/breedable AI profiles**~~ (Done — `SquadProfileManager` is instantiated and wired; crossover functions exist in both `SquadTemplateMutator.crossover()` and `ProfileEvolution._crossover_profiles()`.)
- ~~**Per-component loadout profiles**~~ (Done — `SaveManager.save_component_loadout()`/`load_component_loadout()`, with "This part" Load/Save slots in the Garage UI, scoped per body-slot type.)
- ~~**Water enemies + jumpjet logic**~~ (Done — water divers shipped with flow-field pathing; `_check_drowning()` grants jumpjet-holders immunity while `jumpjet_energy > 0`.)
- ~~**Tutorials/onboarding**~~ (Done — see below.)

## Tutorial, Story & UX (promoted to its own workstream)

- ~~**Tutorial:** first-run guided flow~~ (Done — `TutorialManager.gd` + `tutorial.json`, a full guided flow in Evan's voice: Core → tiles → weapon mounts → Simulate → accumulators → heat → repairs → Black Market/chips → the AI/War Room → minimap. Contextual tile-hover tooltips now also carry a one-line "what does this do" per tile type, and the Synergy Codex covers all 9 synergies + shield counters — though it still skips biome interactions, worth extending.)
- **Story (canon premise, per Natalia):** You spend every day after school at the game shop brawling AI bots in a new game — *PixBots*. You got a base bot for your birthday and want to earn more components. The shop runs a standing competition: defeat the AI and earn merchandise (in-fiction, every match helps train the AI that PixBots fields against all players — which is literally what the SquadDirector's learning loop does). `campaign.json` + `Main._load_campaign()` already exist as the delivery hook; tell it through intermission text and environment dressing, no cutscene tech needed. The Black Market is the shop's glass case; the War Room is your opponent studying your plays.
  - ~~**Rival challenges**~~ (Done — `SquadDirector.gd` has `all_rival_profiles`, `get_next_rival()`, rivals-fought tracking, and named-rival wrapper via `RivalProfilesFactory.gd`.)
  - ~~**PvP via profile swap**~~ (Done, and taken further than the stretch goal described — shipped as Traveling Champions: Champion Card PNGs carry the full build via PNG steganography, doubling as importable Blueprints.)
  - **Confidence & milestone rewards:** the player character grows more confident as the story progresses. Beat 10 bosses/enemy champions → 1 Legendary component + 2 Legendary tiles. Reach level 100 → 1 random Mythic tile + 1 Mythic component. *(Still open - medium: the milestone counter/flag scaffolding exists per CLAUDE_CODE_HANDOFF.md, but nothing sets it true yet.)*
- **UX pass:** the audit bundled with the minimap — HUD legibility, damage-number noise, menu key consistency (`, TAB, U, Esc all live on different layers now), garage discoverability, and save/loadout-slot clarity. *(Garage discoverability and save/loadout-slot clarity are now Done — see GAME_IMPROVEMENT_SUGGESTIONS.md's UX/onboarding section. HUD legibility, damage-number noise, and menu-key consistency remain open - small-medium each.)*

---

## Modding — the actual recommendation

Phased, cheapest-real-value first. Do NOT attempt fully moddable synergies.

1. **Now (nearly free):** formalize what already works — squad templates and AI profiles load from JSON (`config/`, `user://ai_profiles/`). Write a real `MODDING.md` documenting those formats (replaces the deleted junk file).
2. **Data-driven tile stats:** keep behavior in GDScript classes, but expose the numbers (`charge_multiplier`, `damage_boost`, rarity multipliers, splitter face counts…) via JSON overrides loaded at startup. Medium effort, huge modder value.
3. **Custom bot types / graphics:** bot roles as data (archetype weights, module lists — `_get_archetype_weights()` is already table-shaped); texture-override folder for sprites.
4. **Custom tile types:** script registration (a mod ships a `.gd` extending `HexTile` + a manifest). Godot loads scripts at runtime, so this is feasible — but it's a security/stability commitment. Later.
5. **Moddable synergies: don't.** `SynergyType` is a fixed enum threaded through Projectile, Catalyst, shields, jammers, and VFX; making it dynamic is an invasive rewrite with modest payoff. Instead expose synergy *parameters* (colors, status durations, threshold values, shield counter-matrix) as data. Modders get 90% of the expressiveness at 5% of the cost.

---

## Combined Build Order

**UPDATE (July 2026 second review):** large chunks of groups 6-8 have now
ALSO landed: evolving Boss kits (abilities/enrage/positioning via
BossProfile), Rival Challenges (story feature), Drones + Drone Bay,
Piercing Jammers with execute-immunity auras (the §4/§6 exemption made
real), shield Deflector overflow, mass/weight + ramming groundwork, oil
slick hazards, water divers, flow-field pathing, destructible ruins wired
into nav, tutorial system, and death reports. Fixed in the second-review
pass: Mythic Magnet Repel now REFLECTS projectiles (ownership flip),
per-bot element jitter (no more early-wave monoculture), settings moved to
user:// (persist in exported builds), director telemetry persisted
(counter-doctrine remembers between sessions), chips counted in near-peer
power, map-area enemy-density scaling, save-format version log. Unplanned but massive features that also landed: Traveling Champions async PvP (PNG steganography), Procedural Reactive Audio, Wave HP soft-knee scaling, the Mech.gd god-class split (BossBrain/StatusEffectRunner/PlayerController/MagnetSystem/SightAndSearch extracted), the arm module vocabulary (MechModuleLibrary), AI LOD (distance-tiered tick divider), and the Rust GDExtension (`rust_ext.dll`) which ported Part Rasterization and Projectile Physics to native code! Remaining majors: melee actuators proper - see GAME_IMPROVEMENT_SUGGESTIONS.md second review for the full list. (Heat UI is deliberately DROPPED, not pending - the thermal system itself is commented out per design ruling; see CLAUDE_CODE_HANDOFF.md.)

**Status: groups 1-5 SHIPPED ✔, plus original Feature 5 phase 2 SHIPPED ✔**
(manual-hex component upgrades, modifier chip extraction/stacking-infusion,
Mythic toggles batch 1: Core native element, Catalyst invert, Weapon Mount
patterns, Magnet repel, Jumpjet blink, Amplifier focus — all persisted in
saves; Black Market with 10-min deterministic rotation and forbidden-tile
drawbacks. Still open from Feature 5: Resonator sync (needs cross-component
sim plumbing decisions), Shield Aegis/Deflector + Conduit valve + Melee
Actuator modes (blocked on their parent systems), Accumulator threshold
slider (blocked on live-packet rework, likely never).) Unplanned work also shipped:
debug-menu tab layout, Legendary pixel-visual fix, accumulator pre-prime
firing model (passive charge, mouse = normal gun with quality tax,
hold-1/2/3 = full-value dump), enemies spawn 70-100% primed, and the kill
counter-doctrine generalized to every non-RAW synergy with targeted
synergy-jamming. Movement blending (group 3) was found already
ratio-proportional in Projectile physics; the delivered work was instant
lightning + the full status suite. Remaining: groups 6-8.

1. **Finish what's written + War Room:** wire `SquadProfileManager` (persistence + clipboard sharing), **War Room UI** (promoted — makes the AI learning loop visible early and everything after it benefits from the observability), cloak shader, minimap, per-component loadout slots, jumpjet-on-water rule, `MODDING.md` phase 1. *(junk mod guide: deleted ✔)*
2. **Scrap economy** — one system unblocking upgrades, repair, infusion, Black Market, drop-rate rebalance.
3. **VFX cluster:** instant lightning, proportional movement blending, remaining synergy threshold effects.
4. **AI cluster:** Commanders, profile breeding, pierce-counter tracking (War Room UI already live from group 1 to visualize these as they land).
5. **Lightweight heat system** (spec above).
6. **Combat structure:** directional damage (angle mapping + permanence decision), tabletop terrain reskin + destructibles, oil/water hazards, water enemies.
7. **Tutorial + Story + UX workstream** (see dedicated section above) once the above stabilizes; tooltips/codex may land earlier opportunistically.
8. **Big pillars last:** melee/mass physics; data-driven tiles (modding phase 2–4); live-packet accumulators only if derived heat proves insufficient.

---

## Rust Architecture Rewrite (Stretch Goals)

As the game scales to support massive battles (hundreds of mechs, massive hex layouts), performance bottlenecks in GDScript will emerge. A hybrid Godot/Rust approach (via `godot-rust` / GDExtension) provides a scalable, incremental path forward.

### Phase 1 & 2: Low/Medium-Lift (SHIPPED)
- **Part Rasterizer (`part_rasterizer.rs`)**: Nested point-in-polygon loops for generating procedural mech shapes were moved to a single FFI call returning RGBA8 pixels, eliminating enemy-spawn stutter.
- **Projectile Flight Physics (`projectile_flight.rs`)**: Organic velocity math (Kinetic steering, Fire drag, Poison lobs, Vortex swirl, Lightning arcs) batched into a single Rust call for all active projectiles, eliminating GDScript dispatch overhead.
- **HexGrid & Data (`hexmath.rs`)**: pipeline-validation benchmark class (neighbor/distance math with a checksum assert) proving the FFI round trip - NOT the grid solver itself. `_recalculate_grid`/`AutoEquipSolver` remain GDScript and stay on this list if they ever profile hot.

### Phase 3: High-Lift (Physics & Engine Switch)
- **`Mech.gd` & Ramming Physics:** Moving the core mech loop into Rust requires constantly passing position, velocity, and `move_and_slide()` data across the C++/Rust boundary.
- **Full ECS (Bevy Engine):** The nuclear option. If the project outgrows Godot entirely, dropping the Godot UI and rendering pipeline in favor of a pure Rust ECS (Entity Component System) like Bevy. Maximum performance, but requires rebuilding all visual and interface tools from scratch.

---

## Brainstormed Future Expansion (Third Review)

These are concepts to flesh out the mid-to-late game progression, meta-game, and thematic immersion.

### Progression & Meta-Game
- **Expedition Map (Slay-the-Spire Style Progression) [Difficulty: Medium-High]:** Move away from a purely linear wave structure to a branching path "Tournament Bracket" or "Shop Campaign". Nodes could include Standard Matches, Elite Rivals (harder AI, better loot), Black Market, Repair Stations (spend scrap to fix destroyed hexes), and Mystery Events. Gives players strategic agency between battles.
  - **Implementation:** 
    - **UI:** A new node-based map scene showing the branching paths.
    - **Data:** A generator that procedurally creates the node tree, randomizing encounters based on depth.
    - **State:** Updating the save format to track current node, visited nodes, and available paths instead of just a linear wave counter.

- **Corporate Sponsorships (Loot Filtering) [Difficulty: Low-Medium]:** After defeating a boss, align with an in-universe manufacturer (e.g., Heavy Industries for Kinetic/Armor, Quantum Dynamics for Lightning/Energy). Each boss represents a different sponsor, featuring a unique gear table, aesthetic, and loot pool. Defeating them grants access to their specific tech.
  - **Implementation:**
    - **Data:** Define "Sponsors" as data resources (JSON/GDScript), linking them to specific synergies, drop tables, and boss visual themes.
    - **Loot Logic:** Hook into the existing drop generator and Black Market roller to weight probabilities based on the active sponsorship.
    - **Boss Integration:** Add metadata to `BossProfile` linking them to a sponsor to determine their loadout and rewards.

- **Pilot Skill Tree (Meta-Progression) [Difficulty: Medium]:** Earn XP alongside Scrap to level up the Player Character. Unlock permanent passive buffs across all runs, such as a Black Market discount (*Haggler*), free initial hex repair (*Duct Tape*), or a 2x charge multiplier on the first energy packet generated each match (*Overclocker*).
  - **Implementation:**
    - **UI:** A new skill tree menu in the Hub/Garage.
    - **Data/State:** Add XP and unspent skill points to the global save state.
    - **Hooks:** Thread the passive checks into existing systems (e.g., modifying Black Market prices, intercepting `_recalculate_grid()` for the *Overclocker* buff).

### Gameplay & Modes
- **"Real World" Tabletop Hazards [Difficulty: Medium-High]:** Lean into the physical shop aesthetic by having random "Shop Events" act as global battle modifiers for a wave. The most intense hazard is the **Shop Cat**: an entity that attacks bots moving too fast or interfering with its feline goals, causing massive damage and smashing bots against walls.
  - **Implementation:**
    - **Shop Cat:** A neutral, highly unpredictable AI entity (or environmental hazard) on the board. Needs custom logic to detect "fast movement" (velocity thresholds of nearby units) and a unique attack action (massive knockback/collision damage calculation).
    - **Global Modifiers:** Add a modifier system checked at wave start to alter global variables (e.g., heat generation for a broken A/C, or tile friction for spilled soda).

- **Tactical Puzzle Challenges [Difficulty: Medium]:** "Chess puzzle" style challenges set up by Evan. The player is given a specific enemy (e.g., a massive shield-tank) and a restricted box of parts, needing to build a mech to win in under 20 seconds. Teaches advanced, niche synergy interactions safely.
  - **Implementation:**
    - **Data:** A new JSON format defining specific challenge scenarios (fixed enemy loadout, fixed player inventory, time limit, win condition).
    - **Game Flow:** A mode that skips the standard campaign progression, forces a specific Garage state, and auto-fails the battle if the timer runs out.

- **Shop Wars (Asynchronous Clan Battles) [Difficulty: Low]:** Asynchronous PvP where players form clans and share JSON AI profiles online. People upload their JSONs to a website, and others download/upload/share them to fight and conquer territory.
  - **Implementation:**
    - **In-Game:** Utilizing the existing `SquadProfileManager` JSON export/import. The game needs a streamlined UI to load an opponent's JSON file directly from the OS to fight it.
    - **Out-of-Game:** Relies on an external web service or community hub (like Discord) for players to host, share, and track the clan territory map.

### Aesthetics & Rendering
- ~~**"Dead Cells" 3D-to-2D Pixelation (Visual Rework)**~~ **REJECTED** per the Decision Log above (2026-07-10 visual pipeline ruling): needs modeled assets, viewport-bake management for 80 concurrent mechs, and obsoletes the Rust part rasterizer. The chosen path instead was staying purely procedural 2D - shaded-primitive layer + the `MechModuleLibrary` module vocabulary, which shipped. Left here only as a record of what was considered and passed on; do not pick this back up without a fresh decision.

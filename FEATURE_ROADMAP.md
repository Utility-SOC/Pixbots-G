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
| Canonical tabletop scale | **1 inch = ~18px** (a ~100px mech sprite = a ~5.5" pixbot). A 4x8ft plywood sheet = ~55x27 tiles; the "Tabletop" map type ships at 64x32. This scale governs section 6 melee/mass tuning (ram distances, cleave arcs, lunge lengths) and the feature-2 terrain-bit sizing. Blue outer walls = the firring strips. |

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
- **Aesthetic reskin:** cheap — `MapGenerator._get_biome_color()` / `_paint_textured_tile()` already do procedural texturing. Foam-mat palette + terrain-bit sprites.
- **Destructible pillars/blockades:** feasible now — extend the `TreeObstacle` per-node pattern with HP + LoS/projectile blocking.
- **Elevation:** shading-fake only, if at all (see Decision Log). No LoS/projectile/pathfinding height logic.
- **Oil slicks / water hazards:** slot into existing systems (`FireResidue`, water collision layer 2, frozen status). Small.

### 3. Directional Damage & Grid Sabotage
- **Shield protection: already done** — `_apply_shield_mitigation()` fully absorbs part damage while shields hold.
- **Angle-based tile hits:** replace the random-tile pick in `apply_part_damage()` with impact-point → hex mapping via `PartHitbox`.
- **Permanent destruction:** deliberate change from the current disable/reboot model (`HexTile.process_durability`). Decide "destroyed for the run" vs "until repair" before building. (Repair is a natural scrap sink — see economy.)
- **Cascading failures:** per-component sims are already isolated; arm-loss disabling its mounts falls out of the `ComponentLink` structure.
- **Armor stat:** new; fits naturally as a tradeoff inside `ComponentEquipment`'s procedural shape budget.

### 4. Evolving AI & Squad Tactics
Largely already built (`SquadDirector`, `SquadTemplateMutator`, `SolverProfile` — templates, weighted selection, mutation, fitness culling, reactive counter-profiles).
- **New: Commanders** — new role, up to 5 support modules (vs. the 2-cap for standard support bots). Small.
- **New: config borrowing from successful past buildouts** — medium; fitness signal already exists.
- **Prerequisite:** instantiate `SquadProfileManager` — it's fully written but never wired, so learning currently resets every restart.
- **New: pierce-execution counterplay.** Extend the existing `log_player_damage()` tracking to log *kill methods*. When pierce-execution ("cut in half") kills exceed a share threshold, up-weight squad templates containing Piercing Jammers. Combined with the aura exemption, over-reliance on the execute build gets countered automatically — if everything goes as planned.

### 5. Upgrade Paths, Infusion & Black Market
- **Scrap economy first** — `player_scrap` is saved but unpriced anywhere. One economy serves: tile/component upgrades, repair costs, infusion, Black Market. Build it once.
- **Manual hex placement on upgrade:** a Garage editor mode on top of `GarageGridRenderer` + `ComponentEquipment.generate_procedural_shape` foundations. Requires the drop-rate increase to feed salvage.
- **Modifier infusion:** `_roll_stat_modifier()` exists; extraction/stacking is inventory + UI. **Cap stack count** — `amplify()` already needed a 150k magnitude ceiling; unbounded stacking will hit it instantly.
- **Mythic toggles:** ship 3–4 per patch. Already existing: Mythic Splitter (6-face + x2), Mythic Magnet rarity filter, Catalyst `cycle_synergy()`. Magnet Attract/Repel **joins** the filter. Resonator sync is feasible now — cross-component transfer plumbing exists (`_collect_transfers` / `_route_to_peripheral`). Accumulator threshold slider waits for the (maybe-never) live-packet rework.
- **Black Market:** trivial once the economy exists; 10-min real-time rotation is a timer.

### 6. Melee Actuators & Mass Physics
Least-supported feature — zero weight/mass/melee code exists. Scope as its own pillar, build last.
- Weight value on every tile; mass-based movement rebalance (will change the README's beloved Kinetic "Speed Demon" builds — intentional, but flag it in patch notes).
- Ramming = contact damage from `mass × speed`.
- Shield-element ram synergies are the cheap part (`dominant_shield_synergy` exists).
- **Piercing cut-in-half:** percentage chance, with the exemption list from the Decision Log (bosses, Commanders, Piercing Jammers, units in a Piercing Jammer aura) + the AI counter loop from §4.

### 7. Elemental VFX & Instant Arcing
- `LightningChain` already arcs instantly between enemies; remove the flying bolt sprite for lightning-dominant shots, flash impact VFX directly. Modest.
- **Style note:** "photorealistic" contradicts the pixel aesthetic feature 2 preserves — stylized-but-instant jagged polylines instead.
- **Proportional synergy blending:** `Projectile.gd` already blends speed/scale/lifetime/trails/color by synergy *ratios*; the remaining work is converting the threshold-gated movement behaviors (vortex spiral, lightning jitter) to weighted composition. Incremental, not a new system.

---

## Follow-up Items

- **Minimap + UI audit:** nothing exists; U-key toggle, resizable/zoomable/movable. Feed from existing node groups. Cheap win.
- **Synergy threshold effects (remaining 8):** impact statuses today are only frozen/burning; projectile-side threshold checks already exist to hang new ones off. Vampiric corpse-obstacle is the only one adding a new system (corpse collision bodies — watch perf at 80 enemies). Lightning→paralyze and Vampiric→bleed/immobilize already spec'd.
- **Cloak redesign:** `Mech.gd:1244` comment already tracks this — replace alpha fade with a screen-UV distortion-circle shader. Small.
- **War Room UI:** pure new UI over existing data (template weights, fitness, lineage in `SquadDirector`/`SolverProfile`). Solves the "invisible learning loop" problem. Procedural Stargate-style low-collision names: trivial generator.
- **Persistent/shareable/breedable AI profiles:** `SquadProfileManager` has save/load AND `export_to_clipboard` written — just wire it up. Breeding = crossover function in `SquadTemplateMutator`.
- **Per-component loadout profiles:** `SaveManager._serialize_component()` already handles single components; add per-component slots + UI.
- **Water enemies + jumpjet logic:** water is collision layer 2 with drowning; add swim-capable movement flag + water spawn placement. `AutoEquipSolver` rule: near-water roles include jumpjets. **Player rule (locked):** jumpjets auto-activate and stay on when on water — hook into `_check_drowning()`: if `jumpjet_energy > 0`, no drown timer, force jumpjet-active state.
- **Tutorials/onboarding:** highest UX value, but written *after* heat/upgrades/melee stabilize, or it gets rewritten.

## Tutorial, Story & UX (promoted to its own workstream)

- **Tutorial:** first-run guided flow — "here's a Core, here's a Weapon Mount, connect them, watch the packet flow, now fire." The Garage's Simulate Energy Flow is the natural teaching tool; a scripted first loadout walk-through covers 80% of the learning cliff. Follow with contextual tooltips (hover a tile type anywhere → what it does) and an in-game codex for synergies/counters, which currently live only in code and the README.
- **Story (canon premise, per Natalia):** You spend every day after school at the game shop brawling AI bots in a new game — *PixBots*. You got a base bot for your birthday and want to earn more components. The shop runs a standing competition: defeat the AI and earn merchandise (in-fiction, every match helps train the AI that PixBots fields against all players — which is literally what the SquadDirector's learning loop does). `campaign.json` + `Main._load_campaign()` already exist as the delivery hook; tell it through intermission text and environment dressing, no cutscene tech needed. The Black Market is the shop's glass case; the War Room is your opponent studying your plays.
  - **Rival challenges:** sometimes another player challenges you — a specialized match where the enemy mech is built to counter your play to date, directly or within ±15% of directly. Rival loadout quality is equivalent to yours (the reactive SolverProfile system is most of this already; it needs an "equivalent budget" constraint and a named-rival wrapper).
  - **PvP via profile swap (stretch goal):** two players exchange AI profiles (clipboard export already works) and each fights the other's evolved AI as a "Travelling Champion" in the arena — counted like any game-shop challenger, same rewards. Each player has a local rank stored in an encrypted file; when two players fight, relative ranks are assessed and rebalanced from wins/losses.
  - **Confidence & milestone rewards:** the player character grows more confident as the story progresses. Beat 10 bosses/enemy champions → 1 Legendary component + 2 Legendary tiles. Reach level 100 → 1 random Mythic tile + 1 Mythic component.
- **UX pass:** the audit bundled with the minimap — HUD legibility, damage-number noise, menu key consistency (`, TAB, U, Esc all live on different layers now), garage discoverability (Auto-Equip is invisible), and save/loadout-slot clarity flagged in GAME_IMPROVEMENT_SUGGESTIONS.md.
- Sequencing: tooltips + codex can land anytime; the scripted tutorial and story framing should land *after* the scrap economy and heat v1 stabilize, so they teach the real systems, not soon-to-change ones.

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

# Pixbots-G: Improvement Suggestions

Notes compiled after a full read-through of the codebase (data structures, performance, AI, rendering, loot, and progression systems), plus the fixes and new systems added alongside this document (map chunking, mech renderer rewrite, ambusher cloak, scout/support jammer modules and heal beacons, AI squad mutation/culling, procedural component shapes). These are suggestions, not commitments - grouped by area, roughly in order of expected impact.

---

# SECOND REVIEW (July 2026) - post-expansion code health pass

State of the codebase at review time: ~20k lines (up ~60%), with major new
systems since the first review: evolving BossProfile kits (abilities/enrage/
positioning), Rival Challenges, Drones + Drone Bay, Piercing Jammers with
execute-immunity auras, shield Deflector overflow, mass/ramming groundwork,
oil slick hazards, flow-field pathing, tutorial system, death reports.
General health is GOOD - hot loops are being throttled (magnet 10Hz, minimap
12Hz, homing scans), formulas are being generalized (rival power scoring
reuses the player yardstick), and regressions from the big feature push have
been getting fixed at the root. The items below are what's left, grouped and
roughly ordered by impact within each group.

*(Currency pass, 2026-07-12: struck through everything confirmed shipped by reading the actual code, not just trusting prior doc claims - several items below had drifted stale.)*

## A. Requested but still outstanding

1. ~~**Mythic Magnet "Repel" still shoves enemies; the requested behavior is
   projectile REFLECTION with ownership flip** (enemy shot enters field ->
   `fired_by_player = true`, `collision_mask = 4|1`, direction reversed,
   `source_mech` reassigned so lifesteal/damage credit works). Needs
   projectiles registered in a group ("projectile") to find them cheaply -
   they currently aren't in any group.~~ (Fixed in second review pass)
2. ~~**Early-game enemy projectile monoculture.** The reactive SolverProfile
   is the only loadout voice until mutations accumulate, so wave 1-10 bots
   mostly fire the same element. Cheap fix: in `_spawn_bot_for_role`, ~35%
   chance to clone the profile with a random `favored_synergy` (per-bot
   jitter); role loadouts already add some variety, this finishes it.~~ (Fixed in second review pass)
3. ~~**Heat has zero player-facing UI.**~~ (Superseded, not a gap: the thermal
   system itself is fully commented out per an explicit design ruling - see
   `CLAUDE_CODE_HANDOFF.md`/`FEATURE_ROADMAP.md`'s Decision Log. Nothing to
   build a UI for. Don't re-enable thermal without asking first.)

## B. Bugs / correctness risks

4. ~~**`settings.cfg` lives at `res://`** (SettingsMenu, MainMenu, SaveManager
   difficulty). Writable in the editor, READ-ONLY in exported builds -
   difficulty + control scheme will silently fail to persist for players.
   Migrate all settings IO to `user://settings.cfg` in one pass (with a
   one-time res:// -> user:// migration read).~~ (Fixed)
5. ~~**`bank_primed` is written but never read**~~ (Fixed: field removed
   from `WeaponMountTile.gd`, replaced with a comment explaining why - it
   was never serialized, so nothing broke.)
6. ~~**Near-peer power estimate ignores `stat_modifiers`.** Chip-stacked
   builds (+50% per stat) read as weaker than they are to WWYDTTY scaling -
   exactly the clown-shoes build the mode exists for. Fold modifier sums
   into `_estimate_mech_power`.~~ (Fixed)
7. ~~**Director telemetry isn't persisted.** Template weights/fitness survive
   restarts via learned_state.json, but `player_element_usage` and
   `player_kill_methods` reset - so the counter-doctrine has amnesia while
   squad evolution remembers. Inconsistent memory; persist both dicts in
   the same file.~~ (Fixed)
8. ~~**Save `"version": 2` has survived multiple schema changes** (valid_hexes,
   chips, mythic props, forbidden types...). All handled by has()-guards, so
   nothing is broken, but bump the version on schema change and keep a tiny
   migrations comment block, or the first real breaking change will hurt.~~ (Fixed)

## C. Performance

9. ~~**AI LOD is still the biggest unclaimed win**~~ (Fixed: distance-tiered
   tick divider shipped - `_execute_ai_tactics` runs 4Hz beyond 1400px of
   the target, full rate near; see Mech.gd's `_lod_ai_timer`.)
10. ~~**Finish the group-scan consolidation**~~ (Fixed: EntityCache autoload
    serves per-frame cached group snapshots; magnet, drone targeting,
    sight checks, minimap, and projectile impact scans route through it.
    Rare-event scans stay direct on purpose.)
11. ~~**MechPartRenderer bake caching**: every spawned mech re-rasterizes ~6
    part images; near-peer waves bake 80 near-identical sprite sets.~~ (Fixed: Ported entire rasterization loop to Rust `part_rasterizer.rs`, drastically reducing bake time to microseconds)

## D. Structure / spaghetti

12. ~~**Mech.gd is now a 3,190-line god-class** (91 funcs: player input, AI
    tactics, boss kit, statuses, heat, magnet, cloak, ramming, drone base).
    Mechanical split into child nodes/refcounted helpers - BossBrain,
    StatusEffectRunner, PlayerController - no behavior change, huge
    readability/merge-conflict win.~~ (Fixed: exactly that split landed - BossBrain, StatusEffectRunner, PlayerController, plus MagnetSystem and SightAndSearch; Mech.gd is down to ~2.6k lines. The MechModuleLibrary arm vocabulary is a separate VISUALS feature, not this refactor.)
13. ~~**Rarity math is scattered**: 8 copies of `_get_power_multiplier` across
    tiles.~~ (Fixed: the 5 byte-identical tile overrides were deleted - the
    HexTile base class copy is the single source. The OTHER rarity ladders
    (scrap values, drop rates, power scores) are intentionally different
    curves and stay separate.)
14. ~~**Element name/id conversion exists in 5+ places**~~ (Fixed:
    EnergyPacket.SYNERGY_NAMES + element_name()/element_id() are canonical;
    the consolidation also uncovered and fixed THREE divergent numberings
    that were breaking shield rock-paper-scissors and the director's
    counter-doctrine - see ElementTableCheck. Original text: SquadDirector match,
    SYNERGY_NAMES tables in WarRoomMenu + GarageMenu, Projectile's
    dominant_str match, Mech's shield id mapping. Add static
    `EnergyPacket.element_name(id)` / `element_id(name)` beside the color
    helpers and delete the local copies.
15. ~~**Comment debt**: several comments still describe removed systems (the
    old dump-modifier keys, pre-siphon gating).~~ (Checked: the specific
    pre-siphon/`bank_primed` comment is already accurate - it correctly
    documents the field's removal, not a leftover description of dead
    behavior. No other stale "describes a removed system" comments turned
    up in a targeted pass. General guidance stands as ongoing practice, not
    a one-time item: sweep a file's comments whenever it's touched anyway.)

## E. Systems that should be connected but aren't

16. ~~**Difficulty x map size**: enemy count formula doesn't know the Tabletop
    is 1/50th the area of the default map - same 80-cap mosh pit. Scale
    `target_enemy_count` by a map-area ratio.~~ (Fixed)
17. ~~**War Room lacks a "YOUR MECH" card**~~ (Fixed: `WarRoomMenu.gd` has a
    "YOUR MECH: POWER ESTIMATE" section reading the director's own power
    score / dominant rarity data.)
18. ~~**Tutorial coverage vs new systems**~~ (Checked against the actual
    `tutorial.json`: hold-key accumulator dumps and heat were already
    covered ("accumulators"/"heat" steps) - the doc's claim they were
    missing was itself stale. Black Market + modifier chips genuinely
    weren't mentioned; added a `black_market_and_chips` step in Evan's
    voice. Difficulty selection isn't Garage-tutorial-scoped - it's chosen
    before a run starts, not from here.)
19. ~~**MODDING.md drift**~~ (Checked: `boss_profiles` (format v1.2+) and the
    `commander` role are both already documented. Tabletop map type was
    never actually in scope for this doc - it only covers moddable JSON
    formats (AI profiles/squad templates), not map types, so there was
    nothing to add.)
20. ~~**FEATURE_ROADMAP.md status block is far behind reality** - rivals,
    drones, boss evolution, shield modes, Piercing Jammers, oil slicks, and
    mass/ramming groundwork have all landed since it was written. Refresh
    it so it stays a truthful map of the project.~~ (Fixed)

## Progression & pacing

The README already flags that formal progression is "under construction," so this is timely rather than a criticism.

- ~~**Wave scaling runs on a pure `pow(1.10, wave-1)` HP multiplier with no ceiling.** By wave 50 that's a ~106x multiplier; by wave 100 it's ~11,700x.~~ (Fixed: Soft-knee exponential added in recent commit, compounds to wave 25 then goes linear)
- **Bosses are always a scaled-up Brawler** (`Main._spawn_boss` hardcodes `director._spawn_bot_for_role("brawler")`). With sniper, scout, ambusher, jammer, flamethrower, and now support archetypes all in the roster, boss fights would read very differently if the boss role were chosen per-fight (or a genuine "boss-only" kit existed - bigger hitbox, phase changes, etc.) rather than just being a Brawler at 2x/3x/5x/25x scale.
- **The starter inventory looks like debug leftovers**: `Main._initialize_starter_inventory()` hands the player 20 Legendary Splitters outright, on top of 3-of-each-rarity Splitters/Reflectors/Amplifiers. That's a lot of high-value gear with zero play required to earn it - **still open, needs a design call** (intentional "sandbox mode" default vs. gated behind progression), not something to change unilaterally.
- ~~**Scrap economy is thin.**~~ (Superseded: the scrap economy is fully built - 5+ spend sites in `GarageMenu.gd` covering upgrades, repair, infusion, rarity tier-up, and the Black Market.)

## AI & enemy variety

- The new mutation/culling system (this session) makes squad *composition* evolve, but individual mech loadouts within a role are still fixed by `build_loadout_for_role`. A natural follow-up: let component loadouts themselves get variant "builds" per role (e.g. three different Sniper wiring patterns) and let the fitness signal pick winners the same way it now does for squad composition. *(Still open - medium-large.)*
- **Reactive resistance profiling only tracks the player's offense** (`SquadDirector.player_element_usage`). There's no equivalent tracking of what the player's *shield* dominant synergy is doing to counter incoming damage beyond the one-time counter-element roll at spawn. A director that adapts mid-fight (not just at spawn) would read as noticeably smarter. *(Still open - medium.)*
- ~~**Squad composition has no idea what map biome it's spawning into.**~~ (Fixed 2026-07-12 — water only: `MapGenerator.water_fraction` tracks the actual terrain grid's water tile ratio (not just `map_type`, since "Normal" maps can roll a big lake from elevation noise too); `TemplateEvolution.select_template_weighted()` now weights templates with a `"diver"` role up and non-water-capable templates down, proportional to how wet the map is, above a 15% threshold. On top of that, past `MapGenerator.MOSTLY_WATER_THRESHOLD` (50% water), `SquadDirector._spawn_bot_for_role` grants most roles real water safety (`is_amphibious = true`), not just "diver" - so even the squad that does spawn isn't gambling per-member on drowning mid-chase. Per Natalia: `sniper`/`brawler` (`WATER_SAFETY_EXCLUDED_ROLES`) are deliberately left out - the standard rank-and-file stays drown-vulnerable so water remains a real hazard, not blanket-immunized. (First attempt fed a JumpjetTile into the tile solver instead, matching how other role tiles work - reverted: JumpjetTile is an OUTPUT/terminal tile, and the solver's "nothing matched, just place inventory[0]" fallback could park it mid-tree and silently eat the packet meant for something downstream, and even when placement was harmless it usually never received a live packet at all. `is_amphibious` is checked directly in code, not grid routing, so it can't come up empty.) Obstacle-density awareness for ambusher squads is a separate, still-open follow-up.)
- ~~Consider surfacing the AI's learning state to the player~~ (Superseded: War Room UI already exists, showing template weights/fitness/lineage - the reinforcement loop is visible.)
- ~~**`SquadProfileManager` is fully written but never instantiated anywhere**~~ (Fixed: `SquadDirector.gd` instantiates `profile_manager = SquadProfileManager.new()` - learning persists across restarts.)

## Combat depth

- ~~**Elemental synergies are a lot to learn with no in-game reference.**~~ (Fixed: an in-game Synergy Codex exists, reachable from the Garage - covers all 9 synergies + shield counters. Doesn't cover biome interactions yet - worth extending.)
- ~~**No minimap.**~~ (Fixed: `MinimapOverlay.gd` - U to toggle, draggable, zoomable, resizable.)
- **Status effects are limited to frozen/burning** (`Mech.update_status_effects`). Poison and Vortex synergies exist as damage/knockback but don't have a corresponding lingering status the way Fire and Ice do - worth deciding if that's intentional or a gap. *(Still open - medium; Lightning->paralyze and Vampiric->bleed/immobilize are already spec'd in FEATURE_ROADMAP.md, just not built. Watch perf on the Vampiric corpse-obstacle piece specifically at 80 enemies.)*
- Now that Cloak, Jammer Modules, and Heal Beacons exist, it'd be worth a balance pass specifically on **counterplay**: can the player detect an about-to-decloak ambusher (audio cue, faint outline)? Can a heal beacon be focus-fired down before it heals its squad back up? Right now all three are "fire and forget" from the AI side with no player-facing tell beyond the visual pulse ring. *(Still open - medium, design-heavy.)*

## UX / onboarding

- ~~There's no tutorial or first-run guidance~~ (Fixed: `TutorialManager.gd` + `tutorial.json` - a guided first-run flow in Evan's voice, covering Core -> tiles -> weapon mounts -> accumulators -> heat -> repairs -> Black Market/chips -> the AI -> minimap.)
- ~~Auto-Equip (`AutoEquipSolver`) is powerful but invisible~~ (Fixed: added a tooltip on the Auto-Equip button explaining what it prioritizes; hex-tile inventory hover tooltips now also carry a one-line "what does this tile do" description per tile type, not just stat numbers.)
- ~~Save/load only has one autosave slot... clarifying that distinction in-UI~~ (Fixed: added tooltips distinguishing the automatic run-save (Deploy to Battlefield) from the manual full-build Loadout slots and the per-part "This part" slots, including a warning that Load replaces without refunding outgoing parts to inventory.)

## Performance (beyond what's already fixed this session)

- ~~**Off-screen AI still runs at full simulation rate.**~~ (Superseded: AI LOD shipped - `_execute_ai_tactics` runs at a distance-tiered tick divider, 4Hz beyond 1400px of the target, full rate near. See `Mech.gd`'s `_lod_ai_timer`.)
- ~~**`get_tree().get_nodes_in_group(...)` calls in hot paths**~~ (Superseded: `EntityCache` autoload now serves per-frame cached group snapshots; magnet, drone targeting, sight checks, minimap, and projectile-impact scans all route through it. A separate audit this pass found one remaining unthrottled hot path outside this list - `Main._update_player_blind_state()` was walking the whole "enemy" group every frame regardless of state change - now fixed to only touch it on an actual blind-state transition.)
- **The hex-grid energy simulation (`Mech._simulate_grid`) rebuilds from scratch on every loadout change.** *(In progress, not unstarted: `rust_ext/src/hexgrid_sim.rs` is a deliberate stub seeding an engine-agnostic `pixbots_core` Rust port of this exact workload - BFS packet routing, then sync-deviation merge, accumulator banks, and cross-component link transfers, each phase verified against the GDScript sim before moving to the next. This is real, hard, worth-doing-carefully work - see the Rust Architecture section of `FEATURE_ROADMAP.md`.)*

## Modding

~~The presence of `mod_guide_text.txt` and `config/` JSON-loadable AI profiles suggests modding is a design goal.~~ (Superseded: `mod_guide_text.txt` was deleted - it was scraped content from an unrelated game, not real documentation. `MODDING.md` now documents what's actually moddable (AI profiles/squad templates via JSON), and `FEATURE_ROADMAP.md`'s Modding section has the full phased plan for the rest - data-driven tile stats next, then custom bot types, then custom tile types via script registration. Still real, still open work at phases 2-4; see FEATURE_ROADMAP.md's ranking rather than duplicating it here.)

## Smaller items noticed along the way

- ~~`apply_damage`/`apply_part_damage` had duplicated shield-mitigation logic... worth a quick scan for other duplicated blocks like it~~ (Checked: the various `apply_damage(amount, element, source, was_reflected)` overrides on `TreeObstacle`/`RuinObstacle`/`CorpseHusk`/`PartHitbox` share a signature but are legitimately different per-object logic, not copy-pasted duplication - each obstacle type has its own distinct element-weakness/threshold behavior. Nothing further to extract here.)
- ~~Enemy mechs weren't in a Godot group at all before this session... worth a broader pass checking every `get_nodes_in_group(...)` call has a matching `add_to_group(...)`~~ (Checked during this pass's `get_nodes_in_group` audit - no other silently-missing group registrations turned up.)

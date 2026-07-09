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
3. **Heat has zero player-facing UI.** The whole system (generation, siphon
   venting, ice cooling, lightning arcing, overheat knockouts) is invisible
   until the OVERHEAT float text. Minimum: a slim HUD heat bar; ideal: also
   a per-circuit heat rate readout in the Garage stats panel.

## B. Bugs / correctness risks

4. ~~**`settings.cfg` lives at `res://`** (SettingsMenu, MainMenu, SaveManager
   difficulty). Writable in the editor, READ-ONLY in exported builds -
   difficulty + control scheme will silently fail to persist for players.
   Migrate all settings IO to `user://settings.cfg` in one pass (with a
   one-time res:// -> user:// migration read).~~ (Fixed)
5. **`bank_primed` is written but never read** - vestige of the pre-siphon
   gate model; its old comment claimed it "unlocks normal auto-fire," which
   is no longer true (comment fixed this pass, flagged for removal).
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

9. **AI LOD is still the biggest unclaimed win** (carried over from the
   first review, more urgent now): 80 near-peer mechs + boss ability logic
   all full-tick regardless of distance/visibility. A distance-tiered tick
   divider for `_execute_ai_tactics` (full rate near, 1/4 rate far) is the
   cheapest large frame-time lever left.
10. **Finish the group-scan consolidation**: 33 `get_nodes_in_group` sites;
    several hot ones are now throttled, but a per-frame cached snapshot
    (tiny EntityCache autoload: enemies/loot arrays refreshed once per
    frame) would eliminate the remaining redundant tree walks.
11. **MechPartRenderer bake caching**: every spawned mech re-rasterizes ~6
    part images; near-peer waves bake 80 near-identical sprite sets. Cache
    baked textures keyed by (shape points hash, rarity, color, accent) -
    stacks multiplicatively with the trickle spawner on wave-start cost.

## D. Structure / spaghetti

12. **Mech.gd is now a 3,190-line god-class** (91 funcs: player input, AI
    tactics, boss kit, statuses, heat, magnet, cloak, ramming, drone base).
    Mechanical split into child nodes/refcounted helpers - BossBrain,
    StatusEffectRunner, PlayerController - no behavior change, huge
    readability/merge-conflict win. Do it BEFORE the melee pillar lands on
    top of it.
13. **Rarity math is scattered**: 8 copies of `_get_power_multiplier` across
    tiles, plus separate rarity ladders in GarageMenu (scrap), SquadDirector
    (power values), LootManager (drops), upgrade costs. One `RarityMath`
    static class; the 8 tile copies are pure deletion.
14. **Element name/id conversion exists in 5+ places** (SquadDirector match,
    SYNERGY_NAMES tables in WarRoomMenu + GarageMenu, Projectile's
    dominant_str match, Mech's shield id mapping). Add static
    `EnergyPacket.element_name(id)` / `element_id(name)` beside the color
    helpers and delete the local copies.
15. **Comment debt**: several comments still describe removed systems (the
    old dump-modifier keys, pre-siphon gating). Worth a sweep whenever a
    file is touched anyway.

## E. Systems that should be connected but aren't

16. ~~**Difficulty x map size**: enemy count formula doesn't know the Tabletop
    is 1/50th the area of the default map - same 80-cap mosh pit. Scale
    `target_enemy_count` by a map-area ratio.~~ (Fixed)
17. **War Room lacks a "YOUR MECH" card**: the director already computes
    your power score, dominant rarity, and kill-method profile - showing
    the player the same numbers the AI uses to hunt them is both UX gold
    and free (all data exists).
18. **Tutorial coverage vs new systems**: tutorial.json predates hold-key
    dumps, heat, chips, the Black Market, and difficulty selection - verify
    steps exist for each or add them.
19. **MODDING.md drift**: no mention of the `boss_profiles` key (format
    v1.2), the commander role, or the Tabletop map type. Quick refresh.
20. ~~**FEATURE_ROADMAP.md status block is far behind reality** - rivals,
    drones, boss evolution, shield modes, Piercing Jammers, oil slicks, and
    mass/ramming groundwork have all landed since it was written. Refresh
    it so it stays a truthful map of the project.~~ (Fixed)

## Progression & pacing

The README already flags that formal progression is "under construction," so this is timely rather than a criticism.

- **Wave scaling runs on a pure `pow(1.10, wave-1)` HP multiplier with no ceiling.** By wave 50 that's a ~106x multiplier; by wave 100 it's ~11,700x. Even with the player's own power growing, an uncapped exponential against a mostly-linear player damage curve will eventually produce either a wall or a curve that trivializes early waves. Worth plotting expected player DPS against this curve and either flattening it past some wave count or introducing a second scaling lever (enemy count, squad composition variety) instead of pure HP inflation.
- **Bosses are always a scaled-up Brawler** (`Main._spawn_boss` hardcodes `director._spawn_bot_for_role("brawler")`). With sniper, scout, ambusher, jammer, flamethrower, and now support archetypes all in the roster, boss fights would read very differently if the boss role were chosen per-fight (or a genuine "boss-only" kit existed - bigger hitbox, phase changes, etc.) rather than just being a Brawler at 2x/3x/5x/25x scale.
- **The starter inventory looks like debug leftovers**: `Main._initialize_starter_inventory()` hands the player 20 Legendary Splitters outright, on top of 3-of-each-rarity Splitters/Reflectors/Amplifiers. That's a lot of high-value gear with zero play required to earn it - worth deciding whether that's an intentional "sandbox mode" default (matches the README's sandbox framing) or should be gated behind actual progression once a campaign exists.
- **Scrap economy is thin.** `player_scrap` exists and is saved/loaded, but nothing in the read code prices anything in scrap - there's no shop, no scrap-for-reroll, no scrap-for-repair. It's plumbing without a payoff yet.

## AI & enemy variety

- The new mutation/culling system (this session) makes squad *composition* evolve, but individual mech loadouts within a role are still fixed by `build_loadout_for_role`. A natural follow-up: let component loadouts themselves get variant "builds" per role (e.g. three different Sniper wiring patterns) and let the fitness signal pick winners the same way it now does for squad composition.
- **Reactive resistance profiling only tracks the player's offense** (`SquadDirector.player_element_usage`). There's no equivalent tracking of what the player's *shield* dominant synergy is doing to counter incoming damage beyond the one-time counter-element roll at spawn. A director that adapts mid-fight (not just at spawn) would read as noticeably smarter.
- **Squad composition has no idea what map biome it's spawning into.** A flamethrower squad in a Water biome or an ambusher squad with no obstacles to hide behind are both currently possible. Feeding biome/obstacle density into template selection weighting would make squads feel place-appropriate.
- Consider surfacing the AI's learning state to the player somehow (even just a debug-menu readout of current template weights) - right now the reinforcement loop is invisible, so a player has no way to notice "the game is adapting to me," which is one of the more interesting things it's doing under the hood.
- **`SquadProfileManager` (save/load AI templates to `user://ai_profiles/`) is fully written but never instantiated anywhere** - the template weight learning currently resets every time the game restarts. Wiring it up (even just save-on-squad-defeat, load-on-boot) would let the evolutionary system actually accumulate across sessions instead of relearning from scratch every run.

## Combat depth

- **Elemental synergies are a lot to learn with no in-game reference.** Ten synergy types, six shield counter-relationships, biome interactions (Lightning+Water, Fire+Forest) - all of this currently lives only in code and the README. An in-game codex/tooltip (even a simple paged menu) would help a lot, especially once cloak/jammer/heal-beacon add three more systems to learn.
- **No minimap.** The only spatial guidance is the extraction arrow once the timer expires; finding loot drops, avoiding a jammer's aura, or regrouping after a chaotic fight all currently rely on either being on-screen or not existing as a concern.
- **Status effects are limited to frozen/burning** (`Mech.update_status_effects`). Poison and Vortex synergies exist as damage/knockback but don't have a corresponding lingering status the way Fire and Ice do - worth deciding if that's intentional or a gap.
- Now that Cloak, Jammer Modules, and Heal Beacons exist, it'd be worth a balance pass specifically on **counterplay**: can the player detect an about-to-decloak ambusher (audio cue, faint outline)? Can a heal beacon be focus-fired down before it heals its squad back up? Right now all three are "fire and forget" from the AI side with no player-facing tell beyond the visual pulse ring.

## UX / onboarding

- There's no tutorial or first-run guidance found anywhere in the scripts - a new player is dropped straight into the hex-grid routing puzzle, which the README itself describes as a fairly deep engineering sandbox. Even a lightweight "here's a Core, here's a Weapon Mount, connect them" prompt on first Garage entry would lower the barrier a lot.
- Auto-Equip (`AutoEquipSolver`) is powerful but invisible - a player who never opens the debug menu may not know it exists or what it's optimizing for. Surfacing "why did it place this tile here" (e.g. a hover explanation) would make the manual tinkering the game is clearly built around more approachable.
- Save/load only has one autosave slot for the active run, though loadouts have their own separate slot system (`save_loadout`/`load_loadout`). Worth clarifying that distinction in-UI so players don't lose a run expecting a manual-save safety net.

## Performance (beyond what's already fixed this session)

- **Off-screen AI still runs at full simulation rate.** Every enemy mech re-paths every ~0.5s and runs full `_physics_process` regardless of whether it's anywhere near the camera. At the upper end of wave scaling (up to 80 concurrent enemies), a simple "reduce AI tick rate for mechs far outside the camera frustum" LOD system would be a meaningful win that compounds with the fixes already made this session.
- **`get_tree().get_nodes_in_group(...)` calls in hot paths** (magnet pull, jammer/heal pulses, AI target acquisition) scale linearly with group size. Fine at current enemy counts; if wave sizes grow further, a spatial hash/grid for "nearby entities" queries would keep this from becoming the next bottleneck.
- The hex-grid energy simulation (`Mech._simulate_grid`) rebuilds from scratch on every loadout change, which is correct but means a Legendary "closed loop" build (as described in the README's own limit-testing section) does a real BFS over up to 100 steps - worth a periodic profiling pass once players start building the loop configurations the README explicitly encourages.

## Modding

The presence of `mod_guide_text.txt` and `config/` JSON-loadable AI profiles suggests modding is a design goal. If so:

- Consider formalizing what's actually moddable today (tile scripts? squad templates via JSON? map biomes?) into a short reference doc alongside the existing mod guide.
- The new procedural shape primitives (block/line/hook) and squad mutation system are both good candidates for mod-exposed parameters (e.g. a modder-defined role's archetype weights) if that fits the modding vision.

## Smaller items noticed along the way

- `apply_damage`/`apply_part_damage` had duplicated shield-mitigation logic (fixed this session by extracting a shared helper) - worth a quick scan for other duplicated blocks like it, since duplicated logic is exactly the kind of thing that causes silent balance drift when only one copy gets updated.
- Enemy mechs weren't in a Godot group at all before this session, which had silently broken enemy cleanup on player death and the lightning-arc secondary-target effect. Worth a broader pass checking that every `get_nodes_in_group(...)` call in the codebase has a corresponding `add_to_group(...)` somewhere, since that class of bug doesn't show up as an error - it just silently does nothing.

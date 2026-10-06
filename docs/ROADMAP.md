# PixBots-G Roadmap (2026-10-02)

Built from a code + `Status.md` survey of what is unfinished, unverified or
languishing. `Status.md` remains the detailed backlog; this is the ordered plan.
Effort: **S** under a day, **M** a few days, **L** a week or more.
Items marked *(verify)* come from backlog text that has been stale before -
confirm against the code before starting.

## Progress since this was written (2026-10-05)
Done: mock menu buttons, CI off Node 20 (Phase 1), a large share of the Phase 4 and Phase 5
combat and visual work below (element roles, missiles, status particles, solver and enemy-pool
work) and the long-run economy (haul, streak bonus). See the README changelog and
`docs/ENEMY_POOL.md`. Still open from Phase 0: a live playtest of the pool, haul, missile and
mine behaviours (they are covered by headless checks only), and a release-build launch test.

Also done since: Phase 3 (crossfaded, seeded, evolving music; procedural sound effects with music
ducking; scorch decals; hitstop, camera kick and bloom were already in), the smarter Auto-Equip
(simulation-scored refinement), War Room evidence labels, absorbing hard-cover obstacles, and the
Phase 2 (maps that change how you play) is now largely done: terrain movement effects (road speed-up,
ice slide, ash and undergrowth drag), lava vents, shallows, fort hold points with squads that defend them,
village and crash-site caches (all on the minimap), the boss arena, per-biome weather and ambient props,
FightShovel ponds and tracks, Tabletop forest bases and Open Field boulder cover. Still open: enemy use of
chokepoints and ambush spots (flank-route precompute), and more authored set pieces beyond the boss arena
and crash sites.

Phase 8 (optimization) first slice, started 2026-10-06 after three Vulkan device losses on the HD 4000:
ground textures uploaded at 1/4 size (404 -> 40 MB), `[GPU]` memory logging, obstacle nodes drawn by one
canvas item each, an automatic safe-visuals tier after an unclean exit, F3 overlay reset (Shift+F3). Also
fixed on the way: the ground drew over every negative-z effect (decals, vents, rings, shallow tint), and a
spawn watchdog that restarted long waves every 10 s.
Tuning constants for all of the above sit at the top of their scripts.

## Guiding rules (from the design decisions so far)
- Performance first (target hardware: i5-3340M / HD 4000). Measure before and after.
- Procedural visuals and audio by default; no bundled third-party assets.
- Difficulty pressure comes from enemy behaviour and loadouts, never raw stats or tier.
- Frank's world: a dystopian collapse that is implied, never stated outright.
- Nothing is pushed without a go-ahead; releases are tagged `v*`.

---

## Phase 0 - Verify what already shipped (S-M, do first)
Most recent features have only been exercised by headless checks. A playtest pass
finds the bugs that make things feel abandoned.

| Item | What to check |
|---|---|
| New music | Listen to garage, wave (early/late) and boss tracks; tune mix, brightness, busyness. Samples render to `~/pixbots_music_samples/`. |
| New maps | Play each type; check fights near forts/villages, road flow, dungeon corridors (6 wide) vs. mech size, enemy pathing in rooms, frame rate. |
| Garage overload border | Confirm the red outline lands on the right tile; decide whether to mark only the worst tile instead of all overloaded tiles. |
| Credits and Settings panels | Confirm centering at several window sizes. |
| Recent features (orders log, power overlay, tutorial maze, boss events, movement habits, Corp Perks, daily seed) | One live pass each; log defects. |
| Release build | Download the Windows installer and Linux tarball and launch both. |

## Phase 1 - Quick cleanups (S each)
1. **Mock main-menu buttons.** "Import AI Templates" and "Import Mods" only print
   "(Mock)". Wire them to the real War Room import and the modding docs, or remove them.
2. **Stale docs.** Reconcile `Status.md` against the code (Elite Four, sponsorship at
   wave 125, tournament unlock) so the backlog is trustworthy.
3. **Brand placeholders.** Replace one-letter brand marks with procedural logos.
4. **Release hygiene.** Move the CI actions off the deprecated Node 20 runtime; tag
   a release once Phase 0 passes.

## Phase 2 - Make maps change how you play (M-L)
Maps now have structure; they do not yet change tactics.
- **Terrain effects:** road speed bonus, shallows, ice slide, lava or ash hazards that
  tie into the existing oil-slick hazard system.
- **Zone gameplay:** capture or hold points in forts, loot caches in villages,
  ambush spots on roads; enemy squads using chokepoints (feeds the flank-route
  precompute already on the AI list).
- **Per-biome identity:** hazards, ambient props, and weather beyond ground colour.
- **Remaining map types:** apply variety to FightShovel (wider terrain bank, farm
  tracks, ponds), Tabletop and Open Field.
- **Authored set pieces and boss arenas** using the TerrainEditor API.

## Phase 3 - Audio and feel (M)
- Music tuning from Phase 0 feedback; per-biome flavour (scale, tempo, timbre).
- Audio ducking (heavy impacts duck the music bus) and pooled/layered weapon sounds.
- Hitstop and camera kick, after an audit of which timers must ignore time scale.
- Bloom and scorch decals, budgeted against frame time.

## Phase 4 - Combat depth and balance (L)
- **Elemental balance pass:** Lightning, Explosive, Kinetic and Pierce dominate;
  Vortex, Poison and Ice are rarely worth packing. Measure usage, then retune.
- **Heat as a system:** a cost axis that hits fast, spammy elements harder; ties
  directly into the balance pass.
- **Infuser-loop saturation:** real handling (cap, cycle cache or off-thread
  evaluation) beyond the current warning.
- **Solver and AI:** smarter AutoEquipSolver (head and backpack returns,
  catalysts with visible impact); noisy-culling fix; War Room display of pressure
  and plan stats; solver-profile genome follow-ups.

## Phase 5 - Visual identity (L, needs eyes on screen)
- Component visuals: silhouette-driven proportions, energy colour and width
  from the grid, hitbox changes within a cap, LOD for grunts.
- Scout torso as a leg-shaped silhouette.
- Player mech visual identity beyond the paint rack.
- Real brand art on top of the Phase 1 procedural logos.

## Phase 6 - Content (L)
- **Elite-tier rivals** *(verify wiring)*: playable gimmicks, unlock gate after
  all 15 Regulars, late-wave spawn milestones, unique drops, moddable roster.
- **Frank's Challenges:** tactical puzzle scenarios with modifiers (flat damage
  reduction, "The Eye" damage gating).
- **Eight-table week:** the Main Training Table plus seven niche tables.
- **Transparent filler tiles and circuit-logic tiles.**
- **Story:** the outside-world thread told through Frank's lines and cutscenes,
  authored together with the user.
- More Frank cinematics.

## Phase 7 - Platform and community (L)
- **Modding phases 3-4** and a data-driven map and campaign editor sharing the
  game's own schemas.
- **Daily seed leaderboard** behind the existing stub interface.
- **Shared AI gene pool** hosting (only genes, never telemetry).
- **Online multiplayer** (GodotSteam P2P): duels, co-op waves, asymmetric 2v1.

## Phase 8 - Optimization pass: aggressive performance tuning (L, repeatable)
Why: the 2026-10-06 Vulkan device losses on the Intel HD 4000 traced to a 410 MB ground texture that
nobody had budgeted (fixed in 6eb1d50, texture memory 404 -> 40 MB). Resource problems like that are
cheaper to design out than to debug from a crash log. Target hardware stays i5-3340M / HD 4000 with the
Mesa Ivy Bridge Vulkan driver, which is documented as incomplete. Measure before and after every item;
each item gets a budget and a headless or windowed check that fails when it is exceeded.
- **GPU memory budget:** audit every texture and render target (ground chunks, per-bot part textures,
  Garage previews, Test Range, glow/bloom buffers, diorama pass, particles). Set a ceiling (for example
  under 150 MB of texture and 250 MB of video memory at wave 40), expose it in the F3 overlay, and add a
  check that fails above it. Atlas the per-bot pixel-art parts instead of one texture each.
- **Node and canvas-item diet:** about 23k nodes at wave 35 and about 12k canvas items from roughly
  2.8k destructible obstacles at four nodes each. Render obstacles from one batched layer (as
  `TreeRenderLayer` already does for trees) and keep per-obstacle nodes only for collision and hp.
- **Measured 2026-10-06 (windowed bench, wave 35, 45-swarm, HD 4000):** about 20-25 fps with 55-85 enemies
  and about 50 fps with 20, whether or not the AI runs (disabling `SquadDirector` left fps unchanged at 21), and
  GPU render time is only 6-12 ms. So the cost is per-mech scene cost (about 70 nodes per bot, 484 part
  hitboxes, 3 physics steps of 20-40 ms each), not AI, bloom (no clear effect) or the GPU. Next steps: cull or
  simplify off-screen and far mechs (render LOD, stop hitbox syncing), then re-measure. Done already: idle
  tile-durability loops and idle oil slicks no longer tick every frame.
- **Per-frame cost at high waves:** `proc` spikes of 100-200 ms at wave 28+ with 60 enemies and 1100+
  draw calls. Profile with the in-game probes, then attack the top three: enemy simulation LOD beyond
  the screen, projectile and status-aura draw consolidation, separation and sight batching.
- **Bot construction:** about 15 ms per bot. Pre-bake parts during the loading screen, reuse parked
  bots, and move solver and viewability work off the main thread where it is pure data.
- **Garage cost:** the Garage should be nearly free to open. Lazy-build tabs, render previews only
  while visible (done for the two preview viewports), cap the Auto-Equip refiner's simulations, and
  keep the world viewport paused behind it (done).
- **Audio CPU:** keep the synth worker throttled, cap pooled voices (done), and add a cost line to the
  F3 overlay so a regression shows up.
- **Weak-GPU tier:** detect Intel HD 4000 / Mesa Ivy Bridge (or three consecutive slow frames after
  start) and turn off the optional extras automatically (bloom, weather, scorch decals, shallow tint),
  with a Settings override. `PIXBOTS_SAFE_FX=1` and the launcher's `--safe` flag already do this by hand.
- **Device-loss safety net:** write a small "last run crashed on the GPU" marker at start and clear it
  on a clean quit; if it is found on the next launch, start in the weak-GPU tier and say so.
- **Soak test:** a 30-minute scripted run (waves, Garage trips, arm swaps, map changes) that logs
  nodes, orphan nodes, resources and GPU memory every 30 s and fails on growth. The `[GPU]` log lines
  and `BenchGame --swaparm` are the first pieces.
- **Rust ports with a measured win only** (the earlier ports that measured slower were reverted):
  re-measure obstacle and ground baking and the grid simulation hot spots before porting anything.
- **Release gate:** an exported-build launch test on the target machine with the budgets above.

---

## Suggested order
Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4, then Phases 5-7 in whatever
order playtesting says matters most. Phases 3 and 4 can overlap. Phase 8 (optimization) is not a
final step: do a first slice right after Phase 2 (GPU memory budget, node diet, weak-GPU tier) and
repeat it before every release, since each new visual feature adds cost.

## Open questions for the owner
- Phase 8: should the weak-GPU tier switch on automatically, or only suggest itself in Settings?
- Mark only the single worst overloaded tile in the Garage, or every overloaded tile?
- Which map gameplay hooks first: terrain effects, objectives, or enemy use of terrain?
- Should the dark outside-world thread get its own cutscenes, or stay in Frank's quips?
- Priority between Heat (new friction) and the elemental balance pass.

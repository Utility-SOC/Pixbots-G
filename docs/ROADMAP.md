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
Phase 2 so far: terrain movement effects (road speed-up, ice slide, ash and undergrowth drag), lava
vents on volcano ground, shallows (a walkable, slower one-tile band along every shoreline), and zone
gameplay (fort hold points, village loot caches).
Still open in Phase 2: ambush spots and enemy chokepoint use, minimap markers for
objectives, per-biome props and weather, FightShovel/Tabletop/Open Field variety, set pieces.
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

---

## Suggested order
Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4, then Phases 5-7 in whatever
order playtesting says matters most. Phases 3 and 4 can overlap.

## Open questions for the owner
- Mark only the single worst overloaded tile in the Garage, or every overloaded tile?
- Which map gameplay hooks first: terrain effects, objectives, or enemy use of terrain?
- Should the dark outside-world thread get its own cutscenes, or stay in Frank's quips?
- Priority between Heat (new friction) and the elemental balance pass.

# Enemy bot pool, garage-return rebuild, and wave power

Design (agreed 2026-10-05):

- **Every return from the garage is a full enemy rebuild behind a loading screen**, with the
  world paused. The garage is the only place the player's build can change, so counters are
  always current. The loading screen is always shown.
- **Pool.** Enemy bots are pre-built and *parked* (hidden, no processing, no collision, out of
  the `enemy` group) in `SquadDirector`. A wave only activates them.
- **Draft ahead.** `SquadDirector.draft_pool` picks the wave's squad list up front with the
  same weighted selection the wave uses (templates that do well against the player carry more
  weight), queues those templates for `attempt_squad_assembly`, and sets the pool quota to
  exactly their bots. The wave consumes the queue, so spawns are pool hits.
- **Between garage visits nothing is rebuilt.** Rarity tiers are frozen at the rebuild wave
  (`rebuild_wave`); the pool refills one bot per frame in lulls (`Main._refill_pool_for_wave`,
  during each wave's 5 s countdown).
- **Power climbs instead, uncapped:** `energy_scale_for_wave()` = 1 + 0.02 x (waves since the
  rebuild), applied to the energy packets a bot fires (`HexTile._fire_combined_projectile`),
  not by re-simulating its grid (that costs ~35 ms per bot). HP/shield are re-scaled to the
  current wave at activation.
- **The pipeline effect.** A long run with weak gear meets steadily stronger enemies; on
  returning, the rebuild jumps straight to the current wave's tier, so the pool is stocked
  with gear a tier or more above the player's.
- **Rarity unlock waves** (`RARITY_UNLOCK_WAVES`): Uncommon 10, Rare 25, Legendary 75,
  Mythic 120. The guaranteed-Mythic milestone (`Main.MYTHIC_MILESTONE_START_WAVE`) is 120.

Not pooled: bosses, rivals, nemesis, champions, and the first bot of a wave owed a Mythic
milestone (built live so the guarantee fires). A pool miss builds live, as before.

Debug: `--nopool` disables filling, `--pooldebug` logs the first misses; `[POOL] wave N start`
is printed each wave and `[PERF]` spike lines include `pool=hits/spawned stockN`.
Checks: `BotPoolCheck`, `StockBuildCreditCheck`, `WaveMythicMilestoneCheck`.

Open (not built): an economic cost to long runs - unsecured "haul" at risk on death, a streak
bonus to drops/scrap per wave since the last garage, banked on extraction.

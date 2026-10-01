# Enemy AI: how enemies get harder

Goal: the game keeps escalating whatever the player does, until the player changes playstyle. Difficulty comes from
smarter builds and smarter tactics, not bigger numbers or a race to Mythic.

## Layers

| Layer | File | What it decides |
|---|---|---|
| Fitness normalisation | `scripts/ai/FitnessPar.gd` | Scores are relative to a moving par per bucket (`role:rarity`, `squad:wave-band`, `boss:wave-band`). 100 = typical. Higher tier or later wave never scores higher just for existing. |
| Loadouts | `StockBuildEvolution.gd`, `StockBuildMutator.gd` | Champion build per `template:role:rarity:slot`; deviation tests must beat the champion's recent average by a margin to be promoted. |
| Tier gating | `SquadDirector.RARITY_UNLOCK_WAVES`, `ROLE_UNLOCK_DELAY` | Rarer components unlock for enemies by wave (per role), so progress is quality at the current tier. |
| Player model | `PlayerModel.gd` | Recent (fast decay) vs slow memory of damage/kill elements. A large divergence = the player changed playstyle: old counters are retired and pressure eases. |
| Pressure | `PlayerModel.pressure` (0..4) | Ratchets up when the player is barely scratched. Feeds exploration rate, counter-commit chance, and tactic complexity/lead skill. Never raw stats or tier. |
| Squad tactics | `SquadTactics.gd` | Per-squad plan (below), planning tick at 4 Hz. |
| Tactic genome | `TacticGenome.gd` | Evolving pool of plan variants (below). |

## Squad tactics

A plan assigns each member a part (`FLANK`, `PIN`, `COVER`, `BAIT`, `RING`, `STAGE`; shown in the enemy state tag) and
steers it toward goal points around the player. Plans are wave-gated:
`swarm` (0), `synchronized_strike` (3), `pincer` (5), `hammer_anvil` (8), `encircle` (12), `bait_flank` (15).

- Selection is weighted: recent plans are damped (variety), plans that score well against this player are favoured,
  pressure shifts weight away from plain `swarm`, and a pressure-scaled exploration roll picks uniformly.
- A plan that lands no hits for 12 s, or a squad being ground down, triggers a replan to a different plan.
- Shots solve a true intercept using the shooter's real projectile speed (`Mech._ai_shot_speed`, mirrors `Projectile.gd`) and the player's tracked velocity. Lead skill is 0.65 plus 0.1 per pressure (plus the genome's `lead_bonus`), and the lead shrinks against players who jink.
- Squads run a genome from the pool and credit it with the squad's normalised fitness when the squad dies.

## Tactic genome

The six plans are founding archetypes. A genome is an archetype plus overridden parameters, stored in `tactic_pool` in the
learned state (`{id, base, params, n, mean, gen, parent}`).

- Genes: `flank_share`, `arc`, `stage_extra`, `timeout`, `standoff` (goal radius multiplier), `lead_bonus`, `replan_after`;
  flags `stage` and `split` can flip (so a pincer can become a staged pincer). Genes only apply where the archetype uses them.
- Selection: archetype first (anti-repeat, outcome, pressure), then a genome within it. Untested mutants get a slight
  bonus so they actually get trials.
- Breeding: a genome with n >= 3 and mean >= 95 may spawn a mutant (chance 0.5, rising to 0.85 with pressure); mutation step
  grows with pressure. A family holds at most 4; a full family replaces a clear loser (n >= 5, 25 below the parent).
- Culling: n >= 4 and mean < 70. The last genome of an archetype is never culled, and missing archetypes are re-seeded on load.
- Wave gating still applies per archetype, and genomes change behaviour only, never stats or tier.
- Caveat: squad fitness also reflects builds. Random assignment averages that out over n, but early culls can be noisy.
- Log tags: `[TACTICS] born ...`, `[TACTICS] culled ...`. Old saves migrate from `tactic_stats`.

## Solver-profile and formation genes

Solver doctrine (`SolverProfile`, per role) now has config-only genes beyond `favored_synergy`/pierce/amplify:

- `secondary_synergy` + `secondary_mix`: a second element the infuser picks that fraction of the time.
- `engage_scale` (0.7-1.4): scales the role's base `engagement_distance` at spawn (press in vs kite).
- These only touch per-tile config and spawn stats, never tile topology, so the `AutoEquipSolver` topology cache key is unchanged. Keep it that way: a gene that alters placement must extend the cache key (and costs solver time).
- Mutation/crossover live in `ProfileEvolution.gd`; the 35% per-bot element jitter copies all genes (`copy_genes_to`). Old saves load neutral values. The War Room doctrine list shows the second element and range.

Squad templates carry formation genes:

- `tactic_bias`: an archetype name (or none). It multiplies that archetype's draw weight by 2.5 in `TacticGenome.choose` (also on replan), so a composition can learn which tactic suits it without being forced into it.
- `formation_spread` (0.75-1.35): scales flank/ring standoff distance for that squad (kept on `SquadTactics`, not in the genome cfg, so replans keep it).
- `MAX_TOTAL_SIZE = 10`: `SquadTemplateMutator.clamp_size` trims mutated/crossed/random/fused templates, so size can evolve but not balloon. Squad fitness is already per-member normalised, so bigger squads are not rewarded for size alone.

Next: player movement-habit modelling, map flank-route analysis in the loading screen, War Room display of pool/pressure.

Checks: `scripts/debug/SquadTacticsCheck.tscn`, `StockBuildCreditCheck.tscn`.

## Shared gene pool (AI sharing)

An AI profile can be shared as clipboard JSON or as a **Style Card**: the champion-card PNG with a second iTXt chunk (`pixbots.aigenes`, format `pixbots-aigenes-v1`) carrying the best templates, solver profiles, bosses, tactic genomes and stock builds. Only genes travel - never `PlayerModel`, telemetry or the exporter's fitness record, so an import can't pollute the receiving director's read of its own player.

Everything imported lands on **probation** (`GenePool.gd`, `WarRoomSnapshot.merge_imported`):

- Templates, profiles and bosses are capped per import (3/3/2), flagged experimental at reduced weight with their fitness reset, so the normal cull/graduate loop judges them against *this* player. Name collisions are renamed with the origin pilot; re-importing the same export is a no-op.
- Each imported template is also crossbred with the best local template (capped hybrids), so traits mix instead of merely co-existing ("Tommy's fast closers" meet "Bob's snipers").
- Tactic genomes arrive as untested capped immigrants (`TacticGenome.immigrate`) plus a hybrid with the best local genome in the same family; an immigrant stays "on trial" until it has enough credited squads.
- Stock builds for accepted templates come along; the rest become **donors** (`~donor:<pilot>` template name, so they can never take a local champion's slot). `StockBuildMutator.splice` swaps ONE body slot from a donor into the champion to make a deviation candidate, which must beat the champion through the normal promotion gate - components are cleaved in gradually, one slot at a time.
- `GenePool.diversity` feeds the "AI variety" line in the War Room (role/doctrine/element entropy, tactic variants, pilot-sourced entries, spliced builds).

Import hardening (all imports are untrusted data): JSON only, never `load()`/eval/script paths from a payload; schema version and list-length gates; role names allow-listed, plan names checked against `SquadTactics.PLANS`, counts/sizes/spreads clamped, strings truncated; PNG chunk walker bounds-checks lengths and caps chunk size; style cards are deduped by content hash. Regression: `GenePoolCheck.tscn`.

## Orders log, movement habits, boss kits

- **Orders log** (`OrdersLog.gd`, HUD `OrdersPanel.gd`): squads post plan/commit/replan/casualty/wipe events; one line per 2.5 s, per-squad cooldowns, priority-ranked pending queue, stale lines dropped.
- **Movement habits** (`MovementHabits.gd`, `PlayerModel.habits`): sampled at 4 Hz against the nearest enemy; classifies camper/kiter/brawler/strafer and tracks the player's favoured retreat heading. Style multiplies plan weights (`TacticGenome.choose(..., habit_mult)`), and pincer/hammer/bait squads send their fastest flanker to a `CUTOFF` goal on that heading. Shown in the War Room ("The AI's read on you"). Behaviour only.
- **Boss kits** (`BossBrain.gd`, `BossProfile.gd`): 11 abilities (new: meteor_rain, minefield, gravity_well, triple_rail, charge), 6 enrage styles (new: relentless, phase_shift), 5 position styles (new: teleporter, lurker). All ground-telegraphed; bosses never summon. Imported boss profiles go through `BossProfile.sanitize`.
- **Enemy builds** now also solve Head and Backpack as energy conditioners (Catalyst first) and serialize those slots in stock builds.

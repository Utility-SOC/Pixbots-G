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

Next: player movement-habit modelling, map flank-route analysis in the loading screen, War Room display of pool/pressure.

Checks: `scripts/debug/SquadTacticsCheck.tscn`, `StockBuildCreditCheck.tscn`.

# Pixbots-G: a reviewer's read (2026-10-13)

*Written from the code, the 300-odd headless checks, the design docs and the last four play-session logs. I have not played it
with a controller in hand, so feel judgements (hit-stop, camera, audio mix) are the one thing this review cannot make; everything
else is evidence-backed and the evidence is cited.*

## Verdict

An original, ambitious hybrid: a **Factorio-style energy-routing builder whose output is your weapon loadout**, wrapped in
wave combat against an **enemy AI that learns and remembers you**. The mechanical depth is real (ten elements, a shield
counter wheel, combos like shatter and gravity wells, 60+ tile types, Mythic rule-benders), the mech *looks like its grid*, and
the engineering underneath (seeded RNG streams, a Rust port, a 300-check headless suite, a build that targets an Intel HD 4000)
is far beyond a typical indie. The problem is the part you already suspect: **the player is not under enough pressure for the
depth to matter.** A game of this shape lives or dies on whether the build you engineered is *tested*, and right now it mostly
isn't.

| Axis | Read |
|---|---|
| Concept / originality | Strong. "Your build is the program, the AI is the opponent that studies it" is a clean, sellable hook. |
| Mechanical depth | Very strong, and now better balanced (burn/poison scaling, shatter, vortex crashes, element combos on enemies). |
| Challenge and tension | **Weak.** See the next section; this is the headline finding. |
| Onboarding | Mixed: a tutorial maze and Frank exist, but the Garage is dense and the first hour is not curated. |
| Variety / content | Excellent and growing: 34 map types, four war eras, 150+ set pieces, bosses, rivals, Elite Four. |
| Presentation | Distinctive procedural pixel look; set pieces and maps now carry real identity. Voice was inconsistent (fixed in part). |
| Technical polish | Good under test; real-hardware risks remain (device-loss on weak GPUs, 100-400 ms spikes, a 6 MB autosave). |

## The central problem: the player is too powerful, and the AI cannot fix it

Five independent pieces of evidence point the same way.

1. **The AI learns nothing because it never gets hurt.** Across the last four sessions, 394 of 397 defeated squads scored a
   fitness of exactly 0.0 (fitness is clamped at zero and rewards damage dealt/taken and survival). The persistent
   evolution system (squad templates, tactic genomes, solver profiles, stock-build champions) is starved of signal: it is
   selecting among enemies that all die before doing anything measurable. The most distinctive system in the game is idling.
2. **Health had no ceiling.** Heals were uncapped: the recorder shows the player at 1,440,100 HP on a 100 HP bar at wave 38
   (Vampiric lifesteal scaling with six-figure shots). That is a plain bug and is fixed (`HealCapCheck`), but it explains part
   of how runs feel unkillable.
3. **The numbers race favours the builder.** Enemy HP grows exponentially to wave 25 and then linearly: at Normal a wave-38
   enemy is about 71x its base (a brawler: ~21k HP; a scout: ~4k), wave 100 about 300x. A shot can reach **600,000**, and
   routing multipliers (amplifier loops, resonators) compound. The two curves do not need to cross; they only need to be
   far apart, and they are.
4. **No cost axis.** There is no heat, ammo or upkeep (the Heat system is still "on the horizon"). Weight slows you, but a
   build that is strictly better in every dimension costs nothing extra to run, so the optimal build is also the safe build.
5. **The stated design rule works against the problem.** `docs/ENEMY_AI_DESIGN.md` says difficulty comes from *behaviour and
   loadout, never stats*. The behaviour layer is clever, but if the player's output is orders of magnitude above the enemy's
   HP, tactics (pincers, flanks, bait) cannot matter: nothing survives long enough to execute them. Near-peer scaling exists
   but only on the top difficulty.

### What I would do, in order

**A. Measure first (a day).** Add three KPIs to the bench and check them in CI: *median squad lifetime* (target 15-30 s at
every wave band), *player damage taken per wave as a share of effective HP* (target 10-30%), and *share of squads with non-zero
fitness* (target >60%). Run them on two reference builds (a mid and a late build) with `BenchGame`. Balance against numbers,
not feel. Without these you will keep fixing symptoms.

**B. Make pressure scale with the build, with a floor and a slack.** Promote the existing near-peer scaling to *all*
difficulties with different ratios (Casual 0.4x of your power, Normal 0.7x, Hard 1.0x, "Why would you" 1.3x), computed on a
smoothed, capped estimate so it cannot be farmed by swapping to junk before a wave. This turns "design rule: no stat inflation"
into "stat inflation that follows *your* power, so tactics still decide fights". It also revives the AI evolution immediately.

**C. Add a real cost to power (the Heat/Overload pillar).** Outputs above a per-limb threshold generate heat; heat above a
cap forces a vent window. This is what makes the slow elements pay and what gives the Overload Reactor its drama. Make
shields draw from the same budget as weapons while firing, so "all in" has a price.

**D. Give enemies ways to hurt a strong build that are not HP.** Percent-based pressure (corrosion that shrinks max shield),
shield-breaker/EMP units that cut routed energy, artillery that outranges snipers, swarmers that overwhelm single-target
builds, zones that disable healing, and boss mechanics that require movement rather than output. The new geysers, scalding
and unexploded ordnance are in this spirit; make them matter in the normal rotation.

**E. Make objectives the point, not kills.** The new enemy fort-capture (enemies hold points and buff themselves) is the start.
Add escort, siege, "defend X for 90 s" and extraction-under-fire scenarios where raw kill speed is not the measure. Waves
with timers and a shrinking safe area (battle-royale pressure) are cheap and effective.

**F. Opt-in difficulty with real stakes.** Wager Waves (built overnight) and Frank's Challenges (also built) are the right
shape: the player chooses the difficulty and is paid for it. Extend with *mutators* (Hades-style heat pacts) and ascension
tiers that unlock rewards, so power-seeking players have a ladder that never runs out.

**G. Rein in permanence.** The inventory persists and snowballs across runs, so strength is cumulative rather than earned
per run. Consider a per-run draft (pick one of three tiles after each wave) on top of the persistent vault, and a **loadout
budget** per mission (Armored-Core-style weight/energy cap), so a Mythic hoard does not trivialise early waves.

## Other findings

**Onboarding.** The hex-routing puzzle is the game's best idea and its steepest wall. Teach it in isolation first: a short
series of one-screen routing puzzles ("get 3 Fire into the mount with two tiles") before the Garage opens fully, scored on
efficiency. Frank's Challenges are the combat-side cousin. Hide advanced tiles until discovered (the discovery card exists).

**Legibility of the AI.** The Director's learning is invisible to most players. Surface it: after each wave, one line
("It saw 14 Lightning kills. Next wave: insulated bots."), a named recurring **nemesis** squad that remembers a specific
fight, and a War Room view that shows *what changed since last session*. The shareable AI and style cards are a real social
hook; put them on the front page.

**Combat feel.** I cannot judge this from here. The code has hit-stop, telegraphed boss abilities and cover-seeking enemies,
all good signs. Check that very large shots stay readable (the projectile size cap by difficulty is a sensible fix) and that
Casual is genuinely casual and Hard genuinely hard, which ties back to the KPIs above.

**Voice and tone.** Two voices were fighting: the Shopkeeper's warm wry humour and the enemy "radio chatter" in action-movie
slang. Enemy orders now speak as "the Trainer" (clinical, polite, faintly bureaucratic), and `docs/VOICE.md` pins both
voices down. The 622-line intermission pool is large enough; the risk is non-sequitur lines, so tag lines by context
(post-boss, low-HP, first-time-in-biome) rather than drawing from one bag.

**Content and variety.** This is now a strength: 17 map types plus hypertech twins, four war eras that change what is on the
map, kitbashed and surreal set pieces. The risk is breadth outrunning tuning: each map needs an eyes-on pass for spawn
fairness, cover density and enemy pathing. Hilly/Mountains (height, line of sight, valley-limited explosions) is the one
requested map family still missing and is a real systems task.

**Performance and technical.** Strong discipline (benchmarks, parity checks, weak-GPU tier). Watch: 100-420 ms frame spikes
at wave starts, the 6 MB autosave rewritten every garage exit (move to a binary or compressed format and save off-thread),
orphan nodes (one leak found and fixed), and the Intel Vulkan device-loss (OpenGL is now the default on those GPUs).

**Input and accessibility.** No gamepad bindings were found. A twin-stick shooter wants controller support (and Steam Deck
verification is a real sales lever). Add remappable controls everywhere (planned), text scaling in the Garage, and a
colour-blind-safe element palette (the elements lean on hue).

**Market positioning.** Builder-plus-action with a learning opponent is a niche with passionate buyers (Factorio, Opus Magnum,
Mechabellum, Armored Core, Hades). A 30-second pitch exists: *"Wire a mech out of energy and watch an AI that studies your
build learn to beat it."* Lead with the Garage and the AI-learns hook, ship a demo with the first act, and use the daily seed
and shareable AI for community. Steam Workshop for tiles/AI profiles fits the existing modding docs.

## Features that would make it a better game (ranked by value / effort)

1. **Pressure KPIs plus build-relative scaling** (A, B above): the highest-value fix; small code, large effect.
2. **Heat / Overload** (C): the missing cost axis; unlocks the reactor and capacitor designs.
3. **Routing puzzle mode** (Opus Magnum style) as tutorial and endgame: reuses the real simulator, gives shareable, scored content.
4. **Nemesis and director callouts** (AI legibility): turns the best system into the most visible one.
5. **Run structure**: acts with a boss and a draft, so a run has a shape; keep Endless as a mode.
6. **Controller support and remapping.**
7. **Loadout budget and mission modifiers** (G, F): opt-in difficulty with rewards.
8. **Replays and photo mode**: the game looks like its grid; let players show it off.
9. **Online**: duels and co-op waves are on the roadmap; async ghost duels (the ghost system exists) come first.
10. **Platforms**: macOS first, then touch (see `Status.md` backlog); do the touch-first Garage redesign once.

## What changed overnight that bears on this

Heals are capped; Wager Waves (stake scrap on horde/ironclad/glass/feeble waves), Frank's Challenges (flat-reduction, "The
Eye" and shield rules in scripted arenas), enemy fort capture, geysers/ordnance/forest fire hazards, the Colosseum for Elite
Four fights, the Bot League spectator mode, six shop cutscenes and the Shop Cat landed. None of them changes the core balance
by itself; B and C above are the changes that would. All of it is verified headless, none of it play-tested.

## Questions for you

1. Are you willing to let enemy stats track the player's build power (B)? It is the single biggest lever and it bends the
   "behaviour not stats" rule.
2. Heat: should exceeding the budget be a soft penalty (slow, reduced output) or a hard lockout?
3. Do you want runs to have a shape (acts and a draft) or to stay an endless sandbox with modes around it?
4. Which of the new modes (Challenges, Bot League, Wagers) do you want promoted to the main menu's front page?

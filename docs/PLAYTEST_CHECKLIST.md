# Playtest checklist (things only a human on the real machine can confirm)

Everything below is covered by headless checks or benches, but not by eyes, ears or the real GPU.
Tick items off after a session; send the console log (`~/pixbots_session_*/console.log`) for anything odd.
Launcher flags: `--safe` (optional visuals off), `--full-fx` (force them on), `--silent`, `--no-update`.

## Stability (highest priority)
- [ ] Play a normal launch (no `--safe`) to waves 28-40 with several Garage trips and arm swaps. Any
      "Vulkan device was lost"? If yes, send the log; the `[GPU]` lines show memory trend.
- [ ] After a crash, does the next launch say "starting with optional visuals OFF"? Does `--full-fx` turn them back on?
- [ ] F3 shows the overlay (GPU memory line included); Shift+F3 moves it to the top-left.

## Maps (Phase 2)
- [ ] Ground still looks crisp and identical to before (it is now uploaded at 1/4 size).
- [ ] Shallows: a lighter blue band along shorelines, walkable, slower; deep water still blocks.
- [ ] Road is faster, ice (tundra) is slippery, ash (volcano) and undergrowth (forest) slightly slower.
- [ ] Lava vents on volcano: crack glows, ring closes in for ~1 s, then bursts and burns whoever is inside.
- [ ] Forts: hold ring fills in 10 s standing inside; an enemy inside stalls it; leaving at 25%+ brings a squad to defend.
- [ ] Villages and crash sites: walk up to the cache and get a component; crash sites have boulders and burning-capable oil.
- [ ] Boss fights raise a ring of grey pillars that only explosives crack; they vanish when the boss dies.
- [ ] Weather (snow / embers / dust / leaves) and ambient props look right and are not distracting.
- [ ] Scorch marks appear under explosions and fade over ~90 s.
- [ ] Tabletop (green forest bases), Open Field (boulder clusters), FightShovel (ponds, dirt tracks).

## Audio (Phase 3)
- [ ] Sound effects: shots per element, hits, booms, deaths, pickups. Anything too loud or harsh? (`~/pixbots_sfx_preview/*.wav` for auditioning.)
- [ ] Music ducks under big explosions; combat/garage music crossfades with no silent gap; later waves add layers.

## Gameplay
- [ ] Auto-Equip in the Garage gives a sensible, working build (element choices, not all RAW).
- [ ] War Room doctrine rows show evidence (LOW/MEDIUM/HIGH) and "AT RISK" labels.
- [ ] Waves no longer restart every 10 s or log "stalled" warnings.
- [ ] Pool, haul-at-risk and streak-bonus behaviours from the earlier sessions (headless-tested only).

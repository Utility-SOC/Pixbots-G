# Owner decisions and open questions (updated 2026-10-07)

## Decided (2026-10-07)
1. Resistance tiles map Stun = `concussed`, Shock = `paralyzed`, Freeze = `frozen`. Confirmed.
2. Guard strength is **proportional to the energy fed into the tile** (computed once per grid recalculation, lightweight
   over nuance). Built: Stun Guard / Shock Guard / Freeze Guard (`StatusResistTile.gd`).
3. Ice rework: **Shatter + Frost field.** A unit hit with enough cold starts leaving an icy trail, moves slowly and is
   embrittled (takes extra damage); if it dies it throws ice shrapnel. Not built yet (see Status.md).
4. Vortex: a **gravity well that pulls enemies along at the heart of the vortex** (carries them: great with Kinetic, which
   flings them across the map, or with Poison, which clumps them for culling). Not built yet.
5. Rust migration goal: **speed on weak hardware and Pixelbots 2 reuse.**
6. Timeline: **sooner is better; it takes precedence over most feature work** ("the game has to feel fluid to be fun").
7. Dropping the Godot editor for authoring: **yes** (not used).
8. Heat vs balance: **balance first; heat is still on the horizon.**
9. Weak-GPU visuals tier: **switches on automatically, and is switchable in Settings.**
10. Garage overload marking: **mark the chokepoints, but nothing before or after them.**
11. Next map step: **enemy use of terrain.**
12. The dark outside-world thread **gets cutscenes**: strange men dressed all in black (the same kind of hexagon bodies as
    Frank, but different proportions) come in and demand data. Story, spread across the whole game.
13. Pixelbots 2 column joins: **porcupine** (spiky, blocky).
14. Stay on Godot for the 3D sequel: **ideally not.**
- Probably obsolete (closed): the three questions in `docs/PROJECTILE_ARCHITECTURE_ROADMAP.md`.

## Still open
15. `AdaptiveTick` (lowers the physics rate under load) is still off (`PIXBOTS_ADAPTIVE_TICK=1` to try). Test how motion feels?
16. Field Repair is player-only. Keep it that way? (Recommendation: yes.)
17. Guard tuning: how much energy should give full (90%) protection? Placeholder `energy_for_max` = 1500 in
    `tiles/<Kind>GuardTile/stats.json`; needs a real late-game build to calibrate.

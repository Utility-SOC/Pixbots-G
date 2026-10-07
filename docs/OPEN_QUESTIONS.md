# Open questions for the owner (2026-10-07)

Answer by number. "Rec" is the assistant's recommendation.

## Needed for work in progress
1. Resistance tiles: map Stun = `concussed` (Explosion proc), Shock = `paralyzed` (Lightning), Freeze = `frozen` (Ice)? Confirm.
2. Strength of a resistance tile: full immunity at a big grid-capacity cost, or a partial reduction scaling with rarity?
   Rec: partial, scaling with rarity (~25% to ~85% shorter/weaker), capacity cost scaling too.
3. Ice rework (any combination): (a) Shatter: frozen enemies take bonus Kinetic/Explosion/Pierce damage and a frozen kill bursts;
   (b) Frost field: patches that slow and build chill, full chill = ~1.5 s hard freeze with diminishing returns;
   (c) Cold-soak: strips elemental resistances for a few seconds; (d) Ice walls: temporary walls via TerrainEditor.
   Rec: a + b.
4. Vortex suck-and-hold: persistent gravity well for 2-3 s (reuse the boss `gravity_well`), enemies inside slowed/rooted, per-target
   immunity window; or pull followed by an implosion hit?  Rec: persistent well with immunity window.

## Rust migration (docs/RUST_MIGRATION_ROADMAP.md)
5. Goal: speed on weak hardware, independence from Godot, or Pixelbots 2 reuse?
6. Acceptable timeline; is feature work paused during any phase?
7. Is dropping the Godot editor for level/UI authoring acceptable?

## Main roadmap (docs/ROADMAP.md)
8. Priority: Heat (new friction) or the elemental balance pass first?  Rec: balance first. Heat design sketch is in Status.md.
9. Phase 8: weak-GPU visuals tier switches on automatically, or only suggests itself in Settings?
10. Garage: mark only the single worst overloaded tile, or every overloaded tile?
11. Map hooks: terrain effects and objectives have landed; is "enemy use of terrain" next?
12. Dark outside-world thread: its own cutscenes, or stay in Frank's quips?

## Pixelbots 2 (docs/PIXELBOTS_2_HEX_TO_CUBE_MAPPING.md)
13. Adjacent tiles' columns: smooth merged shell or deliberately spiky "porcupine" silhouette?
14. Stay on Godot for the 3D sequel? (tied to 5)

## Probably obsolete, suggest closing (docs/PROJECTILE_ARCHITECTURE_ROADMAP.md)
- Hit-pipeline fidelity, MultiMesh granularity, "is Phase 6 ever the goal": the batch pool has been the default combat
  renderer since 2026-10-05 and the Rust geometry builder supersedes the MultiMesh idea.

## Small
15. AdaptiveTick is still off (PIXBOTS_ADAPTIVE_TICK=1 to try): do you want to test how motion feels?
16. Field Repair is player-only: keep it that way?  Rec: yes.

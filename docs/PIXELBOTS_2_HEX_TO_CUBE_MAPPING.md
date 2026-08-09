# Pixelbots 2: Hex-to-Cube Mapping Proposal

Design proposal, written 2026-08-09. Documentation only — no PB1 code
changes. Refines the axis-mapping idea already recorded in `Status.md`'s
"1a. Pixelbots 2: The 3D Vision" section; read that section first, this
document doesn't repeat its framing, only extends it.

## The starting point

`Status.md` already establishes the core idea: the hex grid isn't 2D
forever, it's the 2D unfolding of a 3D cube grid — each hex a player
places today is a face-projection of a cube, and when the game goes 3D
that same build data describes a genuine voxel structure. It also
records a tentative, explicitly-untested axis mapping: hex E/W → world
X, NE/SW → world Y, SE/NW → world Z (an axial-to-cube-diagonal mapping,
since a hex grid has 3 natural axes/6 directions, matching a cube's 3
axes/6 faces one-to-one).

This proposal checks that idea against the actual current hex-grid code
and finds one thing worth correcting before PB2 work starts: what the
current grid geometrically *is*, and one consequence of the axis mapping
that isn't obvious until you work through it.

## What the current grid actually is

Read directly, not assumed: `HexCoord.gd`, `HexGridComponent.gd`, and
`GarageGridRenderer.gd` implement a **genuine hexagonal tiling** —

- Axial coordinates `(q, r)`, with a real 6-neighbor adjacency (`HexCoord.
  neighbor(direction_idx)` for `direction_idx` 0–5), and an existing
  `to_cube()` helper already converting `(q, r)` to cube coordinates.
- Tiles are drawn as actual hexagon polygons (`GarageGridRenderer._draw_
  hex_filled`), six points around a center at 60° increments, using the
  standard pointy-top axial-to-pixel trig formula.

This is not squares dressed up with a per-row offset — it's exact hex
math already. That's good news for this proposal: the hex-to-cube
correspondence PB2 needs is a well-established, exact geometric fact
(the same relationship hex-grid tutorials use to explain why axial and
cube coordinates are interchangeable), not an approximation to invent
from scratch.

## The finding that changes the plan

Every hex's cube coordinates are `x = q`, `z = r`, `y = -x - z` — which
means `x + y + z = 0`, always. This isn't incidental: every one of the 6
axial neighbor steps changes exactly two of the three cube coordinates
by `+1`/`-1` and leaves the third untouched, so the sum is a preserved
invariant from the origin outward, no matter how far or how strangely a
shape grows.

Naively reinterpreting a hex's cube coordinates as its literal 3D world
position — the most direct reading of "each hex is a cube" — therefore
places **every single hex on one flat diagonal plane**. The tentative
axis mapping in `Status.md` is directionally right (it correctly orients
that plane in 3D space), but on its own it produces a flat diagonal
wafer, not the chunky, volumetric, genuinely wild silhouette the
mech-shape idea is picturing. Worth stating plainly: a literal
implementation of the existing tentative idea, exactly as recorded,
would not land on its own. It needs one more ingredient.

## The proposed fix: extrude, don't just reposition

Give each hex a short column of cubes perpendicular to that diagonal
plane, instead of a single cube sitting flush on it. Column height comes
from data the game already has and that already carries player-facing
meaning — no new fields required:

- **Tile weight** (`HexTile.get_weight()`, already defined per tile type
  — a Weapon Mount already returns `6.0`, for example) as the primary
  extrusion signal. Heavier tiles physically protrude further, so a
  mech's silhouette literally reads its loadout: chunky weapon mounts
  jut outward, thin routing/support tiles stay flush to the shell. This
  reuses a stat the game already tracks for an unrelated reason (mech
  mass/heft), rather than inventing a parallel "visual bulk" number that
  could drift out of sync with it.
- **Rarity** (already 0–4, Common → Mythic) as a secondary multiplier,
  reinforcing the "Mythic tiles are visually special" language the game
  already uses elsewhere (glow effects, special abilities). A torso
  covered in Mythic tiles should read as a hulking 3D mass at a glance,
  not just a stat-sheet difference.

The exact formula (how weight and rarity combine, what the base column
unit is) is deliberately left untuned here — that's a PB2-era balancing
decision, not something to lock in from a documentation pass with no
renderer to test it against.

## A better alternative: de-staggered cross-sections

Raised in discussion after the above was first written, and a real
improvement on it: instead of extruding perpendicular to the natural
diagonal cube-coordinate plane, **de-stagger the hex grid into offset
coordinates first**, then extrude straight up in a dedicated Z axis.

Today's hex rows are visually staggered (alternating rows shifted by
half a hex-width — the standard pointy-top layout `GarageGridRenderer`
already draws). Re-express that same grid in offset coordinates (a
well-known alternative to axial coordinates for exactly this purpose:
shift every even row right so hex centers line up into straight
columns) and each hex's position becomes a simple `(column, row)` pair
with a real vertical column above it — no diagonal plane, no tilt to
fight. The single authored 2D hex grid becomes one cross-sectional
slice of a voxel volume; Z is a purpose-built extrusion axis, not a
side effect of hex-cube geometry.

This is a genuine improvement over the cube-coordinate approach above:
easier to build tooling around (straightforward column/row/layer voxel
data, much closer to how voxel engines already work), and it sidesteps
the diagonal-plane problem by construction rather than by fighting it
with extrusion math. The tradeoff: de-staggering is a deliberate
simplification, not an exact geometric correspondence — a hex's true 6
neighbors don't map onto simple orthogonal/diagonal offset-grid
neighbors without care (the offset flips by row parity), so the exact
neighbor-mapping needs to be worked out carefully, not assumed.

**Taper, and the failure mode it can cause.** The natural refinement on
top of a flat per-tile column height: taper the cross-section as it
extrudes upward, and let the taper rate depend on local width — wide
areas (torso) stay broad for many layers before narrowing to a point,
narrow areas (an arm) narrow almost immediately. Real risk if handled
naively: if a column's *height* is also driven by local width (not just
its taper rate), an area that's thin *everywhere along its length* —
exactly what an upgraded arm becomes, since `generate_shape()`'s
existing template grows arms as long, thin rectangles as rarity rises —
never gets tall anywhere. The result reads as a flat ribbon or disk
instead of a limb.

The fix is to decouple the two things "taper by local width" bundles
together: column **height** stays driven by tile weight/rarity (as
above), completely independent of local 2D width, with a minimum floor
so nothing ever goes fully flat. Local width only controls the taper's
**shape** — how far the cross-section spreads outward before narrowing
to a point at the top of an already-real column. A thin arm segment
still gets real height from its own tile; it just doesn't spread far
before tapering, reading as a spike or rod rather than collapsing to a
disk. The related guardrail (a maximum per-component-type dimension, so
an upgraded arm can't grow into an unbounded noodle) is really a 2D
shape-generation budget question — bounding how long/thin `generate_
shape` lets a limb grow — as much as it is a 3D-extrusion one, and
belongs in that layer too, not just this one.

## Why no new shape-generation work is needed

`ComponentEquipment.generate_shape()` and `generate_procedural_shape()`
already produce exactly the kind of asymmetric, unpredictable
composition that reads as "wild" once it has real depth: fixed templates
for player starter gear (the torso grows as a symmetric hex disc, arms
and legs as tilted rectangles), and for enemy/procedural gear a genuine
random-walk system — line, hook, and block primitives chained together,
weighted by role archetype, until a hex budget is spent. Confirmed by
direct read, not assumption.

The core claim of this proposal: that existing 2D wildness becomes 3D
wildness for free once the cube-mapping-plus-extrusion layer exists
downstream of it. Zero changes to the generation code itself are
implied — both functions already reason about hex geometry as pure data
with no Godot-Node coupling in the algorithm (`Status.md` already
flagged this as the natural PB2 seed; still true). A cube-mapping layer
would be a new, separate consumer reading the same `valid_hexes`/
`HexGridComponent` output these functions already produce today.

## Open questions

Flagged here rather than answered, matching `Status.md`'s own
"genuinely untested, needs real validation" framing for the axis mapping
— these need a real renderer and a real look at the result, not more
documentation:

- **How adjacent tiles' columns should resolve where they meet.**
  Smoothed/merged into one continuous shell, or left as a deliberately
  spiky, blocky "porcupine" silhouette? Either could be the right
  aesthetic call — this proposal doesn't assume the answer is "smooth it
  out."
- **The exact de-staggered offset-coordinate neighbor mapping**, if that
  approach is the one taken forward — a hex's true 6 neighbors don't
  translate to simple orthogonal/diagonal offset-grid neighbors without
  the row-parity correction worked out carefully first.
- **Limb-to-torso attachment geometry.** Whether the seam where a limb's
  extruded volume meets the torso's needs special-cased geometry beyond
  the per-tile extrusion rule, or whether it just works because both
  sides are built from the same rule.
- **The engine question** `Status.md` already raises: whether Godot's
  native 3D tooling stays the right fit for a 3D-heavy sequel, or
  whether that's the point to reconsider. Explicitly not this proposal's
  call to make — flagged, not decided, same as the source document
  treats it.

## Summary

The hex grid is already true hex geometry, so the hex→cube
correspondence this needs is exact math, not invention. A direct
coordinate reinterpretation alone gives a flat diagonal plane; the
de-staggered cross-section approach sidesteps that entirely and is the
more practical direction to build. Either way, the missing piece is
extrusion — the game already has the data (tile weight, rarity) to
drive it meaningfully without adding anything new, as long as column
height stays decoupled from local width (with a floor) so nothing
degenerates into a flat disk. The existing procedural shape generation
already supplies the "wild" asymmetry; this proposal is only about how
that asymmetry becomes volume once PB2 actually starts building a
renderer for it.

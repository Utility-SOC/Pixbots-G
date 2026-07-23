extends Node

# Regression harness for: "the garage is so slow/freezie. I switch
# components and it just hangs for several moments" AND the follow-up "the
# simulation bug persists - I don't know what triggered it this time."
#
# Root cause of the freeze: GarageMenu._on_tab_changed() reran the FULL
# cross-component energy preview on every switch (a dummy Mech._simulate_
# grid pass at the 1000-step Mythic-overcharge cap plus a 200-step replay)
# even when nothing changed. Root cause of the follow-up staleness: the
# first cache implementation invalidated only via _mark_player_grid_dirty,
# but several grid-mutation paths (drag-drop placement, right-click
# removal, Auto-Equip, Clear Grid) never called that at all - so the cache
# happily served results from BEFORE the player's latest edits.
#
# Fix under test: every cache hit re-validates against a cheap content
# hash of ALL components' tiles (type/position/every config knob), so ANY
# mutation - through any code path, present or future - forces a real
# recompute, while genuinely unchanged builds skip the expensive sim.
# _snapshot_computes counts real computes so the assertions below can tell
# a cache hit from a recompute directly.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")
const GarageSimulationRunnerScript = preload("res://scripts/ui/GarageSimulationRunner.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# Core at (0,0) firing East into a Weapon Mount at (1,0).
	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	var hexes: Array[HexCoord] = [HexCoord.new(0, 0), HexCoord.new(1, 0)]
	torso.valid_hexes = hexes
	torso._rebuild_valid_hex_set()
	var core = CoreTileScript.new()
	core.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var mount = WeaponMountTileScript.new()
	torso.hex_grid.add_tile(HexCoord.new(1, 0), mount)

	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.mech_components = {HexTile.BodySlot.TORSO: torso}
	garage.active_component = torso
	garage.stats_label = Label.new()
	garage.add_child(garage.stats_label)
	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.grid_renderer.setup(torso.hex_grid, garage, torso.valid_hexes)
	garage.grid_renderer.active_component = torso
	garage.simulation_runner = GarageSimulationRunnerScript.new(garage)
	var sr = garage.simulation_runner

	sr.run_silent_snapshot()
	_check("first snapshot actually computed", sr._snapshot_computes == 1)
	var first_steps = sr.total_steps
	_check("first snapshot found a real run (nonzero total_steps)", first_steps > 0)

	# Unchanged build, second call - must be a pure cache hit.
	sr.run_silent_snapshot()
	_check("unchanged build: second call is a cache hit (no recompute)", sr._snapshot_computes == 1)
	_check("cache hit returns the same total_steps", sr.total_steps == first_steps)

	# Mutate the grid through a path that does NOT go through
	# _mark_player_grid_dirty (mirrors drag-drop/right-click/Auto-Equip/
	# Clear Grid, none of which mark dirty) - the content hash must catch it.
	torso.hex_grid.remove_tile(HexCoord.new(0, 0))
	sr.run_silent_snapshot()
	_check("a raw grid mutation (no dirty-marking anywhere) still forces a recompute", sr._snapshot_computes == 2)
	_check("the recompute reflects the mutation (Core gone -> 0 steps)", sr.total_steps == 0)

	# Config-only change (no add/remove): re-add the Core, snapshot, then
	# flip one active face - the hash must catch pure orientation edits too.
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	sr.run_silent_snapshot()
	var computes_after_readd = sr._snapshot_computes
	core.active_faces.clear()
	core.active_faces.append(3) # West - away from the mount
	sr.run_silent_snapshot()
	_check("a config-only edit (Core face toggled) also forces a recompute",
		sr._snapshot_computes == computes_after_readd + 1)

	# Explicit invalidation (the _mark_player_grid_dirty path) still works.
	sr.run_silent_snapshot()
	var computes_before_invalidate = sr._snapshot_computes
	garage._mark_player_grid_dirty()
	sr.run_silent_snapshot()
	_check("_mark_player_grid_dirty() still forces a recompute even with an identical hash",
		sr._snapshot_computes == computes_before_invalidate + 1)

	if failures == 0:
		print("PASS: silent snapshots cache on unchanged builds and recompute on ANY mutation, dirty-marked or not")
	get_tree().quit(0 if failures == 0 else 1)

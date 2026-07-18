extends Node

# Regression harness for the "player bot appearance needs to vary more"
# playtest report: MechRenderer._compute_bulk_factor() now derives a
# per-component silhouette-size multiplier from actual tile composition
# (Shield/Core/Accumulator/Missile/Lance = bulkier; Cloak/Jumpjet/Actuator/
# Directional Conduit/Filter = sleeker), folded into the same scale_mult
# lever every _draw_* function already uses for rarity - so two builds at
# the identical rarity no longer converge on the same silhouette.

const MechRendererScript = preload("res://scripts/visuals/MechRenderer.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const ShieldTileScript = preload("res://scripts/tiles/ShieldTile.gd")
const CloakTileScript = preload("res://scripts/tiles/CloakTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_component(tile_scripts: Array) -> ComponentEquipment:
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.COMMON)
	comp.generate_shape()
	var q = 0
	for script in tile_scripts:
		var tile = script.new()
		comp.hex_grid.add_tile(HexCoord.new(q, 0), tile)
		q += 1
	return comp

func _ready():
	var renderer = MechRendererScript.new()

	_check("no component (null) defaults to neutral 1.0", renderer._compute_bulk_factor(null) == 1.0)

	var neutral = _make_component([SplitterTileScript, SplitterTileScript])
	_check("neutral tiles (Splitter) don't shift bulk", renderer._compute_bulk_factor(neutral) == 1.0)

	var shield_heavy = _make_component([ShieldTileScript, ShieldTileScript, ShieldTileScript])
	var shield_bulk = renderer._compute_bulk_factor(shield_heavy)
	_check("3 Shield Generator tiles push bulk above neutral (%.3f)" % shield_bulk, shield_bulk > 1.0)

	var cloak_heavy = _make_component([CloakTileScript, CloakTileScript, CloakTileScript])
	var cloak_bulk = renderer._compute_bulk_factor(cloak_heavy)
	_check("3 Cloak Generator tiles push bulk below neutral (%.3f)" % cloak_bulk, cloak_bulk < 1.0)

	_check("Shield-heavy renders bulkier than Cloak-heavy at the same rarity",
		shield_bulk > cloak_bulk)

	# Clamping: an absurd number of bulky/sleek tiles must not blow past the range
	var extreme_bulky_tiles = []
	for i in range(20):
		extreme_bulky_tiles.append(ShieldTileScript)
	var extreme_bulky = _make_component(extreme_bulky_tiles)
	var extreme_bulk = renderer._compute_bulk_factor(extreme_bulky)
	_check("bulk factor clamps at the max even with 20 Shield Generators (%.3f)" % extreme_bulk, extreme_bulk <= 1.25)

	var extreme_sleek_tiles = []
	for i in range(20):
		extreme_sleek_tiles.append(CloakTileScript)
	var extreme_sleek = _make_component(extreme_sleek_tiles)
	var extreme_sleek_bulk = renderer._compute_bulk_factor(extreme_sleek)
	_check("bulk factor clamps at the min even with 20 Cloak Generators (%.3f)" % extreme_sleek_bulk, extreme_sleek_bulk >= 0.85)

	if failures == 0:
		print("PASS: mech silhouette bulk now reacts to actual tile composition, not just rarity")
	get_tree().quit(0 if failures == 0 else 1)

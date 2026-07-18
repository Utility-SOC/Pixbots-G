extends Node

# Regression harness for the two-axis mech-silhouette-variety feature.
# First pass (single net "bulk minus sleek" scalar) got follow-up playtest
# feedback: "if I have something a bit shieldy but very fast it could be
# bulky sleek... they need to be visually distinct in spite of the bulk" -
# a build with a healthy amount of both bulk and sleek tiles was averaging
# back out to looking plain, the opposite of "visually distinct". Bulk and
# sleek are now independent axes (Vector2, each only ever >= 1.0) applied
# as an anisotropic Node2D.scale on the part's container - this checks both
# the pure _compute_visual_factors() math AND that a real _rebuild_visuals()
# pass actually applies it to the rendered part.

const MechRendererScript = preload("res://scripts/visuals/MechRenderer.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
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

	# --- Pure math: independent axes, never cancel each other ---
	_check("no component (null) defaults to neutral (1,1)", renderer._compute_visual_factors(null) == Vector2.ONE)

	var neutral = _make_component([SplitterTileScript, SplitterTileScript])
	_check("neutral tiles (Splitter) stay at (1,1)", renderer._compute_visual_factors(neutral) == Vector2.ONE)

	var shield_only = _make_component([ShieldTileScript, ShieldTileScript, ShieldTileScript])
	var shield_factors = renderer._compute_visual_factors(shield_only)
	_check("pure-bulk build: x > 1 (%.3f)" % shield_factors.x, shield_factors.x > 1.0)
	_check("pure-bulk build: y stays at 1 (%.3f) - bulk does not shrink sleek" % shield_factors.y, shield_factors.y == 1.0)

	var cloak_only = _make_component([CloakTileScript, CloakTileScript, CloakTileScript])
	var cloak_factors = renderer._compute_visual_factors(cloak_only)
	_check("pure-sleek build: y > 1 (%.3f)" % cloak_factors.y, cloak_factors.y > 1.0)
	_check("pure-sleek build: x stays at 1 (%.3f) - sleek does not shrink bulk" % cloak_factors.x, cloak_factors.x == 1.0)

	var mixed = _make_component([ShieldTileScript, ShieldTileScript, CloakTileScript, CloakTileScript])
	var mixed_factors = renderer._compute_visual_factors(mixed)
	_check("\"bulky sleek\" build (2 Shield + 2 Cloak): BOTH axes rise together instead of cancelling to (1,1) (%s)" % str(mixed_factors),
		mixed_factors.x > 1.0 and mixed_factors.y > 1.0)
	_check("bulky-sleek's bulk axis matches a pure-bulk build with the same Shield count", mixed_factors.x == renderer._compute_visual_factors(_make_component([ShieldTileScript, ShieldTileScript])).x)

	# Clamping
	var extreme_tiles = []
	for i in range(20):
		extreme_tiles.append(ShieldTileScript)
	var extreme = renderer._compute_visual_factors(_make_component(extreme_tiles))
	_check("bulk axis clamps at the max even with 20 Shield Generators (%.3f)" % extreme.x, extreme.x <= 1.25)

	# --- End-to-end: a real _rebuild_visuals() pass actually applies it ---
	var mech = MechScript.new()
	mech.is_player = true
	add_child(mech)
	var torso = ComponentEquipmentScript.create_starter_torso()
	# Stack the torso with bulky+sleek tiles on top of its fixed structural ones
	for i in range(3):
		var st = ShieldTileScript.new()
		if torso.hex_grid.add_tile(HexCoord.new(10 + i, 10), st):
			pass
	mech.equip_component(torso)
	# Parented to the mech itself (a Node2D/CharacterBody2D), matching real
	# usage (Mech.gd:544) - PartHitbox.mech is typed Node2D, so parenting
	# this to a plain Node like the check script itself would fail that
	# assignment with an unrelated, misleading error.
	var live_renderer = MechRendererScript.new()
	live_renderer.name = "MechRenderer"
	live_renderer.components = mech.components
	mech.add_child(live_renderer)
	live_renderer._rebuild_visuals()
	var torso_container = live_renderer.drawn_parts.get("Torso")
	_check("a real _rebuild_visuals() pass sets the Torso container's scale (not left at default (1,1))",
		torso_container != null and torso_container.scale != Vector2.ONE)

	if failures == 0:
		print("PASS: bulk and sleek are independent axes that don't cancel each other, and the real render pass applies them")
	get_tree().quit(0 if failures == 0 else 1)

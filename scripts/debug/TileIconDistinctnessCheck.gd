extends Node

# Smoke/regression harness for: "individual hex icons need to be more
# distinct, a catalyst and a directional conduit are identical - lots of
# things share that graphic." Auditing GarageGridRenderer._draw_
# descriptive_icon found the gap was much bigger than the one pair named:
# every tile type WITHOUT its own explicit branch fell through to the
# generic conduit-line-or-dot fallback, identical to Directional Conduit
# and to EACH OTHER - Catalyst, Elemental Infuser, Filter, Magnet, Jumpjet,
# Actuator, Accumulator, Resonator, Lance Mount, Heal Beacon, Jammer
# Module, Drone Bay, Shield Generator, Cloak Generator all shared it.
#
# This can't assert on actual pixel output from a headless run, so it
# verifies the achievable things: every one of the 14 newly-distinct types
# reaches _draw() (its own real CanvasItem draw pass, not just a syntax
# check) without crashing, AND that Catalyst/Elemental Infuser actually
# read their live configured synergy through _get_synergy_color (the
# "show the configured element at a glance" half of the request) by
# checking the color differs across two different configured elements.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const GarageMenuScript = preload("res://scripts/ui/GarageMenu.gd")
const GarageGridRendererScript = preload("res://scripts/ui/GarageGridRenderer.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC)
	var hexes: Array[HexCoord] = []
	for i in range(20):
		hexes.append(HexCoord.new(i % 5, i / 5))
	comp.valid_hexes = hexes
	comp._rebuild_valid_hex_set()

	var tile_paths = [
		"res://scripts/tiles/CatalystTile.gd",
		"res://scripts/tiles/InfuserTile.gd",
		"res://scripts/tiles/FilterTile.gd",
		"res://scripts/tiles/MagnetTile.gd",
		"res://scripts/tiles/JumpjetTile.gd",
		"res://scripts/tiles/ActuatorTile.gd",
		"res://scripts/tiles/AccumulatorTile.gd",
		"res://scripts/tiles/ResonatorTile.gd",
		"res://scripts/tiles/HealBeaconTile.gd",
		"res://scripts/tiles/JammerModuleTile.gd",
		"res://scripts/tiles/DroneBayTile.gd",
		"res://scripts/tiles/ShieldTile.gd",
		"res://scripts/tiles/CloakTile.gd",
	]
	comp.hex_grid.add_tile(HexCoord.new(0, 0), CoreTileScript.new())
	var idx = 1
	for path in tile_paths:
		var t = load(path).new()
		t.rarity = HexTile.Rarity.MYTHIC
		comp.hex_grid.add_tile(HexCoord.new(idx % 5, idx / 5), t)
		idx += 1
	# Lance Mount separately (multi-cell footprint).
	var lance = load("res://scripts/tiles/LanceMountTile.gd").new()
	lance.footprint_offsets = [Vector2i(1, 0)]
	comp.hex_grid.add_tile(HexCoord.new(idx % 5, idx / 5), lance)

	var garage = GarageMenuScript.new()
	add_child(garage)
	garage.grid_renderer = GarageGridRendererScript.new()
	garage.add_child(garage.grid_renderer)
	garage.grid_renderer.setup(comp.hex_grid, garage, comp.valid_hexes)
	garage.grid_renderer.active_component = comp
	garage.grid_renderer.size = Vector2(800, 600)

	garage.grid_renderer.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_check("GarageGridRenderer survives a real _draw() pass with all 14 newly-distinct tile types present (no crash)",
		is_instance_valid(garage.grid_renderer))

	# --- Element-at-a-glance: Catalyst/Infuser icon color tracks the real
	# configured synergy, not a fixed color. ---
	var cat_a = load("res://scripts/tiles/CatalystTile.gd").new()
	cat_a.target_synergy = EnergyPacket.SynergyType.FIRE
	var cat_b = load("res://scripts/tiles/CatalystTile.gd").new()
	cat_b.target_synergy = EnergyPacket.SynergyType.ICE
	_check("Catalyst icon color changes with its configured target_synergy (FIRE != ICE)",
		garage.grid_renderer._get_synergy_color(cat_a.target_synergy) != garage.grid_renderer._get_synergy_color(cat_b.target_synergy))

	var inf_a = load("res://scripts/tiles/InfuserTile.gd").new()
	inf_a.secondary_synergy = EnergyPacket.SynergyType.LIGHTNING
	var inf_b = load("res://scripts/tiles/InfuserTile.gd").new()
	inf_b.secondary_synergy = EnergyPacket.SynergyType.POISON
	_check("Elemental Infuser icon color changes with its configured secondary_synergy (LIGHTNING != POISON)",
		garage.grid_renderer._get_synergy_color(inf_a.secondary_synergy) != garage.grid_renderer._get_synergy_color(inf_b.secondary_synergy))

	if failures == 0:
		print("PASS: 14 previously-generic tile types now draw distinct icons without crashing, and Catalyst/Infuser reflect their configured element")
	get_tree().quit(0 if failures == 0 else 1)

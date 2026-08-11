extends Node

# Regression check for: "autoequip doesn't work on stuff with weird/cool
# shapes" (2026-08-10 - a looted Head showed "Tiles Used: 1" after hitting
# Auto-Equip, on a shape with dozens of free hexes).
#
# Root cause: every procedurally-shaped component (LootManager._create_
# procedural_component, GarageMarket._build_component, GarageShop._build_
# generated_component - all three call generate_procedural_shape() for the
# organic "weird/cool" loot/market/shop shapes) only ever got an Energy
# Intake fixed_sink and nothing else. Every create_starter_* function ALSO
# adds a second, slot-specific fixed sink (Weapon Mount for arms, Actuator
# for legs, Torso Return for heads, the full 6-spoke link set for torsos) -
# that's what gives AutoEquipSolver an actual second target to route power
# toward. With only the trivial (0,0)-to-(0,0) "path," solve() had nothing
# real to build.
#
# Fixed via ComponentEquipment._add_procedural_payload_sink(), called from
# all three sites right after the (0,0) intake/core. This check drives the
# real solver against a procedurally-shaped component for every affected
# slot and confirms real tiles land beyond the single fixed sink.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const AutoEquipSolverScript = preload("res://scripts/core/AutoEquipSolver.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _real_starter_inventory() -> Array:
	var inventory: Array = []
	var taper = [HexTile.Rarity.COMMON, HexTile.Rarity.UNCOMMON, HexTile.Rarity.RARE]
	var taper_counts = {HexTile.Rarity.COMMON: 5, HexTile.Rarity.UNCOMMON: 3, HexTile.Rarity.RARE: 1}
	var classes = [
		preload("res://scripts/tiles/SplitterTile.gd"),
		preload("res://scripts/tiles/ReflectorTile.gd"),
		preload("res://scripts/tiles/AmplifierTile.gd"),
	]
	for r in taper:
		for c in classes:
			for i in range(taper_counts[r]):
				var tile = c.new()
				tile.rarity = r
				inventory.append(tile)
	return inventory

# Mirrors exactly what LootManager._create_procedural_component now does
# (post-fix) for a given slot, without needing a live Mech to hand it.
func _make_procedural_component(slot: int, rarity: int) -> ComponentEquipment:
	var comp = ComponentEquipmentScript.new(slot, rarity)
	comp.generate_procedural_shape()
	if slot == HexTile.BodySlot.TORSO:
		var core_tile = load("res://scripts/tiles/CoreTile.gd").new()
		core_tile.body_slot = HexTile.BodySlot.TORSO
		core_tile.rarity = rarity
		comp.hex_grid.add_tile(HexCoord.new(0, 0), core_tile)
		comp.fixed_sinks.append(HexCoord.new(0, 0))
	else:
		var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
		intake.tile_type = "Energy Intake"
		intake.body_slot = slot
		comp.hex_grid.add_tile(HexCoord.new(0, 0), intake)
		comp.fixed_sinks.append(HexCoord.new(0, 0))
		ComponentEquipmentScript._orient_intake_to_shape(comp, intake)
	ComponentEquipmentScript._add_procedural_payload_sink(comp, rarity)
	return comp

func _ready():
	var slots = {
		HexTile.BodySlot.ARM_L: "Left Arm",
		HexTile.BodySlot.ARM_R: "Right Arm",
		HexTile.BodySlot.LEG_L: "Left Leg",
		HexTile.BodySlot.LEG_R: "Right Leg",
		HexTile.BodySlot.HEAD: "Head",
		HexTile.BodySlot.TORSO: "Torso",
	}

	for slot in slots:
		var label = slots[slot]
		var comp = _make_procedural_component(slot, HexTile.Rarity.RARE)
		_check("a procedural %s ends up with more than just the intake/core as a fixed sink (%d total)" % [label, comp.fixed_sinks.size()],
			comp.fixed_sinks.size() >= 2)

		var solver = AutoEquipSolverScript.new()
		var leftover = solver.solve(comp, _real_starter_inventory(), null)
		var tiles_used = comp.hex_grid.get_all_tiles().size()
		_check("Auto-Equip places real tiles on a procedural %s beyond the single fixed sink (tiles_used=%d)" % [label, tiles_used],
			tiles_used > 1)

	# Torso specifically should get its full spoke network (up to 6 limb
	# links + core), not just one payload sink like the single-limb slots.
	var torso = _make_procedural_component(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	_check("a procedural Torso gets multiple spoke links, not just one payload sink (%d fixed sinks)" % torso.fixed_sinks.size(),
		torso.fixed_sinks.size() >= 4)

	if failures == 0:
		print("PASS: procedurally-shaped components (loot/market/shop 'weird/cool shapes') get a real slot-specific payload sink, and Auto-Equip actually places tiles on them")
	get_tree().quit(0 if failures == 0 else 1)

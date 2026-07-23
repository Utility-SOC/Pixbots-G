extends Node

# Regression harness for Chloe's swarm-jammer schtick (per the user:
# "Chloe is one of the rivals... her schtick/bias is toward using lots of
# drones - she comes with a jammer, each of her drones should have one too
# so she has a huge jamming field built from their combined power.")
#
# The "combined power" part needs NO new mechanic: every drone's VISION
# Jammer Module projects its own JammerField, and JammerField already
# stacks same-side fields multiplicatively within JAMMER_LINK_RANGE
# (stack_multiplier) - a clustered swarm compounds into one huge blanket.
# What's under test here is the supply side:
#   1. Chloe's RivalProfile carries drones_have_jammers (and it survives
#      the to_dict/from_dict round trip learned-state persistence uses).
#   2. JammerModuleTile.ensure_on_component() places exactly one
#      VISION-mode jammer on a free hex, and is idempotent.
#   3. A drone spawned from a jammer-equipped loadout actually gets
#      has_jammer_module capacity in VISION mode (tile presence is enough,
#      no energy routing required).

const RivalProfilesFactoryScript = preload("res://scripts/ai/RivalProfilesFactory.gd")
const RivalProfileScript = preload("res://scripts/ai/RivalProfile.gd")
const JammerModuleTileScript = preload("res://scripts/tiles/JammerModuleTile.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const DroneBayTileScript = preload("res://scripts/tiles/DroneBayTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1. Profile flag + persistence round trip ---
	var profiles = RivalProfilesFactoryScript.create_profiles({})
	_check("factory produces Chloe", profiles.has("Chloe"))
	var chloe = profiles.get("Chloe")
	if chloe:
		_check("Chloe has drones_have_jammers set", chloe.drones_have_jammers)
		_check("Chloe's megaswarm count honors her intro line (about twenty micro-bots)", chloe.drone_swarm_count == 20)
		_check("no other rival accidentally got the flag",
			not profiles["Arthur"].drones_have_jammers and not profiles["Declan"].drones_have_jammers
			and profiles["Declan"].drone_swarm_count == 0)
		var round_tripped = RivalProfileScript.new()
		round_tripped.from_dict(chloe.to_dict())
		_check("drones_have_jammers survives the to_dict/from_dict round trip", round_tripped.drones_have_jammers)
		_check("drone_swarm_count survives the round trip too", round_tripped.drone_swarm_count == 20)

	# --- 2. ensure_on_component: placement + idempotence ---
	var loadout = ComponentEquipmentScript.create_starter_drone(HexTile.Rarity.RARE)
	_check("a fresh starter drone loadout has no jammer yet", _count_jammers(loadout) == 0)
	_check("ensure_on_component reports success", JammerModuleTileScript.ensure_on_component(loadout))
	_check("exactly one jammer was placed", _count_jammers(loadout) == 1)
	JammerModuleTileScript.ensure_on_component(loadout)
	_check("a second call is a no-op (still exactly one)", _count_jammers(loadout) == 1)
	var placed = _first_jammer(loadout)
	_check("the placed jammer is VISION mode (the spatial-field kind that stacks)",
		placed != null and placed.jam_mode == JammerModuleTileScript.JamMode.VISION)
	_check("the placed jammer inherited the loadout's rarity", placed != null and placed.rarity == HexTile.Rarity.RARE)

	# --- 3. A drone equipped with that loadout gains the capacity ---
	var owner_stub = Node2D.new()
	owner_stub.set_script(_make_owner_stub_script())
	add_child(owner_stub)
	var pack = ComponentEquipmentScript.create_drone_backpack(HexTile.Rarity.RARE)
	var bays = DroneBayTileScript.find_all_in_backpack(pack)
	_check("the drone backpack actually has a bay to test with", bays.size() > 0)
	if bays.size() > 0:
		var bay = bays[0]
		# The bay's own prebuilt loadout can be COMPLETELY full at low
		# rarity (core + jumpjet + mount fill every hex) - ensure must
		# report success even then (full-grid fallback bolts on a pod hex).
		_check("ensure_on_component succeeds on the bay's own (possibly full) loadout",
			JammerModuleTileScript.ensure_on_component(bay.get_or_build_loadout()))
		owner_stub.components = {HexTile.BodySlot.BACKPACK: pack}
		var parent_node = Node.new()
		add_child(parent_node)
		var spawned = DroneBayTileScript.spawn_drones_for(owner_stub, parent_node)
		_check("a drone spawned from the jammer-equipped bay", spawned.size() == 1)
		if spawned.size() == 1:
			var drone = spawned[0]
			drone._recalculate_grid()
			_check("the drone has jammer capacity from tile presence alone", drone.has_jammer_module)
			_check("the drone's jammer is VISION mode (projects a stacking JammerField)", drone.jammer_mode == 0)

	# --- 4. Megaswarm: spawn_drone_swarm clones the template per drone ---
	var swarm_owner = Node2D.new()
	swarm_owner.set_script(_make_owner_stub_script())
	add_child(swarm_owner)
	var swarm_parent = Node.new()
	add_child(swarm_parent)
	var template = ComponentEquipmentScript.create_starter_drone(HexTile.Rarity.RARE)
	JammerModuleTileScript.ensure_on_component(template)
	var swarm = DroneBayTileScript.spawn_drone_swarm(swarm_owner, swarm_parent, template, 6, HexTile.Rarity.RARE)
	_check("spawn_drone_swarm produced the requested 6 drones", swarm.size() == 6)
	var all_jammed = true
	var all_armed = true
	var distinct = true
	var seen_components = {}
	for d in swarm:
		d._recalculate_grid()
		if not d.has_jammer_module:
			all_jammed = false
		if d.precalculated_weapons.is_empty():
			all_armed = false
		for slot in d.components:
			var cid = d.components[slot].get_instance_id()
			if seen_components.has(cid) or d.components[slot] == template:
				distinct = false
			seen_components[cid] = true
	_check("every swarm drone carries its own jammer (cloned from the template)", all_jammed)
	_check("every swarm drone is armed", all_armed)
	_check("every swarm drone got its OWN loadout clone (no shared/stolen component nodes)", distinct)

	if failures == 0:
		print("PASS: Chloe and every one of her drones field VISION jammers - the stacking field mechanic does the rest")
	get_tree().quit(0 if failures == 0 else 1)

func _count_jammers(component) -> int:
	var n = 0
	for tile in component.hex_grid.get_all_tiles():
		if tile.tile_type == "Jammer Module":
			n += 1
	return n

func _first_jammer(component):
	for tile in component.hex_grid.get_all_tiles():
		if tile.tile_type == "Jammer Module":
			return tile
	return null

func _make_owner_stub_script() -> GDScript:
	var src = GDScript.new()
	src.source_code = "extends Node2D\nvar components: Dictionary = {}\n"
	src.reload()
	return src

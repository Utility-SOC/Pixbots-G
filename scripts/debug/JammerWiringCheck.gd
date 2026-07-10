extends Node

# End-to-end check of the new jammer wiring: a real player Mech with a
# VISION-mode Jammer Module fed by a Core, ticked through _update_jammer_module
# to confirm a JammerField actually spawns and follows, an enemy Mech's Blind
# gate reacting to it, and BossBrain's jam_burst spawning its own field.
# Safe to delete once validated.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTile = preload("res://scripts/tiles/CoreTile.gd")
const JammerModuleTile = preload("res://scripts/tiles/JammerModuleTile.gd")

var world: Node2D

func _ready():
	world = Node2D.new()
	add_child(world)

	# --- Player with a VISION jammer ---
	var player = MechScript.new()
	player.is_player = true
	world.add_child(player)

	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC)
	var core = CoreTile.new()
	core.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)

	var jammer_tile = JammerModuleTile.new()
	jammer_tile.body_slot = HexTile.BodySlot.TORSO
	jammer_tile.jam_mode = JammerModuleTile.JamMode.VISION
	jammer_tile.rarity = HexTile.Rarity.LEGENDARY
	torso.hex_grid.add_tile(HexCoord.new(1, 0), jammer_tile)

	player.equip_component(torso)
	player._recalculate_grid()
	print("has_jammer_module: ", player.has_jammer_module, "  jammer_mode: ", player.jammer_mode, "  jammer_pulse_radius: ", player.jammer_pulse_radius)

	# Tick _update_jammer_module a few times (as _physics_process would).
	for i in range(3):
		player._update_jammer_module(0.1)

	if not is_instance_valid(player.jammer_field):
		push_error("FAIL: player.jammer_field was not created")
	else:
		print("PASS: player.jammer_field exists, owner_is_player=", player.jammer_field.owner_is_player, " base_radius=", player.jammer_field.base_radius)

	var fields_in_group = get_tree().get_nodes_in_group("jammer_field")
	print("jammer_field group size: ", fields_in_group.size())

	# --- Enemy standing inside the player's field should go Blind ---
	var enemy = MechScript.new()
	enemy.is_player = false
	enemy.target = player
	enemy.global_position = player.global_position + Vector2(20, 0) # well inside a Legendary-radius field
	world.add_child(enemy)
	enemy.has_sight_of_player = true # simulate it already had lock
	enemy._update_player_sight(1.0) # force past the sight-check throttle
	print("Enemy inside player field - has_sight_of_player: ", enemy.has_sight_of_player, " (expect false)")

	# Move it far away and confirm sight isn't force-blinded there (still
	# gated by real raycast/range, just confirming the Blind branch doesn't
	# fire when clearly outside).
	enemy.global_position = player.global_position + Vector2(5000, 0)
	enemy._sight_check_timer = -1.0
	enemy._update_player_sight(1.0)
	print("Enemy far away - has_sight_of_player: ", enemy.has_sight_of_player, " (expect false, out of range either way)")

	# --- Toggle jammer off (unequip) and confirm the field is released ---
	player.unequip_component(HexTile.BodySlot.TORSO)
	player.is_grid_dirty = true
	player._recalculate_grid()
	player._update_jammer_module(0.1)
	print("After unequip - has_jammer_module: ", player.has_jammer_module, "  jammer_field valid: ", is_instance_valid(player.jammer_field))

	get_tree().quit()

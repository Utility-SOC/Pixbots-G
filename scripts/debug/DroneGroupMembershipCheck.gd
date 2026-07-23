extends Node

# Regression harness for: Drone.gd extends Mech but its _ready() fully
# overrides Mech._ready() without calling super, so drones never picked up
# Mech.gd:578's add_to_group("enemy") for enemy-owned drones - the same class
# of bug that line's own comment already warned about once before (see
# Mech.gd), just unnoticed here since drones were added to the game later.
# Confirms the fix: every drone (either side) joins "drone", and only
# enemy-owned drones also join "enemy" - player-owned drones must NOT join
# "enemy" (that would make them shoot-able by their own squad's IFF checks
# and show up as hostile on the minimap) and must NOT join "player" either
# (several call sites assume that group names exactly the one real player
# mech, e.g. MapGenerator's flow field / Mech._get_player_ref taking
# players[0]).

const MechScript = preload("res://scripts/entities/Mech.gd")
const DroneBayTileScript = preload("res://scripts/tiles/DroneBayTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var world = Node2D.new()
	add_child(world)

	# --- Player-owned drone ---------------------------------------------
	var player = MechScript.new()
	player.is_player = true
	world.add_child(player)
	var pack = ComponentEquipment.create_drone_backpack(HexTile.Rarity.RARE)
	player.equip_component(pack)
	player.set_physics_process(false)

	var player_drones = DroneBayTileScript.spawn_drones_for(player, world)
	_check("player-owned drone spawned", not player_drones.is_empty())
	if not player_drones.is_empty():
		var pd = player_drones[0]
		_check("player-owned drone is in 'drone' group", pd.is_in_group("drone"))
		_check("player-owned drone is NOT in 'enemy' group", not pd.is_in_group("enemy"))
		_check("player-owned drone is NOT in 'player' group (that names the real player mech only)", not pd.is_in_group("player"))

	# --- Enemy-owned drone -------------------------------------------------
	var enemy_owner = MechScript.new()
	enemy_owner.is_player = false
	enemy_owner.combat_role = "commander"
	world.add_child(enemy_owner)
	enemy_owner.set_physics_process(false)

	var enemy_drone = load("res://scripts/entities/Drone.gd").new()
	enemy_drone.setup(enemy_owner, null, HexTile.Rarity.COMMON)
	world.add_child(enemy_drone)

	_check("enemy-owned drone is in 'drone' group", enemy_drone.is_in_group("drone"))
	_check("enemy-owned drone IS in 'enemy' group (fixes jammer-pulse/lightning-arc/minimap/etc.)", enemy_drone.is_in_group("enemy"))

	if failures == 0:
		print("PASS: drones (either side) are visible to group-based queries the same way regular mechs already are")
	get_tree().quit(0 if failures == 0 else 1)

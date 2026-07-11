extends Node

# Two fixes in one harness:
#   1. Mythic Weapon Mount "Mortar" pattern: firing must spawn a MortarShell
#      that telegraphs, flies for its travel time, then applies elemental
#      AoE at the AIM POINT (not along a firing line) - enemy at the target
#      takes damage + FIRE status.
#   2. Wave-save fix (play report: "game save is still not saving wave"):
#      current_wave must round-trip through save_game/load_game. This node
#      doubles as the current_scene stand-in - SaveManager reads
#      current_wave off it.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

var current_wave: int = 7 # read by SaveManager.save_game via current_scene

var world: Node2D
var player: Node
var enemy: Node
var hp_before: float = 0.0
var elapsed: float = 0.0
var failures: int = 0

func _ready():
	world = Node2D.new()
	add_child(world)

	player = MechScript.new()
	player.is_player = true
	world.add_child(player)
	player.set_physics_process(false)

	enemy = MechScript.new()
	enemy.is_player = false
	world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector2(400, 0)
	hp_before = enemy.hp

	# Mythic mount in Mortar mode, FIRE payload, aimed at the enemy.
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.MYTHIC
	mount.mythic_pattern = 4
	mount.body_slot = HexTile.BodySlot.TORSO
	player.components[HexTile.BodySlot.TORSO].hex_grid.add_tile(HexCoord.new(1, 0), mount)
	player.last_aim_position = enemy.global_position

	# Small payload on purpose: Mythic power multiplier is 5x and a dead
	# enemy frees before the assertions can read it.
	var packet = EnergyPacket.new(10.0)
	packet.synergies.clear()
	packet.synergies[EnergyPacket.SynergyType.FIRE] = 10.0
	mount._fire_combined_projectile(player, packet, 0)

	var shell_found = false
	for child in world.get_children():
		if child.get_script() == load("res://scripts/attacks/MortarShell.gd"):
			shell_found = true
	if not shell_found:
		push_error("FAIL: Mortar pattern spawned no MortarShell")
		failures += 1
		_finish()
	else:
		print("1) mortar shell in flight (telegraphing the aim point)")

func _process(delta: float):
	elapsed += delta
	if elapsed < 2.0:
		return
	set_process(false)

	if enemy.hp >= hp_before:
		push_error("FAIL: mortar payload never damaged the enemy at the aim point (hp %.0f)" % enemy.hp)
		failures += 1
	else:
		print("2) payload landed: enemy hp %.0f -> %.0f" % [hp_before, enemy.hp])
	if not enemy.status_effects.has("burning"):
		push_error("FAIL: FIRE mortar didn't apply burning at the impact zone")
		failures += 1
	else:
		print("3) FIRE payload applied burning")
	_finish()

func _finish():
	# --- wave-save round trip ---
	SaveManager.save_game("wavetest_harness", player, [])
	var loaded = SaveManager.load_game("wavetest_harness")
	DirAccess.remove_absolute(SaveManager.SAVE_DIR + "wavetest_harness.json")
	if int(loaded.get("current_wave", -1)) != 7:
		push_error("FAIL: current_wave didn't round-trip (got %s)" % str(loaded.get("current_wave")))
		failures += 1
	else:
		print("4) current_wave=7 round-tripped through save/load")

	if failures == 0:
		print("PASS: mortar remote payload works; wave counter persists in saves")
	get_tree().quit(0 if failures == 0 else 1)

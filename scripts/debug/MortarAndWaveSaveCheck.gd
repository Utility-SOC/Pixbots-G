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
	# Tanky on purpose: the payload drives the FULL direct-fire pipeline
	# (crits, part damage) and a dead enemy frees before the assertions.
	enemy.max_hp = 100000.0
	enemy.hp = 100000.0
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
	# --- LIGHTNING mortar chains like direct fire (the payload drives the
	# real Projectile._handle_hit pipeline, so the arc jumps to a second
	# enemy near the impact) ---
	var e1 = MechScript.new()
	e1.is_player = false
	world.add_child(e1)
	e1.set_physics_process(false)
	e1.global_position = Vector2(900, 0)
	e1.max_hp = 100000.0
	e1.hp = 100000.0
	var e2 = MechScript.new()
	e2.is_player = false
	world.add_child(e2)
	e2.set_physics_process(false)
	e2.global_position = Vector2(1000, 0) # inside chain range of e1
	e2.max_hp = 100000.0
	e2.hp = 100000.0
	var e2_hp = e2.hp

	var shell = load("res://scripts/attacks/MortarShell.gd").new()
	shell.setup(Vector2.ZERO, e1.global_position, 0.5, 40.0, {EnergyPacket.SynergyType.LIGHTNING: 10.0}, true, player)
	world.add_child(shell)
	await get_tree().physics_frame
	await get_tree().physics_frame
	shell._detonate() # skip the flight
	# Blink model: the payload survives the direct hit, re-arms, and
	# teleport-hops to the bystander over the next few physics ticks,
	# landing a full contact hit (not a decaying side-channel zap).
	for i in range(20):
		await get_tree().physics_frame
		if is_instance_valid(e2) and e2.hp < e2_hp:
			break
	if not is_instance_valid(e2) or e2.hp >= e2_hp:
		push_error("FAIL: lightning mortar payload never blink-hopped to the second enemy")
		failures += 1
	else:
		print("5) lightning payload blink-hopped: bystander hp %.0f -> %.0f" % [e2_hp, e2.hp])
	shell.queue_free()

	# --- mortar counter-doctrine: artillery use up-weights cloak/jammer ---
	var director = load("res://scripts/ai/SquadDirector.gd").new()
	add_child(director)
	var t = load("res://scripts/ai/SquadTemplate.gd").new("Smoke Screen", {"ambusher": 2, "jammer": 1})
	director.register_template(t)
	var w_before = t.spawn_weight
	for i in range(16):
		director.log_mortar_shot()
	var intel = director.get_intel_line(5)
	if t.spawn_weight <= w_before or not ("artillery" in intel):
		push_error("FAIL: mortar doctrine (weight %.0f -> %.0f, intel '%s')" % [w_before, t.spawn_weight, intel])
		failures += 1
	else:
		print("6) mortar doctrine: cloak/jammer template %.0f -> %.0f, tell: %s" % [w_before, t.spawn_weight, intel])

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

extends Node

# Regression harness for the HealBeaconSystem extraction (Mech.gd
# tech-debt pass, third and last of the low-risk "equippable ability"
# cuts after CloakSystem/JammerModuleSystem): AI beacons auto-fire on
# timer and heal their squad + self at half strength; the player's beacon
# is keybind-gated (H) and self-heals at full strength; drones are the
# player's healed "allies" instead of the AI squad group.

const MechScript = preload("res://scripts/entities/Mech.gd")

const DT := 1.0 / 30.0

func _ready():
	# The tree is still mid-setup during this very _ready() call - a
	# same-frame add_child(get_tree().root, ...) later on (for the
	# current_scene stand-in) would hit "Parent node is busy setting up
	# children." One deferred frame is enough to clear that.
	await get_tree().process_frame

	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# --- 1. AI beacon: auto-fires on timer, heals squad + self at half ------
	var ai_healer = MechScript.new()
	ai_healer.is_player = false
	world.add_child(ai_healer)
	ai_healer.set_physics_process(false)
	ai_healer.has_healer = true
	ai_healer.heal_pulse_power = 40.0
	ai_healer.heal_pulse_radius = 500.0
	ai_healer.heal_pulse_interval = 1.0
	ai_healer.heal_pulse_timer = 0.02 # less than one DT - guaranteed to cross 0 this tick
	ai_healer.max_hp = 100.0
	ai_healer.hp = 50.0

	var squadmate = MechScript.new()
	squadmate.is_player = false
	squadmate.add_to_group("enemy") # AI beacons heal the "enemy" group (their own squad, same-side convention)
	squadmate.global_position = Vector2(100, 0)
	squadmate.max_hp = 100.0
	squadmate.hp = 50.0
	world.add_child(squadmate)
	squadmate.set_physics_process(false)

	ai_healer._update_healer(DT)
	var squad_healed = squadmate.hp > 50.0
	var self_healed_half = ai_healer.hp > 50.0 and ai_healer.hp < 50.0 + ai_healer.heal_pulse_power
	if not squad_healed:
		push_error("FAIL: AI beacon didn't heal its squadmate (hp still %f)" % squadmate.hp)
		failures += 1
	elif not self_healed_half:
		push_error("FAIL: AI beacon self-heal wasn't at half strength (hp %f, expected between 50 and %f)" % [ai_healer.hp, 50.0 + ai_healer.heal_pulse_power])
		failures += 1
	elif ai_healer.heal_pulse_timer != ai_healer.heal_pulse_interval:
		push_error("FAIL: pulse timer didn't reset to heal_pulse_interval after firing")
		failures += 1
	else:
		print("1) AI beacon auto-fires on timer: heals squad + self at half strength, timer resets")

	# --- 2. Player beacon: keybind-gated, self-heals at FULL strength, heals
	# drones instead of the AI squad group -----------------------------
	if not InputMap.has_action("heal_pulse"):
		InputMap.add_action("heal_pulse")

	var player = MechScript.new()
	player.is_player = true
	world.add_child(player)
	player.set_physics_process(false)
	player.has_healer = true
	player.heal_pulse_power = 40.0
	player.heal_pulse_radius = 500.0
	player.heal_pulse_interval = 1.0
	player.heal_pulse_timer = 0.02
	player.max_hp = 100.0
	player.hp = 50.0

	var drone = MechScript.new()
	drone.is_player = false # a real drone reads is_player from its owner, but for this check only group membership matters
	drone.global_position = Vector2(80, 0)
	drone.max_hp = 100.0
	drone.hp = 50.0
	world.add_child(drone)
	drone.set_physics_process(false)

	# current_scene lookup in _emit_pulse needs main.drone_nodes to be a
	# REAL declared property (Object.set() on an undeclared name is a
	# silent no-op, not a dynamic attribute) - a tiny inline script gives
	# the stand-in "Main" the exact shape the real one exposes.
	var fake_main_script = GDScript.new()
	fake_main_script.source_code = "extends Node2D\nvar drone_nodes: Dictionary = {}\n"
	fake_main_script.reload()
	var fake_main = Node2D.new()
	fake_main.set_script(fake_main_script)
	fake_main.name = "FakeMain"
	# current_scene requires a DIRECT child of the tree root, not just
	# anywhere in the tree - a child of `world` (itself nested under this
	# check's own node) doesn't qualify.
	get_tree().root.add_child(fake_main)
	get_tree().current_scene = fake_main
	fake_main.drone_nodes = {0: drone}

	# Without the H key pressed, the player's beacon must NOT auto-fire even
	# though its timer has expired.
	player._update_healer(DT)
	if player.hp != 50.0 or drone.hp != 50.0:
		push_error("FAIL: player beacon fired without the H keybind being pressed")
		failures += 1
	else:
		print("2) player beacon does NOT auto-fire - keybind-gated as designed")

	# Simulate pressing H and re-tick.
	Input.action_press("heal_pulse")
	player._update_healer(DT)
	Input.action_release("heal_pulse")

	var drone_healed = drone.hp > 50.0
	var player_self_healed_full = player.hp >= 50.0 + player.heal_pulse_power - 0.5
	if not drone_healed:
		push_error("FAIL: player beacon (H pressed) didn't heal the drone (hp still %f)" % drone.hp)
		failures += 1
	elif not player_self_healed_full:
		push_error("FAIL: player self-heal wasn't at full strength (hp %f, expected ~%f)" % [player.hp, 50.0 + player.heal_pulse_power])
		failures += 1
	else:
		print("3) player beacon (H pressed): heals drones (not the AI squad group), self-heals at FULL strength")

	if failures == 0:
		print("PASS: HealBeaconSystem preserves AI auto-fire, player keybind-gating, and side-aware ally targeting")
	get_tree().quit(0 if failures == 0 else 1)

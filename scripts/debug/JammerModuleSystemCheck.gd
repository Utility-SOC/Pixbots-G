extends Node

# Regression harness for the JammerModuleSystem extraction (Mech.gd
# tech-debt pass, same pattern as CloakSystem.gd/b3adf92): the existing
# Jammer* debug checks already cover VISION-mode field lifecycle, power
# scaling, glow rendering, and boss broadcast/receive_jammer_alert
# end-to-end against the extracted system (all still pass unmodified).
# This one closes the one gap none of them exercised: SYNERGY mode's
# actual pulse firing, timing, and side-awareness.

const MechScript = preload("res://scripts/entities/Mech.gd")

const DT := 1.0 / 30.0

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# AI-owned jammer (is_player=false) - victim is the player.
	var jammer = MechScript.new()
	jammer.is_player = false
	world.add_child(jammer)
	jammer.set_physics_process(false)
	jammer.has_jammer_module = true
	jammer.jammer_mode = 1 # SYNERGY
	jammer.jammer_pulse_radius = 500.0
	jammer.jammer_pulse_interval = 1.0
	jammer.jammer_effect_duration = 3.0
	jammer.jammer_target_synergy = EnergyPacket.SynergyType.FIRE
	jammer.jammer_pulse_timer = 0.02 # less than one DT (1/30 ~= 0.033) - guaranteed to cross 0 this tick

	var victim = MechScript.new()
	victim.is_player = true
	victim.add_to_group("player") # _get_player_ref() looks up the GROUP, not the is_player field
	victim.global_position = Vector2(100, 0) # well within the 500px pulse radius
	world.add_child(victim)
	victim.set_physics_process(false)

	# --- 1. Fires once the timer crosses 0, jams the intended synergy ------
	jammer._update_jammer_module(DT) # 0.1 - DT crosses 0 -> should fire
	if not victim.jammed_synergies.has(EnergyPacket.SynergyType.FIRE):
		push_error("FAIL: AI synergy jammer never jammed the player's FIRE synergy")
		failures += 1
	else:
		print("1) AI-owned synergy jammer fires on timer expiry and jams the intended element on the player")

	# --- 2. Timer resets to the configured interval after firing -----------
	if jammer.jammer_pulse_timer != jammer.jammer_pulse_interval:
		push_error("FAIL: pulse timer didn't reset to jammer_pulse_interval after firing (got %f)" % jammer.jammer_pulse_timer)
		failures += 1
	else:
		print("2) pulse timer resets to jammer_pulse_interval after firing")

	# --- 3. Side-awareness: a PLAYER-owned synergy jammer targets enemies,
	# never its own owner (the exact bug the side-aware fix corrected) -----
	var player_jammer = MechScript.new()
	player_jammer.is_player = true
	world.add_child(player_jammer)
	player_jammer.set_physics_process(false)
	player_jammer.has_jammer_module = true
	player_jammer.jammer_mode = 1
	player_jammer.jammer_pulse_radius = 500.0
	player_jammer.jammer_pulse_interval = 1.0
	player_jammer.jammer_effect_duration = 3.0
	player_jammer.jammer_target_synergy = EnergyPacket.SynergyType.ICE
	player_jammer.jammer_pulse_timer = 0.0

	var enemy = MechScript.new()
	enemy.is_player = false
	enemy.combat_role = "brawler"
	enemy.global_position = Vector2(50, 0)
	world.add_child(enemy)
	enemy.set_physics_process(false)

	player_jammer.jammer_module_system = load("res://scripts/entities/JammerModuleSystem.gd").new(player_jammer)
	player_jammer.jammer_module_system._emit_synergy_jam_pulse()
	if player_jammer.jammed_synergies.has(EnergyPacket.SynergyType.ICE):
		push_error("FAIL: player-owned jammer jammed ITSELF")
		failures += 1
	elif not enemy.jammed_synergies.has(EnergyPacket.SynergyType.ICE):
		push_error("FAIL: player-owned jammer never reached the enemy in range")
		failures += 1
	else:
		print("3) player-owned synergy jammer targets enemies, never its own owner")

	if failures == 0:
		print("PASS: JammerModuleSystem SYNERGY-mode pulse firing, timing, and side-awareness all correct")
	get_tree().quit(0 if failures == 0 else 1)

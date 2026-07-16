class_name HealBeaconSystem
extends RefCounted

# Heal Beacon runtime behavior (Support backpack ability), split out of
# Mech.gd's _update_healer/_emit_heal_pulse block - see CloakSystem.gd's
# header for the full split rationale (same composed-RefCounted pattern,
# same reason it can't be a sibling Node).
#
# Capacity fields (has_healer, heal_pulse_power, heal_pulse_radius,
# heal_pulse_interval) and the runtime heal_pulse_timer all stay on Mech -
# _recalculate_grid writes the capacity fields directly on every loadout
# change AND seeds heal_pulse_timer indirectly through them, same reasoning
# as CloakSystem/JammerModuleSystem's capacity fields. _update_healer(delta)
# stays a real Mech method (now a thin lazy-constructing wrapper) since
# _physics_process calls it directly by that name.

var mech: Mech

func _init(p_mech: Mech):
	mech = p_mech

func tick(delta: float) -> void:
	if not mech.has_healer:
		return
	mech.heal_pulse_timer -= delta
	if mech.is_player:
		# Module-keybind ruling ("I need to be able to use every type of
		# module"): the player's Heal Beacon is a BUTTON, not an autocast -
		# press H (registered in Main._ready) when the pulse is charged.
		if mech.heal_pulse_timer <= 0.0 and InputMap.has_action("heal_pulse") and Input.is_action_just_pressed("heal_pulse"):
			mech.heal_pulse_timer = mech.heal_pulse_interval
			_emit_pulse()
	elif mech.heal_pulse_timer <= 0.0:
		mech.heal_pulse_timer = mech.heal_pulse_interval
		_emit_pulse()

func _emit_pulse():
	# Allies by side: AI beacons heal their squad (the "enemy" group); the
	# player's beacon heals their companion drones.
	var allies: Array = []
	if mech.is_player:
		var main = mech.get_tree().current_scene
		if main and "drone_nodes" in main:
			allies = main.drone_nodes.values()
	else:
		allies = EntityCache.get_group("enemy")
	for ally in allies:
		if ally == mech or not is_instance_valid(ally) or not ("hp" in ally):
			continue
		if mech.global_position.distance_to(ally.global_position) > mech.heal_pulse_radius:
			continue
		var healed = min(ally.max_hp, ally.hp + mech.heal_pulse_power) - ally.hp
		ally.hp += healed
		if healed >= 1.0 and ally.has_method("_show_floating_text"):
			ally._show_floating_text("+%d" % int(round(healed)), Color(0.3, 1.0, 0.4))

	# AI beacons self-heal at half strength (the squad is the point); the
	# player's manual pulse self-heals at full - it's their button.
	var self_mult = 1.0 if mech.is_player else 0.5
	var self_healed = min(mech.max_hp, mech.hp + mech.heal_pulse_power * self_mult) - mech.hp
	mech.hp += self_healed
	if self_healed >= 1.0:
		mech._show_floating_text("+%d" % int(round(self_healed)), Color(0.3, 1.0, 0.4))

	var visual_class = load("res://scripts/attacks/PulseRingVisual.gd")
	if visual_class:
		var v = visual_class.new()
		v.global_position = mech.global_position
		v.setup(mech.heal_pulse_radius, Color(0.2, 0.9, 0.5, 1.0))
		if mech.get_parent():
			mech.get_parent().add_child(v)

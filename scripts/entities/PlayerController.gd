extends RefCounted
class_name PlayerController

# Player-only input/movement/firing, split out of Mech.gd (see that file's
# _physics_process for the lazy-construction call site). Composed, not a
# Node - see Mech.gd's boss_brain/status_runner/player_controller fields for
# why (load-bearing _physics_process ordering rules out sibling Nodes).

const JumpjetResidue = preload("res://scripts/attacks/JumpjetResidue.gd")

var mech: Mech

func _init(p_mech: Mech):
	mech = p_mech

# Last-frame state of the 1/2/3 keys for edge detection (one press = one
# big shot, see fire_charged / handle_input).
var _terakey_held: Dictionary = {}
var jumpjet_residue_timer: float = 0.0
var _blink_cooldown: float = 0.0

func handle_input(delta: float):
	if mech.jumpjet_energy and mech.jumpjet_energy.magnitude > 0:
		mech.jumpjet_energy.magnitude *= exp(-2.0 * delta) # Decay energy smoothly
		if mech.jumpjet_energy.magnitude < 0.1: mech.jumpjet_energy.magnitude = 0.0

	if mech.actuator_energy and mech.actuator_energy.magnitude > 0:
		mech.actuator_energy.magnitude *= exp(-2.0 * delta) # Decay energy smoothly
		if mech.actuator_energy.magnitude < 0.1: mech.actuator_energy.magnitude = 0.0

	# Simple WASD movement
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_axis("ui_left", "ui_right")
	input_dir.y = Input.get_axis("ui_up", "ui_down")

	if input_dir.length() > 0:
		input_dir = input_dir.normalized()

	# Calculate base walk multiplier from Actuators
	var actuator_mult = 1.0
	if mech.actuator_energy and mech.actuator_energy.magnitude > 0:
		actuator_mult += (mech.actuator_energy.magnitude / 200.0)
		actuator_mult = min(actuator_mult, 3.5) # User requested max 3.5x for actuator

	# Calculate sprint multiplier from Jumpjets
	var sprint_mult = 0.0
	if Input.is_key_pressed(KEY_SHIFT):
		sprint_mult = 0.5 # Base sprint is +0.5x speed
		if mech.jumpjet_energy and mech.jumpjet_energy.magnitude > 0:
			sprint_mult += (mech.jumpjet_energy.magnitude / 200.0)
			sprint_mult = min(sprint_mult, 2.5) # Up to +2.5x from jumpjets, so jumpjets alone = 3.5x walking speed max

		if mech.is_player:
			mech._ensure_jumpjet_trail()

			var new_color = EnergyPacket.get_color_blend(mech.jumpjet_energy.synergies) if mech.jumpjet_energy else Color.WHITE
			for p in mech.jumpjet_trail.get_children():
				if p.color != new_color: p.color = new_color
				p.emitting = true

			if mech.jumpjet_energy and mech.jumpjet_energy.magnitude > 0:
				jumpjet_residue_timer -= delta
				if jumpjet_residue_timer <= 0.0:
					jumpjet_residue_timer = 0.15 # Spawn residue periodically
					var residue = JumpjetResidue.new()
					residue.global_position = mech.global_position
					var dmg = max(10.0, mech.jumpjet_energy.magnitude * 0.1)
					residue.setup(dmg, mech.jumpjet_energy.synergies)
					mech.get_parent().add_child(residue)
	else:
		if mech.jumpjet_trail:
			for p in mech.jumpjet_trail.get_children():
				p.emitting = false

	# Combine multipliers and enforce absolute cap
	var total_mult = actuator_mult + sprint_mult
	total_mult = min(total_mult, 3.8) # User requested max 3.8x for both combined

	var actual_move_speed = mech.current_move_speed * total_mult
	var target_vel = input_dir * actual_move_speed

	# Scale acceleration much slower to give a feeling of weight
	var accel = 600.0
	if mech.jumpjet_rarity >= 0:
		accel += (mech.jumpjet_rarity * 150.0)
	if mech.thruster_accel_bonus >= 0:
		accel += (mech.thruster_accel_bonus * 200.0)

	if target_vel == Vector2.ZERO:
		mech.velocity = mech.velocity.move_toward(Vector2.ZERO, accel * delta)
	else:
		mech.velocity = mech.velocity.move_toward(target_vel, accel * delta)

	# JumpJets automatically hover over Water (Mask 2) and some obstacles
	if mech.jumpjet_rarity >= 0:
		mech.collision_mask = 1 | 4 | 16 # Only collide with walls/obstacles, Enemy, Loot
	else:
		mech.collision_mask = 1 | 2 | 4 | 16 # Collide with water too

	# Mouse Aiming
	var mouse_pos = mech.get_global_mouse_position()

	# Firing logic
	var is_left_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var is_right_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	# 1/2/3 ARE the fire buttons for the big charged shots (and only those).
	# Edge-triggered: one press = one big hit, if it's ready. The mouse
	# never fires these; they never fire from the mouse. See fire_charged.
	for key_pair in [[KEY_1, "1"], [KEY_2, "2"], [KEY_3, "3"]]:
		var held = Input.is_key_pressed(key_pair[0])
		if held and not _terakey_held.get(key_pair[1], false):
			fire_charged(key_pair[1], mouse_pos)
		_terakey_held[key_pair[1]] = held

	# Mythic Jumpjet Blink: Space teleports toward the cursor, capped range,
	# landing snapped to valid ground, on a cooldown.
	if mech.jumpjet_blink_mode:
		_blink_cooldown -= delta
		if Input.is_action_just_pressed("ui_select") and _blink_cooldown <= 0.0:
			_blink_cooldown = 3.0
			var to_cursor = mech.get_global_mouse_position() - mech.global_position
			if to_cursor.length() > 4.0:
				var dest = mech.global_position + to_cursor.normalized() * min(to_cursor.length(), 240.0)
				var map = mech._get_map_ref()
				if map and map.has_method("get_valid_spawn_position"):
					dest = map.get_valid_spawn_position(dest)
				mech._ensure_jumpjet_trail()
				for p in mech.jumpjet_trail.get_children():
					p.emitting = true
				mech.global_position = dest

	var is_firing = false
	if is_left_pressed and is_right_pressed and not mech.separate_arm_firing:
		mech._shoot(mouse_pos, true, true, delta)
		is_firing = true
	elif is_left_pressed:
		mech._shoot(mouse_pos, true, true, delta)
		is_firing = true
	elif is_right_pressed:
		if mech.separate_arm_firing:
			mech._shoot(mouse_pos, true, false, delta)
		else:
			mech._shoot(mouse_pos, false, false, delta)
		is_firing = true

	# NOTE: no release-fire anymore. Under the pre-prime model charge builds
	# passively, so the old "fire partial charge on mouse release" behavior
	# turned into constant unprompted spray (charge crossed the 10% floor
	# while idling and the next mouse-up frame fired it). Releasing the
	# mouse now does nothing; charge just holds at cap until you shoot.

# Fire the big charged accumulator shot bound to `key`. This is the ONLY
# player-side release path for bank entries: press once, it fires if fully
# charged; if it isn't ready yet you get a charge readout instead of a
# wasted squib. No quality tax here - the big hit always lands full value.
func fire_charged(key: String, target_pos: Vector2):
	mech.last_aim_position = target_pos
	mech.is_firing_outward = true

	for data in mech.precalculated_weapons:
		if data.get("bank_mode", "") != "bank":
			continue
		if data.packet.trigger_key != key:
			continue
		var mount = data.mount
		var required = data.packet.charge_required

		if mount.bank_current_charge < required:
			mech._show_floating_text("Charging %d%%" % int(100.0 * mount.bank_current_charge / max(0.001, required)), Color(0.6, 0.8, 1.0))
			continue

		var packet_to_fire = data.packet.copy()
		packet_to_fire.is_banked_shot = true
		packet_to_fire.magnitude *= mech.current_jammer_debuff
		for k in packet_to_fire.synergies:
			packet_to_fire.synergies[k] *= mech.current_jammer_debuff
		mech._apply_synergy_jamming(packet_to_fire)
		packet_to_fire.magnitude *= mech._get_ambush_multiplier()
		if mech.is_cloaked:
			mech._break_cloak()

		mount._fire_combined_projectile(mech, packet_to_fire, 0)
		mount.bank_current_charge = 0.0
		mech.heat = max(0.0, mech.heat - required * 0.6) # big shot = big heat dump

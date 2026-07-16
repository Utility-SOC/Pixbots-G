class_name JammerModuleSystem
extends RefCounted

# Jammer Module runtime behavior (equippable pulse ability - distinct from
# the JammerMech role, a whole separate continuous-aura mech class), split
# out of Mech.gd's _update_jammer_module/_emit_synergy_jam_pulse/
# _ensure_jammer_field/_release_jammer_field/_tick_jammer_broadcast block -
# see CloakSystem.gd's header for the full split rationale (same composed-
# RefCounted pattern, same reason it can't be a sibling Node).
#
# Capacity/config fields (has_jammer_module, jammer_pulse_radius/interval/
# target_synergy, jammer_mode, jammer_pulse_timer, _jammer_tiles) stay on
# Mech - _recalculate_grid writes ALL of them directly on every loadout
# change, including seeding jammer_pulse_timer, so moving them here would
# force this system to exist eagerly instead of lazily. jammer_field
# itself also stays on Mech: it's read directly (mech.jammer_field) by an
# existing debug check and is meant to be glanceable state, not something
# that requires knowing whether a JammerModuleSystem happens to exist yet.
#
# jammed_synergies/apply_synergy_jam()/_apply_synergy_jamming() are a
# DIFFERENT concern entirely (being jammed BY an enemy jammer, not owning
# one - ticked in update_status_effects, called cross-mech on victims that
# may have no jammer module of their own) and deliberately were never part
# of this cut - they stay on Mech untouched.

var mech: Mech

var _jammer_broadcast_timer: float = 0.0
const JAMMER_BROADCAST_INTERVAL = 2.5
var _jammer_field_exit_hooked: bool = false

func _init(p_mech: Mech):
	mech = p_mech

# VISION mode (jammer_mode == 0) is a persistent, spatial JammerField (see
# that class's own header comment) instead of a periodic full-screen-dim
# pulse - not stealth, an announcement: it broadcasts this mech's rough
# location to the opposing side while denying them an exact position, and
# blinds anyone from the opposing side standing inside it. SYNERGY mode
# (jammer_mode == 1) is the old pulse-timer/duration mute.
func tick(delta: float) -> void:
	# Drain routed packet energy from every equipped Jammer Module each
	# frame regardless of mode (nothing may pile up unread across a mode
	# switch); in VISION mode it feeds the field's power scaling ("jammer
	# field should increase with more power pushed into it").
	var jam_energy = 0.0
	for tile in mech._jammer_tiles:
		jam_energy += tile.get_jam_energy()

	if mech.has_jammer_module and mech.jammer_mode == 0: # VISION
		_ensure_jammer_field()
		if mech.jammer_field and jam_energy > 0.0:
			mech.jammer_field.feed_power(jam_energy)
		if mech.is_player:
			_tick_broadcast(delta)
	else:
		_release_jammer_field()

	if mech.has_jammer_module and mech.jammer_mode == 1: # SYNERGY
		mech.jammer_pulse_timer -= delta
		if mech.is_player:
			# Module-keybind ruling: the player's synergy jam is a BUTTON
			# (J, registered in Main._ready), fired when charged.
			if mech.jammer_pulse_timer <= 0.0 and InputMap.has_action("jam_pulse") and Input.is_action_just_pressed("jam_pulse"):
				mech.jammer_pulse_timer = mech.jammer_pulse_interval
				_emit_synergy_jam_pulse()
		elif mech.jammer_pulse_timer <= 0.0:
			mech.jammer_pulse_timer = mech.jammer_pulse_interval
			_emit_synergy_jam_pulse()

func _emit_synergy_jam_pulse():
	# Side-aware: an AI jammer jams the player; the PLAYER's jammer jams
	# every enemy in the pulse radius.
	var victims: Array = []
	if mech.is_player:
		victims = EntityCache.get_group("enemy")
	else:
		var p = mech._get_player_ref()
		if p:
			victims = [p]
	for v in victims:
		if not is_instance_valid(v):
			continue
		if mech.global_position.distance_to(v.global_position) <= mech.jammer_pulse_radius and v.has_method("apply_synergy_jam"):
			v.apply_synergy_jam(mech.jammer_target_synergy, mech.jammer_effect_duration)

	var visual_class = load("res://scripts/attacks/PulseRingVisual.gd")
	if visual_class:
		var v = visual_class.new()
		v.global_position = mech.global_position
		v.setup(mech.jammer_pulse_radius, Color(0.6, 0.15, 0.85, 1.0))
		if mech.get_parent():
			mech.get_parent().add_child(v)

func _ensure_jammer_field():
	if mech.jammer_field and is_instance_valid(mech.jammer_field):
		return
	if not mech.get_parent():
		return
	mech.jammer_field = JammerField.new()
	mech.jammer_field.global_position = mech.global_position
	mech.jammer_field.setup(mech, mech.jammer_pulse_radius, -1.0)
	mech.get_parent().add_child(mech.jammer_field)
	if not _jammer_field_exit_hooked:
		_jammer_field_exit_hooked = true
		mech.tree_exiting.connect(_release_jammer_field)

func _release_jammer_field():
	if mech.jammer_field and is_instance_valid(mech.jammer_field):
		mech.jammer_field.queue_free()
	mech.jammer_field = null

# Throttled (not per-frame) alert to every enemy on the map that the
# player's jammer is active, and roughly where - reuses the EXISTING
# search-AI primitives entirely unmodified (see Mech.receive_jammer_alert),
# doesn't touch or improve that system, just feeds it a new target.
func _tick_broadcast(delta: float):
	_jammer_broadcast_timer -= delta
	if _jammer_broadcast_timer > 0.0 or not mech.jammer_field or not is_instance_valid(mech.jammer_field):
		return
	_jammer_broadcast_timer = JAMMER_BROADCAST_INTERVAL
	var main = mech.get_tree().current_scene
	if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
		main.world.get_node("SquadDirector").broadcast_jammer_alert(mech.jammer_field.global_position)

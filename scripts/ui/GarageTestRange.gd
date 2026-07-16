class_name GarageTestRange
extends PopupPanel

# Garage Test Range (Status.md queue: "target dummy") - a physical firing
# range in a popup: pick any of your armed Weapon Mounts and test-fire its
# REAL energy feed (the exact precalculated packet combat would fire,
# including accumulator bank shots) at a real dummy mech. Real Projectile
# instances, real flight/spread/patterns/particles, real hits with damage
# numbers - not a simulation of the shot, the shot.
#
# Mount selection is a checklist, not a single dropdown pick (playtest:
# "could the garage test range... allow isolation of weapon mount(s) alone
# or in groups?") - every armed mount gets its own row, checked by default
# (so FIRE reproduces a real full volley out of the box), with a per-row
# Solo button to isolate exactly one and All/None for the rest. FIRE fires
# every currently-checked mount together in one volley, so you can test a
# single mount in isolation OR a chosen combination (e.g. "what do my two
# arms' payloads do when they land on the same target at once").
#
# Runs inside a SubViewport with its OWN World2D: the garage pauses the
# scene tree, so everything under this popup is PROCESS_MODE_ALWAYS, and
# the private physics world keeps stray test shots (and their AoE) from
# ever touching the actual battlefield behind the garage. The dummy is a
# real Mech (real PartHitboxes via MechRenderer) with absurd HP and an
# execution-exempt role, so nothing can actually kill it.

const MechScript = preload("res://scripts/entities/Mech.gd")

const RANGE_SIZE = Vector2(900, 340)
const RIG_POS = Vector2(110, 210)
const DUMMY_POS = Vector2(700, 210)
const AUTO_FIRE_INTERVAL = 0.6

var player: Node = null

var _world_root: Node2D = null
var _rig: Node = null
var _dummy: Node = null
# One entry per armed mount, in the same order as player.precalculated_weapons
# at the moment this popup opened: {checkbox: CheckButton, data: Dictionary}.
var _mount_rows: Array = []
var _mount_list: VBoxContainer = null
var _stats_label: Label = null
var _auto_toggle: CheckButton = null
var _auto_timer: float = 0.0
var _shots_fired: int = 0
var _volleys_fired: int = 0

func setup(p_player: Node):
	player = p_player

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

	var vbox = VBoxContainer.new()
	add_child(vbox)

	var title = Label.new()
	title.text = "TEST RANGE - live fire, real projectiles, nothing leaves this room"
	vbox.add_child(title)

	# Mount checklist row-select controls
	var select_controls = HBoxContainer.new()
	vbox.add_child(select_controls)
	var select_lbl = Label.new()
	select_lbl.text = "Mounts:"
	select_controls.add_child(select_lbl)
	var all_btn = Button.new()
	all_btn.text = "All"
	all_btn.pressed.connect(func(): _set_all_checked(true))
	select_controls.add_child(all_btn)
	var none_btn = Button.new()
	none_btn.text = "None"
	none_btn.pressed.connect(func(): _set_all_checked(false))
	select_controls.add_child(none_btn)

	var mount_scroll = ScrollContainer.new()
	mount_scroll.custom_minimum_size = Vector2(0, 110)
	vbox.add_child(mount_scroll)
	_mount_list = VBoxContainer.new()
	_mount_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mount_scroll.add_child(_mount_list)
	_populate_mounts()

	# Fire controls row
	var controls = HBoxContainer.new()
	vbox.add_child(controls)

	var fire_btn = Button.new()
	fire_btn.text = "FIRE"
	fire_btn.custom_minimum_size = Vector2(90, 0)
	fire_btn.tooltip_text = "Fires every currently-checked mount together as one volley."
	fire_btn.pressed.connect(_fire_selected)
	controls.add_child(fire_btn)

	_auto_toggle = CheckButton.new()
	_auto_toggle.text = "Auto"
	_auto_toggle.tooltip_text = "Keep firing the checked mounts every %.1fs." % AUTO_FIRE_INTERVAL
	controls.add_child(_auto_toggle)

	var reset_btn = Button.new()
	reset_btn.text = "Reset dummy"
	reset_btn.pressed.connect(_reset_dummy_stats)
	controls.add_child(reset_btn)

	# The range itself: SubViewport with a private physics world.
	var vp_container = SubViewportContainer.new()
	vp_container.stretch = true
	vp_container.custom_minimum_size = RANGE_SIZE
	vbox.add_child(vp_container)

	var viewport = SubViewport.new()
	viewport.size = RANGE_SIZE
	# A fresh World2D = a private physics space: test shots (and their AoE)
	# can never touch the real battlefield behind the garage.
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp_container.add_child(viewport)

	_world_root = Node2D.new()
	_world_root.process_mode = Node.PROCESS_MODE_ALWAYS
	viewport.add_child(_world_root)

	# Backdrop + range floor markings
	var bg = ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.size = RANGE_SIZE
	_world_root.add_child(bg)
	for x in range(5):
		var tick = ColorRect.new()
		tick.color = Color(0.2, 0.22, 0.26)
		tick.size = Vector2(2, RANGE_SIZE.y * 0.5)
		tick.position = Vector2(RIG_POS.x + 40 + x * 130, RANGE_SIZE.y * 0.25)
		_world_root.add_child(tick)

	# Firing rig: a minimal Mech stub - it exists so the mount's
	# _fire_combined_projectile has a legitimate source (muzzle position,
	# aim, is_player side) without dragging the whole player onto the range.
	_rig = MechScript.new()
	_rig.is_player = true
	_rig.global_position = RIG_POS
	_world_root.add_child(_rig)
	_rig.set_physics_process(false)
	_rig.last_aim_position = DUMMY_POS

	# The dummy: a real Mech with real per-part hitboxes (Mech._ready
	# assigns the enemy collision layer and "enemy" group itself, which is
	# also what lets homing/blink shots acquire it like a real target).
	# Commander role is pierce-execution-exempt and the HP pool is absurd,
	# so it soaks anything without dying (die() would drop loot in here).
	_dummy = MechScript.new()
	_dummy.is_player = false
	_dummy.combat_role = "commander"
	_dummy.global_position = DUMMY_POS
	_world_root.add_child(_dummy)
	_dummy.set_physics_process(false)
	_dummy.max_hp = 1e12
	_dummy.hp = _dummy.max_hp

	_stats_label = Label.new()
	_stats_label.text = "No shots fired yet."
	vbox.add_child(_stats_label)

	popup_hide.connect(queue_free)

func _populate_mounts():
	for c in _mount_list.get_children():
		c.queue_free()
	_mount_rows.clear()

	if not player or not is_instance_valid(player):
		var lbl = Label.new()
		lbl.text = "(no mech)"
		_mount_list.add_child(lbl)
		return
	if player.is_grid_dirty:
		player._recalculate_grid()
	var slot_names = {
		HexTile.BodySlot.TORSO: "Torso", HexTile.BodySlot.ARM_L: "L.Arm",
		HexTile.BodySlot.ARM_R: "R.Arm", HexTile.BodySlot.LEG_L: "L.Leg",
		HexTile.BodySlot.LEG_R: "R.Leg", HexTile.BodySlot.HEAD: "Head",
		HexTile.BodySlot.BACKPACK: "Backpack",
	}
	for data in player.precalculated_weapons:
		var kind = "bank shot" if data.get("bank_mode", "") == "bank" else "normal fire"
		var elem = EnergyPacket.element_name(data.packet.get_dominant_synergy())
		var row = HBoxContainer.new()
		var check = CheckButton.new()
		check.text = "%s %s - %s, %s (%.0f energy)" % [
			slot_names.get(data.slot_type, "?"), data.mount.tile_type, kind, elem, data.packet.magnitude]
		check.button_pressed = true # everything armed by default - FIRE reproduces a real full volley out of the box
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(check)
		var solo_btn = Button.new()
		solo_btn.text = "Solo"
		solo_btn.tooltip_text = "Check only this mount, uncheck every other one."
		var row_index = _mount_rows.size()
		solo_btn.pressed.connect(func(): _solo_row(row_index))
		row.add_child(solo_btn)
		_mount_list.add_child(row)
		_mount_rows.append({"checkbox": check, "data": data})

	if _mount_rows.is_empty():
		var lbl = Label.new()
		lbl.text = "(no armed mounts - wire energy to a Weapon Mount first)"
		_mount_list.add_child(lbl)

func _set_all_checked(on: bool):
	for row in _mount_rows:
		row.checkbox.button_pressed = on

func _solo_row(index: int):
	for i in range(_mount_rows.size()):
		_mount_rows[i].checkbox.button_pressed = (i == index)

func _checked_weapons() -> Array:
	var out: Array = []
	for row in _mount_rows:
		if row.checkbox.button_pressed:
			out.append(row.data)
	return out

func _fire_selected():
	if not player or not is_instance_valid(player):
		return
	var to_fire = _checked_weapons()
	if to_fire.is_empty():
		return
	_rig.last_aim_position = _dummy.global_position
	for data in to_fire:
		var packet = data.packet.copy()
		if data.get("bank_mode", "") == "bank":
			packet.is_banked_shot = true
		data.mount._fire_combined_projectile(_rig, packet, 0)
		_shots_fired += 1
	_volleys_fired += 1
	_update_stats()

func _reset_dummy_stats():
	if is_instance_valid(_dummy):
		_dummy.hp = _dummy.max_hp
	_shots_fired = 0
	_volleys_fired = 0
	_update_stats()

func _update_stats():
	if not is_instance_valid(_dummy):
		return
	var dealt = _dummy.max_hp - _dummy.hp
	var per_volley = dealt / max(1, _volleys_fired)
	_stats_label.text = "Volleys: %d   Shots: %d   Total damage on dummy: %.0f   Avg per volley: %.0f" % [_volleys_fired, _shots_fired, dealt, per_volley]

func _process(delta):
	if _auto_toggle and _auto_toggle.button_pressed:
		_auto_timer -= delta
		if _auto_timer <= 0.0:
			_auto_timer = AUTO_FIRE_INTERVAL
			_fire_selected()
	# Damage lands asynchronously (real flight time) - keep the readout live.
	if _volleys_fired > 0:
		_update_stats()

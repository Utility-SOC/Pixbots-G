class_name GarageTestRange
extends PopupPanel

# Garage Test Range (Status.md queue: "target dummy") - a physical firing
# range in a popup: pick any of your armed Weapon Mounts and test-fire its
# REAL energy feed (the exact precalculated packet combat would fire,
# including accumulator bank shots) at a real dummy mech. Real Projectile
# instances, real flight/spread/patterns/particles, real hits with damage
# numbers - not a simulation of the shot, the shot.
#
# Runs inside a SubViewport with its OWN World2D: the garage pauses the
# scene tree, so everything under this popup is PROCESS_MODE_ALWAYS, and
# the private physics world keeps stray test shots (and their AoE) from
# ever touching the actual battlefield behind the garage. The dummy is a
# real Mech (real PartHitboxes via MechRenderer) with absurd HP and an
# execution-exempt role, so nothing can actually kill it.

const MechScript = preload("res://scripts/entities/Mech.gd")

const RANGE_SIZE = Vector2(900, 380)
const RIG_POS = Vector2(110, 210)
const DUMMY_POS = Vector2(700, 210)
const AUTO_FIRE_INTERVAL = 0.6

var player: Node = null

var _world_root: Node2D = null
var _rig: Node = null
var _dummy: Node = null
var _mount_select: OptionButton = null
var _stats_label: Label = null
var _auto_toggle: CheckButton = null
var _auto_timer: float = 0.0
var _shots_fired: int = 0

func setup(p_player: Node):
	player = p_player

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS

	var vbox = VBoxContainer.new()
	add_child(vbox)

	var title = Label.new()
	title.text = "TEST RANGE - live fire, real projectiles, nothing leaves this room"
	vbox.add_child(title)

	# Controls row
	var controls = HBoxContainer.new()
	vbox.add_child(controls)

	_mount_select = OptionButton.new()
	_mount_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_mounts()
	controls.add_child(_mount_select)

	var fire_btn = Button.new()
	fire_btn.text = "FIRE"
	fire_btn.custom_minimum_size = Vector2(90, 0)
	fire_btn.pressed.connect(_fire_once)
	controls.add_child(fire_btn)

	_auto_toggle = CheckButton.new()
	_auto_toggle.text = "Auto"
	_auto_toggle.tooltip_text = "Keep firing the selected mount every %.1fs." % AUTO_FIRE_INTERVAL
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
	_mount_select.clear()
	if not player or not is_instance_valid(player):
		_mount_select.add_item("(no mech)")
		return
	if player.is_grid_dirty:
		player._recalculate_grid()
	var slot_names = {
		HexTile.BodySlot.TORSO: "Torso", HexTile.BodySlot.ARM_L: "L.Arm",
		HexTile.BodySlot.ARM_R: "R.Arm", HexTile.BodySlot.LEG_L: "L.Leg",
		HexTile.BodySlot.LEG_R: "R.Leg", HexTile.BodySlot.HEAD: "Head",
		HexTile.BodySlot.BACKPACK: "Backpack",
	}
	var idx = 0
	for data in player.precalculated_weapons:
		var kind = "bank shot" if data.get("bank_mode", "") == "bank" else "normal fire"
		var elem = EnergyPacket.element_name(data.packet.get_dominant_synergy())
		_mount_select.add_item("%s %s - %s, %s (%.0f energy)" % [
			slot_names.get(data.slot_type, "?"), data.mount.tile_type, kind, elem, data.packet.magnitude])
		_mount_select.set_item_metadata(idx, idx)
		idx += 1
	if idx == 0:
		_mount_select.add_item("(no armed mounts - wire energy to a Weapon Mount first)")

func _selected_weapon():
	if not player or not is_instance_valid(player):
		return null
	var meta = _mount_select.get_selected_metadata()
	if meta == null:
		return null
	var idx = int(meta)
	if idx < 0 or idx >= player.precalculated_weapons.size():
		return null
	return player.precalculated_weapons[idx]

func _fire_once():
	var data = _selected_weapon()
	if data == null:
		return
	_rig.last_aim_position = _dummy.global_position
	var packet = data.packet.copy()
	if data.get("bank_mode", "") == "bank":
		packet.is_banked_shot = true
	data.mount._fire_combined_projectile(_rig, packet, 0)
	_shots_fired += 1
	_update_stats()

func _reset_dummy_stats():
	if is_instance_valid(_dummy):
		_dummy.hp = _dummy.max_hp
	_shots_fired = 0
	_update_stats()

func _update_stats():
	if not is_instance_valid(_dummy):
		return
	var dealt = _dummy.max_hp - _dummy.hp
	var per_shot = dealt / max(1, _shots_fired)
	_stats_label.text = "Shots: %d   Total damage on dummy: %.0f   Avg per volley: %.0f" % [_shots_fired, dealt, per_shot]

func _process(delta):
	if _auto_toggle and _auto_toggle.button_pressed:
		_auto_timer -= delta
		if _auto_timer <= 0.0:
			_auto_timer = AUTO_FIRE_INTERVAL
			_fire_once()
	# Damage lands asynchronously (real flight time) - keep the readout live.
	if _shots_fired > 0:
		_update_stats()

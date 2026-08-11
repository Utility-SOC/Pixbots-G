class_name GarageTestRange
extends PopupPanel

# Garage Test Range (Status.md queue: "target dummy") - a physical firing
# range in a popup: pick any of your armed Weapon Mounts and test-fire its
# REAL energy feed (the exact precalculated packet combat would fire,
# including accumulator bank shots) at a real dummy mech. Real Projectile
# instances, real flight/spread/patterns/particles, real hits with damage
# numbers - not a simulation of the shot, the shot. Auto-firing capital
# weapons (Lance Mount/Orbiting Array - Mech.lance_mounts, gated on
# check_face_gate()/ready_to_fire rather than a mouse/key-fired packet) get
# their own row kind alongside the Weapon Mount rows - see
# _add_capital_weapon_rows().
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
const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

const RANGE_SIZE = Vector2(900, 340)
const RIG_POS = Vector2(110, 210)
const DUMMY_POS = Vector2(700, 210)
const AUTO_FIRE_INTERVAL = 0.6
const DEFAULT_DUMMY_HP = 1e12

var player: Node = null

var _world_root: Node2D = null
var _rig: Node = null
var _dummy: Node = null
# One live Drone per Drone Bay tile anywhere in the player's build (same
# DroneBayTile.spawn_drones_for used by real combat/Main.gd), frozen in
# place here (no chase/orbit AI) so its OWN precalculated_weapons can be
# test-fired the same way the rig's are.
var _drones: Array = []
# One entry per armed mount (player body + every spawned drone), in the
# order populated: {checkbox: CheckButton, data: Dictionary, source: Node,
# row: Control, search_text: String}. `source` is whichever Mech the shot
# should actually fire from - the rig for the player's own mounts, or the
# specific Drone instance for a drone's mounts.
var _mount_rows: Array = []
var _mount_list: VBoxContainer = null
var _search_box: LineEdit = null
var _stats_label: Label = null
var _auto_toggle: CheckButton = null
var _hp_override_box: LineEdit = null
var _auto_timer: float = 0.0
var _shots_fired: int = 0
var _volleys_fired: int = 0

# EXPERIMENTAL parallel projectile system (see ProjectileBatchPool.gd's own
# header - "the tree seems to be fucking us"). Opt-in only, here, so it can
# be fired at the dummy and compared against the real path before any of
# its behavior is approved for live combat. Everything else in this file
# (and every other firing path in the game) is completely untouched.
var _batch_toggle: CheckButton = null
var _batch_pool: Node = null
var _render_mode_option: OptionButton = null

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

	# Search/filter box (playtest: "there is a long list of projectiles - but
	# it is only kinda organized. I want a search box, that will let me
	# filter the emitters/projectiles to just right arm, or just torso, or
	# whatever, or like - torso+lightning"). Multi-term: every space/+
	# separated word must match somewhere in the row's own label (slot name,
	# tile type, element) - "torso+lightning" narrows to rows that mention
	# BOTH. All/None below only ever touch currently-visible rows, so the
	# intended workflow is filter -> All -> FIRE to isolate exactly the
	# filtered set instead of the whole build.
	_search_box = LineEdit.new()
	_search_box.placeholder_text = "filter: torso, right arm, lightning, torso+lightning..."
	_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_box.text_changed.connect(func(_t): _apply_search_filter())
	select_controls.add_child(_search_box)

	var mount_scroll = ScrollContainer.new()
	mount_scroll.custom_minimum_size = Vector2(0, 110)
	vbox.add_child(mount_scroll)
	_mount_list = VBoxContainer.new()
	_mount_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mount_scroll.add_child(_mount_list)
	# _populate_mounts() is called further down, once the rig/dummy/drones
	# all exist - it needs _drones populated to list their weapons too.

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

	# EXPERIMENTAL - see ProjectileBatchPool.gd's own header. When on, FIRE/
	# Auto spawn into the no-Node-tree batch pool instead of real
	# Projectile instances. Reached full behavioral+visual parity with the
	# real path as of the batch-pool full-parity plan (2026-08-10) - real
	# per-synergy flight math, Lightning's teleport-hop/re-target chain,
	# Poison's mine mode, Vampiric homing, elemental resistance, status
	# procs, Vampiric heal, Explosion/biome AoE, part-hitbox damage
	# routing, and bespoke visual ornaments all included now, not a
	# simplified stand-in. Still purely for side-by-side comparison; the
	# real path (every other firing site in the game) never routes through
	# this, and cutting real combat over to it needs separate explicit
	# approval after live playtesting, not just this parity work landing.
	_batch_toggle = CheckButton.new()
	_batch_toggle.text = "Batch Renderer (experimental)"
	_batch_toggle.modulate = Color(1.0, 0.7, 0.3)
	_batch_toggle.tooltip_text = "Fire through the experimental no-Node-tree batch pool instead of real Projectiles - full behavioral/visual parity with the real path as of 2026-08-10, still Test Range only, not wired into live combat."
	controls.add_child(_batch_toggle)

	# Render mode selector (user request, 2026-08-11) - independent of the
	# Batch Renderer toggle above (can be changed on its own; only has a
	# visible effect while Batch Renderer is ALSO on, since it's a batch-
	# pool-only rendering feature - see ProjectileBatchPool.RenderMode's own
	# comment). "Pie Chart" swaps ONLY the "hot core" logo for a pie chart of
	# the shot's real synergy ratios; "Shape Blend" replaces the whole main-
	# body silhouette with a weighted-average shape across every synergy
	# present, by ratio. Either way the aura/ghost trail/every other effect
	# (Vortex helix, secondary echoes) stay whatever that mode leaves them as -
	# see ProjectileBatchPool.gd's own per-mode header comments. Shares its
	# value with SettingsMenu.gd's Visuals tab via SaveManager.batch_render_mode
	# (same settings.cfg both read/write), so a choice made in either place is
	# reflected in the other.
	_render_mode_option = OptionButton.new()
	_render_mode_option.add_item("Flat (Default)")
	_render_mode_option.add_item("Pie Chart")
	_render_mode_option.add_item("Shape Blend")
	_render_mode_option.selected = SaveManager.batch_render_mode
	_render_mode_option.tooltip_text = "Batch Renderer only: chooses each shot's main-body treatment. Shared with the main menu's Settings > Visuals tab."
	_render_mode_option.item_selected.connect(func(index):
		SaveManager.set_batch_render_mode(index)
		if _batch_pool:
			_batch_pool.render_mode = index
	)
	controls.add_child(_render_mode_option)

	var reset_btn = Button.new()
	reset_btn.text = "Reset dummy"
	reset_btn.pressed.connect(_reset_dummy_stats)
	controls.add_child(reset_btn)

	# HP override (Status.md queue: "check how many hits of my current build
	# to kill something with exactly N HP, e.g. matching a specific boss's
	# known HP, without needing to actually fight it first"). Empty/invalid
	# text just falls back to DEFAULT_DUMMY_HP in _reset_dummy_stats - this
	# never needs to block firing, only change what "Reset dummy" resets to.
	var hp_label = Label.new()
	hp_label.text = "  Dummy HP:"
	controls.add_child(hp_label)

	_hp_override_box = LineEdit.new()
	_hp_override_box.placeholder_text = "default"
	_hp_override_box.custom_minimum_size = Vector2(90, 0)
	_hp_override_box.tooltip_text = "Custom dummy max HP, applied on next 'Reset dummy' (e.g. match a boss's known HP to count hits-to-kill). Blank = default."
	controls.add_child(_hp_override_box)

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
	_dummy.max_hp = DEFAULT_DUMMY_HP
	_dummy.hp = _dummy.max_hp

	# EXPERIMENTAL batch pool - see ProjectileBatchPool.gd's own header and
	# _batch_toggle's comment above. Lives in this same private World2D, so
	# it never touches anything outside the Test Range.
	_batch_pool = ProjectileBatchPoolScript.new()
	_world_root.add_child(_batch_pool)
	_batch_pool.register_target(_dummy)
	# Sync in case the render-mode selector was already changed before the
	# pool existed - item_selected() only fires on a CHANGE, not this initial
	# state (which itself was seeded from SaveManager.batch_render_mode above).
	if _render_mode_option:
		_batch_pool.render_mode = _render_mode_option.selected

	# Drones (playtest: "I also want drones in the test area") - real Drone
	# instances built from the player's real Drone Bay loadout(s), same spawn
	# helper real combat uses. Frozen (no chase AI, no auto-fire loop of
	# their own) so the checklist below is the only thing that fires them,
	# same as the rig.
	if player and is_instance_valid(player):
		_drones = DroneBayTile.spawn_drones_for(player, _world_root)
	for i in range(_drones.size()):
		var drone = _drones[i]
		drone.set_physics_process(false)
		drone.global_position = RIG_POS + Vector2(0, 60 + i * 40)

	_populate_mounts()

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
	_add_weapon_rows(player.precalculated_weapons, "", _rig, slot_names)
	_add_capital_weapon_rows(player.lance_mounts, "", _rig, slot_names)
	for i in range(_drones.size()):
		var drone = _drones[i]
		if drone.is_grid_dirty:
			drone._recalculate_grid()
		_add_weapon_rows(drone.precalculated_weapons, "Drone %d: " % (i + 1), drone, slot_names)
		_add_capital_weapon_rows(drone.lance_mounts, "Drone %d: " % (i + 1), drone, slot_names)

	if _mount_rows.is_empty():
		var lbl = Label.new()
		lbl.text = "(no armed mounts - wire energy to a Weapon Mount, Missile Rack, Lance Mount, or Orbiting Array first)"
		_mount_list.add_child(lbl)

	_apply_search_filter()

# Shared by the player's own precalculated_weapons and each spawned drone's -
# `source` is whichever Mech FIRE should actually invoke
# _fire_combined_projectile on (the rig, or the specific drone), and
# `label_prefix` distinguishes drone rows ("Drone 1: ...") in the list/search
# without needing a separate slot-name scheme for drones (their own tiny grid
# still uses the same BodySlot enum internally, so slot_names.get still
# resolves sensibly).
func _add_weapon_rows(weapons: Array, label_prefix: String, source: Node, slot_names: Dictionary):
	for data in weapons:
		var kind = "bank shot" if data.get("bank_mode", "") == "bank" else "normal fire"
		var elem = EnergyPacket.element_name(data.packet.get_dominant_synergy())
		var row = HBoxContainer.new()
		var check = CheckButton.new()
		check.text = "%s%s %s - %s, %s (%.0f energy)" % [
			label_prefix, slot_names.get(data.slot_type, "?"), data.mount.tile_type, kind, elem, data.packet.magnitude]
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
		_mount_rows.append({"checkbox": check, "data": data, "source": source, "row": row, "search_text": check.text.to_lower()})

# Lance Mount / Orbiting Array (Mech.lance_mounts) - unlike a Weapon Mount,
# these don't sit in precalculated_weapons at all: they're auto-firing
# capital weapons gated on check_face_gate()/ready_to_fire (set once per
# _recalculate_grid, which the "if is_grid_dirty" call above already ran)
# rather than a mouse/key-triggered packet. _add_weapon_rows above only
# ever reads precalculated_weapons, so without this these tiles never
# appeared in the checklist at all - "armed but nothing to test-fire."
# FIRE on one of these rows calls tile.fire(source) directly (see
# _fire_selected's "capital" branch) instead of _fire_combined_projectile,
# bypassing the tile's own real cooldown pacing for an on-demand test shot,
# same spirit as every other row here firing on demand instead of waiting
# for its real trigger.
func _add_capital_weapon_rows(mounts: Array, label_prefix: String, source: Node, slot_names: Dictionary):
	for tile in mounts:
		if not tile.has_method("fire"):
			continue
		var row = HBoxContainer.new()
		var check = CheckButton.new()
		var status = "ARMED" if tile.ready_to_fire else "not armed - feed 6 external faces >= threshold each"
		var energy_str = ""
		if tile.get("_armed_packet") != null:
			energy_str = " (%.0f energy)" % tile._armed_packet.magnitude
		check.text = "%s%s %s - %s%s" % [
			label_prefix, slot_names.get(tile.body_slot, "?"), tile.tile_type, status, energy_str]
		check.button_pressed = true
		check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(check)
		var solo_btn = Button.new()
		solo_btn.text = "Solo"
		solo_btn.tooltip_text = "Check only this mount, uncheck every other one."
		var row_index = _mount_rows.size()
		solo_btn.pressed.connect(func(): _solo_row(row_index))
		row.add_child(solo_btn)
		_mount_list.add_child(row)
		_mount_rows.append({"checkbox": check, "kind": "capital", "tile": tile, "source": source, "row": row, "search_text": check.text.to_lower()})

func _set_all_checked(on: bool):
	for row in _mount_rows:
		if row.row.visible: # All/None only touch what the current filter shows
			row.checkbox.button_pressed = on

# Splits the search text on spaces/'+' and requires every term to appear
# somewhere in the row's own label (case-insensitive substring match) -
# "torso+lightning" hides every row that isn't both.
func _apply_search_filter():
	if not _search_box:
		return
	var raw = _search_box.text.strip_edges().to_lower()
	var terms: Array = []
	for t in raw.replace("+", " ").split(" "):
		if t != "":
			terms.append(t)
	for row in _mount_rows:
		var visible = true
		for t in terms:
			if not row.search_text.contains(t):
				visible = false
				break
		row.row.visible = visible

func _solo_row(index: int):
	for i in range(_mount_rows.size()):
		_mount_rows[i].checkbox.button_pressed = (i == index)

func _checked_weapons() -> Array:
	var out: Array = []
	for row in _mount_rows:
		if row.checkbox.button_pressed:
			out.append(row)
	return out

func _fire_selected():
	if not player or not is_instance_valid(player):
		return
	var to_fire = _checked_weapons()
	if to_fire.is_empty():
		return
	# Every possible source (rig + each drone) aims at the dummy - a mount
	# fires from whichever Mech it actually lives on, drones included.
	_rig.last_aim_position = _dummy.global_position
	for drone in _drones:
		if is_instance_valid(drone):
			drone.last_aim_position = _dummy.global_position
	var use_batch = _batch_toggle and _batch_toggle.button_pressed
	for row in to_fire:
		var source = row.get("source", _rig)
		if not is_instance_valid(source):
			continue
		if row.get("kind", "mount") == "capital":
			# Lance Mount / Orbiting Array: no discrete packet to hand over,
			# and fire() reads its own _armed_packet - an unarmed tile just
			# no-ops (see LanceMountTile/OrbitingArrayTile.fire()). Not
			# ported to the batch pool - real Projectile path always, even
			# with the toggle on.
			row.tile.fire(source)
		else:
			var data = row.data
			var packet = data.packet.copy()
			if data.get("bank_mode", "") == "bank":
				packet.is_banked_shot = true
			if use_batch:
				_fire_via_batch_pool(source, data.mount, packet)
			else:
				data.mount._fire_combined_projectile(source, packet, 0)
		_shots_fired += 1
	_volleys_fired += 1
	_update_stats()

# EXPERIMENTAL - see ProjectileBatchPool.gd's own header. Deliberately
# rough/approximate, not a faithful port of _fire_combined_projectile's
# real formula - straight-line-toward-the-dummy only, no pattern fanout.
# Real flight math (synergy-specific movement) and real muzzle-position
# lookup ARE both wired in now (batch-pool full-parity plan, 2026-08-10) -
# this comment used to say otherwise, kept stale across several sessions'
# worth of work landing underneath it. "No pattern fanout" is still
# accurate: one shot per mount-fire, no shotgun/radial multi-shot spread.
const BATCH_SHOT_SPEED = 700.0
const BATCH_SHOT_RADIUS = 10.0
# No longer a flat lifetime for every synergy - passed as -1.0 below so
# ProjectileBatchPool.spawn() auto-computes it from this shot's own ratios
# (mirrors Projectile._get_lifetime()) instead of every batch shot living
# exactly 3s regardless of whether it's Fire (should die fast) or Kinetic
# (should live long enough to spend its extended range).
const BATCH_SHOT_LIFETIME_AUTO = -1.0

func _fire_via_batch_pool(source: Node, mount, packet):
	if not _batch_pool or not is_instance_valid(_dummy):
		return
	var from_pos = source.global_position
	if mount != null and mount.has_method("get_muzzle_position"):
		from_pos = mount.get_muzzle_position(source)
	elif mount != null and "global_position" in mount:
		from_pos = mount.global_position

	var to_pos = _dummy.global_position
	var dir = (to_pos - from_pos)
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var dmg = packet.magnitude * mount._get_damage_multiplier() * mount._get_power_multiplier()

	# Same dominant-synergy selection the mount's row label already used
	# (EnergyPacket.dominant_synergy_of, via packet.get_dominant_synergy())
	# - this used to be a separate, hand-rolled RAW-excluding scan that could
	# pick a DIFFERENT dominant than what the row promised (confirmed via a
	# live debug readout: a mount labeled "EXPLOSION" fired a shot whose
	# batch-pool dominant came out KINETIC), so the shot's shape/damage-
	# element silently didn't match the weapon the player selected.
	var dominant = packet.get_dominant_synergy() if packet != null and packet.has_method("get_dominant_synergy") else 0

	# Real Projectile.gd never blends its main body color (_calculate_stats'
	# own comment: "Keep vibrancy by picking dominant color and boosting") -
	# get_color_blend() is only ever used there for a secondary lightning-
	# bolt accent, not the shot itself. The batch pool used to call
	# get_color_blend() for ANY multi-element packet, which washes toward
	# gray/white for anything with real RAW content blended in (RAW's color
	# is pure white) - exactly the "large grey ox" a 600k-energy multi-
	# element shot rendered as. Match the real path: single dominant color,
	# boosted, never blended.
	var color = EnergyPacket.get_color_for_synergy(dominant) if dominant != 0 else Color(0.9, 0.9, 1.0)
	color = (color * 1.5)
	color.a = 1.0

	var ratios = EnergyPacket.compute_ratios(packet.synergies) if packet != null and "synergies" in packet else {}
	# proc_synergies/aoe_bonus (Phase 5/7 of the batch-pool full-parity
	# plan, 2026-08-10) - previously dropped entirely here, so Resonator
	# Sync procs and mount-fed AoE-radius bonuses never reached the batch
	# pool at all.
	var proc_synergies = packet.proc_synergies if packet != null and "proc_synergies" in packet else {}
	var aoe_bonus = packet.aoe_bonus if packet != null and "aoe_bonus" in packet else 0.0

	# Mirrors Projectile._build_visuals' p_scale exactly (2026-08-11 fix -
	# a live playtest comparison against the real renderer found batch
	# shots looking noticeably smaller/sparser even where the underlying
	# damage/hit behavior matched). This used to clamp at 5.0 and never
	# factor in aoe_bonus or the banked-shot bonus at all, so a real
	# Mythic-AoE or banked shot rendered visibly bigger than its batch-pool
	# equivalent even though both dealt identical damage.
	var scale_mult = min(1.0 + log(1.0 + packet.magnitude / 200.0) * 0.5, 5.0)
	scale_mult *= (1.0 + 0.5 * aoe_bonus)
	if "is_banked_shot" in packet and packet.is_banked_shot:
		scale_mult *= 1.35
	scale_mult = min(scale_mult, 8.0)

	_batch_pool.spawn(from_pos, dir, BATCH_SHOT_SPEED, dmg, BATCH_SHOT_RADIUS, BATCH_SHOT_LIFETIME_AUTO, color, scale_mult, source.is_player, source, dominant, ratios, proc_synergies, aoe_bonus)

func _reset_dummy_stats():
	if is_instance_valid(_dummy):
		var override_hp = 0.0
		if _hp_override_box:
			override_hp = _hp_override_box.text.to_float()
		_dummy.max_hp = override_hp if override_hp > 0.0 else DEFAULT_DUMMY_HP
		_dummy.hp = _dummy.max_hp
	_shots_fired = 0
	_volleys_fired = 0
	_update_stats()

func _update_stats():
	if not is_instance_valid(_dummy):
		return
	var dealt = _dummy.max_hp - _dummy.hp
	var per_volley = dealt / max(1, _volleys_fired)
	var text = "Volleys: %d   Shots: %d   Total damage on dummy: %.0f   Avg per volley: %.0f" % [_volleys_fired, _shots_fired, dealt, per_volley]
	_stats_label.text = text

func _process(delta):
	if _auto_toggle and _auto_toggle.button_pressed:
		_auto_timer -= delta
		if _auto_timer <= 0.0:
			_auto_timer = AUTO_FIRE_INTERVAL
			_fire_selected()
	# Damage lands asynchronously (real flight time) - keep the readout live.
	if _volleys_fired > 0:
		_update_stats()

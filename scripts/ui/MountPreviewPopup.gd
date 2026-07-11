extends PanelContainer

# Hover a Weapon Mount in the Garage -> a live mini firing range showing
# the EXACT projectile that mount will spit out with the grid as currently
# wired. The shot on the little stage is a REAL Projectile instance built
# from the simulated packet (same _build_visuals code that runs in combat -
# arrows, deltas, crystals, mines, trails and all), neutered of physics/
# collision and animated along the mount's firing pattern (normal /
# shotgun / radial / beam / mortar). Honest numbers underneath: damage
# after the mount's own multipliers, element split, charge time, bank tag.
# Fed straight from Mech.precalculated_weapons - what you see here is what
# leaves the barrel on deploy, by construction.

var _packet = null            # EnergyPacket (sim output) or null = unpowered
var _pattern: int = 0         # WeaponMountTile.mythic_pattern (0 when not Mythic)
var _has_bank: bool = false
var _damage: float = 0.0
var _charge_time: float = 0.0
var _t: float = 0.0

var canvas: Control
var stage: Node2D             # scaled world-space holder for the live projectiles
var _pool: Array = []         # the neutered Projectile instances being animated
var info: Label

const CYCLE = 1.4 # seconds per animation loop
const PATTERN_NAMES = ["Normal", "Shotgun", "Radial Burst", "Beam", "Mortar"]

func _init():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	visible = false
	var vbox = VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vbox)
	canvas = Control.new()
	canvas.custom_minimum_size = Vector2(190, 86)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.clip_contents = true # big charged shots have deliberately oversized glow
	canvas.draw.connect(_draw_canvas)
	vbox.add_child(canvas)
	stage = Node2D.new()
	canvas.add_child(stage)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 11)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(info)

func _process(delta: float):
	if visible:
		_t += delta
		_animate_pool()
		canvas.queue_redraw()

func hide_preview():
	visible = false
	_clear_pool()

func _clear_pool():
	for p in _pool:
		if is_instance_valid(p):
			p.queue_free()
	_pool.clear()

# A REAL Projectile built from the simulated packet, with everything that
# makes it a weapon turned off: no physics, no collision, no flight-math
# registration - just the living visual (_build_visuals + its trails).
func _make_preview_projectile() -> Node2D:
	var proj = load("res://scripts/entities/Projectile.gd").new()
	proj.synergies = _packet.synergies.duplicate()
	proj.damage = _damage
	proj.fired_by_player = true
	proj.direction = Vector2.RIGHT
	stage.add_child(proj) # _ready builds the real combat visuals
	ProjectileManager.unregister(proj)
	proj.set_physics_process(false)
	proj.monitoring = false
	proj.monitorable = false
	proj.collision_layer = 0
	proj.collision_mask = 0
	proj.remove_from_group("projectile") # invisible to magnet reflection etc.
	proj.rotation = 0.0
	return proj

func _rebuild_pool():
	_clear_pool()
	if _packet == null:
		stage.scale = Vector2.ONE
		return
	var count = 1
	if _pattern == 1 or _pattern == 2: # shotgun / radial show a small volley
		count = 3
	for i in range(count):
		_pool.append(_make_preview_projectile())
	# Fit the stage: combat projectiles are world-sized (a big charged shot
	# renders 60px+ before glow) - zoom out so it stays inside the range.
	var proj = _pool[0]
	var approx = 8.0 * max(0.1, proj.scale.x) * max(1.0, float(proj.get("visual_scale") if "visual_scale" in proj else 1.0))
	stage.scale = Vector2.ONE * clamp(26.0 / approx, 0.2, 1.4)

# mount: the hovered WeaponMountTile; entries: every precalculated_weapons
# dict for this mount (possibly several traversal steps + a bank);
# fire_rate: the owning mech's, for the charge-time estimate.
func show_for(mount, entries: Array, fire_rate: float, screen_pos: Vector2):
	_pattern = int(mount.get("mythic_pattern")) if ("mythic_pattern" in mount and mount.rarity == HexTile.Rarity.MYTHIC) else 0
	_packet = null
	_has_bank = false
	var shown = null
	for d in entries:
		if d.get("bank_mode", "") == "bank":
			_has_bank = true
		elif shown == null:
			shown = d
	if shown == null and not entries.is_empty():
		shown = entries[0] # bank-only mount: preview the bank payload
	if shown != null:
		_packet = shown.packet
		_damage = _packet.magnitude * mount._get_damage_multiplier() * mount._get_power_multiplier()
		_charge_time = _packet.charge_required * max(0.01, fire_rate)

	if _packet == null:
		info.text = "NO ENERGY\nThis mount receives no packets\non the equipped mech's grid."
	else:
		var elements = _top_elements(_packet.synergies, 2)
		var line = "%s   ~%d dmg/shot" % [PATTERN_NAMES[clamp(_pattern, 0, 4)], int(round(_damage))]
		if _has_bank:
			line += "  [+BANK]"
		info.text = line + "\n" + elements + "\nCharge: %.1fs" % _charge_time

	# Sit beside the cursor, clamped on-screen.
	var vp = get_viewport_rect().size if is_inside_tree() else Vector2(1152, 648)
	global_position = Vector2(min(screen_pos.x + 18, vp.x - 210), min(screen_pos.y + 12, vp.y - 150))
	visible = true
	_rebuild_pool()

func _top_elements(synergies: Dictionary, count: int) -> String:
	var total = 0.0
	for v in synergies.values():
		total += v
	if total <= 0.0:
		return "RAW 100%"
	var pairs = []
	for k in synergies:
		pairs.append([k, synergies[k]])
	pairs.sort_custom(func(a, b): return a[1] > b[1])
	var bits = []
	for i in range(min(count, pairs.size())):
		if pairs[i][1] / total < 0.05:
			break
		bits.append("%s %d%%" % [EnergyPacket.element_name(pairs[i][0]), int(round(100.0 * pairs[i][1] / total))])
	return " / ".join(bits)

# Moves the LIVE projectile instances along the firing pattern's paths.
# Positions are in canvas space, converted to the (possibly zoomed) stage.
func _animate_pool():
	if _pool.is_empty():
		return
	var size = canvas.size
	var muzzle = Vector2(16, size.y * 0.5)
	var reach = size.x - 34.0
	var t = fmod(_t, CYCLE) / CYCLE
	var inv = 1.0 / max(0.01, stage.scale.x)

	match _pattern:
		1: # shotgun fan (3 representative pellets of the volley)
			for i in range(_pool.size()):
				var ang = deg_to_rad(-18.0 + 18.0 * i)
				var dir = Vector2.RIGHT.rotated(ang)
				_place(_pool[i], (muzzle + dir * reach * t) * inv, ang)
		2: # radial burst from a point downrange
			var center = muzzle + Vector2(reach * 0.45, 0)
			for i in range(_pool.size()):
				var ang = TAU * i / _pool.size() + 0.4
				var dir = Vector2.RIGHT.rotated(ang)
				_place(_pool[i], (center + dir * reach * 0.4 * t) * inv, ang)
		3: # beam: the shot crosses near-instantly, then holds at the far end
			var sweep = clamp(t * 3.0, 0.0, 1.0)
			_place(_pool[0], (muzzle + Vector2(reach * sweep, 0)) * inv, 0.0)
		4: # mortar: lobbed arc into the telegraph, hidden during the flash
			if t < 0.75:
				var ft = t / 0.75
				var p = muzzle.lerp(muzzle + Vector2(reach, 6), ft) + Vector2(0, -sin(ft * PI) * 26.0)
				_pool[0].visible = true
				_place(_pool[0], p * inv, lerp(-0.5, 1.1, ft))
			else:
				_pool[0].visible = false
		_: # normal single shot downrange
			_place(_pool[0], (muzzle + Vector2(reach * t, 0)) * inv, 0.0)

func _place(proj, pos: Vector2, angle: float):
	if is_instance_valid(proj):
		proj.position = pos
		proj.rotation = angle

# Underlays only - the projectile itself is the real instance on the stage.
func _draw_canvas():
	var size = canvas.size
	# range floor + muzzle block
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.075, 0.1, 0.95))
	canvas.draw_line(Vector2(6, size.y - 8), Vector2(size.x - 6, size.y - 8), Color(0.25, 0.27, 0.32), 1.0)
	var muzzle = Vector2(16, size.y * 0.5)
	canvas.draw_rect(Rect2(muzzle + Vector2(-8, -7), Vector2(8, 14)), Color(0.3, 0.32, 0.38))

	if _packet == null:
		canvas.draw_circle(muzzle + Vector2(2, 0), 3.0, Color(0.3, 0.3, 0.32))
		return

	var color = EnergyPacket.get_color_blend(_packet.synergies)
	var t = fmod(_t, CYCLE) / CYCLE

	if _pattern == 3: # beam pattern: the piercing streak behind the shot
		var sweep = clamp(t * 3.0, 0.0, 1.0)
		canvas.draw_line(muzzle, muzzle + Vector2((size.x - 34.0) * sweep, 0), Color(color.r, color.g, color.b, 0.5), 3.0)
	elif _pattern == 4: # mortar telegraph ring + impact flash
		var target = muzzle + Vector2(size.x - 34.0, 6)
		canvas.draw_arc(target, 13.0, 0, TAU, 16, Color(color.r, color.g, color.b, 0.5), 1.5)
		if t >= 0.75:
			var ft = (t - 0.75) / 0.25
			canvas.draw_circle(target, 13.0 * ft, Color(color.r, color.g, color.b, 0.6 * (1.0 - ft)))

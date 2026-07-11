extends PanelContainer

# Hover a Weapon Mount in the Garage -> a live mini firing range showing
# the EXACT projectile that mount will spit out with the grid as currently
# wired: color/size from the simulated packet's real synergy blend, the
# firing pattern animated (normal / shotgun / radial / beam / mortar), and
# the honest numbers underneath (damage after the mount's own multipliers,
# element split, charge time, bank tag). Fed straight from
# Mech.precalculated_weapons - the same data combat fires from, so what
# you see here is what leaves the barrel on deploy.

var _packet = null            # EnergyPacket (sim output) or null = unpowered
var _pattern: int = 0         # WeaponMountTile.mythic_pattern (0 when not Mythic)
var _has_bank: bool = false
var _damage: float = 0.0
var _charge_time: float = 0.0
var _t: float = 0.0

var canvas: Control
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
	canvas.draw.connect(_draw_canvas)
	vbox.add_child(canvas)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 11)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(info)

func _process(delta: float):
	if visible:
		_t += delta
		canvas.queue_redraw()

func hide_preview():
	visible = false

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
	var radius = clamp(2.0 + sqrt(max(0.0, _damage)) * 0.18, 2.5, 8.0)
	var t = fmod(_t, CYCLE) / CYCLE
	var reach = size.x - 34.0

	match _pattern:
		1: # shotgun fan
			for i in range(5):
				var ang = deg_to_rad(-24.0 + 12.0 * i)
				var dir = Vector2.RIGHT.rotated(ang)
				var p = muzzle + dir * reach * t
				_dot_with_trail(muzzle, p, color, radius * 0.6)
		2: # radial burst from a point downrange
			var center = muzzle + Vector2(reach * 0.45, 0)
			canvas.draw_circle(center, 2.0, color.darkened(0.3))
			for i in range(8):
				var dir = Vector2.RIGHT.rotated(TAU * i / 8.0)
				_dot_with_trail(center, center + dir * reach * 0.4 * t, color, radius * 0.55)
		3: # beam: near-instant streak with a sweep flash
			var sweep = clamp(t * 3.0, 0.0, 1.0)
			canvas.draw_line(muzzle, muzzle + Vector2(reach * sweep, 0), color, radius)
			canvas.draw_line(muzzle, muzzle + Vector2(reach * sweep, 0), Color(1, 1, 1, 0.7), radius * 0.4)
		4: # mortar: arc to a telegraphed ring, then flash
			var target = muzzle + Vector2(reach, 6)
			canvas.draw_arc(target, 13.0, 0, TAU, 16, Color(color.r, color.g, color.b, 0.5), 1.5)
			if t < 0.75:
				var ft = t / 0.75
				var p = muzzle.lerp(target, ft) + Vector2(0, -sin(ft * PI) * 26.0)
				canvas.draw_circle(p, radius * 0.7, color)
			else:
				var ft = (t - 0.75) / 0.25
				canvas.draw_circle(target, 13.0 * ft, Color(color.r, color.g, color.b, 0.6 * (1.0 - ft)))
		_: # normal single shot
			_dot_with_trail(muzzle, muzzle + Vector2(reach * t, 0), color, radius)

func _dot_with_trail(origin: Vector2, p: Vector2, color: Color, radius: float):
	var back = (origin - p).normalized() * min(18.0, origin.distance_to(p))
	canvas.draw_line(p, p + back, Color(color.r, color.g, color.b, 0.35), radius * 0.9)
	canvas.draw_circle(p, radius, color)
	canvas.draw_circle(p + Vector2(-radius * 0.3, -radius * 0.3), radius * 0.4, Color(1, 1, 1, 0.8))

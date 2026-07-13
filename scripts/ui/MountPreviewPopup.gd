extends PanelContainer

# Hover a Weapon Mount in the Garage -> a mini firing-range preview showing
# the pattern/element/damage that mount will produce with the grid as
# currently wired. Fed straight from Mech.precalculated_weapons - what you
# see here is what leaves the barrel on deploy, by construction.
#
# Previously this spawned REAL Projectile instances (full _ready()/
# _build_visuals() - particles, materials, polygons) and rebuilt the whole
# pool on every hover-hex-transition, which was the actual freeze (a fast
# mouse sweep across several tiles fired several full Projectile builds in
# quick succession) - and the live shot's shape was whatever dominant-
# synergy silhouette _build_visuals() picked, which for a Beam mount often
# just looked like a generic (e.g. lightning-bolt-shaped) blob rather than
# reading as "a beam" (Utility-SOC: "the graphic still is not quite
# accurate - it shows an icon of the dominant, but... lightning beams it is
# deceptive"). Replaced with cheap static per-pattern glyphs drawn directly
# here: zero node instantiation, and each pattern (Normal/Shotgun/Radial/
# Beam/Mortar) gets its own honest shape instead of borrowing whichever
# element's silhouette happens to dominate.

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
	canvas.clip_contents = true
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

	# Docked to the top-right of the screen, NOT following the cursor -
	# cursor-following covered the tile tooltip and the mount's own config
	# popup (playtest report: "it covers the setting, so I can't change the
	# weapon type"). A fixed dock is predictable and never in the way of
	# what you're actually pointing at.
	var vp = get_viewport_rect().size if is_inside_tree() else Vector2(1152, 648)
	global_position = Vector2(vp.x - 214, 8)
	visible = true
	_t = 0.0

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

# A small filled dart/arrowhead, oriented along `dir` - the shared glyph
# shape for Normal/Shotgun/Radial pellets (a discrete travelling shot).
func _draw_dart(pos: Vector2, dir: Vector2, color: Color):
	var fwd = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	var side = Vector2(-fwd.y, fwd.x)
	var pts = PackedVector2Array([
		pos + fwd * 6.0,
		pos - fwd * 4.0 + side * 3.5,
		pos - fwd * 4.0 - side * 3.5,
	])
	canvas.draw_colored_polygon(pts, color)

func _draw_canvas():
	var size = canvas.size
	canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.07, 0.075, 0.1, 0.95))
	canvas.draw_line(Vector2(6, size.y - 8), Vector2(size.x - 6, size.y - 8), Color(0.25, 0.27, 0.32), 1.0)
	var muzzle = Vector2(16, size.y * 0.5)
	canvas.draw_rect(Rect2(muzzle + Vector2(-8, -7), Vector2(8, 14)), Color(0.3, 0.32, 0.38))

	if _packet == null:
		canvas.draw_circle(muzzle + Vector2(2, 0), 3.0, Color(0.3, 0.3, 0.32))
		return

	var color = EnergyPacket.get_color_blend(_packet.synergies)
	var t = fmod(_t, CYCLE) / CYCLE
	var reach = size.x - 34.0

	match _pattern:
		1: # shotgun fan: 3 darts diverging at fixed angles
			for i in range(3):
				var ang = deg_to_rad(-18.0 + 18.0 * i)
				var dir = Vector2.RIGHT.rotated(ang)
				_draw_dart(muzzle + dir * reach * t, dir, color)
		2: # radial burst: darts racing outward in a full ring from a point downrange
			var center = muzzle + Vector2(reach * 0.45, 0)
			var shard_count = 6
			for i in range(shard_count):
				var ang = TAU * i / shard_count + 0.4
				var dir = Vector2.RIGHT.rotated(ang)
				_draw_dart(center + dir * reach * 0.4 * t, dir, color)
		3: # Beam: a dense, bright, near-instant single stream - the glyph
			# IS the beam (no separate riding shape), addressing the old
			# "looks like a generic dominant-synergy blob" complaint head-on.
			var sweep = clamp(t * 3.0, 0.0, 1.0)
			var tip = muzzle + Vector2(reach * sweep, 0)
			canvas.draw_line(muzzle, tip, Color(color.r, color.g, color.b, 0.95), 4.0)
			canvas.draw_line(muzzle, tip, Color(1, 1, 1, 0.55), 1.5) # bright hot core
			if sweep >= 1.0:
				canvas.draw_circle(tip, 3.0, Color(1, 1, 1, 0.8))
		4: # mortar: lobbed shell arc into the telegraph, then impact flash
			if t < 0.75:
				var ft = t / 0.75
				var p = muzzle.lerp(muzzle + Vector2(reach, 6), ft) + Vector2(0, -sin(ft * PI) * 26.0)
				canvas.draw_circle(p, 3.0, color)
		_: # normal single shot downrange
			_draw_dart(muzzle + Vector2(reach * t, 0), Vector2.RIGHT, color)

	if _pattern == 4: # mortar telegraph ring + impact flash
		var target = muzzle + Vector2(reach, 6)
		canvas.draw_arc(target, 13.0, 0, TAU, 16, Color(color.r, color.g, color.b, 0.5), 1.5)
		if t >= 0.75:
			var ft = (t - 0.75) / 0.25
			canvas.draw_circle(target, 13.0 * ft, Color(color.r, color.g, color.b, 0.6 * (1.0 - ft)))

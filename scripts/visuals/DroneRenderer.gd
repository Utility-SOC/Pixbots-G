class_name DroneRenderer
extends Node2D

# Distinct (non-mech-shaped) visual for the Drone companion, per Natalia's
# choice: a small hovering drone silhouette rather than a shrunk-down reuse
# of MechRenderer's humanoid look. Deliberately simple - one _draw() body
# per chassis class, no multi-part node tree or particles - this exists on
# every active drone (and a build can now field several at once via
# multiple Drone Bay tiles - see DroneBayTile.gd), and this session already
# found projectile-count performance to be a real concern, so the
# companion's own rendering should stay cheap.
#
# Chassis variety (drone_ref.drone_visual_class, set once on the owning
# DroneBayTile and persisted - see that file's visual_class field comment)
# gives each drone bay a distinct, stable silhouette instead of every drone
# in the game being an identical recolored diamond:
#   0 - Quad-rotor: the original diamond body + 4 spinning rotor arms.
#   1 - Hover-orb: round body, pulsing anti-grav halo, no rotors.
#   2 - Spider-drone: angular body, jointed legs radiating outward/down.
#   3 - Wing/flyer: elongated delta silhouette, twin engine glow trails.

const MechStatusBars = preload("res://scripts/visuals/MechStatusBars.gd")

var drone_ref: Node = null
var last_render_scale: float = 0.55 # read by MechStatusBars for bar position scaling
var _spin: float = 0.0

const RARITY_COLORS = [
	Color(0.55, 0.6, 0.65),  # Common - gunmetal
	Color(0.3, 0.75, 0.4),   # Uncommon - green
	Color(0.3, 0.55, 0.95),  # Rare - blue
	Color(0.75, 0.4, 0.9),   # Legendary - purple
	Color(0.95, 0.7, 0.15),  # Mythic - gold
]

const CLASS_COUNT = 4

func _get_rarity() -> int:
	if drone_ref and "base_rarity" in drone_ref:
		return clamp(int(drone_ref.base_rarity), 0, RARITY_COLORS.size() - 1)
	return 0

func _get_visual_class() -> int:
	if drone_ref and "drone_visual_class" in drone_ref:
		return clamp(int(drone_ref.drone_visual_class), 0, CLASS_COUNT - 1)
	return 0

func _rebuild_visuals():
	var rarity = _get_rarity()
	scale = Vector2.ONE * (0.85 + rarity * 0.08)
	queue_redraw()

	if not has_node("StatusBars"):
		var bars = MechStatusBars.new()
		bars.name = "StatusBars"
		bars.owner_mech = drone_ref
		bars.owner_renderer = self
		add_child(bars)

func _process(delta):
	_spin += delta * 4.0
	queue_redraw()

func _draw():
	var col = RARITY_COLORS[_get_rarity()]
	match _get_visual_class():
		1:
			_draw_hover_orb(col)
		2:
			_draw_spider(col)
		3:
			_draw_flyer(col)
		_:
			_draw_quad_rotor(col)

func _draw_quad_rotor(col: Color):
	# Four rotor arms with a small spinning blade blip at each tip.
	for i in range(4):
		var ang = PI / 4.0 + i * (PI / 2.0)
		var tip = Vector2(cos(ang), sin(ang)) * 14.0
		draw_line(Vector2.ZERO, tip, col.darkened(0.3), 2.0)
		var blade_ang = _spin + i * (PI / 2.0)
		var blade_tip = tip + Vector2(cos(blade_ang), sin(blade_ang)) * 6.0
		draw_line(tip - (blade_tip - tip), blade_tip, Color(1, 1, 1, 0.55), 1.5)

	# Central body: a small rounded diamond with a glowing "eye" core.
	var body_pts = PackedVector2Array([
		Vector2(0, -10), Vector2(9, 0), Vector2(0, 10), Vector2(-9, 0)
	])
	draw_colored_polygon(body_pts, col)
	draw_polyline(body_pts + PackedVector2Array([body_pts[0]]), col.darkened(0.4), 1.5)
	draw_circle(Vector2.ZERO, 3.5, Color(1.0, 0.95, 0.6, 0.9))

# Round anti-grav hull with a slow-pulsing halo ring standing in for
# thrusters (nothing spins - reads as "floating," not "flying").
func _draw_hover_orb(col: Color):
	var pulse = 0.5 + sin(_spin * 1.5) * 0.5
	var halo_r = 13.0 + pulse * 3.0
	draw_arc(Vector2.ZERO, halo_r, 0, TAU, 24, Color(col.r, col.g, col.b, 0.35 + pulse * 0.25), 2.0)

	draw_circle(Vector2.ZERO, 9.0, col)
	draw_arc(Vector2.ZERO, 9.0, 0, TAU, 20, col.darkened(0.4), 1.5)

	# Two small stabilizer fins - just enough asymmetry to read as a
	# mechanical hull rather than a plain ball.
	for side in [-1, 1]:
		var fin = PackedVector2Array([
			Vector2(side * 8.0, -2.0), Vector2(side * 14.0, 0.0), Vector2(side * 8.0, 2.0)
		])
		draw_colored_polygon(fin, col.darkened(0.25))

	draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.95, 0.6, 0.9))

# Small angular hull on jointed legs that flex outward and down, like a
# compact ground-hugging combat spider rather than an aircraft.
func _draw_spider(col: Color):
	var body_pts = PackedVector2Array([
		Vector2(-6, -8), Vector2(6, -8), Vector2(9, 0), Vector2(6, 8), Vector2(-6, 8), Vector2(-9, 0)
	])
	draw_colored_polygon(body_pts, col)
	draw_polyline(body_pts + PackedVector2Array([body_pts[0]]), col.darkened(0.4), 1.5)

	var leg_count = 6
	for i in range(leg_count):
		var base_ang = (TAU / leg_count) * i + PI / leg_count
		var twitch = sin(_spin * 2.0 + i * 1.3) * 0.08
		var hip = Vector2(cos(base_ang), sin(base_ang)) * 7.0
		var knee = hip + Vector2(cos(base_ang + twitch), sin(base_ang + twitch)) * 8.0
		var foot = knee + Vector2(cos(base_ang + 0.35 + twitch), sin(base_ang + 0.35 + twitch) * 0.6) * 7.0
		draw_line(hip, knee, col.darkened(0.35), 1.8)
		draw_line(knee, foot, col.darkened(0.5), 1.5)

	draw_circle(Vector2.ZERO, 3.0, Color(1.0, 0.95, 0.6, 0.9))

# Elongated delta/arrow silhouette with twin engine glow trails - the only
# archetype that reads as "fast" rather than "hovering in place."
func _draw_flyer(col: Color):
	var body_pts = PackedVector2Array([
		Vector2(0, -15), Vector2(4, 4), Vector2(11, 9), Vector2(0, 5), Vector2(-11, 9), Vector2(-4, 4)
	])
	draw_colored_polygon(body_pts, col)
	draw_polyline(body_pts + PackedVector2Array([body_pts[0]]), col.darkened(0.4), 1.5)

	var flicker = 0.6 + sin(_spin * 6.0) * 0.4
	for side in [-1, 1]:
		var engine_pos = Vector2(side * 6.0, 9.0)
		draw_circle(engine_pos, 2.2, Color(1.0, 0.8, 0.4, flicker))
		draw_line(engine_pos, engine_pos + Vector2(0, 6.0), Color(1.0, 0.6, 0.2, flicker * 0.5), 2.0)

	draw_circle(Vector2(0, -4), 2.5, Color(1.0, 0.95, 0.6, 0.9))

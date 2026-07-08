class_name DroneRenderer
extends Node2D

# Distinct (non-mech-shaped) visual for the Drone companion, per Natalia's
# choice: a small hovering drone silhouette rather than a shrunk-down reuse
# of MechRenderer's humanoid look. Deliberately simple - one _draw() body
# plus four spinning rotor blips, no multi-part node tree or particles -
# this exists on every active drone, and this session already found
# projectile-count performance to be a real concern, so the companion's own
# rendering should stay cheap.

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

func _get_rarity() -> int:
	if drone_ref and "base_rarity" in drone_ref:
		return clamp(int(drone_ref.base_rarity), 0, RARITY_COLORS.size() - 1)
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

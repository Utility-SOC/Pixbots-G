extends "res://scripts/entities/Mech.gd"

# Support/utility unit (user request, 2026-08-10): "an environmental
# remediation unit - it cleans up the damage puddles from missiles
# (Travelling around with a circular aura cleaning up standing residue
# from missile explosions)". "Travelling around" comes for free from the
# base Mech AI (SightAndSearch's patrol legs when it has no sight of the
# player, normal engagement-distance movement otherwise, same as every
# other role) - no bespoke movement/patrol logic needed here, just the
# cleanup aura itself.
#
# Scans the "missile_puddle" group (ElementalPuddle.gd, tagged in its own
# _ready()) on a throttled tick and calls ElementalPuddle.remediate() on
# anything within radius - fades it out fast instead of an abrupt pop.
# Cleans up ANY puddle in range regardless of which side spawned it
# (a lingering DoT hazard is equally a nuisance to both sides standing in
# it - unlike the anti-missile aura, there's no "friendly puddle" to leave
# alone).

var remediation_radius: float = 250.0

const SCAN_HZ = 4.0
var _scan_timer: float = 0.0

func _ready():
	super._ready()
	_scan_timer = randf() * (1.0 / SCAN_HZ)

func _process(delta: float):
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 1.0 / SCAN_HZ
		_clean_nearby_puddles()
	queue_redraw()

func _clean_nearby_puddles():
	if not is_inside_tree():
		return
	for puddle in get_tree().get_nodes_in_group("missile_puddle"):
		if not is_instance_valid(puddle):
			continue
		if global_position.distance_to(puddle.global_position) <= remediation_radius:
			puddle.remediate()

func _draw():
	var pulse = 0.5 + sin(Time.get_ticks_msec() / 150.0) * 0.2
	var c = Color(0.35, 0.85, 0.35) # green - reads as "cleanup," distinct from every other aura color in use
	draw_arc(Vector2.ZERO, remediation_radius, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.12 * pulse), 10.0, true)
	draw_arc(Vector2.ZERO, remediation_radius, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.5), 2.0, true)

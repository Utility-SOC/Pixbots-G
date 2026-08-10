extends "res://scripts/entities/Mech.gd"

# Point-defense unit (user request, 2026-08-10): "an anti-missile jammer
# class - no visual distortion but they can shoot down missiles, as well
# as prevent missiles from detonating in their range (they will crash to
# the ground harmlessly)". First real missile-interception mechanic in the
# game - MortarShell.gd previously had no group membership at all, and
# OrbitingProjectile.gd's old interception design has been dead code since
# the Rust Phase 3 Area2D -> Node2D cutover (see that file's own header
# comment) - a plain Node2D never fires area_entered.
#
# Deliberately does NOT use the cloak's distortion-circle shader (explicit
# user ask: "no visual distortion") - reuses the JammerMech/SupportMech
# idiom instead (plain draw_arc rings, no shader), just in this unit's own
# amber color so it reads as a distinct unit type at a glance.
#
# Two halves, one radius, one aura:
#   - Active: on a throttled tick, scans the "mortar_shell" group for
#     enemy-fired shells still in flight within jammer_radius and shoots
#     them down (MortarShell.release() - no detonation, no puddle, it just
#     vanishes early).
#   - Passive backstop: joins the "anti_missile_aura" group so MortarShell.
#     gd's own landing check (see that file's _is_neutralized_by_anti_
#     missile_aura()) can catch anything this unit's own throttled scan
#     missed between ticks - any hostile shell landing within radius
#     crashes harmlessly instead of detonating. Same group-membership
#     pattern Mech._is_pierce_execution_exempt() already uses for
#     "pierce_immunity_aura".
#
# Note: MortarShell's global_position is pinned to its IMPACT point for its
# entire flight (that file's own setup() comment: "node sits at the impact
# point; shell is drawn offset"), not its live in-air position - so both
# halves here defend by "this shell's impact point is within my radius,"
# not by literally tracking the shell's arcing flight path.

var jammer_radius: float = 650.0

const SCAN_HZ = 8.0
var _scan_timer: float = 0.0

func _ready():
	super._ready()
	add_to_group("anti_missile_aura")
	_scan_timer = randf() * (1.0 / SCAN_HZ)

func _process(delta: float):
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 1.0 / SCAN_HZ
		_intercept_nearby_shells()
	queue_redraw()

func _intercept_nearby_shells():
	if not is_inside_tree():
		return
	for shell in get_tree().get_nodes_in_group("mortar_shell"):
		if not is_instance_valid(shell) or shell._landed:
			continue
		if shell.fired_by_player == is_player:
			continue # friendly-fired, not this unit's problem
		if global_position.distance_to(shell.global_position) <= jammer_radius:
			shell.release()

func _draw():
	var pulse = 0.5 + sin(Time.get_ticks_msec() / 150.0) * 0.2
	var c = Color(1.0, 0.55, 0.15) # amber - distinct from the blue power-jam / teal support rings
	draw_arc(Vector2.ZERO, jammer_radius, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.10 * pulse), 14.0, true)
	draw_arc(Vector2.ZERO, jammer_radius, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.22 * pulse), 7.0, true)
	draw_arc(Vector2.ZERO, jammer_radius, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.55), 2.0, true)

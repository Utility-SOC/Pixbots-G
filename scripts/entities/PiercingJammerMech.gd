extends "res://scripts/entities/JammerMech.gd"

# Piercing Jammer: the enemy variant referenced (but never built) in
# FEATURE_ROADMAP.md's Decision Log and §4/§6 - "bosses, Commanders,
# Piercing Jammers, and any unit inside a Piercing Jammer's aura" are exempt
# from the player's PIERCE cut-in-half instant execution (see
# Mech._is_pierce_execution_exempt). This is the AI's answer to a player
# leaning hard on execute-cheese: a support unit that doesn't out-damage the
# problem, it just makes the kill denied entirely for anyone standing near
# it (including itself). Combined with SquadDirector's kill-method telemetry
# (log_player_kill/_apply_kill_method_counter_pressure), heavy PIERCE-kill
# reliance up-weights jammer/commander-bearing squads generally - templates
# that include this role specifically are how that pressure actually bites.
#
# Mechanically a JammerMech subclass (reuses the continuous vision/power
# debuff aura wholesale via inherited _process) - a Piercing Jammer still
# jams like a Warden, it just ALSO radiates the execute-immunity field.

const PIERCE_AURA_RADIUS = 500.0

func _ready():
	super._ready()
	add_to_group("piercing_jammer_aura")
	# Slightly tighter/weaker power-jam than a stock Warden (this unit's
	# value is the execute-immunity field, not out-jamming the player too) -
	# recompute from the same wave-scaling formula JammerMech._ready used,
	# just with a gentler floor.
	var main = get_tree().current_scene
	if main and "current_wave" in main:
		jammer_power = max(0.35, 0.6 - (main.current_wave * 0.01))
	jammer_radius = 650.0

	# Distinct red-tinted ring (vs. the Warden's blue) - see JammerMech's
	# ring_glow_color field comment.
	ring_glow_color = Color(0.85, 0.2, 0.25)

# The aura radius is meaningfully larger than the jam radius (protects a
# whole squad clustered around it, not just whoever it's actively jamming) -
# draw a second, larger glow ring so the protective radius itself is
# readable on screen instead of being an invisible game-state check.
func _draw():
	super._draw()
	var pulse = 0.5 + sin(Time.get_ticks_msec() / 150.0) * 0.2
	var c = Color(0.95, 0.3, 0.2)
	draw_arc(Vector2.ZERO, PIERCE_AURA_RADIUS, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.08 * pulse), 10.0, true)
	draw_arc(Vector2.ZERO, PIERCE_AURA_RADIUS, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.35), 1.5, true)

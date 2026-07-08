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

	# Distinct red-tinted aura ring (vs. the Warden's blue) so players can
	# visually tell "this one is protecting kills" from "this one is muting
	# my damage" at a glance.
	if jammer_visual:
		jammer_visual.color = Color(0.8, 0.15, 0.2, 0.1)
		jammer_visual.scale = Vector2(jammer_radius, jammer_radius)

	# The aura radius is meaningfully larger than the jam radius (protects
	# a whole squad clustered around it, not just whoever it's actively
	# jamming) - draw a second, larger ring so the protective radius itself
	# is readable on screen instead of being an invisible game-state check.
	var aura_ring = Polygon2D.new()
	var pts = PackedVector2Array()
	for i in range(32):
		var a = i * PI / 16.0
		pts.append(Vector2(cos(a), sin(a)))
	aura_ring.polygon = pts
	aura_ring.scale = Vector2(PIERCE_AURA_RADIUS, PIERCE_AURA_RADIUS)
	aura_ring.color = Color(0.95, 0.25, 0.2, 0.05)
	aura_ring.z_index = -6
	add_child(aura_ring)

func _process(delta: float):
	super._process(delta)
	if jammer_visual:
		# Keep the pulsing alpha in the red family instead of JammerMech's
		# blue - super._process() already recolors it toward blue each call,
		# so re-tint after the fact rather than duplicating the whole method.
		var a = jammer_visual.color.a
		jammer_visual.color = Color(0.8, 0.15, 0.2, a)

extends Node2D

# Spawned by LanceMountTile.fire(): draws the beam itself for a few
# seconds, then leaves behind a chain of JumpjetResidue-style damage-tick
# zones along its path (Utility-SOC: "leaves a damage field where it was
# fired - like, everywhere the beam hits there is a field of damage
# residue... kinda like cooling lava"). Reuses JumpjetResidue rather than
# inventing a new damage-tick-zone class - same family as PulseRingVisual/
# JammerField (a self-contained Area2D that periodically ticks damage to
# whoever's inside).

# User feedback (2026-08-05): "the lance should be wider" - was 90.0/25.0,
# leaving visible gaps between residue circles along the beam's path (radius
# 25 * 2 = 50px diameter against 90px spacing). Tightened spacing and grew
# the base radius so consecutive segments touch/overlap instead of leaving
# gaps a mob could walk through untouched - k=1 (no saturation) now reads as
# one continuous threatening lane, not a dotted line.
const SEGMENT_SPACING = 70.0
# User feedback (2026-08-05): the beam flash itself read as too quick/thin
# against the residue puddle chain it leaves behind - bumped from 3.0 to
# read as a real lingering plasma lance, not a blink-and-you-miss-it flash.
# Bumped again same day ("the lance should be... longer lived") - this is
# the BEAM's own visual presence, distinct from the residue puddles below
# (which got shorter, not longer - see LanceMountTile/stats.json).
const BEAM_LINGER_TIME = 8.0

var start_pos: Vector2
var end_pos: Vector2
var damage: float = 0.0
var synergies: Dictionary = {}
var by_player: bool = true
var source_mech: Node = null
var residue_lifetime: float = 25.0

func setup(p_start: Vector2, p_end: Vector2, p_damage: float, p_synergies: Dictionary, p_by_player: bool, p_source: Node, p_residue_lifetime: float):
	start_pos = p_start
	end_pos = p_end
	damage = p_damage
	synergies = p_synergies
	by_player = p_by_player
	source_mech = p_source
	residue_lifetime = p_residue_lifetime

func _ready():
	_spawn_residue_chain()
	queue_redraw()
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, BEAM_LINGER_TIME)
	tween.tween_callback(queue_free)

func _spawn_residue_chain():
	var world = get_parent()
	if not world:
		return
	var JumpjetResidueScript = load("res://scripts/attacks/JumpjetResidue.gd")
	var total_len = start_pos.distance_to(end_pos)
	if total_len < 1.0:
		return
	var dir = (end_pos - start_pos) / total_len

	# Saturation-aware chain density (same ProjectileManager signal every
	# other weapon's consolidation already keys off - see its own header
	# for the tier table). A beam_range=6000 Lance drops ~67 of these
	# per shot at the default 90px spacing, each living residue_lifetime
	# (25s default) against a 10s cooldown - a continuously-firing Lance
	# alone steady-states at ~200 concurrent hazard nodes. This spacing
	# knob was originally added because each node was a real Area2D running
	# an overlap query every physics frame (measured as tanking FPS well
	# past what enemy count alone would explain); JumpjetResidue.gd has
	# since been converted to a plain Node2D with a throttled EntityCache
	# distance check instead (2026-08-05, same fix OrbitingProjectile.gd got
	# a day earlier) so the per-node cost is much lower now, but the
	# saturation scaling stays - visual/gameplay density at 200 concurrent
	# hazard nodes was already at the edge of "readable," independent of
	# what each node costs to run. Spacing widens and each zone's own radius
	# grows to match (area, not just spacing, scales with k - otherwise
	# widely-spaced small circles would leave gaps a beam this size is
	# supposed to threaten) - k=1 (no saturation) reproduces today's exact
	# spacing/radius unchanged.
	var k = ProjectileManager.consolidation_factor()
	var spacing = SEGMENT_SPACING * k
	var seg_radius = 35.0 * sqrt(float(k)) # was 25.0 - see "wider" comment above

	var count = max(1, int(total_len / spacing))
	# Total beam damage spread across the residue's own lifetime as a DPS,
	# so standing in one segment for the field's whole duration takes
	# roughly the beam's own hit - not a separate full hit per segment.
	var dps = damage / max(1.0, residue_lifetime * 0.3)
	for i in range(count + 1):
		var dist = min(spacing * i, total_len)
		var pos = start_pos + dir * dist
		var residue = JumpjetResidueScript.new()
		residue.lifetime = residue_lifetime
		residue.radius = seg_radius
		residue.source_mech = source_mech if by_player else null
		residue.by_player = by_player
		residue.global_position = pos
		residue.setup(dps, synergies)
		world.add_child(residue)

func _draw():
	var local_start = to_local(start_pos)
	var local_end = to_local(end_pos)
	
	# Determine base beam color: default to bright intense RED (Super Robot Wars style),
	# or blend energy synergies if non-default synergies exist.
	var color = Color(1.0, 0.15, 0.15) # Default Super Robot Wars Red
	if not synergies.is_empty():
		var blend = EnergyPacket.get_color_blend(synergies)
		if blend != Color.WHITE:
			color = blend

	# User feedback (2026-08-05): "the beam should... be wider" - all 5 layers
	# scaled up ~1.4x from the original 36/24/14/6/2 core widths.
	# Layer 1: Outer Plasma Aura (50px wide)
	draw_line(local_start, local_end, Color(color.r, color.g, color.b, 0.25), 50.0)
	# Layer 2: Outer Glow Halo (34px wide)
	draw_line(local_start, local_end, Color(color.r, color.g, color.b, 0.6), 34.0)
	# Layer 3: Main Energy Channel (20px wide)
	draw_line(local_start, local_end, Color(min(color.r + 0.2, 1.0), min(color.g + 0.2, 1.0), min(color.b + 0.2, 1.0), 0.9), 20.0)
	# Layer 4: Intense White Core (8px wide)
	draw_line(local_start, local_end, Color(1.0, 1.0, 1.0, 0.95), 8.0)
	# Layer 5: Ultra-bright Needle Core (3px wide)
	draw_line(local_start, local_end, Color(1.0, 1.0, 1.0, 1.0), 3.0)

	# Terminal Emitter Flares (start & end) - scaled up to match the wider beam
	draw_circle(local_start, 30.0, Color(color.r, color.g, color.b, 0.7))
	draw_circle(local_start, 14.0, Color(1.0, 1.0, 1.0, 0.95))
	draw_circle(local_end, 25.0, Color(color.r, color.g, color.b, 0.5))
	draw_circle(local_end, 11.0, Color(1.0, 1.0, 1.0, 0.9))

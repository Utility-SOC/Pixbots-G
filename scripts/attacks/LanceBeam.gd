extends Node2D

# Spawned by LanceMountTile.fire(): draws the beam itself for a few
# seconds, then leaves behind a chain of JumpjetResidue-style damage-tick
# zones along its path (Utility-SOC: "leaves a damage field where it was
# fired - like, everywhere the beam hits there is a field of damage
# residue... kinda like cooling lava"). Reuses JumpjetResidue rather than
# inventing a new damage-tick-zone class - same family as PulseRingVisual/
# JammerField (a self-contained Area2D that periodically ticks damage to
# whoever's inside).

const SEGMENT_SPACING = 90.0
const BEAM_LINGER_TIME = 3.0

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
	var count = max(1, int(total_len / SEGMENT_SPACING))
	# Total beam damage spread across the residue's own lifetime as a DPS,
	# so standing in one segment for the field's whole duration takes
	# roughly the beam's own hit - not a separate full hit per segment.
	var dps = damage / max(1.0, residue_lifetime * 0.3)
	for i in range(count + 1):
		var dist = min(SEGMENT_SPACING * i, total_len)
		var pos = start_pos + dir * dist
		var residue = JumpjetResidueScript.new()
		residue.lifetime = residue_lifetime
		residue.source_mech = source_mech if by_player else null
		residue.collision_mask = 4 if by_player else 8 # Enemies : Player
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

	# Layer 1: Outer Plasma Aura (36px wide)
	draw_line(local_start, local_end, Color(color.r, color.g, color.b, 0.25), 36.0)
	# Layer 2: Outer Glow Halo (24px wide)
	draw_line(local_start, local_end, Color(color.r, color.g, color.b, 0.6), 24.0)
	# Layer 3: Main Energy Channel (14px wide)
	draw_line(local_start, local_end, Color(min(color.r + 0.2, 1.0), min(color.g + 0.2, 1.0), min(color.b + 0.2, 1.0), 0.9), 14.0)
	# Layer 4: Intense White Core (6px wide)
	draw_line(local_start, local_end, Color(1.0, 1.0, 1.0, 0.95), 6.0)
	# Layer 5: Ultra-bright Needle Core (2px wide)
	draw_line(local_start, local_end, Color(1.0, 1.0, 1.0, 1.0), 2.0)

	# Terminal Emitter Flares (start & end)
	draw_circle(local_start, 22.0, Color(color.r, color.g, color.b, 0.7))
	draw_circle(local_start, 10.0, Color(1.0, 1.0, 1.0, 0.95))
	draw_circle(local_end, 18.0, Color(color.r, color.g, color.b, 0.5))
	draw_circle(local_end, 8.0, Color(1.0, 1.0, 1.0, 0.9))

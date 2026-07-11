class_name CorpseHusk
extends StaticBody2D

# Drained-husk terrain from VAMPIRIC kills (see Mech._spawn_corpse_obstacle).
# Playtest ruling: destructible by just about ANYTHING - a small hp pool
# and no elemental gating, so any shot or blast clears your path. Jumpjet
# bypass arrives with the obstacle-layer split (task: jumpjets clear all
# terrain obstacles).

var hp: float = 25.0

func apply_damage(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false):
	hp -= amount
	if hp <= 0 and not is_queued_for_deletion():
		queue_free()

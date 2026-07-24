class_name CorpseHusk
extends StaticBody2D

# Drained-husk terrain from VAMPIRIC kills (see Mech._spawn_corpse_obstacle).
# Playtest ruling: destructible by just about ANYTHING - a small hp pool
# and no elemental gating, so any shot or blast clears your path. Jumpjet
# bypass arrives with the obstacle-layer split (task: jumpjets clear all
# terrain obstacles).

var hp: float = 25.0

# Projectile hit-broadphase (see scripts/core/ProjectileBroadphase.gd).
# Mech._spawn_corpse_obstacle sets collision_layer/collision_mask and adds
# the CollisionShape2D child BEFORE add_child(husk) (that add is itself
# call_deferred'd), so by the time _ready() runs here the shape is already
# in place - just read it back rather than duplicating its radius as a
# second hardcoded constant.
var broadphase_radius: float = 0.0

func _ready():
	add_to_group("obstacle")
	for c in get_children():
		if c is CollisionShape2D and c.shape:
			if c.shape is CircleShape2D:
				broadphase_radius = c.shape.radius
			elif c.shape is RectangleShape2D:
				broadphase_radius = c.shape.size.length() / 2.0
			break

func apply_damage(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false, source_label_override: String = ""):
	hp -= amount
	if hp <= 0 and not is_queued_for_deletion():
		queue_free()

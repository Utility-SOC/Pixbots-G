class_name PartHitbox
extends Area2D

var mech: Node2D
var body_slot: int = -1

func _physics_process(_delta: float):
	if is_instance_valid(mech) and "collision_layer" in mech:
		collision_layer = mech.collision_layer

# `source` accepted (and ignored - apply_part_damage has no concept of a
# damage source yet) purely so this matches every caller's actual arity.
# Projectile._handle_hit() calls target.apply_damage(damage, dominant_str,
# source_mech) - a straight 3-argument call - against whatever it actually
# hit, which for any mech is usually one of these PartHitbox area children
# (see MechRenderer._render_mechanical_part(): every body part gets one, and
# Projectile._on_body_entered deliberately skips the parent CharacterBody2D's
# own collision for anything with apply_part_damage, so PartHitbox is the
# real hit target). This 2-argument signature silently errored ("too many
# arguments") on every such call, which aborted _handle_hit() before it ever
# reached the post-damage logic further down that same function - status
# effects, chain lightning, Vampiric lifesteal, explosions. Regular shots
# mostly connect center-mass against the main body collision box instead (so
# this mostly hid behind that path succeeding); Vampiric's aggressive
# last-second homing steering disproportionately curves shots onto an
# outstretched limb tip's hitbox instead, which is why it specifically read
# as "pure vampiric shots go right through with no damage, no repair."
func apply_damage(amount: float, element: String = "RAW", source: Node = null):
	if mech and mech.has_method("apply_part_damage"):
		mech.apply_part_damage(body_slot, amount, element)

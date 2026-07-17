class_name PartHitbox
extends Area2D

var mech: Node2D
var body_slot: int = -1

func _physics_process(_delta: float):
	if is_instance_valid(mech) and "collision_layer" in mech:
		collision_layer = mech.collision_layer

# `source`/`was_reflected`/`source_label_override` accepted (and ignored -
# apply_part_damage has no concept of a damage source, reflection, or death-
# report label yet) purely so this matches every caller's actual arity.
# Projectile._handle_hit() calls target.apply_damage(damage, dominant_str,
# source_mech, was_reflected, source_label) against whatever it actually
# hit, which for any mech is usually one of these PartHitbox area children
# (see MechRenderer._render_mechanical_part(): every body part gets one, and
# Projectile._on_body_entered deliberately skips the parent CharacterBody2D's
# own collision for anything with apply_part_damage, so PartHitbox is the
# real hit target). A signature with fewer accepted arguments than the call
# site sends silently errors ("too many arguments" / "expected N arguments")
# on every such call, which aborts _handle_hit() before it ever reaches the
# post-damage logic further down that same function - status effects, chain
# lightning, Vampiric lifesteal, explosions. This has now broken THREE times
# from the same root cause (Mech.apply_damage() gaining a new trailing param
# without this file - or CorpseHusk.gd/RuinObstacle.gd/TreeObstacle.gd,
# which have the exact same problem - being kept in sync). If Mech.
# apply_damage()'s signature changes again, update all four.
func apply_damage(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false, source_label_override: String = ""):
	if mech and mech.has_method("apply_part_damage"):
		mech.apply_part_damage(body_slot, amount, element)

class_name PartHitbox
extends Area2D

var mech: Node2D
var body_slot: int = -1

func _physics_process(_delta: float):
	if is_instance_valid(mech) and "collision_layer" in mech:
		collision_layer = mech.collision_layer

func apply_damage(amount: float, element: String = "RAW"):
	if mech and mech.has_method("apply_part_damage"):
		mech.apply_part_damage(body_slot, amount, element)

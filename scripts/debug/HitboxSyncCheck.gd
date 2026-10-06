extends Node

const MechScript = preload("res://scripts/entities/Mech.gd")
const HitboxScript = preload("res://scripts/entities/PartHitbox.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var m = MechScript.new()
	m.collision_layer = 4
	add_child(m)
	m.set_physics_process(false)
	var hb = HitboxScript.new()
	hb.mech = m
	hb.collision_layer = 0
	m.add_child(hb)
	await get_tree().process_frame
	_check("a hitbox owned by a real Mech stops polling every tick", not hb.is_physics_processing())
	m.sync_hitbox_layers()
	_check("the Mech pushes its layer into the hitbox", hb.collision_layer == 4)
	m.collision_layer = 0
	m.sync_hitbox_layers()
	_check("and follows when the body goes to layer 0", hb.collision_layer == 0)
	# periodic sync from the physics tick
	m.collision_layer = 4
	m.set_physics_process(true)
	var synced = false
	for i in range(HITBOX_TICKS()):
		await get_tree().physics_frame
		if hb.collision_layer == 4:
			synced = true
			break
	_check("the staggered periodic sync lands within %d ticks" % HITBOX_TICKS(), synced)
	# stub owner keeps polling
	var stub = Node2D.new()
	stub.set("collision_layer", 0)
	add_child(stub)
	var hb2 = HitboxScript.new()
	hb2.mech = stub
	stub.add_child(hb2)
	await get_tree().process_frame
	_check("a non-Mech owner (preview stub) keeps the per-tick fallback", hb2.is_physics_processing())
	# freed hitboxes are pruned
	hb.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	m.sync_hitbox_layers()
	_check("freed hitboxes are pruned from the registry", not m._hitboxes.has(hb) and m._hitboxes.all(func(x): return is_instance_valid(x)))
	print("hitbox sync check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

func HITBOX_TICKS() -> int:
	return MechScript.HITBOX_SYNC_TICKS + 2

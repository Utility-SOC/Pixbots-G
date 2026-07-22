extends Node

# Regression harness for task #14 (draw batching): Godot's 2D batcher keys
# off Material RESOURCE IDENTITY (RID), not property-value equality - two
# separate CanvasItemMaterial.new() instances with the same blend_mode
# still break the batch run between them. Projectile._build_visuals() used
# to allocate a fresh CanvasItemMaterial per shot for a blend_mode that
# never actually varies - with up to hundreds of live shots (see
# ProjectileManager's saturation tiers), that's hundreds of distinct
# material RIDs fighting the batcher for free. Verifies every projectile's
# visual_node now shares ONE static material instance per blend mode
# instead of allocating its own.

const ProjectileScript = preload("res://scripts/entities/Projectile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_projectile(synergy: int) -> Node:
	var p = ProjectileScript.new()
	p.fired_by_player = true
	p.damage = 10.0
	p.synergies = {synergy: 50.0}
	p.direction = Vector2.RIGHT
	p.target_direction = Vector2.RIGHT
	add_child(p)
	return p

func _ready():
	# 1. Two ordinary (non-fire) projectiles share the exact same ADD
	# material instance, not just equal-valued separate ones.
	var p1 = _make_projectile(EnergyPacket.SynergyType.RAW)
	var p2 = _make_projectile(EnergyPacket.SynergyType.KINETIC)
	_check("projectile visual_node has a material with BLEND_MODE_ADD",
		p1.visual_node.material is CanvasItemMaterial and p1.visual_node.material.blend_mode == CanvasItemMaterial.BLEND_MODE_ADD)
	_check("two different projectiles share the SAME material RESOURCE instance (same RID, not just equal values)",
		p1.visual_node.material == p2.visual_node.material)

	# 2. The shared instance is the same one _get_add_material() itself
	# returns - proves it's actually the cached static, not a coincidence.
	_check("the shared material is exactly what _get_add_material() returns",
		p1.visual_node.material == ProjectileScript._get_add_material())

	p1.queue_free()
	p2.queue_free()

	# 3. The fire trail's MIX material (a separate blend mode, only used for
	# FIRE-dominant shots) is ALSO cached as its own shared static, distinct
	# from the ADD one - two calls return the identical instance.
	var mix_a = ProjectileScript._get_mix_material()
	var mix_b = ProjectileScript._get_mix_material()
	_check("the fire-trail MIX material is also cached (repeated calls return the same instance)",
		mix_a == mix_b and mix_a.blend_mode == CanvasItemMaterial.BLEND_MODE_MIX)
	_check("the ADD and MIX materials are two distinct instances (different blend modes, not accidentally shared)",
		mix_a != ProjectileScript._get_add_material())

	if failures == 0:
		print("PASS: projectiles share cached material instances instead of allocating one per shot (batching-friendly)")
	get_tree().quit(0 if failures == 0 else 1)

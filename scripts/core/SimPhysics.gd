class_name SimPhysics
extends RefCounted

# The one place simulation code asks "what does the world physically say?". Mech/Drone/Hazard logic calls
# these instead of touching PhysicsServer2D, direct_space_state or move_and_slide directly, so the Rust
# spatial index (Rust migration Phase 1/2, docs/RUST_MIGRATION_ROADMAP.md) can replace the Godot bodies
# behind this file without rewriting the callers. Today every function is a thin pass-through to Godot,
# so behaviour is unchanged.
#
# Layer bits (project convention): 1 env, 2 water, 4 enemy, 8 player, 16 loot, 32 obstacles.

const LAYER_ENV = 1
const LAYER_WATER = 2
const LAYER_ENEMY = 4
const LAYER_PLAYER = 8
const LAYER_LOOT = 16
const LAYER_OBSTACLE = 32

# Slide a body along its current velocity for this physics tick (CharacterBody2D.move_and_slide).
static func move(body: CharacterBody2D) -> void:
	body.move_and_slide()

# True when a straight segment from `from` to `to` hits anything on `mask`.
static func segment_blocked(from_body: Node2D, from: Vector2, to: Vector2, mask: int) -> bool:
	var space_state = from_body.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(from, to, mask)
	return not space_state.intersect_ray(query).is_empty()

# Colliders overlapping a circle on `mask` (same shape query Projectile._trigger_biome_explosion and
# OilSlickHazard use). Returns the colliders, not the raw result dictionaries.
static func circle_colliders(from_body: Node2D, center: Vector2, radius: float, mask: int) -> Array:
	var space_state = from_body.get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = radius
	query.shape = shape
	query.transform = Transform2D(0.0, center)
	query.collision_mask = mask
	var out: Array = []
	for res in space_state.intersect_shape(query):
		out.append(res["collider"])
	return out

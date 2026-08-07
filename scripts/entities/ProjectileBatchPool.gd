class_name ProjectileBatchPool
extends Node2D

# EXPERIMENTAL parallel projectile system (2026-08-07, "the tree seems to be
# fucking us" - user's own framing). Projectiles here are NOT Node2D
# instances at all - no add_child/remove_child, no per-shot canvas-item
# registration, no group membership, no per-instance _process/
# _physics_process dispatch. They're rows in flat PackedArrays, stepped in
# one batch loop and rendered in one MultiMesh draw call instead of one
# Node2D tree per shot.
#
# DELIBERATELY NOT WIRED INTO LIVE COMBAT. This is a parallel system,
# opt-in only via GarageTestRange.gd's toggle (see that file), so it can be
# played with and compared against the real Projectile.gd path before any
# behavior is approved. The real path is completely untouched.
#
# V1 SCOPE (this is a multi-session project, not a one-night rewrite):
#   - Straight-line flight only. None of Projectile.gd's exotic movement
#     (Lightning blink-hop, Vortex spiral, Poison mine, gravity lob,
#     kinetic-scaled range/speed curves) is replicated yet - this proves
#     the no-Node-tree + MultiMesh architecture first, movement richness
#     comes once that's validated.
#   - One shared QuadMesh, tinted per-instance by dominant-synergy color
#     and scaled by magnitude - not per-synergy shapes yet (that's the
#     separately-discussed "bake the aesthetic" idea, a natural follow-up
#     once this foundation holds up).
#   - Hit detection is a plain per-tick distance check against whatever
#     targets are registered (see register_target/unregister_target) -
#     not integrated with ProjectileBroadphase or Projectile._handle_hit()
#     yet, so no chain lightning / status procs / elemental resistance
#     pipeline. Real integration is later, deliberate work.
#   - GDScript, not Rust, for now - same "prototype first, port the hot
#     loop to Rust once the shape is proven" discipline this codebase
#     already used for ProjectileFlight/ProjectileBroadphaseRs. If this
#     holds up under real load, `step()`'s inner loop is the obvious next
#     candidate for a Rust port mirroring that exact precedent.

const DEFAULT_CAPACITY = 2048

var capacity: int = DEFAULT_CAPACITY
var _free_indices: Array[int] = []

# --- Flat per-slot state (index-parallel arrays, not one Object per shot) ---
var _alive: PackedByteArray
var _position: PackedVector2Array
var _direction: PackedVector2Array
var _speed: PackedFloat32Array
var _damage: PackedFloat32Array
var _radius: PackedFloat32Array
var _elapsed: PackedFloat32Array
var _lifetime: PackedFloat32Array
var _color: Array = [] # Color per slot - no PackedColorArray in this Godot version's exposed API surface used elsewhere in this file, plain Array is fine at this capacity
var _scale: PackedFloat32Array
var _fired_by_player: PackedByteArray
var _source_mech: Array = [] # Node refs - can't be packed, kept as a plain Array

var _highest_active: int = -1 # compaction hint for the render loop - see _step_render

var _targets: Array = [] # registered hit-test targets (Node with global_position/broadphase_radius/apply_damage)

var _mesh_instance: MultiMeshInstance2D
var _multimesh: MultiMesh

func _init(p_capacity: int = DEFAULT_CAPACITY):
	capacity = p_capacity
	_alive.resize(capacity)
	_position.resize(capacity)
	_direction.resize(capacity)
	_speed.resize(capacity)
	_damage.resize(capacity)
	_radius.resize(capacity)
	_elapsed.resize(capacity)
	_lifetime.resize(capacity)
	_scale.resize(capacity)
	_fired_by_player.resize(capacity)
	_color.resize(capacity)
	_source_mech.resize(capacity)
	for i in range(capacity):
		_free_indices.append(i)
		_color[i] = Color.WHITE

func _ready():
	process_priority = -900 # step before anything reads this frame's positions, mirrors ProjectileManager's early-priority convention
	_setup_multimesh()

func _setup_multimesh():
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_2D
	_multimesh.use_colors = true
	var mesh = QuadMesh.new()
	mesh.size = Vector2(10, 10)
	_multimesh.mesh = mesh
	_multimesh.instance_count = capacity
	# Every slot starts fully collapsed (zero scale) so an unused/dead slot
	# draws nothing without needing to shrink instance_count dynamically
	# every frame (MultiMesh doesn't support a sparse/compacted instance
	# list - collapsing to a zero-area transform is the standard idiom).
	for i in range(capacity):
		_multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO).scaled(Vector2.ZERO))

	_mesh_instance = MultiMeshInstance2D.new()
	_mesh_instance.multimesh = _multimesh
	add_child(_mesh_instance)

# --- Public API -------------------------------------------------------------

func register_target(target: Node):
	if not _targets.has(target):
		_targets.append(target)

func unregister_target(target: Node):
	_targets.erase(target)

# Spawns one batch-pool shot. Returns the slot index, or -1 if the pool is
# full (capped, not resized - a saturated pool should degrade gracefully,
# same "cap rather than grow unbounded" convention as every other pool in
# this codebase tonight).
func spawn(pos: Vector2, dir: Vector2, speed: float, dmg: float, radius: float, lifetime: float, color: Color, scale_mult: float, by_player: bool, source: Node) -> int:
	if _free_indices.is_empty():
		return -1
	var i = _free_indices.pop_back()
	_alive[i] = 1
	_position[i] = pos
	_direction[i] = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_speed[i] = speed
	_damage[i] = dmg
	_radius[i] = radius
	_elapsed[i] = 0.0
	_lifetime[i] = lifetime
	_color[i] = color
	_scale[i] = scale_mult
	_fired_by_player[i] = 1 if by_player else 0
	_source_mech[i] = source
	if i > _highest_active:
		_highest_active = i
	return i

func despawn(i: int):
	if i < 0 or i >= capacity or _alive[i] == 0:
		return
	_alive[i] = 0
	_source_mech[i] = null
	_multimesh.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO).scaled(Vector2.ZERO))
	_free_indices.append(i)

func live_count() -> int:
	return capacity - _free_indices.size()

func _process(delta):
	_step_simulate(delta)
	_step_hit_test()
	_step_render()

# One batch loop over every alive slot - no per-instance _process() dispatch
# at the engine level, just a single GDScript for-loop over flat arrays.
# This is the exact shape a Rust port would take over later (mirrors
# ProjectileFlight.compute_batch_flat's own flat-array contract).
func _step_simulate(delta: float):
	for i in range(_highest_active + 1):
		if _alive[i] == 0:
			continue
		_elapsed[i] += delta
		if _elapsed[i] >= _lifetime[i]:
			despawn(i)
			continue
		_position[i] += _direction[i] * _speed[i] * delta

func _step_hit_test():
	if _targets.is_empty():
		return
	for i in range(_highest_active + 1):
		if _alive[i] == 0:
			continue
		var pos = _position[i]
		for t in _targets:
			if not is_instance_valid(t):
				continue
			if t.get("is_dead") == true:
				continue
			var t_radius = t.get("broadphase_radius") if "broadphase_radius" in t else 20.0
			if pos.distance_to(t.global_position) <= _radius[i] + t_radius:
				if t.has_method("apply_damage"):
					var src = _source_mech[i] if is_instance_valid(_source_mech[i]) else null
					t.apply_damage(_damage[i], "RAW", src, false, "Batch Test Shot")
				despawn(i)
				break

func _step_render():
	for i in range(_highest_active + 1):
		if _alive[i] == 0:
			continue
		var rot = _direction[i].angle()
		var xform = Transform2D(rot, _position[i]).scaled(Vector2(_scale[i], _scale[i]))
		_multimesh.set_instance_transform_2d(i, xform)
		_multimesh.set_instance_color(i, _color[i])

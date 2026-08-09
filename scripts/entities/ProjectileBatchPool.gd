class_name ProjectileBatchPool
extends Node2D

# EXPERIMENTAL parallel projectile system (2026-08-07, "the tree seems to be
# fucking us" - user's own framing). Projectiles here are NOT Node2D
# instances at all - no add_child/remove_child, no per-shot canvas-item
# registration, no group membership, no per-instance _process/
# _physics_process dispatch. They're rows in flat PackedArrays, stepped in
# one batch loop and rendered in MultiMesh draw calls instead of one
# Node2D tree per shot.
#
# DELIBERATELY NOT WIRED INTO LIVE COMBAT. This is a parallel system,
# opt-in only via GarageTestRange.gd's toggle (see that file), so it can be
# played with and compared against the real Projectile.gd path before any
# behavior is approved. The real path is completely untouched.

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
var _color: Array = []
var _scale: PackedFloat32Array
var _fired_by_player: PackedByteArray
var _source_mech: Array = []
var _dominant_synergy: PackedByteArray # 0..9 (RAW, FIRE, ICE, LIGHTNING, VORTEX, POISON, EXPLOSION, KINETIC, PIERCE, VAMPIRIC)

var _highest_active: int = -1

var _targets: Array = []

# MultiMesh rendering setup (1 per synergy family for exact shape + additive core rendering parity)
var _add_material: CanvasItemMaterial
var _synergy_multimeshes: Array[MultiMesh] = []
var _synergy_instances: Array[MultiMeshInstance2D] = []

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
	_dominant_synergy.resize(capacity)
	for i in range(capacity):
		_free_indices.append(i)
		_color[i] = Color.WHITE

func _ready():
	process_priority = -900
	_setup_multimesh()

# Build per-synergy meshes matching Projectile.gd's procedural shapes,
# featuring a bright additive material and white-hot core for full visual parity.
func _setup_multimesh():
	_add_material = CanvasItemMaterial.new()
	_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_synergy_multimeshes.resize(10)
	_synergy_instances.resize(10)

	for syn_idx in range(10):
		var poly = _get_polygon_for_synergy(syn_idx)
		var mesh = _build_synergy_mesh(poly)
		if mesh == null:
			var quad = QuadMesh.new()
			quad.size = Vector2(10, 10)
			mesh = quad

		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = capacity

		for i in range(capacity):
			mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO).scaled(Vector2.ZERO))

		var inst = MultiMeshInstance2D.new()
		inst.multimesh = mm
		inst.material = _add_material
		add_child(inst)

		_synergy_multimeshes[syn_idx] = mm
		_synergy_instances[syn_idx] = inst

static func _get_polygon_for_synergy(syn: int) -> PackedVector2Array:
	match syn:
		1: # FIRE
			return PackedVector2Array([Vector2(9, 0), Vector2(-4, 4), Vector2(-6, 0), Vector2(-4, -4)])
		2: # ICE
			return PackedVector2Array([Vector2(8, 0), Vector2(0, 4), Vector2(-5, 2), Vector2(-3, 0), Vector2(-5, -2), Vector2(0, -4)])
		3: # LIGHTNING
			return PackedVector2Array([Vector2(8, -2), Vector2(2, 4), Vector2(0, 0), Vector2(-6, 4), Vector2(-2, -4), Vector2(0, 0)])
		4: # VORTEX
			return PackedVector2Array([Vector2(5, 0), Vector2(0, 5), Vector2(-5, 0), Vector2(0, -5)])
		5: # POISON
			return PackedVector2Array([Vector2(8, 0), Vector2(-2, 4), Vector2(-5, 2), Vector2(-5, -2), Vector2(-2, -4)])
		6: # EXPLOSION
			return PackedVector2Array([Vector2(6, 0), Vector2(2, 2), Vector2(0, 6), Vector2(-2, 2), Vector2(-6, 0), Vector2(-2, -2), Vector2(0, -6), Vector2(2, -2)])
		7: # KINETIC
			return PackedVector2Array([Vector2(10, 0), Vector2(-5, 5), Vector2(-2, 0), Vector2(-5, -5)])
		8: # PIERCE
			return PackedVector2Array([Vector2(12, 0), Vector2(-6, 2), Vector2(-4, 0), Vector2(-6, -2)])
		9: # VAMPIRIC
			return PackedVector2Array([Vector2(8, 0), Vector2(-4, 6), Vector2(-2, 0), Vector2(-4, -6)])
		_: # RAW (0) or default
			var pts = PackedVector2Array()
			for i in range(16):
				var a = i * PI / 8.0
				pts.append(Vector2(cos(a), sin(a)) * 5.0)
			return pts

static func _build_synergy_mesh(poly: PackedVector2Array) -> ArrayMesh:
	var indices_outer = Geometry2D.triangulate_polygon(poly)
	if indices_outer.is_empty():
		return null
	var vertices_outer = PackedVector3Array()
	var uvs_outer = PackedVector2Array()
	for pt in poly:
		vertices_outer.append(Vector3(pt.x, pt.y, 0.0))
		uvs_outer.append(Vector2(pt.x, pt.y))

	var arr_mesh = ArrayMesh.new()

	# Surface 0: Outer glowing elemental aura
	var arrays0 = []
	arrays0.resize(Mesh.ARRAY_MAX)
	arrays0[Mesh.ARRAY_VERTEX] = vertices_outer
	arrays0[Mesh.ARRAY_INDEX] = indices_outer
	arrays0[Mesh.ARRAY_TEX_UV] = uvs_outer
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays0)

	# Surface 1: Searing hot core (0.5x scale)
	var poly_inner = PackedVector2Array()
	for pt in poly:
		poly_inner.append(pt * 0.5)
	var indices_inner = Geometry2D.triangulate_polygon(poly_inner)
	if not indices_inner.is_empty():
		var vertices_inner = PackedVector3Array()
		var uvs_inner = PackedVector2Array()
		for pt in poly_inner:
			vertices_inner.append(Vector3(pt.x, pt.y, 0.0))
			uvs_inner.append(Vector2(pt.x, pt.y))
		var arrays1 = []
		arrays1.resize(Mesh.ARRAY_MAX)
		arrays1[Mesh.ARRAY_VERTEX] = vertices_inner
		arrays1[Mesh.ARRAY_INDEX] = indices_inner
		arrays1[Mesh.ARRAY_TEX_UV] = uvs_inner
		arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays1)

	return arr_mesh

# --- Public API -------------------------------------------------------------

func register_target(target: Node):
	if not _targets.has(target):
		_targets.append(target)

func unregister_target(target: Node):
	_targets.erase(target)

func spawn(pos: Vector2, dir: Vector2, speed: float, dmg: float, radius: float, lifetime: float, color: Color, scale_mult: float, by_player: bool, source: Node, dominant_synergy: int = 0) -> int:
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
	_dominant_synergy[i] = clamp(dominant_synergy, 0, 9)
	if i > _highest_active:
		_highest_active = i
	return i

func despawn(i: int):
	if i < 0 or i >= capacity or _alive[i] == 0:
		return
	_alive[i] = 0
	var old_syn = _dominant_synergy[i]
	if old_syn >= 0 and old_syn < 10:
		_synergy_multimeshes[old_syn].set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO).scaled(Vector2.ZERO))
	_source_mech[i] = null
	_free_indices.append(i)

func live_count() -> int:
	return capacity - _free_indices.size()

func _process(delta):
	_step_simulate(delta)
	_step_hit_test()
	_step_render()

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
		var syn = _dominant_synergy[i]
		if syn >= 0 and syn < 10:
			_synergy_multimeshes[syn].set_instance_transform_2d(i, xform)
			_synergy_multimeshes[syn].set_instance_color(i, _color[i])

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

# Kinetic range/lifetime scaling (Phase 1 of the batch-pool full-parity
# plan, 2026-08-10). Reuses the real constants directly (not duplicated
# magic numbers) via a preloaded script reference, same "load(path), not
# the bare global class name" convention this codebase already uses
# elsewhere for Projectile.gd (see MissileRackTile.gd's own matching
# comment on why: a fresh checkout/fresh class-cache headless run can fail
# to resolve a bare global class_name reference).
const _ProjectileScript = preload("res://scripts/entities/Projectile.gd")

var capacity: int = DEFAULT_CAPACITY
var _free_indices: Array[int] = []

# --- Flat per-slot state (index-parallel arrays, not one Object per shot) ---
var _alive: PackedByteArray
var _position: PackedVector2Array
var _direction: PackedVector2Array
var _speed: PackedFloat32Array
var _damage: PackedFloat32Array
var _radius: PackedFloat32Array
# Position at the START of this tick's movement, before _step_simulate
# applies velocity*delta - lets _step_hit_test check the swept SEGMENT a
# shot travelled this tick, not just its end-of-tick point. A pure end-
# point check tunnels: a fast/swirling shot (Vortex's tangential wobble
# especially) can hop clean over a target's hit radius between two
# consecutive tick positions without either one landing inside it - real,
# demonstrated bug (a Vortex-ratio shot missed a stationary target
# entirely at a normal 60fps tick rate in this session's own repro).
var _prev_position: PackedVector2Array
var _elapsed: PackedFloat32Array
var _lifetime: PackedFloat32Array
# Distance-based expiry cap, alongside the time-based _lifetime above - real
# Projectile.gd expires a shot on whichever of these two independent caps
# hits first (Projectile.gd:1414-1417). Previously absent entirely: every
# batch shot used one flat caller-supplied lifetime regardless of synergy,
# so Fire-dominant shots lived far too long and Kinetic-dominant ones
# lived far too short (KINETIC_RANGE_BONUS never had anything to spend it
# on). See _compute_lifetime()/_compute_max_range() below and spawn()'s use
# of them.
var _max_range: PackedFloat32Array
var _distance_traveled: PackedFloat32Array
var _color: Array = []
var _scale: PackedFloat32Array
var _fired_by_player: PackedByteArray
var _source_mech: Array = []
var _dominant_synergy: PackedByteArray # 0..9 (RAW, FIRE, ICE, LIGHTNING, VORTEX, POISON, EXPLOSION, KINETIC, PIERCE, VAMPIRIC)
var _dominant_synergy_name: Array = [] # element name String, for apply_damage's resistance lookup

# --- Flight-math state (mirrors Projectile.gd's _flight_r_*/_prepare_
# flight_state fields - see ProjectileFlight.compute_batch_flat's own
# field-order comment, rust_ext/src/projectile_flight.rs:287-294) ---
var _r_kin: PackedFloat32Array
var _r_ice: PackedFloat32Array # only feeds steering_resistance locally, not part of the Rust request stride itself
var _r_vamp: PackedFloat32Array
var _r_fire: PackedFloat32Array
var _r_psn: PackedFloat32Array
var _r_vtx: PackedFloat32Array
var _r_ltg: PackedFloat32Array
var _r_prc: PackedFloat32Array
var _visual_offset: PackedVector2Array
var _lightning_segment_index: PackedFloat32Array
var _lightning_prev_offset: PackedFloat32Array
var _lightning_target_offset: PackedFloat32Array
# Synthetic per-slot identity fed to compute_batch_flat as instance_ids -
# these aren't real Nodes, so there's no real get_instance_id(). A bare
# slot index would give the lightning-jitter seed (hashes off instance_id,
# see projectile_flight.rs) the exact same jaggedness pattern every time a
# slot gets reused; a monotonic counter avoids that for free.
var _spawn_gen: PackedInt64Array
var _next_spawn_gen: int = 1

# --- Hit-pipeline state (mirrors Projectile.gd's pierce_count/
# _handled_targets - see _handle_hit, Projectile.gd:1793-1801,1985-1987) ---
var _pierce_count: PackedInt32Array
var _handled_targets: Array = [] # per-slot Dictionary[instance_id -> true], same dedup-set shape as Projectile._handled_targets

# --- Secondary-synergy echoes (layered visual representation) - the user:
# "in the old version I think it was more than the top two being
# represented in projectiles." Real Projectile.gd never makes synergies
# compete for one "winner" slot: Fire gets its own particle trail, Vortex
# its own spiral, Poison its own toxic trail, PLUS small orbiting helix
# particles for any secondary elements - each driven independently by its
# OWN ratio (see Projectile.gd:987-1037's helix particles, angle = time_
# alive*speed+phase). A single dominant-color main body (B1/the dominant-
# color fix) only tells half the story for a genuinely blended packet.
#
# Up to 2 secondary synergies (the next-biggest ratios after the dominant,
# above SECONDARY_SYNERGY_THRESHOLD) get small orbiting "echo" instances
# using THEIR OWN procedural mesh/color - reusing the SAME per-synergy
# MultiMesh sets already built for the main body/trail layers, since pool
# slot `i` is a unique identity: no other live shot will ever write to
# index `i` in ANY of the 10 synergy multimeshes while this shot is alive,
# so borrowing two synergy channels this shot ISN'T using as its own
# dominant is always safe. Echo 1 reuses the target synergy's MAIN body
# multimesh, echo 2 its TRAIL multimesh - both otherwise idle for this slot.
const SECONDARY_SYNERGY_THRESHOLD = 0.15
const ECHO_ORBIT_RADIUS = 16.0
const ECHO_ORBIT_SPEED = 8.0 # rad/s, matches Projectile.gd helix particles' rough pace
const ECHO_SCALE_MULT = 0.4
const NO_SYNERGY: int = 255 # sentinel for PackedByteArray (unsigned, can't hold -1)
var _secondary_synergy_1: PackedByteArray
var _secondary_synergy_2: PackedByteArray

var _flight_checked: bool = false
var _flight_rasterizer = null

var _highest_active: int = -1

var _targets: Array = []

# MultiMesh rendering setup (1 per synergy family for exact shape + additive core rendering parity)
var _add_material: CanvasItemMaterial
var _synergy_multimeshes: Array[MultiMesh] = []
var _synergy_instances: Array[MultiMeshInstance2D] = []

# Ghost-trail layer (B3, visual flourish) - real trails (FireTrail2D/Trail2D/
# GPUParticles2D/Line2D) are genuine child-Node/particle systems, fundamentally
# incompatible with this Node-less pool. Instead: one extra MultiMeshInstance2D
# per synergy, same mesh as the main body reused (no second mesh build),
# drawn a fixed offset behind each live shot along its current direction at
# reduced scale/alpha - reads as a short streak without any per-shot Node.
const TRAIL_OFFSET_PX = 14.0
const TRAIL_SCALE_MULT = 0.55
const TRAIL_ALPHA_MULT = 0.35
var _trail_multimeshes: Array[MultiMesh] = []
var _trail_instances: Array[MultiMeshInstance2D] = []

func _init(p_capacity: int = DEFAULT_CAPACITY):
	capacity = p_capacity
	_alive.resize(capacity)
	_position.resize(capacity)
	_prev_position.resize(capacity)
	_direction.resize(capacity)
	_speed.resize(capacity)
	_damage.resize(capacity)
	_radius.resize(capacity)
	_elapsed.resize(capacity)
	_lifetime.resize(capacity)
	_max_range.resize(capacity)
	_distance_traveled.resize(capacity)
	_scale.resize(capacity)
	_fired_by_player.resize(capacity)
	_color.resize(capacity)
	_source_mech.resize(capacity)
	_dominant_synergy.resize(capacity)
	_dominant_synergy_name.resize(capacity)
	_r_kin.resize(capacity)
	_r_ice.resize(capacity)
	_r_vamp.resize(capacity)
	_r_fire.resize(capacity)
	_r_psn.resize(capacity)
	_r_vtx.resize(capacity)
	_r_ltg.resize(capacity)
	_r_prc.resize(capacity)
	_visual_offset.resize(capacity)
	_lightning_segment_index.resize(capacity)
	_lightning_prev_offset.resize(capacity)
	_lightning_target_offset.resize(capacity)
	_spawn_gen.resize(capacity)
	_pierce_count.resize(capacity)
	_handled_targets.resize(capacity)
	_secondary_synergy_1.resize(capacity)
	_secondary_synergy_2.resize(capacity)
	for i in range(capacity):
		_free_indices.append(i)
		_color[i] = Color.WHITE
		_dominant_synergy_name[i] = "RAW"
		_handled_targets[i] = {}
		_secondary_synergy_1[i] = NO_SYNERGY
		_secondary_synergy_2[i] = NO_SYNERGY

func _ready():
	process_priority = -900
	_setup_multimesh()
	_ensure_flight_rust()

# Same pattern as ProjectileManager._ensure_flight_rust() - real Node
# instance_ids don't exist for these slots, so this pool makes its own
# ProjectileFlight instance rather than sharing ProjectileManager's (which
# batches only real registered Projectile.gd Nodes).
func _ensure_flight_rust():
	if not _flight_checked:
		_flight_checked = true
		if ClassDB.class_exists("ProjectileFlight"):
			_flight_rasterizer = ClassDB.instantiate("ProjectileFlight")

# Build per-synergy meshes matching Projectile.gd's procedural shapes,
# featuring a bright additive material and white-hot core for full visual parity.
func _setup_multimesh():
	_add_material = CanvasItemMaterial.new()
	_add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	_synergy_multimeshes.resize(10)
	_synergy_instances.resize(10)
	_trail_multimeshes.resize(10)
	_trail_instances.resize(10)

	for syn_idx in range(10):
		var poly = _get_polygon_for_synergy(syn_idx)
		var mesh = _build_synergy_mesh(poly)
		if mesh == null:
			var quad = QuadMesh.new()
			quad.size = Vector2(10, 10)
			mesh = quad

		# Trail layer added FIRST so it draws behind the main body (additive
		# blend makes this mostly moot for color, but keeps the main body's
		# silhouette on top for the two-surface hot-core trick to still read).
		var trail_mm = MultiMesh.new()
		trail_mm.transform_format = MultiMesh.TRANSFORM_2D
		trail_mm.use_colors = true
		trail_mm.mesh = mesh # same mesh resource, no second build
		trail_mm.instance_count = capacity
		for i in range(capacity):
			trail_mm.set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO).scaled(Vector2.ZERO))
		var trail_inst = MultiMeshInstance2D.new()
		trail_inst.multimesh = trail_mm
		trail_inst.material = _add_material
		add_child(trail_inst)
		_trail_multimeshes[syn_idx] = trail_mm
		_trail_instances[syn_idx] = trail_inst

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

func spawn(pos: Vector2, dir: Vector2, speed: float, dmg: float, radius: float, lifetime: float, color: Color, scale_mult: float, by_player: bool, source: Node, dominant_synergy: int = 0, ratios: Dictionary = {}) -> int:
	if _free_indices.is_empty():
		return -1
	var i = _free_indices.pop_back()
	_alive[i] = 1
	_position[i] = pos
	_prev_position[i] = pos
	_direction[i] = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_speed[i] = speed
	_damage[i] = dmg
	_radius[i] = radius
	_elapsed[i] = 0.0
	# `lifetime` stays an explicit per-call override when the caller passes a
	# real positive value (every existing BatchPool*Check.gd call site does
	# this deliberately, for ratio-independent controlled testing - keeping
	# them authoritative here is a zero-behavior-change guarantee for all of
	# them). <= 0.0 opts into auto-computing from this shot's own ratios
	# instead, mirroring real Projectile._get_lifetime() - this is what
	# GarageTestRange._fire_via_batch_pool now uses instead of one flat
	# constant for every synergy.
	var r_fire_for_life = ratios.get(EnergyPacket.SynergyType.FIRE, 0.0)
	var r_kin_for_life = ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)
	_lifetime[i] = lifetime if lifetime > 0.0 else _compute_lifetime(r_fire_for_life, r_kin_for_life)
	_max_range[i] = _compute_max_range(r_kin_for_life)
	_distance_traveled[i] = 0.0
	_color[i] = color
	_scale[i] = scale_mult
	_fired_by_player[i] = 1 if by_player else 0
	_source_mech[i] = source
	_dominant_synergy[i] = clamp(dominant_synergy, 0, 9)
	_dominant_synergy_name[i] = EnergyPacket.element_name(dominant_synergy)

	_r_kin[i] = ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)
	_r_ice[i] = ratios.get(EnergyPacket.SynergyType.ICE, 0.0)
	_r_vamp[i] = ratios.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0)
	_r_fire[i] = ratios.get(EnergyPacket.SynergyType.FIRE, 0.0)
	_r_psn[i] = ratios.get(EnergyPacket.SynergyType.POISON, 0.0)
	_r_vtx[i] = ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0)
	_r_ltg[i] = ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0)
	_r_prc[i] = ratios.get(EnergyPacket.SynergyType.PIERCE, 0.0)
	# Mirrors Projectile.gd:598-601's pierce_count derivation.
	_pierce_count[i] = 1 + int(4.0 * _r_prc[i]) if _r_prc[i] > 0.0 else 1
	_handled_targets[i] = {}
	_visual_offset[i] = Vector2.ZERO
	_lightning_segment_index[i] = -1.0 # forces the first segment to roll on tick 1, same as Projectile.gd's default
	_lightning_prev_offset[i] = 0.0
	_lightning_target_offset[i] = 0.0
	_spawn_gen[i] = _next_spawn_gen
	_next_spawn_gen += 1

	var secondaries = _compute_secondary_synergies(ratios, _dominant_synergy[i])
	_secondary_synergy_1[i] = secondaries[0]
	_secondary_synergy_2[i] = secondaries[1]

	if i > _highest_active:
		_highest_active = i
	return i

# Direct port of Projectile._get_lifetime() (Projectile.gd:509-522), taking
# the two ratios that formula actually branches on rather than a whole
# ratios Dictionary - matches this pool's existing per-field style
# (_apply_status_effects already reads individual _r_* arrays the same way).
# `ratios.has(X)` in the real version is equivalent here to `r_x > 0.0`:
# EnergyPacket.compute_ratios() only ever produces a key for a synergy with
# real nonzero contribution, so a spawned shot's r_fire/r_kin are exactly
# 0.0 precisely when the real dict wouldn't have had that key at all.
static func _compute_lifetime(r_fire: float, r_kin: float) -> float:
	var base_life = 4.0
	if r_fire > 0.0:
		base_life = lerp(base_life, 0.4, r_fire)
		if r_kin > 0.0:
			base_life += 1.0 * r_kin
	elif r_kin > 0.0:
		base_life += 8.0 * r_kin
	return max(0.1, base_life)

# Direct port of the max_range half of Projectile._calculate_stats()
# (Projectile.gd:548) - the is_beam_shot/range_mult multipliers that
# formula also applies don't have a batch-pool equivalent concept (no beam
# shots, no per-mount range_mult plumbed through spawn() today), so this is
# the BASE_RANGE + KINETIC_RANGE_BONUS term only.
static func _compute_max_range(r_kin: float) -> float:
	return _ProjectileScript.BASE_RANGE + _ProjectileScript.KINETIC_RANGE_BONUS * r_kin

# Pure function (no MultiMesh involved, testable directly - same "test the
# math, not a MultiMesh round-trip" reasoning as _compute_trail_render) -
# the two next-biggest ratios after the dominant, above SECONDARY_SYNERGY_
# THRESHOLD, sorted descending. Returns [syn_or_NO_SYNERGY, syn_or_NO_SYNERGY].
static func _compute_secondary_synergies(ratios: Dictionary, dominant: int) -> Array:
	var best1 = NO_SYNERGY
	var best1_val = SECONDARY_SYNERGY_THRESHOLD
	var best2 = NO_SYNERGY
	var best2_val = SECONDARY_SYNERGY_THRESHOLD
	for syn_type in ratios:
		if int(syn_type) == dominant:
			continue
		var v = ratios[syn_type]
		if v > best1_val:
			best2 = best1
			best2_val = best1_val
			best1 = int(syn_type)
			best1_val = v
		elif v > best2_val:
			best2 = int(syn_type)
			best2_val = v
	return [best1, best2]

func despawn(i: int):
	if i < 0 or i >= capacity or _alive[i] == 0:
		return
	_alive[i] = 0
	# Clear EVERY synergy's main+trail slot for this index, not just the
	# dominant's - secondary echoes (see the block comment above) may have
	# borrowed other synergies' otherwise-idle channels at this same index,
	# and an orphaned echo would linger visibly if only the dominant's
	# slot got cleared.
	for syn in range(10):
		_synergy_multimeshes[syn].set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO).scaled(Vector2.ZERO))
		_trail_multimeshes[syn].set_instance_transform_2d(i, Transform2D(0.0, Vector2.ZERO).scaled(Vector2.ZERO))
	_secondary_synergy_1[i] = NO_SYNERGY
	_secondary_synergy_2[i] = NO_SYNERGY
	_source_mech[i] = null
	_free_indices.append(i)

func live_count() -> int:
	return capacity - _free_indices.size()

func _process(delta):
	_step_simulate(delta)
	_step_hit_test()
	_step_render()

const REQUEST_STRIDE = 20 # MUST match rust_ext/src/projectile_flight.rs's compute_batch_flat contract
const RESPONSE_STRIDE = 12

# NOTE: this does NOT include Lightning's blink-hop teleport (Projectile.
# _update_blink/_apply_blink_hop) - that's a separate targeting-query-driven
# system, out of scope here (see this session's batch-pool parity plan).
# The zigzag visual jaggedness (part of compute_batch_flat's own output) IS
# included below.
func _step_simulate(delta: float):
	# Lifetime expiry first, before this tick's movement batch, so an
	# about-to-expire slot never gets included in the Rust call below.
	for i in range(_highest_active + 1):
		if _alive[i] == 0:
			continue
		_elapsed[i] += delta
		if _elapsed[i] >= _lifetime[i]:
			despawn(i)

	if not _flight_rasterizer:
		# No Rust extension loaded - degrade to the old straight-line
		# movement rather than not moving at all.
		for i in range(_highest_active + 1):
			if _alive[i] == 0:
				continue
			_prev_position[i] = _position[i]
			var step = _direction[i] * _speed[i] * delta
			_position[i] += step
			_distance_traveled[i] += step.length()
			if _distance_traveled[i] >= _max_range[i]:
				despawn(i)
		return

	var live_indices := PackedInt32Array()
	var instance_ids := PackedInt64Array()
	var requests_flat := PackedFloat64Array()
	for i in range(_highest_active + 1):
		if _alive[i] == 0:
			continue
		live_indices.append(i)
		instance_ids.append(_spawn_gen[i])
		# Mirrors Projectile._prepare_flight_state's local derivation
		# (Projectile.gd:1122,1126) - these two aren't part of the Rust
		# request stride's ratio fields, they're precomputed on this side.
		var steering_resistance = 1.0 + (3.0 * _r_ice[i])
		var straighten = clamp(1.0 - _r_kin[i], 0.0, 1.0)
		requests_flat.append(_r_kin[i])
		requests_flat.append(_r_vamp[i])
		requests_flat.append(_r_fire[i])
		requests_flat.append(_r_psn[i])
		requests_flat.append(_r_vtx[i])
		requests_flat.append(_r_ltg[i])
		requests_flat.append(_r_prc[i])
		requests_flat.append(_direction[i].x)
		requests_flat.append(_direction[i].y)
		requests_flat.append(0.0) # target_direction.x - Test Range shots don't home
		requests_flat.append(0.0) # target_direction.y
		requests_flat.append(0.0) # has_homing_target
		requests_flat.append(_speed[i]) # final_speed
		requests_flat.append(_elapsed[i]) # time_alive
		requests_flat.append(delta)
		requests_flat.append(steering_resistance)
		requests_flat.append(straighten)
		requests_flat.append(_lightning_segment_index[i])
		requests_flat.append(_lightning_prev_offset[i])
		requests_flat.append(_lightning_target_offset[i])

	if live_indices.is_empty():
		return

	var results_flat: PackedFloat64Array = _flight_rasterizer.compute_batch_flat(instance_ids, requests_flat)
	for k in range(live_indices.size()):
		var i = live_indices[k]
		var base = k * RESPONSE_STRIDE
		_direction[i] = Vector2(results_flat[base], results_flat[base + 1])
		var velocity = Vector2(results_flat[base + 2], results_flat[base + 3])
		_visual_offset[i] = Vector2(results_flat[base + 4], results_flat[base + 5])
		_lightning_segment_index[i] = results_flat[base + 9]
		_lightning_prev_offset[i] = results_flat[base + 10]
		_lightning_target_offset[i] = results_flat[base + 11]
		_prev_position[i] = _position[i]
		var step = velocity * delta
		_position[i] += step
		_distance_traveled[i] += step.length()
		if _distance_traveled[i] >= _max_range[i]:
			despawn(i)

func _step_hit_test():
	if _targets.is_empty():
		return
	for i in range(_highest_active + 1):
		if _alive[i] == 0:
			continue
		# Swept-segment check (this tick's prev_position -> position), not
		# just the end-of-tick point - a point-only check tunnels: a fast or
		# swirling shot (Vortex's tangential wobble especially) can hop clean
		# over a target's hit radius between two consecutive tick positions
		# without either one landing inside it. Real, demonstrated bug (a
		# Vortex-ratio shot missed a stationary target entirely at a normal
		# 60fps tick rate before this fix - see this session's own repro).
		for t in _targets:
			if not is_instance_valid(t):
				continue
			if t.get("is_dead") == true:
				continue
			var t_radius = t.get("broadphase_radius") if "broadphase_radius" in t else 20.0
			var nearest_on_path = Geometry2D.get_closest_point_to_segment(t.global_position, _prev_position[i], _position[i])
			if nearest_on_path.distance_to(t.global_position) <= _radius[i] + t_radius:
				# Dedup (mirrors Projectile.gd's _handled_targets guard) - a
				# pierce shot re-checking the same still-in-range target on a
				# later tick must not double-hit it.
				var target_id = t.get_instance_id()
				if _handled_targets[i].has(target_id):
					continue
				_handled_targets[i][target_id] = true
				if t.has_method("apply_damage"):
					var src = _source_mech[i] if is_instance_valid(_source_mech[i]) else null
					t.apply_damage(_damage[i], _dominant_synergy_name[i], src, false, "Batch Test Shot")
				_apply_status_effects(i, t)
				_pierce_count[i] -= 1
				if _pierce_count[i] <= 0:
					despawn(i)
				break

# Portable subset of Projectile._apply_synergy_status_effects
# (Projectile.gd:1864-1911) - deliberately excludes anything that touches
# camera/UI (crit floaters, screen shake), Vampiric heal, Explosion AoE,
# and biome cross-triggers (vampiric heal/AoE/biome all touch other Nodes/
# EntityCache groups - bigger scope for a still-experimental, non-combat-
# facing system, see this session's batch-pool parity plan). EXPLOSION's
# "concussed" proc is also skipped - its ratio isn't tracked per-slot here.
func _apply_status_effects(i: int, target: Node):
	if not target.has_method("apply_status"):
		return
	if _r_fire[i] > 0.1:
		target.apply_status("burning", 3.0 * _r_fire[i])
	if _r_ice[i] > 0.1:
		target.apply_status("frozen", 3.0 * _r_ice[i])
	var rl = _r_ltg[i]
	if rl > 0.15 and randf() < 0.35 * rl:
		target.apply_status("paralyzed", 0.4 + 0.5 * rl)
	if _r_psn[i] > 0.1:
		target.apply_status("poisoned", 4.0 + 3.0 * _r_psn[i])
	var rk = _r_kin[i]
	if rk > 0.2:
		target.apply_status("staggered", 0.4 + 0.3 * rk)
		if "external_force" in target:
			target.external_force += _direction[i] * 260.0 * rk
	if _r_prc[i] > 0.15:
		target.apply_status("rent", 4.0)
	var rv = _r_vtx[i]
	if rv > 0.15:
		if "vortex_drag_point" in target:
			target.vortex_drag_point = _position[i]
		target.apply_status("vortexed", 0.4 + 0.6 * rv)
	var rvm = _r_vamp[i]
	if rvm > 0.1:
		target.apply_status("bleeding", 3.0 + 2.0 * rvm)
		if rvm > 0.5 and randf() < 0.3:
			target.apply_status("immobilized", 0.5)

# Pure computation for the ghost-trail layer (B3), split out from
# _step_render() so it's testable directly without needing a real
# MultiMesh/RenderingServer round-trip - get_instance_transform_2d/
# get_instance_color don't reliably reflect a same-frame set_instance_*
# write under --headless with no actual render sync ever occurring
# (confirmed via an isolated probe: set-then-immediately-get on a bare
# MultiMesh returns stale/default data in this environment). Testing the
# math here sidesteps that engine/environment limitation entirely.
static func _compute_trail_render(render_pos: Vector2, direction: Vector2, main_color: Color) -> Dictionary:
	var trail_c = main_color
	trail_c.a = main_color.a * TRAIL_ALPHA_MULT
	return {"position": render_pos - direction * TRAIL_OFFSET_PX, "color": trail_c}

# Pure computation for one secondary-synergy echo (same "test the math, not
# a MultiMesh round-trip" reasoning as _compute_trail_render) - orbits the
# main body, mirroring Projectile.gd's helix particles (angle = time_alive*
# speed+phase, Projectile.gd:1433). phase=0.0 for the first echo, PI for
# the second, so two simultaneous secondaries land on opposite sides
# instead of overlapping.
static func _compute_echo_render(render_pos: Vector2, elapsed: float, phase: float, alpha: float, synergy: int) -> Dictionary:
	var angle = elapsed * ECHO_ORBIT_SPEED + phase
	var offset = Vector2(cos(angle), sin(angle)) * ECHO_ORBIT_RADIUS
	var c = EnergyPacket.get_color_for_synergy(synergy) * 1.5
	c.a = alpha
	return {"position": render_pos + offset, "color": c}

func _step_render():
	for i in range(_highest_active + 1):
		if _alive[i] == 0:
			continue
		var rot = _direction[i].angle()
		var render_pos = _position[i] + _visual_offset[i]
		var xform = Transform2D(rot, render_pos).scaled(Vector2(_scale[i], _scale[i]))
		var syn = _dominant_synergy[i]
		if syn >= 0 and syn < 10:
			var c = _color[i]
			var life_frac = clamp(_elapsed[i] / _lifetime[i], 0.0, 1.0) if _lifetime[i] > 0.0 else 0.0
			c.a = 1.0 - life_frac
			_synergy_multimeshes[syn].set_instance_transform_2d(i, xform)
			_synergy_multimeshes[syn].set_instance_color(i, c)

			# Ghost-trail layer (B3) - fixed offset behind current heading,
			# smaller and dimmer than the main body. See TRAIL_* consts.
			var trail_render = _compute_trail_render(render_pos, _direction[i], c)
			var trail_xform = Transform2D(rot, trail_render["position"]).scaled(Vector2(_scale[i], _scale[i]) * TRAIL_SCALE_MULT)
			_trail_multimeshes[syn].set_instance_transform_2d(i, trail_xform)
			_trail_multimeshes[syn].set_instance_color(i, trail_render["color"])

			# Secondary-synergy echoes - orbiting instances for up to 2
			# non-dominant ratios, so a blended packet reads as more than
			# just its single loudest element. Borrows each secondary's OWN
			# otherwise-idle main-body (echo 1) / trail (echo 2) multimesh
			# channel at this same slot index - see the class-level comment
			# on _secondary_synergy_1/_secondary_synergy_2 for why that's safe.
			var syn2_1 = _secondary_synergy_1[i]
			if syn2_1 != NO_SYNERGY:
				var echo1 = _compute_echo_render(render_pos, _elapsed[i], 0.0, c.a, syn2_1)
				var echo1_xform = Transform2D(rot, echo1["position"]).scaled(Vector2(_scale[i], _scale[i]) * ECHO_SCALE_MULT)
				_synergy_multimeshes[syn2_1].set_instance_transform_2d(i, echo1_xform)
				_synergy_multimeshes[syn2_1].set_instance_color(i, echo1["color"])
			var syn2_2 = _secondary_synergy_2[i]
			if syn2_2 != NO_SYNERGY:
				var echo2 = _compute_echo_render(render_pos, _elapsed[i], PI, c.a, syn2_2)
				var echo2_xform = Transform2D(rot, echo2["position"]).scaled(Vector2(_scale[i], _scale[i]) * ECHO_SCALE_MULT)
				_trail_multimeshes[syn2_2].set_instance_transform_2d(i, echo2_xform)
				_trail_multimeshes[syn2_2].set_instance_color(i, echo2["color"])

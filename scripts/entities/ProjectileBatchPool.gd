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
# Explosion ratio - previously not tracked per-slot at all (only fed into
# the dominant-synergy int/name and the visual shape, never kept as its
# own ratio field) since nothing needed it until Concussed/Explosion AoE
# (Phases 5/7 of the batch-pool full-parity plan, 2026-08-10).
var _r_exp: PackedFloat32Array
# aoe_bonus - real per-mount AoE-radius stat (EnergyPacket.aoe_bonus, fed
# into Projectile.explosion_radius_for/poison-mine detonation radius).
# Previously dropped entirely at the GarageTestRange call site; now
# threaded through spawn() so Explosion/mine AoE radius matches the real
# formula instead of silently assuming aoe_bonus=0 for every shot.
var _aoe_bonus: PackedFloat32Array
var _visual_offset: PackedVector2Array
var _lightning_segment_index: PackedFloat32Array
var _lightning_prev_offset: PackedFloat32Array
var _lightning_target_offset: PackedFloat32Array
# Lightning teleport-hop state (Phase 2 of the batch-pool full-parity plan,
# 2026-08-10) - mirrors Projectile.gd's own _blink_timer/_lightning_hops_
# left fields exactly. This is a real gameplay-defining mechanic, not just
# cosmetic: every BLINK_INTERVAL a Lightning-ratio shot teleport-hops
# toward the nearest live target instead of flying to it - the zigzag
# jaggedness already coming out of compute_batch_flat above is purely
# cosmetic and was the only part of Lightning's identity this pool had
# before this phase. Targeting is a plain per-tick linear scan against
# this pool's own small _targets array (resolved decision: the real
# ProjectileTargetingBatcher exists specifically to avoid expensive scans
# across dozens of live enemies in real combat - a problem the handful-of-
# targets Test Range doesn't have, so extending that shared infrastructure
# isn't worth it here).
var _blink_timer: PackedFloat32Array
var _hops_left: PackedInt32Array
# Captured once at spawn (Phase 6) - _hops_left/_pierce_count only ever
# count DOWN from these, so "how much is left, as a fraction of how much
# there ever was" (_compute_hit_decay's whole job) needs the original max
# kept separately. Mirrors Projectile.gd's own _lightning_hops_max/
# _pierce_count_max fields exactly.
var _hops_max: PackedInt32Array

# Poison mine-crawl mode (Phase 3 of the batch-pool full-parity plan,
# 2026-08-10) - unlike Lightning's hop (an event layered on top of the
# normal flight step), this is a genuine full movement-MODE switch in the
# real system: Projectile._physics_process_body early-returns into
# _physics_process_mine instead of the organic Rust-driven flight block at
# all once poison_ratio > MINE_POISON_THRESHOLD (real system also skips
# _update_blink entirely for mine shots, even ones that also carry real
# Lightning ratio - mine mode fully replaces movement, not just distorts
# it). Set once at spawn, never changes for a slot's lifetime.
var _is_mine: PackedByteArray
# Detonation guard (Phase 8) - mirrors Projectile.gd's own _mine_detonated:
# a mine can be detonated by EITHER a contact hit OR running out of
# lifetime/range, whichever happens first - this stops the other trigger
# from firing a second detonation on the same slot.
var _mine_detonated: PackedByteArray
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
var _pierce_count_max: PackedInt32Array # captured at spawn, see _hops_max's comment above for why
var _handled_targets: Array = [] # per-slot Dictionary[instance_id -> true], same dedup-set shape as Projectile._handled_targets
# Resonator Sync proc_synergies (Phase 5) - a SECOND, independent ratio
# Dictionary a packet can carry (EnergyPacket.proc_synergies), entirely
# separate from its real elemental composition/damage. Real Projectile.gd
# reuses its whole status-effect threshold table against this dict too
# (see _apply_synergy_status_effects's own "sr" parameter and header
# comment: "a sync-conferred burn behaves identically to a real one").
var _proc_synergies: Array = [] # per-slot Dictionary, same shape as EnergyPacket.proc_synergies

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
	_r_exp.resize(capacity)
	_aoe_bonus.resize(capacity)
	_visual_offset.resize(capacity)
	_lightning_segment_index.resize(capacity)
	_lightning_prev_offset.resize(capacity)
	_lightning_target_offset.resize(capacity)
	_blink_timer.resize(capacity)
	_hops_left.resize(capacity)
	_hops_max.resize(capacity)
	_is_mine.resize(capacity)
	_mine_detonated.resize(capacity)
	_spawn_gen.resize(capacity)
	_pierce_count.resize(capacity)
	_pierce_count_max.resize(capacity)
	_handled_targets.resize(capacity)
	_proc_synergies.resize(capacity)
	_secondary_synergy_1.resize(capacity)
	_secondary_synergy_2.resize(capacity)
	for i in range(capacity):
		_free_indices.append(i)
		_color[i] = Color.WHITE
		_dominant_synergy_name[i] = "RAW"
		_handled_targets[i] = {}
		_proc_synergies[i] = {}
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
		# Fire (1) and Kinetic (7) get their OWN bespoke trail mesh instead of
		# reusing the main body's (Phase 10 of the batch-pool full-parity
		# plan, 2026-08-10) - real Projectile.gd gives these two genuinely
		# distinct ornaments (Fire's GPUParticles2D smoke trail, Kinetic's
		# Trail2D speed-line) instead of the uniform reused-shape trail every
		# other synergy gets here. A literal GPUParticles2D per shot is
		# correctly ruled out for a Node-less MultiMesh pool (see this file's
		# own header) - a tapered, alpha-gradient "comet" mesh is the
		# MultiMesh-native substitute, closer to a heat/speed streak than the
		# uniform-scaled main-body copy every other trail still uses.
		var trail_mesh = mesh
		if syn_idx == 1: # FIRE
			trail_mesh = _build_tapered_trail_mesh(22.0, 7.0)
		elif syn_idx == 7: # KINETIC
			trail_mesh = _build_tapered_trail_mesh(16.0, 3.0)
		var trail_mm = MultiMesh.new()
		trail_mm.transform_format = MultiMesh.TRANSFORM_2D
		trail_mm.use_colors = true
		trail_mm.mesh = trail_mesh
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

# MultiMesh-native substitute for a real GPUParticles2D/Trail2D per-shot
# trail (Phase 10 of the batch-pool full-parity plan, 2026-08-10) - a
# tapered "comet" triangle, wide and fully opaque at the front (nearest the
# shot's own body), narrowing to a transparent point at the back. The alpha
# fade is baked into the mesh's own per-VERTEX colors (Mesh.ARRAY_COLOR),
# which MultiMesh's per-INSTANCE color (see trail_mm.use_colors) multiplies
# against - so this compounds with the existing whole-trail alpha fade
# (_compute_trail_render's TRAIL_ALPHA_MULT) rather than fighting it.
static func _build_tapered_trail_mesh(length: float, width: float) -> ArrayMesh:
	var vertices = PackedVector3Array([
		Vector3(0.0, width * 0.5, 0.0),
		Vector3(0.0, -width * 0.5, 0.0),
		Vector3(-length, 0.0, 0.0),
	])
	var colors = PackedColorArray([
		Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0),
	])
	var indices = PackedInt32Array([0, 1, 2])
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var arr_mesh = ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh

# --- Public API -------------------------------------------------------------

func register_target(target: Node):
	if not _targets.has(target):
		_targets.append(target)

func unregister_target(target: Node):
	_targets.erase(target)

func spawn(pos: Vector2, dir: Vector2, speed: float, dmg: float, radius: float, lifetime: float, color: Color, scale_mult: float, by_player: bool, source: Node, dominant_synergy: int = 0, ratios: Dictionary = {}, proc_synergies: Dictionary = {}, aoe_bonus: float = 0.0) -> int:
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
	_r_exp[i] = ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0)
	_aoe_bonus[i] = aoe_bonus
	# Mirrors Projectile.gd:350's _is_poison_mine derivation exactly.
	_is_mine[i] = 1 if _r_psn[i] > _ProjectileScript.MINE_POISON_THRESHOLD else 0
	_mine_detonated[i] = 0
	# Mirrors Projectile.gd:598-601's pierce_count derivation.
	_pierce_count[i] = 1 + int(4.0 * _r_prc[i]) if _r_prc[i] > 0.0 else 1
	_pierce_count_max[i] = _pierce_count[i]
	_handled_targets[i] = {}
	_proc_synergies[i] = proc_synergies.duplicate()
	_visual_offset[i] = Vector2.ZERO
	_lightning_segment_index[i] = -1.0 # forces the first segment to roll on tick 1, same as Projectile.gd's default
	_lightning_prev_offset[i] = 0.0
	_lightning_target_offset[i] = 0.0
	# Mirrors Projectile.gd:565-570's _lightning_hops_left derivation exactly.
	_blink_timer[i] = 0.0
	_hops_left[i] = int(round(4.0 * _r_ltg[i])) if _r_ltg[i] > _ProjectileScript.LIGHTNING_BLINK_MIN else 0
	_hops_max[i] = _hops_left[i]
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

func _step_simulate(delta: float):
	# Lifetime expiry first, before this tick's movement batch, so an
	# about-to-expire slot never gets included in the Rust call below.
	for i in range(_highest_active + 1):
		if _alive[i] == 0:
			continue
		_elapsed[i] += delta
		if _elapsed[i] >= _lifetime[i]:
			# Mirrors Projectile._expire()'s own "if _is_poison_mine:
			# _trigger_poison_mine_detonation()" - a mine that runs out of
			# time without ever being contacted still detonates rather than
			# silently vanishing.
			if _is_mine[i] == 1:
				_trigger_poison_mine_detonation(i)
			despawn(i)

	# Mine-mode slots are a fully disjoint movement track from here on (see
	# _is_mine's own field comment) - handled entirely by _step_mine_movement,
	# excluded from every loop below via `if _is_mine[i]: continue`.
	_step_mine_movement(delta)

	if not _flight_rasterizer:
		# No Rust extension loaded - degrade to the old straight-line
		# movement rather than not moving at all.
		for i in range(_highest_active + 1):
			if _alive[i] == 0 or _is_mine[i] == 1:
				continue
			_prev_position[i] = _position[i]
			var step = _direction[i] * _speed[i] * delta
			_position[i] += step
			_distance_traveled[i] += step.length()
			if _distance_traveled[i] >= _max_range[i]:
				despawn(i)
		_step_blink_hops(delta)
		return

	var live_indices := PackedInt32Array()
	var instance_ids := PackedInt64Array()
	var requests_flat := PackedFloat64Array()
	for i in range(_highest_active + 1):
		if _alive[i] == 0 or _is_mine[i] == 1:
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
		# Vampiric homing ("The Hunter") - Phase 4 of the batch-pool full-
		# parity plan, 2026-08-10. The shared Rust code already has this
		# steering branch fully implemented and parity-tested; this pool
		# just used to hardcode has_homing_target=0.0/target_direction=zero
		# unconditionally. Threshold (0.05) and acquire-range formula both
		# mirror Projectile._calculate_stats()/_request_homing_target()
		# exactly (Projectile.gd:605, 1635-1637). Always picks the NEAREST
		# live target via the same direct scan Phase 2's blink-hop uses
		# (real Projectile.gd prefers the FURTHEST target when Kinetic+
		# Vampiric are both present - skipped here since the Test Range
		# only ever has one real target, making that distinction moot in
		# this system's only actual deployment).
		var target_dir = Vector2.ZERO
		var has_homing = 0.0
		if _r_vamp[i] > 0.05:
			var acquire_dist = 400.0 + 300.0 * _r_vamp[i]
			if _r_ltg[i] > 0.0:
				acquire_dist += 500.0 * _r_ltg[i]
			var homing_target = _find_nearest_target(_position[i], acquire_dist, i)
			if homing_target != null:
				target_dir = (homing_target.global_position - _position[i]).normalized()
				has_homing = 1.0
		requests_flat.append(target_dir.x)
		requests_flat.append(target_dir.y)
		requests_flat.append(has_homing)
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
	_step_blink_hops(delta)

# Poison mine-crawl movement (Phase 3) - direct port of Projectile.
# _physics_process_mine (real system's own header: "no gravity lob, vortex
# swirl, fire drag, homing, or range-based speed bonuses - just a straight
# crawl (or a dead stop with no KINETIC)... Lightning's cosmetic zig-zag
# visual offset is kept even at zero velocity"). Completely bypasses the
# Rust flight call for these slots (see the two `_is_mine[i] == 1: continue`
# skips added to the Rust-request and no-Rust-fallback loops above) - the
# real system's own early-return means a mine shot never even reaches the
# organic flight block, so this has to be a fully separate movement path,
# not a distortion layered on top of the shared one.
func _step_mine_movement(delta: float):
	for i in range(_highest_active + 1):
		if _alive[i] == 0 or _is_mine[i] == 0:
			continue
		_prev_position[i] = _position[i]
		var velocity = _direction[i] * _ProjectileScript.MINE_CRAWL_SPEED * _r_kin[i]
		var step = velocity * delta
		_position[i] += step
		_distance_traveled[i] += step.length()
		if _distance_traveled[i] >= _max_range[i]:
			# Mirrors Projectile._expire()'s mine-detonation-on-timeout, see
			# the matching comment on the lifetime-expiry pass above.
			_trigger_poison_mine_detonation(i)
			despawn(i)
			continue

		# Cosmetic zig-zag visual offset, ported from Projectile.gd:1519-1533 -
		# reuses the SAME per-slot _lightning_segment_index/_lightning_prev_
		# offset/_lightning_target_offset fields the Rust call normally
		# drives for non-mine shots (mine shots never reach that call, so
		# these would otherwise sit frozen at their spawn-time defaults).
		# _spawn_gen[i] substitutes for get_instance_id() as the per-shot
		# jitter seed - same substitution this pool already makes feeding
		# the Rust call's own instance_ids (see that field's own comment).
		if _r_ltg[i] > 0.0:
			var ortho = Vector2(-_direction[i].y, _direction[i].x)
			var segment_length = 0.045
			var segment_index = int(_elapsed[i] / segment_length)
			if float(segment_index) != _lightning_segment_index[i]:
				_lightning_segment_index[i] = float(segment_index)
				_lightning_prev_offset[i] = _lightning_target_offset[i]
				var seed = int(hash(_spawn_gen[i])) ^ segment_index
				_lightning_target_offset[i] = (float(abs(seed) % 2000) / 1000.0) - 1.0
			var seg_t = clamp(fmod(_elapsed[i], segment_length) / segment_length, 0.0, 1.0)
			seg_t = seg_t * seg_t
			var lightning_wave = lerp(_lightning_prev_offset[i], _lightning_target_offset[i], seg_t)
			_visual_offset[i] = ortho * lightning_wave * (26.0 * _r_ltg[i])
		else:
			_visual_offset[i] = Vector2.ZERO

# Lightning teleport-hop pass (Phase 2) - direct port of Projectile.
# _update_blink/_apply_blink_hop's actual behavior, just with a plain
# linear-scan target lookup instead of ProjectileTargetingBatcher (see the
# _blink_timer/_hops_left field comment for why). Runs AFTER this tick's
# normal movement (mirrors Projectile.gd:1391-1404's own ordering: position
# += velocity*delta, THEN _update_blink) so a hop's teleport distance
# stacks onto the SAME tick's swept segment for _step_hit_test - a hop
# "spends range budget and gets swept for whatever it crosses," same
# real-system design property (Projectile.gd:1401-1403's own comment).
func _step_blink_hops(delta: float):
	for i in range(_highest_active + 1):
		if _alive[i] == 0 or _is_mine[i] == 1:
			continue
		if _hops_left[i] <= 0 or _r_ltg[i] <= _ProjectileScript.LIGHTNING_BLINK_MIN:
			continue
		_blink_timer[i] -= delta
		if _blink_timer[i] > 0.0:
			continue
		_blink_timer[i] = _ProjectileScript.BLINK_INTERVAL
		var max_dist = _ProjectileScript.BLINK_ACQUIRE_RANGE * (1.0 + _r_kin[i])
		var target = _find_nearest_target(_position[i], max_dist, i)
		if target == null:
			continue
		var to_target = target.global_position - _position[i]
		if to_target.length() < 2.0:
			continue
		var hop = to_target * min(1.0, _r_ltg[i])
		_position[i] += hop
		_direction[i] = to_target.normalized()
		_distance_traveled[i] += hop.length()
		if _distance_traveled[i] >= _max_range[i]:
			despawn(i)

# Nearest live, not-yet-handled-by-this-shot target within max_dist - mirrors
# ProjectileTargetingBatcher._resolve_blink's own candidate filter (valid,
# not dead, excludes _handled_targets) but as a plain synchronous scan over
# this pool's own tiny _targets array rather than a batched cross-shot
# query. No friend/foe filtering, matching _step_hit_test's own existing
# simplification (the Test Range only ever has one dummy target regardless
# of side).
func _find_nearest_target(pos: Vector2, max_dist: float, slot_idx: int) -> Node:
	var best: Node = null
	var best_dist = max_dist
	for t in _targets:
		if not is_instance_valid(t) or t.get("is_dead") == true:
			continue
		if _handled_targets[slot_idx].has(t.get_instance_id()):
			continue
		var d = pos.distance_to(t.global_position)
		if d < best_dist:
			best_dist = d
			best = t
	return best

# Part-hitbox damage routing (Phase 11 of the batch-pool full-parity plan,
# 2026-08-10) - real combat never applies damage straight to a target's
# total HP. Every hit (including AoE/biome splash - PartHitbox Area2D
# children sit on the same collision layer/mask a physics query matches,
# so a real Explosion/biome burst lands on THEM too, not the parent
# CharacterBody2D) actually goes through PartHitbox.apply_damage ->
# Mech.apply_part_damage(slot, amount, element), which sends only ~20% to
# global HP and the rest to that specific component's own structural tile
# HP (plus a chance to disable/destroy a priority tile - see Mech.gd's own
# _roll_component_disable). The batch pool has no real per-part collision
# geometry (shots aren't Nodes; building one would be a genuinely bigger
# architectural addition than anything else in this plan, not attempted
# here) - this picks a RANDOM valid slot from the target's own components
# each hit instead, mirroring apply_part_damage's own inner tile pick
# ("still not picky about exactly where the structural HP damage lands"),
# just one level up (which COMPONENT, not just which tile within it).
# Falls back to plain apply_damage for anything that isn't a real Mech
# (has_method gate), same graceful degradation PartHitbox.apply_damage
# itself already uses. Note apply_part_damage's own signature has no
# source/was_reflected/label params at all - real combat already loses
# that context for the global-HP portion of a part-routed hit (its own
# internal apply_damage(amount*0.2, element) call passes neither), so
# dropping them here isn't a new simplification, it matches real behavior.
func _apply_damage_to_target(target: Node, amount: float, element: String, src: Node = null, source_label: String = "Batch Test Shot"):
	if target.has_method("apply_part_damage") and "components" in target and not target.components.is_empty():
		var slots = target.components.keys()
		var slot = slots[randi() % slots.size()]
		target.apply_part_damage(slot, amount, element)
	elif target.has_method("apply_damage"):
		target.apply_damage(amount, element, src, false, source_label)

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
				if t.has_method("apply_damage") or t.has_method("apply_part_damage"):
					var src = _source_mech[i] if is_instance_valid(_source_mech[i]) else null
					_apply_damage_to_target(t, _damage[i], _dominant_synergy_name[i], src, "Batch Test Shot")

				# hit_decay computed BEFORE any hop/pierce decrement below,
				# mirroring Projectile._handle_hit's own ordering exactly
				# (Projectile.gd:1925 runs before the hop/pierce decrements
				# at 1979-1987) - the FIRST hit of a hop/pierce chain gets
				# full-strength Vampiric heal/Explosion AoE, later legs
				# progressively taper toward zero.
				var hit_decay = _compute_hit_decay(i)
				_apply_status_effects(i, t)
				_apply_vampiric_heal(i, hit_decay)
				_apply_explosion_aoe(i, t, hit_decay)
				_apply_biome_triggers(i, t)

				# Poison mine: contact detonates it immediately (see
				# _trigger_poison_mine_detonation's own header) instead of
				# piercing through like a normal shot - consumes the mine
				# outright regardless of pierce/hop state.
				if _is_mine[i] == 1:
					_trigger_poison_mine_detonation(i)
					despawn(i)
					break

				# LIGHTNING re-target: instead of despawning, hop out to the
				# next victim. Each new leg gets the full range budget back
				# and the blink timer is zeroed so the jump happens on the
				# very next tick - mirrors Projectile.gd:1979-1983 exactly.
				if _hops_left[i] > 0:
					_hops_left[i] -= 1
					_distance_traveled[i] = 0.0
					_blink_timer[i] = 0.0
					break

				_pierce_count[i] -= 1
				if _pierce_count[i] <= 0:
					despawn(i)
				break

# Ratio-or-less-than-full-strength-per-hop decay factor (Projectile.gd:
# 1783-1788's own "string of pearls" framing) - full strength (1.0) on a
# shot's first hit, progressively smaller for later legs of a Lightning
# hop chain or later pierces of a Pierce shot. Feeds Vampiric Heal/
# Explosion AoE below so repeated hits from one long-lived shot don't
# apply the same full-strength side-effect over and over for free.
func _compute_hit_decay(i: int) -> float:
	if _hops_max[i] > 0:
		return float(_hops_left[i]) / float(_hops_max[i])
	elif _pierce_count_max[i] > 1:
		return float(_pierce_count[i] - 1) / float(_pierce_count_max[i] - 1)
	return 1.0

# Direct port of Projectile._apply_synergy_status_effects (Projectile.gd:
# 1864-1911) - now includes EXPLOSION's "concussed" proc (previously
# skipped since _r_exp wasn't tracked at all) and reuses the same
# threshold table against Resonator Sync proc_synergies too, exactly like
# the real function's own "sr" parameter/header comment ("a sync-conferred
# burn behaves identically to a real one - just routed through a second,
# non-damage-affecting dict"). Still deliberately excludes anything that
# touches camera/UI (crit floaters, screen shake) - cosmetic, and the Test
# Range dummy doesn't need them for a fair comparison.
func _apply_status_effects(i: int, target: Node):
	if not target.has_method("apply_status"):
		return
	var sr = {
		EnergyPacket.SynergyType.FIRE: _r_fire[i],
		EnergyPacket.SynergyType.ICE: _r_ice[i],
		EnergyPacket.SynergyType.LIGHTNING: _r_ltg[i],
		EnergyPacket.SynergyType.POISON: _r_psn[i],
		EnergyPacket.SynergyType.KINETIC: _r_kin[i],
		EnergyPacket.SynergyType.PIERCE: _r_prc[i],
		EnergyPacket.SynergyType.EXPLOSION: _r_exp[i],
		EnergyPacket.SynergyType.VORTEX: _r_vtx[i],
		EnergyPacket.SynergyType.VAMPIRIC: _r_vamp[i],
	}
	_apply_synergy_status_effects_from_dict(i, target, sr)
	if not _proc_synergies[i].is_empty():
		_apply_synergy_status_effects_from_dict(i, target, _proc_synergies[i])

func _apply_synergy_status_effects_from_dict(i: int, target: Node, sr: Dictionary):
	if sr.get(EnergyPacket.SynergyType.FIRE, 0.0) > 0.1:
		target.apply_status("burning", 3.0 * sr[EnergyPacket.SynergyType.FIRE])
	if sr.get(EnergyPacket.SynergyType.ICE, 0.0) > 0.1:
		target.apply_status("frozen", 3.0 * sr[EnergyPacket.SynergyType.ICE])
	var rl = sr.get(EnergyPacket.SynergyType.LIGHTNING, 0.0)
	if rl > 0.15 and randf() < 0.35 * rl:
		target.apply_status("paralyzed", 0.4 + 0.5 * rl)
	if sr.get(EnergyPacket.SynergyType.POISON, 0.0) > 0.1:
		target.apply_status("poisoned", 4.0 + 3.0 * sr[EnergyPacket.SynergyType.POISON])
	var rk = sr.get(EnergyPacket.SynergyType.KINETIC, 0.0)
	if rk > 0.2:
		target.apply_status("staggered", 0.4 + 0.3 * rk)
		if "external_force" in target:
			target.external_force += _direction[i] * 260.0 * rk
	if sr.get(EnergyPacket.SynergyType.PIERCE, 0.0) > 0.15:
		target.apply_status("rent", 4.0)
	var re = sr.get(EnergyPacket.SynergyType.EXPLOSION, 0.0)
	if re > 0.2 and randf() < 0.5 * re:
		target.apply_status("concussed", 0.35)
	var rv = sr.get(EnergyPacket.SynergyType.VORTEX, 0.0)
	if rv > 0.15:
		if "vortex_drag_point" in target:
			target.vortex_drag_point = _position[i]
		target.apply_status("vortexed", 0.4 + 0.6 * rv)
	var rvm = sr.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0)
	if rvm > 0.1:
		target.apply_status("bleeding", 3.0 + 2.0 * rvm)
		if rvm > 0.5 and randf() < 0.3:
			target.apply_status("immobilized", 0.5)

# Mirrors Projectile.gd:1927-1931 - heals the SHOOTER's HP pool, not the
# hit target, so it's its own function rather than living inside the
# per-target status-effect loop above (the first status effect that
# reaches outside the single target this shot actually hit).
func _apply_vampiric_heal(i: int, hit_decay: float):
	if _r_vamp[i] <= 0.1 or hit_decay <= 0.0:
		return
	var players = EntityCache.get_group("player")
	if players.size() > 0 and is_instance_valid(players[0]) and players[0].has_method("apply_damage"):
		players[0].apply_damage(-_damage[i] * 0.3 * _r_vamp[i] * hit_decay)

# Mirrors Projectile.gd:1933-1935/_trigger_explosion. The real version
# runs a PhysicsShapeQueryParameters2D scene query; this pool has no
# physics-query infrastructure at all, so it reuses the same linear scan
# over its own tiny _targets array _step_hit_test already does - the Test
# Range's target count is always small enough that this is equivalent in
# practice, not a meaningful simplification. No explicit damage element
# passed to apply_damage, matching the real _trigger_explosion call
# exactly (falls back to whatever apply_damage's own default element is -
# Explosion splash bypasses elemental resistance in the real system too).
func _apply_explosion_aoe(i: int, primary_target: Node, hit_decay: float):
	if _r_exp[i] <= 0.1 or hit_decay <= 0.0:
		return
	var ratios_for_radius = {EnergyPacket.SynergyType.EXPLOSION: _r_exp[i], EnergyPacket.SynergyType.KINETIC: _r_kin[i]}
	var radius = _ProjectileScript.explosion_radius_for(ratios_for_radius, _aoe_bonus[i]) * hit_decay
	for t in _targets:
		if not is_instance_valid(t) or t == primary_target or t.get("is_dead") == true:
			continue
		if not t.has_method("apply_damage") and not t.has_method("apply_part_damage"):
			continue
		if t.global_position.distance_to(_position[i]) <= radius:
			_apply_damage_to_target(t, _damage[i] * 0.5 * hit_decay, "RAW")

# Mirrors Projectile._trigger_poison_mine_detonation (Projectile.gd:1547-
# 1624) - themed by whichever non-Poison/Kinetic/RAW synergy is strongest
# in the packet. Reuses the same linear-_targets-scan approach as
# _apply_explosion_aoe above (same reasoning). Guarded by _mine_detonated
# so a mine detonated on contact here never ALSO detonates a second time
# on lifetime/range expiry (see _step_simulate's own expiry-branch call).
func _trigger_poison_mine_detonation(i: int):
	if _mine_detonated[i] == 1:
		return
	_mine_detonated[i] = 1

	var theme = -1
	var theme_ratio = 0.0
	var theme_candidates = {
		EnergyPacket.SynergyType.LIGHTNING: _r_ltg[i], EnergyPacket.SynergyType.VORTEX: _r_vtx[i],
		EnergyPacket.SynergyType.FIRE: _r_fire[i], EnergyPacket.SynergyType.ICE: _r_ice[i],
		EnergyPacket.SynergyType.EXPLOSION: _r_exp[i], EnergyPacket.SynergyType.PIERCE: _r_prc[i],
		EnergyPacket.SynergyType.VAMPIRIC: _r_vamp[i],
	}
	for k in theme_candidates:
		if theme_candidates[k] > theme_ratio:
			theme_ratio = theme_candidates[k]
			theme = k

	var radius = 220.0 * (1.0 + 0.5 * _aoe_bonus[i])
	var burst_damage = _damage[i] * 1.5
	var status_by_theme = {
		EnergyPacket.SynergyType.LIGHTNING: ["paralyzed", 0.6],
		EnergyPacket.SynergyType.VORTEX: ["vortexed", 1.2],
		EnergyPacket.SynergyType.FIRE: ["burning", 5.0],
		EnergyPacket.SynergyType.ICE: ["frozen", 3.0],
	}
	var dmg_mult = 0.6 if theme == EnergyPacket.SynergyType.ICE else 1.0
	# Real _trigger_poison_mine_detonation only ever passes an explicit
	# element for the Lightning theme (Projectile.gd:1580: `col.apply_
	# damage(burst_damage, "LIGHTNING")`) - every other theme's damage call
	# has no element arg at all (RAW default, bypasses resistance).
	var element = "LIGHTNING" if theme == EnergyPacket.SynergyType.LIGHTNING else "RAW"

	for t in _targets:
		if not is_instance_valid(t) or t.get("is_dead") == true:
			continue
		if not t.has_method("apply_damage") and not t.has_method("apply_part_damage"):
			continue
		if t.global_position.distance_to(_position[i]) <= radius:
			_apply_damage_to_target(t, burst_damage * dmg_mult, element)
			if status_by_theme.has(theme) and t.has_method("apply_status"):
				t.apply_status(status_by_theme[theme][0], status_by_theme[theme][1])

# Mirrors Projectile.gd:1937-1965's biome/oil-slick cross-triggers,
# reading EntityCache.get_group("map_generator")/"oil_slick" exactly like
# the real system. The Garage Test Range's own private SubViewport/World2D
# has neither registered (deliberately isolated - see GarageTestRange.gd's
# own header comment: "the private physics world keeps stray test shots
# and their AoE from ever touching the actual battlefield"), so this can
# never actually fire anything observable in the Test Range as currently
# scoped. Ported and verified against a FAKE map/oil-slick stub
# (BatchPoolBiomeTriggerCheck.gd) rather than skipped, per the
# resolved decision to keep "full parity" true in the code even where
# it's not yet visible in this system's only real deployment. Deliberately
# does NOT port the real system's obstacle-destruction sub-case (Fire+
# Forest also queue_frees a directly-hit Obstacle node) - the Test Range
# has no real obstacles registered as targets, so there's nothing for that
# to ever apply to here.
func _apply_biome_triggers(i: int, _target: Node):
	var maps = EntityCache.get_group("map_generator")
	if maps.size() > 0 and is_instance_valid(maps[0]) and maps[0].has_method("get_biome_at_world_pos"):
		var map = maps[0]
		var biome = map.get_biome_at_world_pos(_position[i])
		if _r_ltg[i] > 0.1 and biome == map.BiomeType.WATER:
			_apply_area_burst(i, 400.0, _damage[i] * 2.0, "")
		if _r_fire[i] > 0.1 and biome == map.BiomeType.FOREST:
			_apply_area_burst(i, 200.0, _damage[i] * 1.5, "burning")
	if _r_fire[i] > 0.1:
		for slick in EntityCache.get_group("oil_slick"):
			if is_instance_valid(slick) and slick.has_method("ignite") and "IGNITE_RADIUS" in slick:
				if _position[i].distance_to(slick.global_position) <= slick.IGNITE_RADIUS:
					slick.ignite()

func _apply_area_burst(i: int, radius: float, dmg: float, status_name: String):
	for t in _targets:
		if not is_instance_valid(t) or t.get("is_dead") == true:
			continue
		if not t.has_method("apply_damage") and not t.has_method("apply_part_damage"):
			continue
		if t.global_position.distance_to(_position[i]) <= radius:
			_apply_damage_to_target(t, dmg, "RAW")
			if status_name != "" and t.has_method("apply_status"):
				t.apply_status(status_name, 5.0)

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
	if synergy == EnergyPacket.SynergyType.PIERCE:
		# Pierce as a secondary gets a STATIC glowing core, not an orbiting
		# dot (Phase 10 of the batch-pool full-parity plan, 2026-08-10) -
		# mirrors Projectile.gd's own Pierce-secondary ornament exactly (a
		# fixed white core at zero offset, Projectile.gd:971-979 - not a
		# moving element like every other secondary treatment).
		return {"position": render_pos, "color": Color(1.0, 1.0, 1.0, alpha * 0.8)}
	var angle = elapsed * ECHO_ORBIT_SPEED + phase
	var offset = Vector2(cos(angle), sin(angle)) * ECHO_ORBIT_RADIUS
	var c = EnergyPacket.get_color_for_synergy(synergy) * 1.5
	c.a = alpha
	return {"position": render_pos + offset, "color": c}

# Vortex-dominant 3-orb helix (Phase 10) - mirrors Projectile.gd's own
# Vortex Helix Orbs exactly (3 orbiting orbs, own fixed radius/speed,
# Projectile.gd:1019-1034), which the generic 2-echo mechanism above
# can't reproduce: that trick borrows a shot's OWN secondary synergies'
# otherwise-idle channels, but a shot whose DOMINANT is Vortex has already
# spent its own main+trail channels on itself, leaving no "free channel of
# its own" for secondaries to use. Generalizes the same safety invariant
# one level further: when Vortex is dominant, the shot's normal 2-echo
# rendering is skipped entirely (see _step_render's own gate) so these 3
# FIXED channels (RAW/EXPLOSION/PIERCE main-body, chosen as thematically
# neutral/low-collision-risk picks) are GUARANTEED idle for this slot -
# nothing else will ever write index i in those channels for a Vortex-
# dominant shot, the same "no other live shot touches this index in a
# channel that isn't its own dominant" argument the class-level echo
# comment already relies on, just applied to the dominant shot's own
# bespoke ornament instead of a secondary's.
const VORTEX_HELIX_CHANNELS = [0, 6, 8] # RAW, EXPLOSION, PIERCE main-body slots
const VORTEX_HELIX_SPEED = 15.0
const VORTEX_HELIX_RADIUS = 8.0

static func _compute_vortex_helix_render(render_pos: Vector2, elapsed: float, orb_index: int, alpha: float) -> Dictionary:
	var phase = orb_index * (PI * 2.0 / 3.0)
	var angle = elapsed * VORTEX_HELIX_SPEED + phase
	var offset = Vector2(cos(angle), sin(angle)) * VORTEX_HELIX_RADIUS
	var c = EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.VORTEX)
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

			if syn == EnergyPacket.SynergyType.VORTEX:
				# Vortex-dominant 3-orb helix (Phase 10) instead of the
				# generic 2-echo mechanism - see _compute_vortex_helix_
				# render's own header for why this needs 3 FIXED channels
				# and skips secondary echoes entirely rather than trying to
				# combine both on one slot.
				for orb_index in range(3):
					var orb = _compute_vortex_helix_render(render_pos, _elapsed[i], orb_index, c.a)
					var orb_xform = Transform2D(rot, orb["position"]).scaled(Vector2(_scale[i], _scale[i]) * ECHO_SCALE_MULT)
					_synergy_multimeshes[VORTEX_HELIX_CHANNELS[orb_index]].set_instance_transform_2d(i, orb_xform)
					_synergy_multimeshes[VORTEX_HELIX_CHANNELS[orb_index]].set_instance_color(i, orb["color"])
			else:
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

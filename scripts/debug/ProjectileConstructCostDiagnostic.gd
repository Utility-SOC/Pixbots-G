extends Node

# Diagnostic: reads Mech._perf_shoot_usec / HexTile._perf_projectile_construct_usec
# DIRECTLY (real accumulated microsecond counters incremented by the real
# firing code path) rather than diffing wall-clock frame times across two
# separately-spawned configs - sidesteps the whole class of first-trial JIT/
# shader-warmup contamination that made ProjectileBroadphaseProfileDiagnostic.gd
# and MechPhysicsCostDiagnostic.gd's P/Q/V/W comparison untrustworthy (see
# their own header comments). No differencing, no noise: this just asks
# "of the real recorded shoot cost, what fraction was spent constructing the
# Projectile node (_ready()/_build_visuals()) vs the merge/pattern math
# around it" - both numbers come from the exact same real _shoot()/
# _fire_combined_projectile() calls in this run.
#
# Follow-up to the 2026-07-27 playtest video (34 enemies, 495 live shots,
# 2fps, "shoot" the dominant named per-second cost in FpsCounter's overlay).

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

const MECH_COUNT = 30
const SHOTS_PER_MECH = 20 # 30 x 20 = 600 real fired shots, comparable to the video's ~500 live-shot scenario

var world: Node2D

# Builds one Mech with a deterministic 2-mount torso (same pattern
# TestRangeCheck.gd uses), armed with a synergy-blended packet so
# _build_visuals() exercises its full particle/helix/trail branches - a bare
# RAW packet would understate real construction cost.
func _spawn_armed_mech() -> Node:
	var mech = MechScript.new()
	mech.is_player = false
	world.add_child(mech)
	mech.set_physics_process(false)
	mech.global_position = Vector2(randf_range(-500, 500), randf_range(-500, 500))

	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.RARE)
	torso.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.RARE
	var active: Array[int] = [0, 1]
	core.active_faces = active
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var mount_a = WeaponMountTileScript.new()
	mount_a.rarity = HexTile.Rarity.RARE
	mount_a.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(1, 0), mount_a)
	var mount_b = WeaponMountTileScript.new()
	mount_b.rarity = HexTile.Rarity.RARE
	mount_b.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(0, 1), mount_b)

	mech.equip_component(torso)
	for slot in mech.components.keys().duplicate():
		if slot != HexTile.BodySlot.TORSO:
			mech.unequip_component(slot)
	mech.last_aim_position = mech.global_position + Vector2(600, 0)
	mech._recalculate_grid()
	return mech

func _force_full_charge(mech: Node):
	for data in mech.precalculated_weapons:
		data.mount.current_charge = data.packet.charge_required
		# Blend in a real multi-synergy mix so the fired packet isn't bare
		# RAW - matches a real ornamented shot's _build_visuals() cost.
		data.packet.synergies[EnergyPacket.SynergyType.KINETIC] = data.packet.magnitude * 0.4
		data.packet.synergies[EnergyPacket.SynergyType.FIRE] = data.packet.magnitude * 0.3
		data.packet.synergies[EnergyPacket.SynergyType.VORTEX] = data.packet.magnitude * 0.2

func _run_batch(mechs: Array) -> float:
	Mech._perf_shoot_usec = 0
	for round in range(SHOTS_PER_MECH):
		for mech in mechs:
			_force_full_charge(mech)
			mech._shoot(mech.last_aim_position, true)
	return Mech._perf_shoot_usec / 1000.0

func _fresh_mechs() -> Array:
	var mechs: Array = []
	for i in range(MECH_COUNT):
		mechs.append(_spawn_armed_mech())
	return mechs

func _ready():
	world = Node2D.new()
	add_child(world)

	var probe = _spawn_armed_mech()
	if probe.precalculated_weapons.is_empty():
		push_error("FAIL: setup produced no armed mounts - can't measure real fire cost")
		get_tree().quit(1)
		return
	probe.queue_free()

	# Controlled A/B, each config on its OWN freshly-spawned mech set (no
	# shared consolidation-buffer/live-projectile-count carryover between
	# configs - reusing one mech set sequentially was a real confound: the
	# second config to run inherits whatever saturation state the first one
	# left behind, which changes how much REAL work it does independent of
	# which implementation is faster). Run twice in alternating order to
	# also rule out a simple warmup/order bias.
	Mech._ensure_packet_tax_rust()
	var real_rasterizer = Mech._packet_tax_rasterizer
	if real_rasterizer == null:
		push_error("FAIL: PacketTaxRs not available - can't compare against Rust")
		get_tree().quit(1)
		return

	# Interleaved A/B/A/B/... trials, many of them - the first several are
	# expected to be dominated by JIT/cache/allocator warmup (confirmed this
	# session: a plain 2-trial alternation still showed a strong monotonic
	# decrease regardless of which config ran, 43.73->27.09->21.92->20.39).
	# Only the back half (steady-state) trials are trusted for the verdict;
	# all trials are printed so the warmup curve itself is visible.
	const TOTAL_TRIALS = 10
	const WARMUP_TRIALS = 5 # discarded from the verdict, still printed
	var a_trials: Array = []
	var b_trials: Array = []
	for t in range(TOTAL_TRIALS):
		Mech._packet_tax_rasterizer = null
		var a = _run_batch(_fresh_mechs())
		Mech._packet_tax_rasterizer = real_rasterizer
		var b = _run_batch(_fresh_mechs())
		a_trials.append(a)
		b_trials.append(b)
		print("trial %d:  A=%.2fms  B=%.2fms%s" % [t, a, b, "  (warmup, excluded)" if t < WARMUP_TRIALS else ""])

	var a_steady: Array = a_trials.slice(WARMUP_TRIALS)
	var b_steady: Array = b_trials.slice(WARMUP_TRIALS)
	var a_avg = 0.0
	for v in a_steady: a_avg += v
	a_avg /= a_steady.size()
	var b_avg = 0.0
	for v in b_steady: b_avg += v
	b_avg /= b_steady.size()

	print("")
	print("=== A/B RESULT (%d mechs x %d rounds, %d steady-state trials each after %d warmup trials discarded) ===" % [MECH_COUNT, SHOTS_PER_MECH, a_steady.size(), WARMUP_TRIALS])
	print("A (GDScript-only) steady-state avg: %.2f ms  %s" % [a_avg, a_steady])
	print("B (Rust-batched)  steady-state avg: %.2f ms  %s  (delta vs A: %+.2f, %+.1f%%)" % [b_avg, b_steady, b_avg - a_avg, 100.0 * (b_avg - a_avg) / max(0.001, a_avg)])
	if b_avg < a_avg * 0.95:
		print("VERDICT: Rust batching is a real win here.")
	elif b_avg > a_avg * 1.05:
		print("VERDICT: Rust batching is SLOWER here - FFI/array-marshalling overhead exceeds the saved arithmetic at this batch size (2 mounts/mech). Not worth keeping wired in at this scope.")
	else:
		print("VERDICT: no meaningful difference - a wash.")

	get_tree().quit(0)

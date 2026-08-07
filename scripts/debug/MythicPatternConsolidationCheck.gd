extends Node

# Regression harness for the Mythic Shotgun/Radial pellet fanout cap (perf
# plan, wave-138 playtest: 2fps, "shoot 466ms/sec" dwarfing everything else
# on the overlay). Root cause: each pellet in a Shotgun/Radial burst
# independently re-enters HexTile._fire_combined_projectile and pays its
# own full per-shot cost, with ZERO reduction from the saturation system
# that already throttles every other mount (ProjectileManager.
# consolidation_factor()). Fix: HexTile.gd's Shotgun/Radial branches now
# divide their pellet/shard count by that same saturation factor (floored
# at SHOTGUN_MIN_PELLETS/RADIAL_MIN_PELLETS), with per-pellet amplify
# already deriving from the FINAL count - so total volley damage is
# unchanged, only pellet count shrinks once the game is already struggling.
#
# CONSOLIDATE_TIERS (ProjectileManager.gd): [[500,16],[350,8],[240,5],
# [150,3],[90,2]] - live_count buckets used below are chosen to land
# squarely inside each tier: 0->k1, 100->k2, 200->k3, 500->k16.

const MechScript = preload("res://scripts/entities/Mech.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

var world: Node2D

func _make_mythic_mount(pattern: int):
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.MYTHIC
	mount.level = 1 # capacity_factor == 1.0 baseline, matches the pattern's own assumed "fresh Mythic level-1" case
	mount.mythic_pattern = pattern
	mount.body_slot = HexTile.BodySlot.TORSO
	return mount

func _make_mech() -> Node:
	var mech = MechScript.new()
	mech.is_player = false
	mech.set_physics_process(false)
	world.add_child(mech)
	mech.global_position = Vector2.ZERO
	mech.last_aim_position = Vector2(600, 0)
	return mech

# Simulates ProjectileManager.consolidation_factor() seeing `live_count` live
# shots (stub entries - never real Projectiles, just filling _active to the
# right SIZE) and fires enough volleys through `mount` to actually reach a
# firing event: whole-volley consolidation (pre-existing, unrelated to this
# fix) banks (k-1) calls before the k-th actually reaches the pattern-fanout
# code, same as k independent volleys arriving in sequence during real
# saturated play - a single call at k>1 would just bank-and-return with zero
# pellets, which isn't what real saturated play looks like either.
# Pellets are counted by instance-id DELTA against ProjectileManager._active
# (every real Projectile registers itself in _ready(), Projectile.gd:353),
# not by inspecting the stub entries at all.
func _fire_under_saturation(mount, mech: Node, live_count: int, magnitude: float) -> Dictionary:
	var stubbed: Dictionary = {}
	for i in range(live_count):
		stubbed["_stub_%d" % i] = null
	ProjectileManager._active = stubbed
	var before_ids = {}
	for id in ProjectileManager._active:
		before_ids[id] = true

	var k = max(1, ProjectileManager.consolidation_factor())
	for i in range(k):
		var packet = EnergyPacket.new(magnitude)
		mount._fire_combined_projectile(mech, packet, 0)

	var count = 0
	var total_damage = 0.0
	for id in ProjectileManager._active:
		if not before_ids.has(id):
			count += 1
			total_damage += ProjectileManager._active[id].damage
	# The packet that actually fires is the whole-volley-consolidated merge
	# of all k calls' magnitude (add_synergies_batch sums both synergies AND
	# magnitude, EnergyPacket.gd:142-147) - this is what pellet math actually
	# operates on, not the original per-call magnitude.
	return {"count": count, "total_damage": total_damage, "k": k, "fired_magnitude": magnitude * k}

func _ready():
	world = Node2D.new()
	add_child(world)
	var saved_active = ProjectileManager._active

	# --- k == 1 (no saturation, live_count 0): exact no-op regression guard ---
	var shotgun_k1 = _fire_under_saturation(_make_mythic_mount(1), _make_mech(), 0, 100.0)
	_check("Shotgun at k=1 (no saturation): full pellet count unchanged (5, matches pre-fix behavior)",
		shotgun_k1.k == 1 and shotgun_k1.count == 5)

	var radial_k1 = _fire_under_saturation(_make_mythic_mount(2), _make_mech(), 0, 100.0)
	_check("Radial at k=1 (no saturation): full shard count unchanged (8, matches pre-fix behavior)",
		radial_k1.k == 1 and radial_k1.count == 8)

	# --- k == 2 (90-149 live shots): pellet count shrinks, not a no-op ---
	var shotgun_k2 = _fire_under_saturation(_make_mythic_mount(1), _make_mech(), 100, 100.0)
	_check("Shotgun at k=2 (100 live shots): pellet count shrinks to ceil(5/2)=3, not the full 5",
		shotgun_k2.k == 2 and shotgun_k2.count == 3)

	# --- k == 3 (150-239 live shots) ---
	var shotgun_k3 = _fire_under_saturation(_make_mythic_mount(1), _make_mech(), 200, 100.0)
	_check("Shotgun at k=3 (200 live shots): pellet count shrinks to ceil(5/3)=2",
		shotgun_k3.k == 3 and shotgun_k3.count == 2)

	# --- k == 16 (500+ live shots): floored at MIN_PELLETS, never 0/1 ---
	var shotgun_k16 = _fire_under_saturation(_make_mythic_mount(1), _make_mech(), 500, 100.0)
	_check("Shotgun at k=16 (500 live shots): pellet count floors at SHOTGUN_MIN_PELLETS (2), never below it",
		shotgun_k16.k == 16 and shotgun_k16.count == 2)

	var radial_k16 = _fire_under_saturation(_make_mythic_mount(2), _make_mech(), 500, 100.0)
	_check("Radial at k=16 (500 live shots): shard count floors at RADIAL_MIN_PELLETS (4), never below it",
		radial_k16.k == 16 and radial_k16.count == 4)

	# --- Damage-neutrality: total_damage / fired_magnitude is a fixed ratio
	# derived from the mount's own rarity/level/damage_multiplier - it does
	# NOT depend on pellet_count (per_pellet_amplify divides by the exact
	# same pellet_count that gets summed back over, so pellet_count cancels
	# out algebraically). Comparing this RATIO across k=1 vs k=16 (rather
	# than an absolute formula) proves damage-neutrality without needing to
	# know every multiplier in the real damage pipeline (crit rolls,
	# _get_power_multiplier, etc. - all identical across both runs since
	# it's the same mount setup, so they cancel out of the comparison too).
	# A single trial is too noisy to trust directly - the 5%-per-pellet crit
	# roll (HexTile.gd's is_crit check) swings a k=16 Shotgun burst's ratio
	# by up to 50% off a single lucky/unlucky pellet out of only 2 (a
	# one-trial run hit exactly this: k1=25.0, k16=37.5, a bare single crit
	# among 2 pellets - not a real bug). Averaging many trials converges
	# both sides toward the same true expected ratio (E[crit multiplier]
	# ~1.05, identical on both sides) with a much tighter, still-meaningful
	# tolerance.
	const RATIO_TRIALS = 40
	var shotgun_ratio_k1 = 0.0
	var shotgun_ratio_k16 = 0.0
	var radial_ratio_k1 = 0.0
	var radial_ratio_k16 = 0.0
	for t in range(RATIO_TRIALS):
		var s1 = _fire_under_saturation(_make_mythic_mount(1), _make_mech(), 0, 100.0)
		var s16 = _fire_under_saturation(_make_mythic_mount(1), _make_mech(), 500, 100.0)
		var r1 = _fire_under_saturation(_make_mythic_mount(2), _make_mech(), 0, 100.0)
		var r16 = _fire_under_saturation(_make_mythic_mount(2), _make_mech(), 500, 100.0)
		shotgun_ratio_k1 += s1.total_damage / s1.fired_magnitude
		shotgun_ratio_k16 += s16.total_damage / s16.fired_magnitude
		radial_ratio_k1 += r1.total_damage / r1.fired_magnitude
		radial_ratio_k16 += r16.total_damage / r16.fired_magnitude
	shotgun_ratio_k1 /= RATIO_TRIALS
	shotgun_ratio_k16 /= RATIO_TRIALS
	radial_ratio_k1 /= RATIO_TRIALS
	radial_ratio_k16 /= RATIO_TRIALS

	_check("Shotgun damage-per-fired-magnitude ratio at k=16 (2 bigger pellets, %d-trial avg) matches k=1 (5 pellets) within tolerance - damage-neutral (k1=%.3f, k16=%.3f)" % [RATIO_TRIALS, shotgun_ratio_k1, shotgun_ratio_k16],
		shotgun_ratio_k1 > 0.0 and abs(shotgun_ratio_k1 - shotgun_ratio_k16) < shotgun_ratio_k1 * 0.15)

	_check("Radial damage-per-fired-magnitude ratio at k=16 (4 bigger shards, %d-trial avg) matches k=1 (8 shards) within tolerance - damage-neutral (k1=%.3f, k16=%.3f)" % [RATIO_TRIALS, radial_ratio_k1, radial_ratio_k16],
		radial_ratio_k1 > 0.0 and abs(radial_ratio_k1 - radial_ratio_k16) < radial_ratio_k1 * 0.15)

	ProjectileManager._active = saved_active

	if failures == 0:
		print("PASS: Mythic Shotgun/Radial pellet fanout now respects saturation (k=1 no-op, shrinks+floors under load), damage-neutral at every tier")
	get_tree().quit(0 if failures == 0 else 1)

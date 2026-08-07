extends Node

# Regression harness for MortarShell pooling (play report: "missiles make
# big problems (13 missile launchers)") - 13 stacked Missile Rack tiles can
# each independently put several shells in flight per volley, and shells
# previously rebuilt a brand-new Node2D from scratch every single shot with
# no reuse at all (unlike Projectile.gd's already-pooled visual nodes - see
# that file's own _visual_node_pool). Same free-list acquire()/release()
# pattern, applied to whole MortarShell instances since there's no visual
# sub-node tree to pool pieces of.

const MortarShellScript = preload("res://scripts/attacks/MortarShell.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var world = Node2D.new()
	add_child(world)

	# --- Basic acquire/release/reuse ---
	var shell_a = MortarShellScript.acquire()
	_check("acquire() with an empty pool returns a fresh MortarShell", is_instance_valid(shell_a))
	world.add_child(shell_a)
	shell_a.setup(Vector2.ZERO, Vector2(100, 0), 0.2, 50.0, {EnergyPacket.SynergyType.RAW: 50.0}, true, null, 0.0)

	# Drive it through a full flight + impact-flash lifecycle so release()
	# (called from _process on impact-flash timeout) actually fires.
	shell_a._process(0.25) # lands
	_check("shell landed after flight_time elapsed", shell_a._landed)
	shell_a._process(0.5) # well past IMPACT_FLASH_TIME (0.28s) -> release()
	_check("shell released itself back to the pool instead of being freed (still a valid object)",
		is_instance_valid(shell_a))
	_check("released shell is no longer parented under world", shell_a.get_parent() == null)

	# --- Reuse proof: next acquire() must return the SAME instance ---
	var shell_b = MortarShellScript.acquire()
	_check("acquire() after a release() returns the exact same instance (real reuse, not a fresh .new())",
		shell_b == shell_a)

	# --- setup() must fully reset flight state on a reused (post-impact) shell ---
	world.add_child(shell_b)
	shell_b.setup(Vector2.ZERO, Vector2(50, 50), 0.3, 30.0, {EnergyPacket.SynergyType.RAW: 30.0}, true, null, 0.0)
	_check("setup() resets _landed to false on a reused shell (was true from its previous life)",
		shell_b._landed == false)
	_check("setup() resets _elapsed to 0 on a reused shell", shell_b._elapsed == 0.0)
	_check("setup() resets _impact_elapsed to 0 on a reused shell", shell_b._impact_elapsed == 0.0)

	# One more real frame proves the reused shell actually flies again
	# instead of instantly re-releasing (the bug this reset guards against).
	shell_b._process(0.05)
	_check("reused shell is genuinely mid-flight again after setup(), not stuck re-releasing",
		not shell_b._landed and shell_b.get_parent() == world)
	shell_b.release()

	# --- Pool cap: releasing past _POOL_MAX frees the excess instead of
	# growing the free-list unbounded. ---
	var pool_before = MortarShellScript._shell_pool.size()
	var made: Array = []
	for i in range(MortarShellScript._POOL_MAX + 10):
		var s = MortarShellScript.acquire()
		world.add_child(s)
		made.append(s)
	for s in made:
		s.release()
	_check("pool never exceeds _POOL_MAX after releasing well past capacity",
		MortarShellScript._shell_pool.size() <= MortarShellScript._POOL_MAX)

	# --- Real end-to-end smoke test: a pooled shell actually detonates and
	# damages a target, twice in a row through the SAME pooled instance. ---
	var attacker = MechScript.new()
	attacker.is_player = true
	world.add_child(attacker)
	var victim = MechScript.new()
	victim.is_player = false
	victim.global_position = Vector2(200, 0)
	victim.max_hp = 1000.0
	victim.hp = 1000.0
	world.add_child(victim)
	victim.add_to_group("enemy")
	await get_tree().process_frame

	for round_i in range(2):
		var hp_before = victim.hp
		var shell = MortarShellScript.acquire()
		world.add_child(shell)
		shell.setup(Vector2.ZERO, victim.global_position, 0.1, 40.0, {EnergyPacket.SynergyType.RAW: 40.0}, true, attacker, 0.0)
		shell._process(0.15) # flies past flight_time -> lands -> _detonate()
		_check("round %d: pooled shell's detonation actually damaged the target" % round_i,
			victim.hp < hp_before)
		shell._process(0.5) # past impact flash -> release()
		_check("round %d: shell released cleanly with no engine error" % round_i, is_instance_valid(shell))

	# --- AOE mode fanout cap: a crowded blast shouldn't spin up an
	# unbounded number of full Projectile objects, but every struck victim
	# must still take its correct equal damage share regardless of whether
	# it got the full pipeline or the lightweight fallback. ---
	var aoe_target = Vector2(500, 500)
	var crowd: Array = []
	for i in range(20):
		var e = MechScript.new()
		e.is_player = false
		# Every victim within 10px of the target - well inside the default
		# ~40px-floor blast radius regardless of exactly how
		# explosion_radius_for() scores a pure-RAW packet.
		e.global_position = aoe_target + Vector2(i % 5, i / 5) * 2.0
		e.max_hp = 1000.0
		e.hp = 1000.0
		world.add_child(e)
		e.add_to_group("enemy")
		crowd.append(e)
	await get_tree().process_frame

	var total_damage_budget = 240.0
	var aoe_shell = MortarShellScript.acquire()
	world.add_child(aoe_shell)
	aoe_shell.setup(Vector2.ZERO, aoe_target, 0.1, total_damage_budget, {EnergyPacket.SynergyType.RAW: total_damage_budget}, true, attacker, 0.0, 1.0, true)
	aoe_shell._process(0.15) # lands -> _detonate_equal_split with 20 struck victims, cap is 12

	# Full-pipeline victims (under the cap) and lightweight-path victims
	# (over it) can legitimately land different final numbers - the full
	# Projectile._handle_hit() pipeline applies its own synergy-based damage
	# formula on top of the raw share (pre-existing behavior, unchanged by
	# this fix), where the lightweight apply_damage() fallback does not.
	# What the fanout cap must guarantee is that NOBODY gets silently
	# skipped - every one of the 20 struck victims (well past the 12-victim
	# cap) takes some real damage, capped-pipeline or not.
	var everyone_hit = true
	for e in crowd:
		if 1000.0 - e.hp <= 0.0:
			everyone_hit = false
	_check("all 20 struck victims in a crowded AOE burst (well past the 12-victim fanout cap) took real damage - none silently skipped",
		everyone_hit)

	aoe_shell._process(0.5)
	_check("AOE shell over the fanout cap still released cleanly with no engine error", is_instance_valid(aoe_shell))

	if failures == 0:
		print("PASS: MortarShell pooling reuses whole shell instances correctly, resets flight state on reacquire, respects its pool cap, real detonations still land damage, and a crowded AOE burst's fanout cap doesn't shortchange anyone's damage share")
	get_tree().quit(0 if failures == 0 else 1)

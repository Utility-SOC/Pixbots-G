extends Node

# Regression check for SquadTactics: wave-gated plan pool, anti-repeat/outcome
# weighting, lead aiming, flank/pin/cover role assignment with split sides,
# staging that releases on first contact, and per-plan outcome stats.

const Tactics = preload("res://scripts/ai/SquadTactics.gd")
const DirectorScript = preload("res://scripts/ai/SquadDirector.gd")

class FakeMech extends Node2D:
	var target: Node2D = null
	var combat_role: String = "brawler"
	var base_speed: float = 100.0
	var engagement_distance: float = 250.0
	var is_amphibious: bool = false
	var tactic_goal: Vector2 = Vector2.ZERO
	var tactic_goal_active: bool = false
	var tactic_path_clear: bool = false
	var tactic_hold: bool = false
	var tactic_label: String = ""

class FakeSquad extends Node:
	var members: Array = []
	var first_engagement_time: float = -1.0
	var total_damage_taken: float = 0.0
	var total_damage_dealt: float = 0.0
	var hits_landed: int = 0
	var initial_members: int = 0
	var active_members: int = 0
	func get_center_position() -> Vector2:
		var c = Vector2.ZERO
		for m in members:
			c += m.global_position
		return c / max(1, members.size())

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _mk(squad: FakeSquad, player: Node2D, role: String, speed: float, pos: Vector2) -> FakeMech:
	var m = FakeMech.new()
	m.combat_role = role
	m.base_speed = speed
	m.target = player
	squad.add_child(m)
	m.global_position = pos
	squad.members.append(m)
	squad.initial_members += 1
	squad.active_members += 1
	return m

func _run(t, squad: FakeSquad, secs: float):
	var steps = int(secs / 0.05)
	for i in range(steps):
		t.update(squad, 0.05)

func _ready():
	# --- plan pool is wave-gated
	_check("wave 0 only swarm", Tactics.available_plans(0) == ["swarm"])
	_check("wave 6 has pincer, not encircle", Tactics.available_plans(6).has("pincer") and not Tactics.available_plans(6).has("encircle"))
	_check("wave 20 has all plans", Tactics.available_plans(20).size() == Tactics.PLANS.size())

	# --- selection: anti-repeat memory and outcome feedback
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var base_count = 0
	var damped_count = 0
	for i in range(600):
		if Tactics.choose_plan(20, 0.0, [], {}, "", rng) == "pincer":
			base_count += 1
		if Tactics.choose_plan(20, 0.0, ["pincer", "pincer", "pincer"], {}, "", rng) == "pincer":
			damped_count += 1
	_check("recent repeats damp a plan (%d -> %d)" % [base_count, damped_count], damped_count < base_count * 0.6)
	var good = {"encircle": {"n": 10, "mean": 200.0}, "pincer": {"n": 10, "mean": 20.0}}
	var enc = 0
	var pin = 0
	for i in range(600):
		var pick = Tactics.choose_plan(20, 0.0, [], good, "", rng)
		if pick == "encircle": enc += 1
		if pick == "pincer": pin += 1
	_check("outcome stats favour winners (%d vs %d)" % [enc, pin], enc > pin * 0.8 * (0.8 / 1.2) and pin < base_count)
	_check("exclude honoured", Tactics.choose_plan(20, 0.0, [], {}, "swarm", rng) != "swarm")
	var swarm_hi = 0
	var swarm_lo = 0
	for i in range(600):
		if Tactics.choose_plan(20, 4.0, [], {}, "", rng) == "swarm": swarm_hi += 1
		if Tactics.choose_plan(20, 0.0, [], {}, "", rng) == "swarm": swarm_lo += 1
	_check("pressure shifts away from plain swarm (%d < %d)" % [swarm_hi, swarm_lo], swarm_hi < swarm_lo)

	# --- lead aiming
	var player = Node2D.new()
	add_child(player)
	var sq = FakeSquad.new()
	add_child(sq)
	var t = Tactics.new()
	t.set_plan("swarm")
	t.lead_skill = 1.0
	sq.members = []
	_mk(sq, player, "sniper", 100.0, Vector2(800, 0))
	player.global_position = Vector2.ZERO
	t.update(sq, 0.05)
	_check("static player: no lead", t.lead_point(Vector2.ZERO, 500.0) == Vector2.ZERO)
	for i in range(80):
		player.global_position += Vector2(10, 0) # 200 px/s
		t.update(sq, 0.05)
	var lp = t.lead_point(player.global_position, 500.0)
	_check("steady runner is led ahead (%.0f)" % (lp.x - player.global_position.x), lp.x - player.global_position.x > 60.0)
	var t2 = Tactics.new()
	t2.set_plan("swarm")
	t2.lead_skill = 1.0
	player.global_position = Vector2.ZERO
	t2.update(sq, 0.05)
	var dirn = 1.0
	for i in range(200):
		if i % 4 == 0:
			dirn = -dirn
		player.global_position += Vector2(10 * dirn, 0)
		t2.update(sq, 0.05)
	_check("jinking player earns less lead", t2._predictability < t._predictability)

	# --- pincer: flankers split both sides, backline covers, others pin
	player.global_position = Vector2(0, 0)
	var sq2 = FakeSquad.new()
	add_child(sq2)
	var scout_a = _mk(sq2, player, "scout", 220.0, Vector2(900, 100))
	var scout_b = _mk(sq2, player, "diver", 200.0, Vector2(900, -100))
	var brawl = _mk(sq2, player, "brawler", 130.0, Vector2(950, 0))
	var brawl2 = _mk(sq2, player, "brawler", 128.0, Vector2(950, 40))
	var snip = _mk(sq2, player, "sniper", 100.0, Vector2(1000, 0))
	var tp = Tactics.new()
	tp.set_plan("pincer")
	sq2.first_engagement_time = 1.0
	_run(tp, sq2, 0.6)
	_check("scouts flank", scout_a.tactic_label == "FLANK" and scout_b.tactic_label == "FLANK")
	_check("flankers have goals", scout_a.tactic_goal_active and scout_b.tactic_goal_active)
	_check("split flanks land on opposite sides", sign(scout_a.tactic_goal.y) != sign(scout_b.tactic_goal.y))
	_check("brawlers pin, sniper covers", brawl.tactic_label == "PIN" and snip.tactic_label == "COVER" and not snip.tactic_goal_active)
	var d = scout_a.tactic_goal.length()
	_check("flank goal sits at engagement standoff (%.0f)" % d, d > 150.0 and d < 500.0)

	# --- staging releases on first contact
	var sq3 = FakeSquad.new()
	add_child(sq3)
	var s1 = _mk(sq3, player, "scout", 200.0, Vector2(1400, 0))
	var s2 = _mk(sq3, player, "brawler", 130.0, Vector2(1450, 30))
	var ts = Tactics.new()
	ts.set_plan("synchronized_strike")
	_run(ts, sq3, 0.6)
	_check("staging holds members at a ring", s1.tactic_label == "STAGE" and s1.tactic_goal_active and s1.tactic_goal.length() > 500.0)
	sq3.first_engagement_time = 2.0
	_run(ts, sq3, 0.6)
	_check("contact releases staging", s1.tactic_label != "STAGE" and not s2.tactic_hold)

	# --- outcome stats via the director
	var director = DirectorScript.new()
	var fake = Squad.new()
	fake.tactics = Tactics.new()
	fake.tactics.set_plan("pincer")
	fake.tactics.set_plan("swarm")
	director.record_tactic_results(fake, 150.0)
	director.record_tactic_results(fake, 50.0)
	_check("both plans credited", director.tactic_stats.has("pincer") and director.tactic_stats.has("swarm") and int(director.tactic_stats["pincer"].n) == 2)
	_check("mean moves toward new sample", float(director.tactic_stats["pincer"].mean) < 150.0 and float(director.tactic_stats["pincer"].mean) > 50.0)

	print("tactics check done, failures=%d" % failures)
	get_tree().quit(failures)

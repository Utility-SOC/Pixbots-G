extends Node

# Regression check for SquadTactics: wave-gated plan pool, anti-repeat/outcome
# weighting, lead aiming, flank/pin/cover role assignment with split sides,
# staging that releases on first contact, and the evolvable tactic genome
# (bounded mutation, breeding/culling, persistence, director credit).

const Tactics = preload("res://scripts/ai/SquadTactics.gd")
const Genome = preload("res://scripts/ai/TacticGenome.gd")
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

	# --- selection: anti-repeat memory and outcome feedback (founding pool)
	var rng = RandomNumberGenerator.new()
	rng.seed = 7
	var pool = Genome.seed_pool()
	var picks = 0
	var base_count = 0
	var damped_count = 0
	for i in range(600):
		if Genome.choose(20, 0.0, [], pool, "", rng) == "pincer":
			base_count += 1
		if Genome.choose(20, 0.0, ["pincer", "pincer", "pincer"], pool, "", rng) == "pincer":
			damped_count += 1
	_check("recent repeats damp a plan (%d -> %d)" % [base_count, damped_count], damped_count < base_count * 0.6)
	var good = Genome.seed_pool({"encircle": {"n": 10, "mean": 200.0}, "pincer": {"n": 10, "mean": 20.0}})
	var enc = 0
	var pin = 0
	for i in range(600):
		var pick = Genome.choose(20, 0.0, [], good, "", rng)
		if pick == "encircle": enc += 1
		if pick == "pincer": pin += 1
	_check("outcome stats favour winners (%d vs %d)" % [enc, pin], enc > pin * 0.8 * (0.8 / 1.2) and pin < base_count)
	_check("exclude honoured", Genome.choose(20, 0.0, [], pool, "swarm", rng) != "swarm")
	var swarm_hi = 0
	var swarm_lo = 0
	for i in range(600):
		if Genome.choose(20, 4.0, [], pool, "", rng) == "swarm": swarm_hi += 1
		if Genome.choose(20, 0.0, [], pool, "", rng) == "swarm": swarm_lo += 1
	_check("pressure shifts away from plain swarm (%d < %d)" % [swarm_hi, swarm_lo], swarm_hi < swarm_lo)
	_check("wave 0 picks only swarm", Genome.choose(0, 0.0, [], pool, "", rng) == "swarm")
	_check("wave gating holds for the pool", Genome.available(pool, 6).size() == Tactics.available_plans(6).size())

	# --- genome: mutation is bounded, valid, and actually different
	var parent = Genome.seed_genome("pincer")
	var bounded = true
	var differs = true
	var g = parent
	for i in range(300):
		var child = Genome.mutate(g, i + 1, rng, float(i % 5))
		var cfg = Genome.cfg_of(child)
		for k in Genome.GENES:
			if child["params"].has(k):
				var spec = Genome.GENES[k]
				if child["params"][k] < spec["min"] - 0.0001 or child["params"][k] > spec["max"] + 0.0001:
					bounded = false
		if child["params"] == g["params"]:
			differs = false
		if child["base"] != "pincer" or int(child["gen"]) != int(g["gen"]) + 1 or child["parent"] != g["id"]:
			bounded = false
		g = child if i % 3 == 0 else parent
	_check("300 mutations stay in bounds with lineage", bounded)
	_check("every mutation changes something", differs)
	var swarm_child = Genome.mutate(Genome.seed_genome("swarm"), 1, rng, 0.0)
	_check("swarm can still mutate", not swarm_child["params"].is_empty())
	var cfgx = Genome.cfg_of({"base": "pincer", "params": {"arc": 2.0, "stage": true}})
	_check("params overlay archetype defaults", cfgx["arc"] == 2.0 and cfgx["stage"] == true and cfgx["split"] == true)

	# --- genome: breeding and culling through evolve()
	var ep = Genome.seed_pool()
	for i in range(3):
		Genome.record(ep, "pincer", 140.0)
	var born = false
	for i in range(40):
		var res = Genome.evolve(ep, "pincer", 100 + i, rng, 2.0)
		if not res["born"].is_empty():
			born = true
			break
	_check("proven winner breeds a mutant", born)
	var fam = 0
	for id in ep:
		if ep[id]["base"] == "pincer": fam += 1
	for i in range(80):
		Genome.evolve(ep, "pincer", 200 + i, rng, 2.0)
	var fam2 = 0
	for id in ep:
		if ep[id]["base"] == "pincer": fam2 += 1
	_check("family capped at %d (was %d, now %d)" % [Genome.MAX_PER_BASE, fam, fam2], fam2 <= Genome.MAX_PER_BASE)
	var cp = Genome.seed_pool()
	cp["pincer.9"] = Genome.mutate(cp["pincer"], 9, rng, 0.0)
	for i in range(5):
		Genome.record(cp, "pincer.9", 20.0)
	var res2 = Genome.evolve(cp, "pincer.9", 10, rng, 0.0)
	_check("proven loser is culled", res2["culled"].has("pincer.9") and not cp.has("pincer.9"))
	var losers = Genome.seed_pool()
	for i in range(6):
		Genome.record(losers, "swarm", 10.0)
	Genome.evolve(losers, "swarm", 11, rng, 0.0)
	_check("last genome of an archetype is never culled", losers.has("swarm"))
	var np = Genome.seed_pool()
	np["pincer.3"] = Genome.mutate(np["pincer"], 3, rng, 0.0)
	var seen_mut = 0
	for i in range(400):
		if Genome.choose(20, 0.0, [], np, "", rng) == "pincer.3": seen_mut += 1
	_check("untested mutants get trials (%d)" % seen_mut, seen_mut > 10)

	# --- genome: persistence round trip + hostile data
	var saved = JSON.parse_string(JSON.stringify(np))
	var loaded = Genome.sanitize(saved)
	_check("pool survives JSON round trip", loaded.has("pincer.3") and loaded["pincer.3"]["params"] == np["pincer.3"]["params"] and loaded["pincer.3"]["parent"] == "pincer")
	var hostile = Genome.sanitize({"x": {"base": "nonsense"}, "y": {"base": "pincer", "params": {"arc": 99.0, "bogus": 1.0, "split": "yes"}}, "z": 5})
	_check("hostile data dropped/clamped", not hostile.has("x") and not hostile.has("z") and hostile["y"]["params"]["arc"] <= Genome.GENES["arc"]["max"] and not hostile["y"]["params"].has("bogus") and not hostile["y"]["params"].has("split"))
	var partial = Genome.sanitize({"swarm": Genome.seed_genome("swarm")})
	Genome.ensure_archetypes(partial)
	_check("missing archetypes are restored", partial.size() == Tactics.PLANS.size())

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
	_check("static player: no lead", t.lead_point(Vector2(800, 0), Vector2.ZERO, 500.0) == Vector2.ZERO)
	for i in range(80):
		player.global_position += Vector2(10, 0) # 200 px/s
		t.update(sq, 0.05)
	var lp = t.lead_point(player.global_position + Vector2(-500, 0), player.global_position, 500.0)
	_check("steady runner is led ahead (%.0f)" % (lp.x - player.global_position.x), lp.x - player.global_position.x > 60.0)
	# exact intercept: a slow shot fired at a perpendicular runner must land on the runner
	var tx = Tactics.new()
	tx.lead_skill = 1.0
	tx._player_vel = Vector2(0, 200)
	var shooter = Vector2(-500, 0)
	var tpos = Vector2.ZERO
	for spd in [500.0, 1700.0]:
		var aim = tx.lead_point(shooter, tpos, spd)
		var flight = (aim - shooter).length() / spd
		var miss = (tpos + tx._player_vel * flight).distance_to(aim)
		_check("intercept at speed %.0f lands on target (miss %.1f px)" % [spd, miss], miss < 3.0)
	_check("faster shot needs less lead", tx.lead_point(shooter, tpos, 1700.0).length() < tx.lead_point(shooter, tpos, 500.0).length())
	tx._player_vel = Vector2(0, 900)
	_check("target outrunning the shot still gets a bounded lead", tx.lead_point(shooter, tpos, 500.0).length() <= Tactics.MAX_LEAD_DIST + 0.1)
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
	_check("both genomes credited", int(director.tactic_pool["pincer"].n) == 2 and int(director.tactic_pool["swarm"].n) == 2)
	_check("mean moves toward new sample", float(director.tactic_pool["pincer"].mean) < 150.0 and float(director.tactic_pool["pincer"].mean) > 50.0)
	var mut = Genome.mutate(director.tactic_pool["pincer"], 77, rng, 1.0)
	director.tactic_pool[mut["id"]] = mut
	var ft = Tactics.new()
	ft.set_genome(mut)
	_check("squad runs the genome's config", ft.genome_id == mut["id"] and ft.plan_name == "pincer" and ft.cfg["arc"] == Genome.cfg_of(mut)["arc"])

	print("tactics check done, failures=%d" % failures)
	get_tree().quit(failures)

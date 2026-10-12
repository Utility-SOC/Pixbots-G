extends Node

# Bot League: the simulation is deterministic and terminates; stronger gear wins nearly always; element counters matter; Lightning
# chains, Vampiric heals, Ice slows; a season plays out to one champion; wagers pay by the odds and lose their stake when wrong.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _team(seed_v: int, tier: int) -> Array:
	var r = RandomNumberGenerator.new()
	r.seed = seed_v
	return BotLeagueSim.make_team(r, tier)

func _unit(el: int, shield_el: int, dps: float = 40.0, hp: float = 400.0, shield: float = 300.0, role: String = "brawler") -> Dictionary:
	return {"role": role, "max_hp": hp, "max_shield": shield, "speed": 100.0, "range": 200.0, "dps": dps, "mix": {el: 1.0}, "shield_el": shield_el}

func _duel(a: Dictionary, b: Dictionary, seconds: float = 10.0) -> BotLeagueSim:
	var sim = BotLeagueSim.new()
	sim.setup([a], [b], 3, Vector2(300, 200))
	var t = 0.0
	while t < seconds and sim.winner() == 0:
		sim.step(0.05)
		t += 0.05
	return sim

func _ready():
	var E = BotLeagueSim.E
	var a = _team(1, 3)
	var b = _team(2, 3)
	var s1 = BotLeagueSim.new()
	s1.setup(a, b, 9)
	var w1 = s1.run_to_end()
	var s2 = BotLeagueSim.new()
	s2.setup(a, b, 9)
	var w2 = s2.run_to_end()
	_check("a match ends (%d) in under the time limit plus a step" % w1, w1 != 0 and s1.time <= BotLeagueSim.TIME_LIMIT + 0.2)
	_check("the simulation is deterministic (same result, same time, same hp)", w1 == w2 and is_equal_approx(s1.time, s2.time) and is_equal_approx(s1._hp_fraction(0), s2._hp_fraction(0)))
	_check("teams have five units each with the role's numbers", a.size() == BotLeagueSim.TEAM_SIZE and a[0]["max_hp"] > 0.0)
	var strong_wins = 0
	for i in range(30):
		var sim = BotLeagueSim.new()
		sim.setup(_team(100 + i, 5), _team(200 + i, 1), 50 + i)
		if sim.run_to_end() == 1:
			strong_wins += 1
	_check("tier 5 beats tier 1 almost always (%d of 30)" % strong_wins, strong_wins >= 28)
	var even = 0
	for i in range(40):
		var sim2 = BotLeagueSim.new()
		sim2.setup(_team(300 + i, 3), _team(400 + i, 3), 70 + i)
		if sim2.run_to_end() == 1:
			even += 1
	_check("equal tiers are a contest (%d of 40 for side A)" % even, even >= 8 and even <= 32)
	_check("rating and odds agree: the stronger team is favoured", BotLeagueSim.odds(_team(1, 5), _team(2, 1)) > 0.8 and absf(BotLeagueSim.odds(a, a) - 0.5) < 0.001)

	var vs_ice = _duel(_unit(E.FIRE, E.KINETIC, 40.0, 5000.0, 400.0), _unit(E.KINETIC, E.ICE, 1.0, 5000.0, 400.0), 3.0)
	var vs_other = _duel(_unit(E.FIRE, E.KINETIC, 40.0, 5000.0, 400.0), _unit(E.KINETIC, E.POISON, 1.0, 5000.0, 400.0), 3.0)
	_check("a counter doubles the damage to a shield (%.0f vs %.0f left)" % [vs_ice.units[1]["shield"], vs_other.units[1]["shield"]], vs_ice.units[1]["shield"] < vs_other.units[1]["shield"] - 20.0)
	var lt = _duel(_unit(E.LIGHTNING, E.KINETIC, 40.0, 5000.0, 0.0), _unit(E.KINETIC, E.KINETIC, 1.0, 5000.0, 400.0), 3.0)
	var nl = _duel(_unit(E.PIERCE, E.KINETIC, 40.0, 5000.0, 0.0), _unit(E.KINETIC, E.KINETIC, 1.0, 5000.0, 400.0), 3.0)
	_check("Lightning hits a shield harder than a plain hit would (x1.5 vs Pierce's half)", lt.units[1]["shield"] < nl.units[1]["shield"])
	var vsim = BotLeagueSim.new()
	vsim.setup([_unit(E.VAMPIRIC, E.KINETIC, 60.0, 5000.0, 100.0)], [_unit(E.KINETIC, E.KINETIC, 1.0, 5000.0, 400.0)], 3, Vector2(300, 200))
	vsim.units[0]["hp"] = 1000.0
	for i in range(60):
		vsim.step(0.05)
	_check("Vampiric heals its owner (%.0f from 1000)" % vsim.units[0]["hp"], vsim.units[0]["hp"] > 1000.0)
	var isim = BotLeagueSim.new()
	isim.setup([_unit(E.ICE, E.KINETIC, 40.0, 5000.0, 400.0)], [_unit(E.KINETIC, E.KINETIC, 1.0, 5000.0, 400.0)], 3, Vector2(300, 200))
	for i in range(14):
		isim.step(0.05)
	_check("Ice slows its target", isim.units[1]["slow_t"] > 0.0)

	var league = BotLeague.new(77)
	_check("a season has eight teams and four quarter-finals", league.teams.size() == 8 and league.rounds[0].size() == 4)
	var guard = 0
	while league.champion < 0 and guard < 20:
		league.quick_sim()
		guard += 1
	_check("a season ends with a champion after seven matches (%d played)" % league.history.size(), league.champion >= 0 and league.history.size() == 7)
	_check("round names run quarter, semi, final", league.history[0]["round"] == "Quarter-final" and league.history[4]["round"] == "Semi-final" and league.history[6]["round"] == "Final")

	var lg = BotLeague.new(5)
	var m = lg.current_match()
	var favourite = 0 if lg.odds_a() >= 0.5 else 1
	_check("longer odds pay more", lg.payout_for(1 - favourite, 100) > lg.payout_for(favourite, 100) and lg.payout_for(favourite, 100) >= 110)
	_check("a wager needs credits", not lg.place_wager(0, 1000) and not lg.place_wager(0, 0) and lg.place_wager(0, 50))
	var before = lg.credits
	var winner_idx = m["a"]
	lg.report(1)
	_check("a winning wager pays (%d -> %d)" % [before, lg.credits], lg.credits > before and lg.last_wager_delta > 0)
	var lg2 = BotLeague.new(5)
	lg2.place_wager(0, 50)
	lg2.report(2)
	_check("a losing wager costs the stake", lg2.credits == BotLeague.START_CREDITS - 50 and lg2.last_wager_delta == -50)
	print("BotLeagueCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

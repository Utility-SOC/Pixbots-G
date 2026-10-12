class_name BotLeague
extends RefCounted

# One Bot League season: eight named teams of rising gear tiers in a single-elimination bracket (quarters, semis, final), played
# one match at a time by BotLeagueSim. Holds the bracket, the odds for the next match and the credits a spectator can wager.

const TEAM_NAMES = ["Rust Bucket Rangers", "Capacitor Kings", "The Hex Hounds", "Gridlock", "Amplifier Anonymous", "Short Circuit Society",
	"Splitter Cell", "The Overclockers", "Phase Shift", "Nine Tile Nobodies", "Kilowatt Kittens", "Static Cling", "Heat Sink Heroes", "Zero Point"]
const ROUND_NAMES = ["Quarter-final", "Semi-final", "Final"]
const START_CREDITS = 100
const PAYOUT = 1.9 # a winning wager returns the stake times this, scaled by how unlikely the pick was (see payout_for)

var season_seed: int = 0
var teams: Array = [] # [{name, tier, units}]
var rounds: Array = [] # per round: Array of {a, b, winner} (team indexes)
var round_index: int = 0
var match_index: int = 0
var champion: int = -1
var credits: int = START_CREDITS
var history: Array = [] # played matches, newest last

func _init(p_seed: int = 0):
	season_seed = p_seed if p_seed != 0 else int(Time.get_unix_time_from_system())
	var rng = RandomNumberGenerator.new()
	rng.seed = season_seed
	var names = TEAM_NAMES.duplicate()
	for i in range(names.size() - 1, 0, -1):
		var j = rng.randi() % (i + 1)
		var tmp = names[i]
		names[i] = names[j]
		names[j] = tmp
	for i in range(8):
		var tier = 1 + (i * 5) / 8 + (1 if rng.randf() < 0.3 else 0)
		tier = clampi(tier, 1, 5)
		teams.append({"name": names[i], "tier": tier, "units": BotLeagueSim.make_team(rng, tier)})
	var first: Array = []
	for i in range(4):
		first.append({"a": i, "b": 7 - i, "winner": -1}) # seeded so the strongest meet late
	rounds.append(first)

func current_match() -> Dictionary:
	if champion >= 0 or round_index >= rounds.size():
		return {}
	return rounds[round_index][match_index]

func round_name() -> String:
	return ROUND_NAMES[mini(round_index, ROUND_NAMES.size() - 1)]

# Chance that team A wins the current match, from the ratings.
func odds_a() -> float:
	var m = current_match()
	if m.is_empty():
		return 0.5
	return BotLeagueSim.odds(teams[m["a"]]["units"], teams[m["b"]]["units"])

# What a wager of `stake` on side `pick` (0 = A, 1 = B) pays out in total if it wins: longer odds pay more.
func payout_for(pick: int, stake: int) -> int:
	var p = odds_a() if pick == 0 else 1.0 - odds_a()
	return int(round(float(stake) * clampf(PAYOUT * 0.5 / maxf(p, 0.05), 1.1, 6.0)))

# Runs the current match without watching it; returns the winner team index (a draw goes to the higher tier).
func quick_sim() -> int:
	var m = current_match()
	var sim = BotLeagueSim.new()
	sim.setup(teams[m["a"]]["units"], teams[m["b"]]["units"], season_seed + round_index * 100 + match_index)
	var w = sim.run_to_end()
	return report(w)

# Records a finished match (1 = A, 2 = B, 3 = draw) and advances the bracket. Returns the winning team index.
func report(sim_winner: int) -> int:
	var m = current_match()
	if m.is_empty():
		return -1
	var win_idx: int
	if sim_winner == 1:
		win_idx = m["a"]
	elif sim_winner == 2:
		win_idx = m["b"]
	else:
		win_idx = m["a"] if int(teams[m["a"]]["tier"]) >= int(teams[m["b"]]["tier"]) else m["b"]
	m["winner"] = win_idx
	_settle(win_idx)
	history.append({"round": round_name(), "a": m["a"], "b": m["b"], "winner": win_idx})
	match_index += 1
	if match_index >= rounds[round_index].size():
		var advancing: Array = []
		for mm in rounds[round_index]:
			advancing.append(mm["winner"])
		if advancing.size() == 1:
			champion = advancing[0]
		else:
			var nxt: Array = []
			for i in range(0, advancing.size(), 2):
				nxt.append({"a": advancing[i], "b": advancing[i + 1], "winner": -1})
			rounds.append(nxt)
			round_index += 1
			match_index = 0
	return win_idx

# A wager on the current match: `pick` 0 = A, 1 = B. The stake is held (credits are settled when the match is reported).
var wager: Dictionary = {}
var last_wager_delta: int = 0

func place_wager(pick: int, stake: int) -> bool:
	if current_match().is_empty() or stake <= 0 or stake > credits or (pick != 0 and pick != 1):
		return false
	wager = {"pick": pick, "stake": stake, "payout": payout_for(pick, stake), "match": current_match()}
	return true

func _settle(win_idx: int) -> void:
	last_wager_delta = 0
	if wager.is_empty():
		return
	var m: Dictionary = wager["match"]
	var picked = m["a"] if int(wager["pick"]) == 0 else m["b"]
	if picked == win_idx:
		last_wager_delta = int(wager["payout"]) - int(wager["stake"])
	else:
		last_wager_delta = -int(wager["stake"])
	credits += last_wager_delta
	wager = {}

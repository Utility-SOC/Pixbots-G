class_name BotLeagueSim
extends RefCounted

# Bot League: a self-contained, deterministic team-vs-team battle for spectating. No player, no Mech nodes: each unit is a small
# record (role, hp, shield, element mix, dps, range, speed) simulated in 2D, using the game's own element rules (shield counters x2,
# Lightning x1.5 against any shield, Pierce slips past shields, Fire burns, Ice slows, Lightning chains, Explosion splashes,
# Vampiric heals, Kinetic shoves, Vortex pulls, Poison lingers) at a coarse grain. It is its own game mode, and because it is plain
# data and a step function it can later drive RTS-style levels and cinematics. All numbers (tune).

const E = EnergyPacket.SynergyType
const ROLES = {
	"scout": {"hp": 60.0, "shield": 20.0, "speed": 190.0, "range": 260.0, "dps": 22.0},
	"brawler": {"hp": 160.0, "shield": 60.0, "speed": 110.0, "range": 150.0, "dps": 36.0},
	"sniper": {"hp": 50.0, "shield": 30.0, "speed": 90.0, "range": 520.0, "dps": 28.0},
	"support": {"hp": 80.0, "shield": 50.0, "speed": 100.0, "range": 300.0, "dps": 12.0},
	"flamer": {"hp": 120.0, "shield": 40.0, "speed": 100.0, "range": 170.0, "dps": 40.0},
}
const ELEMENTS = [E.FIRE, E.ICE, E.LIGHTNING, E.VORTEX, E.POISON, E.EXPLOSION, E.KINETIC, E.PIERCE, E.VAMPIRIC]
const SHIELD_COUNTER = {E.FIRE: E.ICE, E.ICE: E.FIRE, E.POISON: E.VAMPIRIC, E.VAMPIRIC: E.POISON, E.KINETIC: E.LIGHTNING, E.LIGHTNING: E.KINETIC}
const TEAM_SIZE = 5
const ARENA = Vector2(1400, 800)
const TIME_LIMIT = 150.0

var units: Array = [] # Dictionary per unit
var time: float = 0.0
var arena: Vector2 = ARENA
var shots: Array = [] # [from, to, color, ttl] for the viewer
var _rng := RandomNumberGenerator.new()
var _retarget: float = 0.0

# ---- team building --------------------------------------------------------------------------------------------------------

static func tier_scale(tier: int, per_tier: float) -> float:
	return 1.0 + per_tier * float(maxi(0, tier - 1))

# A team of TEAM_SIZE units for gear `tier` 1..5 (stats scale with it; the composition and elements come from `rng`).
static func make_team(rng: RandomNumberGenerator, tier: int) -> Array:
	var team: Array = []
	var role_names = ROLES.keys()
	for i in range(TEAM_SIZE):
		var role: String = role_names[rng.randi() % role_names.size()]
		var base: Dictionary = ROLES[role]
		var el = ELEMENTS[rng.randi() % ELEMENTS.size()] if role != "flamer" else E.FIRE
		var mix = {el: 1.0}
		if rng.randf() < 0.35:
			var second = ELEMENTS[rng.randi() % ELEMENTS.size()]
			if second != el:
				mix = {el: 0.6, second: 0.4}
		var shield_el = ELEMENTS[rng.randi() % ELEMENTS.size()]
		team.append({
			"role": role, "max_hp": float(base["hp"]) * tier_scale(tier, 0.55), "max_shield": float(base["shield"]) * tier_scale(tier, 0.55),
			"speed": float(base["speed"]), "range": float(base["range"]), "dps": float(base["dps"]) * tier_scale(tier, 0.45),
			"mix": mix, "shield_el": shield_el,
		})
	return team

# A single number for how strong a team is (used for odds and to sanity-check the sim).
static func rating(team: Array) -> float:
	var hp = 0.0
	var dps = 0.0
	for u in team:
		hp += float(u["max_hp"]) + float(u["max_shield"])
		dps += float(u["dps"])
	return sqrt(hp * dps)

# Chance team A beats team B implied by the ratings (a squashed ratio so upsets stay possible).
static func odds(a: Array, b: Array) -> float:
	var ra = pow(rating(a), 2.0)
	var rb = pow(rating(b), 2.0)
	return ra / (ra + rb)

# ---- the match -----------------------------------------------------------------------------------------------------------------

func setup(team_a: Array, team_b: Array, seed_value: int, arena_size: Vector2 = ARENA) -> void:
	_rng.seed = seed_value
	arena = arena_size
	units.clear()
	shots.clear()
	time = 0.0
	_retarget = 0.0
	_spawn(team_a, 0)
	_spawn(team_b, 1)

func _spawn(team: Array, side: int) -> void:
	for i in range(team.size()):
		var u: Dictionary = team[i].duplicate(true)
		u["team"] = side
		u["id"] = units.size()
		var x = arena.x * (0.12 if side == 0 else 0.88)
		var y = arena.y * (0.2 + 0.6 * float(i) / float(maxi(1, team.size() - 1)))
		u["pos"] = Vector2(x, y)
		u["hp"] = u["max_hp"]
		u["shield"] = u["max_shield"]
		u["target"] = -1
		u["slow_t"] = 0.0
		u["burn_t"] = 0.0
		u["burn_dps"] = 0.0
		u["alive"] = true
		units.append(u)

func alive(side: int) -> int:
	var n = 0
	for u in units:
		if u["alive"] and u["team"] == side:
			n += 1
	return n

# 0 = still going, 1 = team A, 2 = team B, 3 = draw
func winner() -> int:
	var a = alive(0)
	var b = alive(1)
	if a > 0 and b == 0:
		return 1
	if b > 0 and a == 0:
		return 2
	if a == 0 and b == 0:
		return 3
	if time >= TIME_LIMIT:
		var fa = _hp_fraction(0)
		var fb = _hp_fraction(1)
		return 1 if fa > fb else (2 if fb > fa else 3)
	return 0

func _hp_fraction(side: int) -> float:
	var hp = 0.0
	var mx = 0.0
	for u in units:
		if u["team"] == side:
			hp += float(u["hp"]) + float(u["shield"]) if u["alive"] else 0.0
			mx += float(u["max_hp"]) + float(u["max_shield"])
	return hp / maxf(mx, 1.0)

func _nearest_enemy(u: Dictionary) -> int:
	var best = -1
	var best_d = 1.0e12
	for o in units:
		if o["alive"] and o["team"] != u["team"]:
			var d = u["pos"].distance_squared_to(o["pos"])
			if d < best_d:
				best_d = d
				best = o["id"]
	return best

func _lowest_ally(u: Dictionary) -> int:
	var best = -1
	var best_f = 1.0
	for o in units:
		if o["alive"] and o["team"] == u["team"] and o["id"] != u["id"]:
			var f = float(o["hp"]) / float(o["max_hp"])
			if f < best_f:
				best_f = f
				best = o["id"]
	return best

func step(dt: float) -> void:
	if winner() != 0:
		return
	time += dt
	_retarget -= dt
	var do_retarget = _retarget <= 0.0
	if do_retarget:
		_retarget = 0.5
	for i in range(shots.size() - 1, -1, -1):
		shots[i][3] -= dt
		if shots[i][3] <= 0.0:
			shots.remove_at(i)
	for u in units:
		if not u["alive"]:
			continue
		_status_tick(u, dt)
		if not u["alive"]:
			continue
		if do_retarget or u["target"] < 0 or not units[u["target"]]["alive"]:
			u["target"] = _nearest_enemy(u)
		if u["target"] < 0:
			continue
		var t: Dictionary = units[u["target"]]
		var to_t: Vector2 = t["pos"] - u["pos"]
		var dist = to_t.length()
		var speed = float(u["speed"]) * (0.5 if u["slow_t"] > 0.0 else 1.0)
		var rng_u = float(u["range"])
		if dist > rng_u * 0.9:
			u["pos"] += to_t.normalized() * speed * dt
		elif u["role"] == "sniper" and dist < rng_u * 0.45:
			u["pos"] -= to_t.normalized() * speed * dt # snipers back off
		u["pos"] = Vector2(clampf(u["pos"].x, 20.0, arena.x - 20.0), clampf(u["pos"].y, 20.0, arena.y - 20.0))
		if u["role"] == "support":
			var ally = _lowest_ally(u)
			if ally >= 0:
				var a: Dictionary = units[ally]
				a["hp"] = minf(float(a["max_hp"]), float(a["hp"]) + 18.0 * dt * tier_boost(u))
		if dist <= rng_u:
			_fire(u, t, dt)
	units_cleanup()

func tier_boost(u: Dictionary) -> float:
	return maxf(1.0, float(u["dps"]) / float(ROLES[u["role"]]["dps"]))

func units_cleanup() -> void:
	pass

func _status_tick(u: Dictionary, dt: float) -> void:
	if u["slow_t"] > 0.0:
		u["slow_t"] -= dt
	if u["burn_t"] > 0.0:
		u["burn_t"] -= dt
		_damage_raw(u, float(u["burn_dps"]) * dt)

func _damage_raw(u: Dictionary, amount: float) -> void:
	u["hp"] -= amount
	if u["hp"] <= 0.0:
		u["hp"] = 0.0
		u["alive"] = false

# Damage `amount` of `element` onto `target`: shield first (with counter and Pierce rules), then hp. Returns what was dealt.
func _hit(target: Dictionary, element: int, amount: float) -> float:
	var dealt = 0.0
	var left = amount
	if target["shield"] > 0.0:
		var mult = 1.0
		if element == E.LIGHTNING:
			mult *= 1.5
		if SHIELD_COUNTER.get(int(target["shield_el"]), -1) == element:
			mult *= 2.0
		var pierce_through = 0.5 * left if element == E.PIERCE else 0.0
		var on_shield = (left - pierce_through) * mult
		var absorbed = minf(float(target["shield"]), on_shield)
		target["shield"] -= absorbed
		dealt += absorbed
		left = pierce_through + maxf(0.0, on_shield - absorbed) / maxf(mult, 0.001)
	if left > 0.0:
		_damage_raw(target, left)
		dealt += left
	return dealt

func _fire(u: Dictionary, t: Dictionary, dt: float) -> void:
	var total = float(u["dps"]) * dt
	for el in u["mix"]:
		var amount = total * float(u["mix"][el])
		var dealt = _hit(t, int(el), amount)
		match int(el):
			E.FIRE:
				t["burn_t"] = 3.0
				t["burn_dps"] = maxf(float(t["burn_dps"]), 0.15 * float(u["dps"]) * float(u["mix"][el]))
			E.ICE:
				if float(u["mix"][el]) >= 0.4:
					t["slow_t"] = 1.5
			E.LIGHTNING:
				var second = _second_target(u, t, 150.0)
				if second != null:
					_hit(second, E.LIGHTNING, amount * 0.4)
			E.EXPLOSION:
				for o in units:
					if o["alive"] and o["team"] != u["team"] and o["id"] != t["id"] and o["pos"].distance_to(t["pos"]) <= 70.0:
						_hit(o, E.EXPLOSION, amount * 0.35)
			E.VAMPIRIC:
				u["hp"] = minf(float(u["max_hp"]), float(u["hp"]) + dealt * 0.25)
			E.KINETIC:
				t["pos"] += (t["pos"] - u["pos"]).normalized() * 30.0 * float(u["mix"][el]) * dt
			E.VORTEX:
				t["pos"] += (u["pos"] - t["pos"]).normalized() * 40.0 * float(u["mix"][el]) * dt
			E.POISON:
				t["burn_t"] = maxf(float(t["burn_t"]), 4.0)
				t["burn_dps"] = maxf(float(t["burn_dps"]), 0.08 * float(u["dps"]) * float(u["mix"][el]))
	if shots.size() < 60 and _rng.randf() < 6.0 * dt:
		shots.append([u["pos"], t["pos"], _element_color(int(u["mix"].keys()[0])), 0.12])

func _second_target(u: Dictionary, first: Dictionary, radius: float):
	var best = null
	var best_d = radius
	for o in units:
		if o["alive"] and o["team"] != u["team"] and o["id"] != first["id"]:
			var d = o["pos"].distance_to(first["pos"])
			if d < best_d:
				best_d = d
				best = o
	return best

static func _element_color(el: int) -> Color:
	match el:
		E.FIRE: return Color(1.0, 0.45, 0.15)
		E.ICE: return Color(0.5, 0.85, 1.0)
		E.LIGHTNING: return Color(1.0, 0.95, 0.3)
		E.VORTEX: return Color(0.6, 0.3, 0.9)
		E.POISON: return Color(0.4, 0.9, 0.3)
		E.EXPLOSION: return Color(1.0, 0.7, 0.2)
		E.KINETIC: return Color(0.85, 0.85, 0.9)
		E.PIERCE: return Color(1.0, 0.4, 0.6)
		E.VAMPIRIC: return Color(0.8, 0.15, 0.25)
	return Color.WHITE

# Runs a whole match at a fixed step and returns the winner (for the league, tests and quick-sim).
func run_to_end(dt: float = 0.1) -> int:
	var guard = 0
	while winner() == 0 and guard < 10000:
		step(dt)
		guard += 1
	return winner()

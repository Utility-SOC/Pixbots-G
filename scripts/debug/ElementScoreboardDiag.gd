extends Node

# Diagnostic: per-element scoreboard through the REAL batch-pool hit pipeline (ProjectileBatchPool _step_simulate +
# _step_hit_test) and Mech status ticking. Every scenario fires the same shots (same base damage, same cadence, real
# per-element shot speed) at the same victims, so the table shows what the element itself adds:
#   tank   single-target damage over time (direct + damage-over-time) and crowd-control victim-seconds
#   clus   8 victims in a ring: area / chain / spread damage, how many get hit, kills, CC victim-seconds
#   line   5 victims in a straight line along the firing axis: how many one volley reaches (pierce / chain)
#   heal   hp the shooter regains (Vampiric)
# Scenarios are one weapon per element plus multi-weapon pairs (e.g. ICE+KINETIC fired together, which is how Ice's
# shatter pays off). Victims are execution-exempt (role "commander") so Pierce's flat 4% per-hit instant kill does not
# swamp the table; that proc is reported analytically at the end. Damage-only metrics do not price crowd control or
# movement denial, so CC victim-seconds sit beside them. A map of where each element sits, not a final verdict (no
# enemy AI, no movement, no resistances).
#   godot --headless --path . res://scripts/debug/ElementScoreboardDiag.tscn
const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

const STEP = 1.0 / 60.0
const SHOT_DAMAGES = [120.0, 600.0] # early / late-game magnitude; hp scales with it so kills stay comparable
const SHOT_INTERVAL = 0.4
const FIRE_SECONDS = 8.0
const TOTAL_SECONDS = 12.0 # extra tail lets damage-over-time play out
const TANK_HP = 6000.0 # at the 120 shot; scaled by shot/120
const CLUSTER_HP = 1500.0
const CLUSTER_COUNT = 8
const CLUSTER_SPACING = 38.0
const LINE_COUNT = 5
const LINE_SPACING = 60.0
const MUZZLE = Vector2(0, 0)
const TARGET_X = 300.0
const SEED = 20261011
const SHOOTER_START_HP = 500.0
# Status names that deny movement or action; anything else counts as damage-only.
const CC_STATUSES = ["frozen", "paralyzed", "paralysed", "stunned", "pinned", "held", "concussed", "rooted", "slowed", "slow", "vortexed", "immobilized", "staggered"]
const E = EnergyPacket.SynergyType
const NAMES = ["RAW", "FIRE", "ICE", "LIGHTNING", "VORTEX", "POISON", "EXPLOSION", "KINETIC", "PIERCE", "VAMPIRIC"]

# [label, [weapon ratio dicts...]]; weapons in a scenario fire together every interval.
func _scenarios() -> Array:
	var out: Array = []
	for e in range(NAMES.size()):
		out.append([NAMES[e], [{e: 1.0}]])
	out.append(["ICE+KINETIC (2 guns)", [{E.ICE: 1.0}, {E.KINETIC: 1.0}]])
	out.append(["KINETIC x2 (control)", [{E.KINETIC: 1.0}, {E.KINETIC: 1.0}]])
	out.append(["ICE .5/KIN .5 (1 gun)", [{E.ICE: 0.5, E.KINETIC: 0.5}]])
	out.append(["ICE+EXPLOSION (2 guns)", [{E.ICE: 1.0}, {E.EXPLOSION: 1.0}]])
	return out

# Mirrors Mech._ai_shot_speed / Projectile's speed stat: 500 base, +1200 pierce, -250 poison, -200 ice.
static func shot_speed(ratios: Dictionary) -> float:
	return 500.0 + 1200.0 * float(ratios.get(E.PIERCE, 0.0)) - 250.0 * float(ratios.get(E.POISON, 0.0)) - 200.0 * float(ratios.get(E.ICE, 0.0))

static func dominant(ratios: Dictionary) -> int:
	var best = 0
	var best_v = -1.0
	for k in ratios:
		if float(ratios[k]) > best_v:
			best_v = float(ratios[k])
			best = int(k)
	return best

func _victim(world: Node, pos: Vector2, hp: float) -> Node:
	var t = MechScript.new()
	t.is_player = false
	t.combat_role = "commander" # exempt from Pierce's instant-kill proc
	world.add_child(t)
	t.set_physics_process(false)
	t.max_hp = hp
	t.hp = hp
	t.global_position = pos
	return t

func _shooter(world: Node) -> Node:
	var s = MechScript.new()
	s.is_player = true
	s.max_hp = 1e6
	s.hp = SHOOTER_START_HP
	world.add_child(s)
	s.set_physics_process(false)
	s.add_to_group("player")
	return s

# layout: "tank" | "cluster" | "line"; returns metrics
func _run(weapons: Array, layout: String, shot_damage: float, volleys_only: bool = false) -> Dictionary:
	SimRng.seed_all(SEED)
	var hp_scale = shot_damage / 120.0
	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(128)
	world.add_child(pool)
	var shooter = _shooter(world)
	var victims: Array = []
	match layout:
		"tank":
			victims.append(_victim(world, Vector2(TARGET_X, 0), TANK_HP * hp_scale))
		"cluster":
			victims.append(_victim(world, Vector2(TARGET_X, 0), CLUSTER_HP * hp_scale))
			for i in range(CLUSTER_COUNT - 1):
				var a = TAU * float(i) / float(CLUSTER_COUNT - 1)
				victims.append(_victim(world, Vector2(TARGET_X, 0) + Vector2.from_angle(a) * CLUSTER_SPACING, CLUSTER_HP * hp_scale))
		"line":
			for i in range(LINE_COUNT):
				victims.append(_victim(world, Vector2(TARGET_X + LINE_SPACING * i, 0), 1e9))
	for v in victims:
		pool.register_target(v)
	var statuses := {}
	var cc_seconds := 0.0
	var t = 0.0
	var next_shot = 0.0
	var total_time = 4.0 if layout == "line" else TOTAL_SECONDS
	var fire_time = 0.1 if layout == "line" else FIRE_SECONDS # line: a single volley
	while t < total_time:
		if t >= next_shot and t < fire_time:
			next_shot += SHOT_INTERVAL
			for w in weapons:
				# A Poison shot with no Kinetic is a stationary mine: it sits where it spawns and detonates when something
				# touches it, so it is laid right in front of the victims rather than fired from the muzzle.
				var is_static_mine = float(w.get(E.POISON, 0.0)) > 0.15 and float(w.get(E.KINETIC, 0.0)) <= 0.0
				var origin = Vector2(TARGET_X - 30.0, 0) if is_static_mine else MUZZLE
				pool.spawn(origin, Vector2.RIGHT, shot_speed(w), shot_damage, 20.0, 5.0, Color.WHITE, 1.0, true, null, dominant(w), w)
		EntityCache._stamp = -2 # the cache keys on engine frame counters, which this synchronous loop never advances
		pool._step_simulate(STEP)
		pool._step_hit_test()
		for v in victims:
			if not is_instance_valid(v) or v.hp <= 0.0:
				continue
			v.update_status_effects(STEP)
			var cc = false
			for k in v.status_effects:
				if float(v.status_effects[k]) > 0.0:
					statuses[k] = true
					if k in CC_STATUSES:
						cc = true
			if cc:
				cc_seconds += STEP
		t += STEP
	var dealt = 0.0
	var hit = 0
	var kills = 0
	for v in victims:
		if not is_instance_valid(v):
			continue
		var base_hp = v.max_hp
		var lost = base_hp - maxf(v.hp, 0.0)
		dealt += lost
		if lost > 0.0:
			hit += 1
		if v.hp <= 0.0:
			kills += 1
	var out = {"dealt": dealt, "hit": hit, "kills": kills, "cc": cc_seconds, "statuses": statuses.keys(), "heal": shooter.hp - SHOOTER_START_HP}
	for v in victims:
		if is_instance_valid(v):
			v.free()
	shooter.free()
	world.free()
	return out

func _ready():
	print("ElementScoreboard: shots every %.1fs for %ds (+%ds tail); tank hp %d; cluster %d x hp %d @ %dpx; line %d @ %dpx; victims execution-exempt" % [
		SHOT_INTERVAL, FIRE_SECONDS, TOTAL_SECONDS - FIRE_SECONDS, TANK_HP, CLUSTER_COUNT, CLUSTER_HP, CLUSTER_SPACING, LINE_COUNT, LINE_SPACING])
	for dmg in SHOT_DAMAGES:
		print("\nshot damage %d (tank hp %d, cluster hp %d each)" % [dmg, TANK_HP * dmg / 120.0, CLUSTER_HP * dmg / 120.0])
		print("%-22s | %8s %5s | %8s %4s %5s %6s | %4s | %6s | %s" % ["scenario", "tank dmg", "cc s", "clus dmg", "hit", "kills", "cc s", "line", "heal", "statuses seen"])
		for sc in _scenarios():
			var a = _run(sc[1], "tank", dmg)
			var b = _run(sc[1], "cluster", dmg)
			var c = _run(sc[1], "line", dmg)
			var st = {}
			for s in a["statuses"] + b["statuses"]:
				st[s] = true
			print("%-22s | %8.0f %5.1f | %8.0f %4d %5d %6.1f | %4d | %6.0f | %s" % [sc[0], a["dealt"], a["cc"], b["dealt"], b["hit"], b["kills"], b["cc"], c["hit"], a["heal"], ",".join(st.keys())])
	var hits = int(FIRE_SECONDS / SHOT_INTERVAL)
	print("\nPierce execution proc: %.0f%% per hit, so %d hits kill a non-exempt (non-boss, non-commander/support) target outright %.0f%% of the time." % [
		100.0 * MechScript.PIERCE_EXECUTION_CHANCE, hits, 100.0 * (1.0 - pow(1.0 - MechScript.PIERCE_EXECUTION_CHANCE, hits))])
	get_tree().quit(0)

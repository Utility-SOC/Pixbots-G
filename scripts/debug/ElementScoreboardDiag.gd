extends Node

# Diagnostic: per-element scoreboard through the REAL batch-pool hit pipeline (ProjectileBatchPool._step_hit_test) and
# Mech status ticking. Every element fires the same shot (same base damage, same cadence) at the same victims, so the
# table shows what the element itself adds: single-target damage, area/chain spread, kills, damage-over-time, and how
# long victims are crowd-controlled (frozen / paralysed / held etc.). Damage-only metrics do NOT price crowd control or
# movement denial, so CC victim-seconds are reported next to them. Read it as a map of where each element sits, not as
# a final balance verdict (no enemy AI, no movement, no resistances).
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
const SEED = 20261011
# Status names that deny movement or action; anything else counts as damage-only.
const CC_STATUSES = ["frozen", "paralyzed", "paralysed", "stunned", "pinned", "held", "concussed", "rooted", "slowed", "slow", "vortexed", "immobilized", "staggered"]

func _victim(world: Node, pos: Vector2, hp: float) -> Node:
	var t = MechScript.new()
	t.is_player = false
	t.combat_role = "brawler"
	world.add_child(t)
	t.set_physics_process(false)
	t.max_hp = hp
	t.hp = hp
	t.global_position = pos
	return t

func _run(element: int, cluster: bool, shot_damage: float) -> Dictionary:
	var hp_scale = shot_damage / 120.0
	SimRng.seed_all(SEED + element)
	var world = Node2D.new()
	add_child(world)
	var pool = ProjectileBatchPoolScript.new(64)
	world.add_child(pool)
	var victims: Array = []
	if cluster:
		victims.append(_victim(world, Vector2(300, 0), CLUSTER_HP * hp_scale))
		for i in range(CLUSTER_COUNT - 1):
			var a = TAU * float(i) / float(CLUSTER_COUNT - 1)
			victims.append(_victim(world, Vector2(300, 0) + Vector2.from_angle(a) * CLUSTER_SPACING, CLUSTER_HP * hp_scale))
	else:
		victims.append(_victim(world, Vector2(300, 0), TANK_HP * hp_scale))
	for v in victims:
		pool.register_target(v)
	var statuses := {}
	var cc_seconds := 0.0
	var kills := 0
	var t = 0.0
	var next_shot = 0.0
	var ratios = {element: 1.0}
	while t < TOTAL_SECONDS:
		if t >= next_shot and t < FIRE_SECONDS:
			next_shot += SHOT_INTERVAL
			var i = pool.spawn(Vector2(295, 0), Vector2.RIGHT, 10.0, shot_damage, 20.0, 5.0, Color.WHITE, 1.0, true, null, element, ratios)
			if i < 0:
				continue
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
	for v in victims:
		if not is_instance_valid(v):
			continue
		var lost = v.max_hp - maxf(v.hp, 0.0)
		dealt += lost
		if lost > 0.0:
			hit += 1
		if v.hp <= 0.0:
			kills += 1
	var out = {"dealt": dealt, "hit": hit, "kills": kills, "cc": cc_seconds, "statuses": statuses.keys()}
	for v in victims:
		if is_instance_valid(v):
			v.free()
	world.free()
	return out

func _ready():
	var names = ["RAW", "FIRE", "ICE", "LIGHTNING", "VORTEX", "POISON", "EXPLOSION", "KINETIC", "PIERCE", "VAMPIRIC"]
	for dmg in SHOT_DAMAGES:
		print("\nElementScoreboard: shot dmg %d every %.1fs for %ds (+%ds tail); tank hp %d; cluster %d x hp %d @ %dpx" % [
			dmg, SHOT_INTERVAL, FIRE_SECONDS, TOTAL_SECONDS - FIRE_SECONDS, TANK_HP * dmg / 120.0, CLUSTER_COUNT, CLUSTER_HP * dmg / 120.0, CLUSTER_SPACING])
		print("%-10s | %8s %5s | %8s %4s %5s %6s | %s" % ["element", "tank dmg", "cc s", "clus dmg", "hit", "kills", "cc s", "statuses seen"])
		for e in range(names.size()):
			var a = _run(e, false, dmg)
			var b = _run(e, true, dmg)
			var st = {}
			for s in a["statuses"] + b["statuses"]:
				st[s] = true
			print("%-10s | %8.0f %5.1f | %8.0f %4d %5d %6.1f | %s" % [names[e], a["dealt"], a["cc"], b["dealt"], b["hit"], b["kills"], b["cc"], ",".join(st.keys())])
	get_tree().quit(0)

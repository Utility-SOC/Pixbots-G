extends RefCounted

# Squad-level combat tactics: a plan picks who does what (pin, flank, hold
# back, bait) and steers members toward goal positions around the player, so a
# squad fights as a group instead of N independent chasers. Runs a planning
# tick at TICK_INTERVAL (not per frame); members read the resulting
# tactic_goal / tactic_path_clear / tactic_hold / tactic_label fields.
#
# PLANS are the founding archetypes. Squads actually run a genome (see
# TacticGenome.gd): an archetype plus evolved parameter overrides, selected and
# credited by the director (SquadDirector.tactic_pool).

const TICK_INTERVAL = 0.25
const PROJECTILE_SPEED = 500.0
const MAX_LEAD_DIST = 420.0
const MAX_LEAD_TIME = 1.5
const ARRIVE_RADIUS = 70.0
const STALL_TICKS = 6
const STALL_BAN_SECONDS = 3.0
const REPLAN_AFTER = 12.0
const REPLAN_COOLDOWN = 15.0
const RECENT_PLAN_MEMORY = 5

const BACKLINE_ROLES = ["sniper", "jammer", "support", "commander", "anti_missile", "remediation"]

# min_wave gates complexity (like rarity gates): early waves get simple
# coordination, later waves get the full playbook.
const PLANS = {
	"swarm": {"min_wave": 0, "weight": 1.0},
	"synchronized_strike": {"min_wave": 3, "weight": 1.0, "stage": true, "stage_extra": 320.0, "timeout": 6.0},
	"pincer": {"min_wave": 5, "weight": 1.2, "flank_share": 0.5, "arc": 1.5708, "split": true},
	"hammer_anvil": {"min_wave": 8, "weight": 1.0, "flank_share": 0.5, "arc": 3.14159, "split": false},
	"encircle": {"min_wave": 12, "weight": 0.8, "ring": true},
	"bait_flank": {"min_wave": 15, "weight": 0.8, "bait": true, "stage": true, "stage_extra": 300.0, "timeout": 9.0, "flank_share": 0.6, "arc": 1.9, "split": true},
}

var plan_name: String = "swarm" # archetype
var genome_id: String = "swarm"
var plans_used: Array = [] # genome ids, for credit
var cfg: Dictionary = {}
# Set from the squad template (formation genes); kept outside cfg so a replan keeps them.
var bias: String = ""
var spread: float = 1.0
var lead_skill: float = 0.65

var _phase: String = "commit" # "stage" | "commit"
var _phase_time: float = 0.0
var _stage_goal_ticks: int = 0
var _tick_timer: float = 0.0
var _plan_time: float = 0.0
var _replan_cooldown: float = 0.0
var _plan_hits_at_start: int = 0
var _last_player_pos: Vector2 = Vector2.ZERO
var _have_player_pos: bool = false
var _player_vel: Vector2 = Vector2.ZERO
var _predictability: float = 1.0
var _approach_angle: float = 0.0
var _assign: Dictionary = {} # instance_id -> {"kind": String, "side": float, "slot": int}
var _assign_ids: Array = []
var _progress: Dictionary = {} # instance_id -> {"best": float, "stall": int, "ban_until": float}
var _clock: float = 0.0

static func plan_cfg(name: String) -> Dictionary:
	return PLANS.get(name, PLANS["swarm"])

# Archetype defaults overlaid with a genome's evolved params.
static func cfg_for(g: Dictionary) -> Dictionary:
	var out = plan_cfg(str(g.get("base", "swarm"))).duplicate()
	var params = g.get("params", {})
	for k in params:
		out[k] = params[k]
	return out

static func available_plans(wave: int) -> Array:
	var out = []
	for n in PLANS:
		if wave >= int(PLANS[n]["min_wave"]):
			out.append(n)
	return out

func set_plan(name: String) -> void:
	var base = name if PLANS.has(name) else "swarm"
	set_genome({"id": base, "base": base, "params": {}})

func set_genome(g: Dictionary) -> void:
	plan_name = str(g.get("base", "swarm"))
	if not PLANS.has(plan_name):
		plan_name = "swarm"
	genome_id = str(g.get("id", plan_name))
	cfg = cfg_for(g)
	plans_used.append(genome_id)
	_plan_time = 0.0
	_phase = "stage" if cfg.get("stage", false) else "commit"
	_phase_time = 0.0
	_stage_goal_ticks = 0
	_assign.clear()
	_assign_ids.clear()
	_progress.clear()

# Per-frame: cheap player velocity tracking, tick planning at TICK_INTERVAL.
func update(squad: Node, delta: float) -> void:
	_clock += delta
	_plan_time += delta
	_phase_time += delta
	_replan_cooldown = max(0.0, _replan_cooldown - delta)
	var player = _player(squad)
	if player:
		var p: Vector2 = player.global_position
		if _have_player_pos and delta > 0.0:
			var v = (p - _last_player_pos) / delta
			# Lower predictability when the player reverses/jinks: lead only pays off against steady movement.
			if v.length() > 40.0 and _player_vel.length() > 40.0:
				_predictability = lerp(_predictability, clamp(0.5 + 0.5 * v.normalized().dot(_player_vel.normalized()), 0.0, 1.0), 0.05)
			_player_vel = _player_vel.lerp(v, 0.25)
		_last_player_pos = p
		_have_player_pos = true
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer = TICK_INTERVAL
	if player:
		_tick(squad, player)

# Where to aim so a projectile of `proj_speed` fired from `shooter_pos` meets a
# target moving at its tracked velocity: the exact intercept time from
# |D + V t| = s t, scaled by lead_skill (and shrunk against jinking players).
func lead_point(shooter_pos: Vector2, target_pos: Vector2, proj_speed: float = PROJECTILE_SPEED) -> Vector2:
	if lead_skill <= 0.0 or _player_vel.length() < 20.0:
		return target_pos
	var s = max(proj_speed, 50.0)
	var d = target_pos - shooter_pos
	var v = _player_vel
	var a = v.dot(v) - s * s
	var b = 2.0 * d.dot(v)
	var c = d.dot(d)
	var t = d.length() / s
	if abs(a) < 0.001:
		if abs(b) > 0.001 and -c / b > 0.0:
			t = -c / b
	else:
		var disc = b * b - 4.0 * a * c
		if disc >= 0.0:
			var sq = sqrt(disc)
			var t1 = (-b - sq) / (2.0 * a)
			var t2 = (-b + sq) / (2.0 * a)
			var best = INF
			for cand in [t1, t2]:
				if cand > 0.0 and cand < best:
					best = cand
			if best < INF:
				t = best
	t = min(t, MAX_LEAD_TIME)
	var lead = v * t * lead_skill * lerp(0.6, 1.0, _predictability)
	if lead.length() > MAX_LEAD_DIST:
		lead = lead.normalized() * MAX_LEAD_DIST
	return target_pos + lead

func _player(squad: Node) -> Node2D:
	for m in squad.members:
		if is_instance_valid(m) and "target" in m and is_instance_valid(m.target):
			return m.target
	return null

func _valid_members(squad: Node) -> Array:
	var out = []
	for m in squad.members:
		if is_instance_valid(m) and not m.is_queued_for_deletion() and m is Node2D:
			out.append(m)
	return out

func _tick(squad: Node, player: Node2D) -> void:
	var members = _valid_members(squad)
	if members.is_empty():
		return
	var P: Vector2 = player.global_position

	var director = squad.get_parent()
	if director and "player_model" in director and director.player_model:
		lead_skill = clamp(0.65 + 0.1 * director.player_model.pressure + float(cfg.get("lead_bonus", 0.0)), 0.0, 1.0)

	# Approach bearing (player -> squad centre), smoothed so goals don't spin
	# when the squad wraps around the player.
	var centre = squad.get_center_position()
	if centre.distance_to(P) > 120.0:
		var raw = (centre - P).angle()
		_approach_angle = _approach_angle + angle_difference(_approach_angle, raw) * 0.3 if _plan_time > TICK_INTERVAL * 2 else raw

	_maybe_replan(squad, members, director)

	# Staging only makes sense before first contact.
	if _phase == "stage":
		var engaged = squad.first_engagement_time >= 0.0 or squad.total_damage_taken > 0.0
		if engaged or _phase_time > float(cfg.get("timeout", 6.0)) or (_stage_goal_ticks > 0 and _stage_ready(members, P, cfg)):
			_phase = "commit"
			_phase_time = 0.0
			_say(squad, director, "commit", plan_name)

	var ids = []
	for m in members:
		ids.append(m.get_instance_id())
	if ids != _assign_ids:
		_assign_roles(members, cfg)
		_assign_ids = ids

	var map = members[0].call("_get_map_ref") if members[0].has_method("_get_map_ref") else null
	var ring_n = 0
	for m in members:
		if _assign[m.get_instance_id()].kind == "ring":
			ring_n += 1
	for m in members:
		_set_member_goal(m, _assign[m.get_instance_id()], P, cfg, map, ring_n)
	if _phase == "stage":
		_stage_goal_ticks += 1

func _say(squad: Node, director: Node, kind: String, plan: String) -> void:
	if director and "orders" in director:
		director.orders.post(kind, squad.template.template_name if "template" in squad and squad.template else "", squad.get_instance_id(), plan)

func _stage_ready(members: Array, P: Vector2, cfg: Dictionary) -> bool:
	var arrived = 0
	for m in members:
		if not m.tactic_goal_active or m.global_position.distance_to(m.tactic_goal) <= ARRIVE_RADIUS * 1.5:
			arrived += 1
	return float(arrived) / float(members.size()) >= 0.7

func _assign_roles(members: Array, cfg: Dictionary) -> void:
	_assign.clear()
	var mobile = []
	for m in members:
		var role = str(m.combat_role) if "combat_role" in m else ""
		if role in BACKLINE_ROLES:
			_assign[m.get_instance_id()] = {"kind": "overwatch", "side": 0.0, "slot": 0}
		else:
			mobile.append(m)
	# Fastest first (stable tie-break) so the same members keep flank duty as the squad shrinks.
	mobile.sort_custom(func(a, b):
		var sa = float(a.base_speed) if "base_speed" in a else 0.0
		var sb = float(b.base_speed) if "base_speed" in b else 0.0
		if sa != sb:
			return sa > sb
		return a.get_instance_id() < b.get_instance_id())
	var idx = 0
	if cfg.get("bait", false) and not mobile.is_empty():
		_assign[mobile[0].get_instance_id()] = {"kind": "bait", "side": 0.0, "slot": 0}
		idx = 1
	var remaining = mobile.size() - idx
	var flank_count = 0
	var share = float(cfg.get("flank_share", 0.0))
	if share > 0.0 and remaining >= 2:
		flank_count = clampi(int(round(share * remaining)), 1, remaining - 1)
	var side = 1.0
	var ring_slot = 0
	for i in range(idx, mobile.size()):
		var id = mobile[i].get_instance_id()
		if cfg.get("ring", false):
			_assign[id] = {"kind": "ring", "side": 0.0, "slot": ring_slot}
			ring_slot += 1
		elif i - idx < flank_count:
			_assign[id] = {"kind": "flank", "side": side, "slot": i - idx}
			if cfg.get("split", false):
				side = -side
		else:
			_assign[id] = {"kind": "anchor", "side": 0.0, "slot": 0}

func _jitter(m: Node) -> float:
	return float((m.get_instance_id() % 7) - 3) * 0.1

func _set_member_goal(m: Node, info: Dictionary, P: Vector2, cfg: Dictionary, map: Node, ring_n: int) -> void:
	var kind: String = info.kind
	var eng = float(m.engagement_distance) if "engagement_distance" in m else 250.0
	var goal = Vector2.ZERO
	var label = ""
	var hold = false

	if _phase == "stage" and kind != "bait":
		var r = max(eng, 350.0) + float(cfg.get("stage_extra", 300.0))
		goal = P + Vector2.from_angle(_approach_angle + _jitter(m)) * r
		label = "STAGE"
		hold = true
	else:
		match kind:
			"flank":
				var ang = _approach_angle + float(info.side) * float(cfg.get("arc", 1.5708)) + _jitter(m) * 0.5
				if not cfg.get("split", false) and float(cfg.get("arc", 0.0)) >= 3.0:
					ang = _approach_angle + 3.14159 + _jitter(m)
				goal = P + Vector2.from_angle(ang) * max(eng, 220.0) * float(cfg.get("standoff", 1.0)) * spread
				label = "FLANK"
			"ring":
				var n = max(ring_n, 1)
				goal = P + Vector2.from_angle(_approach_angle + TAU * float(info.slot) / float(n)) * max(eng, 220.0) * float(cfg.get("standoff", 1.0)) * spread
				label = "RING"
			"bait":
				label = "BAIT"
			"anchor":
				label = "PIN"
			"overwatch":
				label = "COVER"

	var prog = _progress.get(m.get_instance_id(), {"best": INF, "stall": 0, "ban_until": 0.0})
	if goal != Vector2.ZERO:
		var amph = bool(m.is_amphibious) if "is_amphibious" in m else false
		if map and map.has_method("is_world_walkable") and not map.is_world_walkable(goal, amph):
			goal = _nudge_walkable(map, P, goal, amph)
		if goal == Vector2.ZERO or _clock < float(prog.ban_until):
			goal = Vector2.ZERO
			hold = false
		else:
			var d = m.global_position.distance_to(goal)
			if d <= ARRIVE_RADIUS:
				prog.best = INF
				prog.stall = 0
				if not hold:
					goal = Vector2.ZERO # arrived: default engage/orbit logic takes over
			else:
				# Stuck-detection: no meaningful closing over STALL_TICKS ticks -> abandon this goal for a while.
				if d < float(prog.best) - 20.0:
					prog.best = d
					prog.stall = 0
				else:
					prog.stall = int(prog.stall) + 1
					if int(prog.stall) >= STALL_TICKS:
						prog.ban_until = _clock + STALL_BAN_SECONDS
						prog.best = INF
						prog.stall = 0
						goal = Vector2.ZERO
						hold = false
	_progress[m.get_instance_id()] = prog

	m.tactic_goal = goal
	m.tactic_goal_active = goal != Vector2.ZERO
	m.tactic_hold = hold and m.tactic_goal_active
	m.tactic_label = label
	if m.tactic_goal_active and map and map.has_method("segment_walkable"):
		m.tactic_path_clear = map.segment_walkable(m.global_position, goal, bool(m.is_amphibious) if "is_amphibious" in m else false)
	else:
		m.tactic_path_clear = false

func _nudge_walkable(map: Node, P: Vector2, goal: Vector2, amph: bool) -> Vector2:
	var off = goal - P
	for scale in [0.75, 0.5]:
		var c = P + off * scale
		if map.is_world_walkable(c, amph):
			return c
	for da in [0.5, -0.5, 1.0, -1.0]:
		var c2 = P + off.rotated(da)
		if map.is_world_walkable(c2, amph):
			return c2
	return Vector2.ZERO

# If the current plan is clearly failing (no hits landed after REPLAN_AFTER
# seconds, or the squad is being ground down), swap to a different one.
func _maybe_replan(squad: Node, members: Array, director: Node) -> void:
	if _replan_cooldown > 0.0 or _plan_time < float(cfg.get("replan_after", REPLAN_AFTER)) or director == null or not director.has_method("choose_tactic_genome"):
		return
	var no_hits = squad.hits_landed - _plan_hits_at_start <= 0 and squad.first_engagement_time >= 0.0
	var ground_down = squad.initial_members >= 3 and squad.active_members * 2 <= squad.initial_members and squad.total_damage_taken > squad.total_damage_dealt
	if not (no_hits or ground_down):
		return
	var next: Dictionary = director.choose_tactic_genome(plan_name, bias)
	if next.is_empty() or str(next.get("base", "")) == plan_name:
		return
	print("[TACTICS] '%s' failing -> switching to '%s'" % [genome_id, next["id"]])
	set_genome(next)
	_say(squad, director, "replan", plan_name)
	_plan_hits_at_start = squad.hits_landed
	_replan_cooldown = REPLAN_COOLDOWN

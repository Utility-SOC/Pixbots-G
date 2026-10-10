class_name CoverSense
extends RefCounted

# Cover queries on the shared obstacle grid (SolidGridBatcher: Rust grid march with a GDScript fallback). Obstacles are
# real cover: projectiles collide with them (layer 32) and sight is blocked by them (SightAndSearchBatcher). Everything
# here is pure query logic over `map` (obstacles dict, tile_size, is_world_walkable) so CoverBrain (an enemy using cover)
# and SquadTactics (a squad reacting to the player using cover) share one definition of "cover".
#
# Cells are chosen for a body 40 px wide: a standable cell has no obstacle orthogonally next to it (a mech centred
# beside an obstacle would overlap it), so cover means "an obstacle between me and the threat, a step or two away".

const BACKLINE_ROLES = ["sniper", "jammer", "support", "commander", "anti_missile", "remediation"] # mirrors SquadTactics.BACKLINE_ROLES
const SEARCH_RADIUS_TILES = 7
const BLOCKER_MAX_TILES = 3.5 # the blocking obstacle must sit this close to the covered body to count as cover
const PEEK_RADIUS_TILES = 3
const MIN_THREAT_FRAC = 0.55 # never hide closer to the threat than this fraction of engagement distance
const PEEK_RANGE_SLACK = 120.0

# Test seam: checks inject a batcher bound to a synthetic map; live play uses the SolidGridBatcher autoload.
static var batcher = null

static func _grid():
	return batcher if batcher != null else SolidGridBatcher

# Plans per physics frame across all callers (a plan is ~100-200 cells and one batched grid march).
const PLANS_PER_FRAME = 3
static var _budget_frame: int = -1
static var _budget_used: int = 0

static func take_budget() -> bool:
	var f = Engine.get_physics_frames()
	if f != _budget_frame:
		_budget_frame = f
		_budget_used = 0
	if _budget_used >= PLANS_PER_FRAME:
		return false
	_budget_used += 1
	return true

static func cell_of(map, pos: Vector2) -> Vector2i:
	var ts = float(map.tile_size)
	return Vector2i(int(floor(pos.x / ts)), int(floor(pos.y / ts)))

static func center_of(map, cell: Vector2i) -> Vector2:
	var ts = float(map.tile_size)
	return Vector2((cell.x + 0.5) * ts, (cell.y + 0.5) * ts)

# Walkable, and no obstacle orthogonally adjacent: a 40 px body centred 32 px from an obstacle's centre overlaps it, but
# a diagonal neighbour (45 px away) does not. (tune: the old 3x3 rule left almost no cells in dense forest.)
static func standable(map, cell: Vector2i, amph: bool = false) -> bool:
	if not map.is_world_walkable(center_of(map, cell), amph):
		return false
	return not (map.obstacles.has(Vector2i(cell.x + 1, cell.y)) or map.obstacles.has(Vector2i(cell.x - 1, cell.y)) \
		or map.obstacles.has(Vector2i(cell.x, cell.y + 1)) or map.obstacles.has(Vector2i(cell.x, cell.y - 1)))

# A hiding cell near `from` that the threat cannot see, plus a "peek" cell a short step away that it CAN, within weapon
# reach. Returns {} when nothing suitable is close: {"hide": Vector2, "peek": Vector2}.
static func find_cover(map, from: Vector2, threat: Vector2, eng: float, amph: bool = false) -> Dictionary:
	if map == null:
		return {}
	var ts = float(map.tile_size)
	var c0 = cell_of(map, from)
	var min_threat = eng * MIN_THREAT_FRAC
	var cells: Array = []
	var queries: Array = []
	for dx in range(-SEARCH_RADIUS_TILES, SEARCH_RADIUS_TILES + 1):
		for dy in range(-SEARCH_RADIUS_TILES, SEARCH_RADIUS_TILES + 1):
			var cell = Vector2i(c0.x + dx, c0.y + dy)
			var pos = center_of(map, cell)
			var dt = pos.distance_to(threat)
			if dt < min_threat or dt > eng + PEEK_RANGE_SLACK * 2.0:
				continue
			if not standable(map, cell, amph):
				continue
			cells.append(cell)
			queries.append({"from": pos, "to": threat})
	if cells.is_empty():
		return {}
	var clearance: Array = _grid().batch_probe_clearance(queries)
	var scored: Array = []
	for i in range(cells.size()):
		var pos = center_of(map, cells[i])
		var dt = pos.distance_to(threat)
		var clr = float(clearance[i])
		# Blocked (the march stopped short of the threat) by something close to this cell.
		if clr < dt - ts and clr <= BLOCKER_MAX_TILES * ts:
			scored.append({"cell": cells[i], "score": from.distance_to(pos) + 0.5 * absf(dt - eng)})
	if scored.is_empty():
		return {}
	scored.sort_custom(func(a, b): return a.score < b.score)
	for k in range(mini(8, scored.size())):
		var hide_cell: Vector2i = scored[k].cell
		var hide_pos = center_of(map, hide_cell)
		if not _robustly_hidden(map, hide_pos, threat):
			continue
		var peek = _find_peek(map, hide_cell, threat, eng, amph)
		if peek != Vector2.ZERO:
			return {"hide": hide_pos, "peek": peek}
	return {}

# A cell on the very edge of a shadow is useless (the body is 40 px wide and arrives a few px off-centre): the line from
# a small offset to either side must be blocked too.
static func _robustly_hidden(map, pos: Vector2, threat: Vector2) -> bool:
	var ts = float(map.tile_size)
	var side = (threat - pos).normalized().orthogonal() * (ts * 0.45)
	var dt = pos.distance_to(threat)
	var res: Array = _grid().batch_probe_clearance([{"from": pos + side, "to": threat}, {"from": pos - side, "to": threat}])
	for r in res:
		if float(r) >= dt - ts:
			return false
	return true

static func _find_peek(map, hide_cell: Vector2i, threat: Vector2, eng: float, amph: bool) -> Vector2:
	var cells: Array = []
	var queries: Array = []
	var hide_pos = center_of(map, hide_cell)
	for dx in range(-PEEK_RADIUS_TILES, PEEK_RADIUS_TILES + 1):
		for dy in range(-PEEK_RADIUS_TILES, PEEK_RADIUS_TILES + 1):
			if dx == 0 and dy == 0:
				continue # the hide cell itself
			var cell = Vector2i(hide_cell.x + dx, hide_cell.y + dy)
			var pos = center_of(map, cell)
			if pos.distance_to(threat) > eng + PEEK_RANGE_SLACK or not standable(map, cell, amph):
				continue
			cells.append(cell)
			queries.append({"from": pos, "to": threat})
	if cells.is_empty():
		return Vector2.ZERO
	var los: Array = _grid().batch_line_of_sight(queries)
	var best = Vector2.ZERO
	var best_d = INF
	for i in range(cells.size()):
		if not los[i]:
			continue
		var pos = center_of(map, cells[i])
		var d = pos.distance_to(hide_pos)
		if d < best_d:
			best_d = d
			best = pos
	return best

# Is `body_pos` using cover against `from`? True when an obstacle within BLOCKER_MAX_TILES of the body stops the line to
# `from`. Returns {"covered": bool, "depth": px to the blocker}.
static func body_cover(map, body_pos: Vector2, from: Vector2) -> Dictionary:
	if map == null:
		return {"covered": false, "depth": 0.0}
	var ts = float(map.tile_size)
	var dist = body_pos.distance_to(from)
	var clr = float(_grid().batch_probe_clearance([{"from": body_pos, "to": from}])[0])
	var covered = clr < dist - ts and clr <= BLOCKER_MAX_TILES * ts
	return {"covered": covered, "depth": clr}

# What is in the way between `from` and `to`: {"cell", "pos", "name"} for the first obstacle the line meets, {} when the
# line is clear. Lets a bot aim at the rock the player is hiding behind.
static func blocker_info(map, from: Vector2, to: Vector2) -> Dictionary:
	if map == null:
		return {}
	var ts = float(map.tile_size)
	var dist = from.distance_to(to)
	if dist < 1.0:
		return {}
	var clr = float(_grid().batch_probe_clearance([{"from": from, "to": to}])[0])
	if clr >= dist - ts * 0.25:
		return {}
	var hit = from + (to - from) / dist * (clr + ts * 0.5)
	var c = cell_of(map, hit)
	var best = Vector2i(-999, -999)
	var best_d = INF
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var cc = Vector2i(c.x + dx, c.y + dy)
			if map.obstacles.has(cc):
				var d = center_of(map, cc).distance_to(hit)
				if d < best_d:
					best_d = d
					best = cc
	if best.x == -999:
		return {}
	return {"cell": best, "pos": center_of(map, best), "name": str(map.obstacles[best])}

# Can a bot with this much Explosion in its shots actually wear this obstacle down? Hard cover (boulders, stone walls)
# shrugs off everything but explosives; soft cover and trees chip away under anything.
const SUPPRESS_MIN_EXPLOSION = 0.25
static func can_damage(obstacle_name: String, explosion_share: float) -> bool:
	if obstacle_name == "Tree" or obstacle_name == "RuinPart":
		return true
	if not DestructibleObstacle.OBSTACLE_STATS.has(obstacle_name):
		return false
	if obstacle_name in DestructibleObstacle.ABSORBERS:
		return explosion_share >= SUPPRESS_MIN_EXPLOSION
	return true

# A walkable cell near `ideal` from which `target` is visible at a sensible firing distance: where to send a flanker so
# a target behind cover is flushed out instead of shot at through the obstacle. Vector2.ZERO when there is none.
static func find_exposed_cell(map, target: Vector2, ideal: Vector2, eng: float, amph: bool = false, radius_tiles: int = 10) -> Vector2:
	if map == null:
		return Vector2.ZERO
	var c0 = cell_of(map, ideal)
	var cells: Array = []
	var queries: Array = []
	var lo = maxf(eng * 0.6, 160.0)
	var hi = eng * 1.25 + 60.0
	for dx in range(-radius_tiles, radius_tiles + 1):
		for dy in range(-radius_tiles, radius_tiles + 1):
			var cell = Vector2i(c0.x + dx, c0.y + dy)
			var pos = center_of(map, cell)
			var dt = pos.distance_to(target)
			if dt < lo or dt > hi or not standable(map, cell, amph):
				continue
			cells.append(cell)
			queries.append({"from": pos, "to": target})
	if cells.is_empty():
		return Vector2.ZERO
	var los: Array = _grid().batch_line_of_sight(queries)
	var best = Vector2.ZERO
	var best_d = INF
	for i in range(cells.size()):
		if not los[i]:
			continue
		var pos = center_of(map, cells[i])
		var d = pos.distance_to(ideal)
		if d < best_d:
			best_d = d
			best = pos
	return best

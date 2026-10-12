extends Node

# Cover awareness (scripts/ai/CoverSense.gd, CoverBrain.gd, SquadTactics flush): on a synthetic map with one wall,
# an enemy finds a hide cell the player cannot see plus a peek cell it can, runs the SEEK -> HIDE -> PEEK cycle and
# does not shoot while hidden; bosses and melee bots never use cover; a player standing behind the wall is detected as
# covered and flankers are redirected to cells with a clear line.

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const SolidGridBatcherScript = preload("res://scripts/core/SolidGridBatcher.gd")
const SquadTacticsScript = preload("res://scripts/ai/SquadTactics.gd")
const PlayerModelScript = preload("res://scripts/ai/PlayerModel.gd")
const SquadDirectorScript = preload("res://scripts/ai/SquadDirector.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

const TILE = 32
const W = 40
const H = 40

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _cc(cx: int, cy: int) -> Vector2:
	return Vector2((cx + 0.5) * TILE, (cy + 0.5) * TILE)

func _ready():
	var map = MapGeneratorScript.new()
	map.width = W
	map.height = H
	map.tile_size = TILE
	map.obstacles = {}
	map.terrain = []
	for y in range(H):
		var row = []
		for x in range(W):
			row.append(MapGeneratorScript.BiomeType.GRASSLAND)
		map.terrain.append(row)
	for y in range(15, 26): # wall x=20, y=15..25
		map.obstacles[Vector2i(20, y)] = "Boulder"
	var batcher = SolidGridBatcherScript.new()
	batcher._map = map
	CoverSense.batcher = batcher

	# --- cover queries --------------------------------------------------------
	var threat = _cc(28, 20)
	var from = _cc(17, 8)
	_check("exposed before: clear line from the start point", batcher.batch_line_of_sight([{"from": from, "to": threat}])[0])
	var spot = CoverSense.find_cover(map, from, threat, 300.0)
	_check("find_cover finds a hide/peek pair", not spot.is_empty())
	if not spot.is_empty():
		_check("hide cell is out of the threat's sight", not batcher.batch_line_of_sight([{"from": spot.hide, "to": threat}])[0])
		_check("peek cell sees the threat", batcher.batch_line_of_sight([{"from": spot.peek, "to": threat}])[0])
		_check("peek is within a few tiles of hide", spot.hide.distance_to(spot.peek) <= 4.5 * TILE)
		_check("hide cell is standable (no obstacle orthogonally next to it)", CoverSense.standable(map, CoverSense.cell_of(map, spot.hide)))
		_check("hide cell is not closer to the threat than the minimum", spot.hide.distance_to(threat) >= 300.0 * CoverSense.MIN_THREAT_FRAC)
	var open = CoverSense.find_cover(map, _cc(5, 35), _cc(8, 38), 300.0)
	_check("no wall near an open-field position: no cover offered", open.is_empty())

	# --- player cover ---------------------------------------------------------
	_check("player behind the wall is covered", CoverSense.body_cover(map, _cc(22, 20), _cc(10, 20))["covered"])
	_check("player in the open is not covered", not CoverSense.body_cover(map, _cc(22, 5), _cc(10, 5))["covered"])
	_check("player far behind the wall is not 'using' it", not CoverSense.body_cover(map, _cc(35, 20), _cc(5, 20))["covered"])
	var flush = CoverSense.find_exposed_cell(map, _cc(22, 20), _cc(14, 16), 300.0)
	_check("a flanker is sent to a cell with a clear line to the covered player", flush != Vector2.ZERO and batcher.batch_line_of_sight([{"from": flush, "to": _cc(22, 20)}])[0])

	# --- the enemy cycle ------------------------------------------------------
	var player = Node2D.new()
	player.global_position = threat
	var m = MechScript.new()
	m.global_position = from
	m.target = player
	m.engagement_distance = 300.0
	m.max_hp = 100.0
	m.hp = 30.0 # wounded -> pressured
	m.time_since_last_hit = 0.0
	m.has_sight_of_player = true
	var brain = CoverBrain.new(m)
	var seen := {}
	var shot_while_hidden = false
	var hidden_in_los = false
	var was_active = false
	var ended = false
	for step in range(400): # 40 s at 0.1
		CoverSense._budget_frame = -1
		brain.update(0.1, map)
		m.time_since_last_hit = 0.0 # keep the pressure on
		if was_active and not brain.active():
			ended = true
		was_active = brain.active()
		if brain.active():
			seen[brain.mode] = true
			m.global_position += brain.desired_velocity(180.0) * 0.1
			if brain.hiding():
				if batcher.batch_line_of_sight([{"from": m.global_position, "to": threat}])[0] and m.global_position.distance_to(brain.hide_pos) < 20.0:
					hidden_in_los = true
	_check("enemy took cover (SEEK)", seen.has(CoverBrain.Mode.SEEK))
	_check("enemy hid (HIDE)", seen.has(CoverBrain.Mode.HIDE))
	_check("enemy peeked (PEEK)", seen.has(CoverBrain.Mode.PEEK))
	_check("a hiding enemy at its cell is out of the player's sight", not hidden_in_los)
	_check("the cycle ends (cooldown, not stuck in cover forever)", ended)

	var boss = MechScript.new()
	boss.is_boss = true
	boss.target = player
	boss.engagement_distance = 300.0
	boss.hp = 10.0
	boss.global_position = from
	var boss_brain = CoverBrain.new(boss)
	for i in range(50):
		CoverSense._budget_frame = -1
		boss_brain.update(0.1, map)
	_check("bosses never use cover", not boss_brain.active())
	var brawler = MechScript.new()
	brawler.target = player
	brawler.engagement_distance = 90.0
	brawler.hp = 10.0
	brawler.global_position = from
	var br_brain = CoverBrain.new(brawler)
	for i in range(50):
		CoverSense._budget_frame = -1
		br_brain.update(0.1, map)
	_check("melee bots never use cover", not br_brain.active())
	var healthy = MechScript.new()
	healthy.target = player
	healthy.engagement_distance = 300.0
	healthy.hp = 100.0
	healthy.max_hp = 100.0
	healthy.time_since_last_hit = 99.0
	healthy.global_position = from
	var h_brain = CoverBrain.new(healthy)
	for i in range(50):
		CoverSense._budget_frame = -1
		h_brain.update(0.1, map)
	_check("an unhurt, unpressured bot stays in the fight", not h_brain.active())

	# --- squad tactics flush --------------------------------------------------
	var tactics = SquadTacticsScript.new()
	tactics.player_covered = true
	tactics._flush_active = true
	var fm = MechScript.new()
	fm.global_position = _cc(14, 16)
	fm.engagement_distance = 300.0
	fm.combat_role = "brawler"
	var info = {"kind": "flank", "side": 1.0, "slot": 0}
	tactics._set_member_goal(fm, info, _cc(22, 20), {"arc": 1.5708}, map, 0)
	_check("a flanker's goal is flagged FLUSH and sees the covered player", fm.tactic_label == "FLUSH" and batcher.batch_line_of_sight([{"from": fm.tactic_goal, "to": _cc(22, 20)}])[0])

	# --- caution ---------------------------------------------------------------
	var cautions = {}
	for i in range(20):
		var cm = MechScript.new()
		cautions[CoverBrain.new(cm).caution] = true
		cm.free()
	_check("bots differ in caution (%d distinct of 20)" % cautions.size(), cautions.size() >= 10)
	var all_in_range = true
	for c in cautions:
		all_in_range = all_in_range and c >= CoverBrain.CAUTION_RANGE.x and c <= 1.0
	_check("caution stays within its range", all_in_range)
	# Large instance ids (a long session) used to wrap id * 2654435761 negative and drag caution below its range.
	var big_ok = true
	for i in range(50):
		var h = float(posmod((8143174189266 + i * 16777259) * 2654435761, 1000)) / 1000.0
		big_ok = big_ok and h >= 0.0 and h < 1.0
	_check("the caution hash stays in [0,1) for very large instance ids", big_ok)
	var sniper = MechScript.new()
	sniper.combat_role = "sniper"
	var plain = MechScript.new()
	plain.combat_role = "brawler"
	_check("backline roles are warier than the same bot as a brawler", CoverBrain.new(sniper).caution >= CoverBrain.new(plain).caution)

	# --- a single chip does not send a healthy bot hiding; a real beating does -----
	var chip = MechScript.new()
	chip.target = player
	chip.engagement_distance = 300.0
	chip.max_hp = 100.0
	chip.hp = 100.0
	chip.global_position = from
	chip.has_sight_of_player = true
	var chip_brain = CoverBrain.new(chip)
	chip_brain.caution = 1.0
	chip.hp = 96.0
	for i in range(30):
		CoverSense._budget_frame = -1
		chip_brain.update(0.1, map)
	_check("a 4% chip on a healthy bot does not trigger cover", not chip_brain.active())
	chip.hp = 80.0 # a 16% loss in one tick
	for i in range(30):
		CoverSense._budget_frame = -1
		chip_brain.update(0.1, map)
	_check("a 16% hit does trigger cover", chip_brain.active() or chip_brain._cooldown > 0.0)

	# --- reactive duck + compromised cover --------------------------------------
	var duck = MechScript.new()
	duck.target = player
	duck.engagement_distance = 300.0
	duck.max_hp = 100.0
	duck.hp = 45.0
	duck.global_position = from
	duck.has_sight_of_player = true
	var duck_brain = CoverBrain.new(duck)
	duck_brain.caution = 1.0
	var ducks_before = CoverBrain.stat_ducks
	var replans_before = CoverBrain.stat_replans
	var went_peek = false
	for step in range(300):
		CoverSense._budget_frame = -1
		duck_brain.update(0.1, map)
		if duck_brain.active():
			duck.global_position += duck_brain.desired_velocity(180.0) * 0.1
		if duck_brain.mode == CoverBrain.Mode.PEEK and not went_peek:
			went_peek = true
			duck.hp -= 10.0 # shot while standing in the open
	_check("shot while peeking, the bot ducks back at once", went_peek and CoverBrain.stat_ducks > ducks_before)

	var wall_backup = map.obstacles.duplicate()
	var brain2_bot = MechScript.new()
	brain2_bot.target = player
	brain2_bot.engagement_distance = 300.0
	brain2_bot.max_hp = 100.0
	brain2_bot.hp = 40.0
	brain2_bot.global_position = from
	brain2_bot.has_sight_of_player = true
	var b2 = CoverBrain.new(brain2_bot)
	b2.caution = 1.0
	var hid = false
	for step in range(200):
		CoverSense._budget_frame = -1
		b2.update(0.1, map)
		if b2.active():
			brain2_bot.global_position += b2.desired_velocity(180.0) * 0.1
		if b2.hiding() and brain2_bot.global_position.distance_to(b2.hide_pos) < 20.0 and not hid:
			hid = true
			for y in range(15, 26):
				map.obstacles.erase(Vector2i(20, y)) # the cover is shot away
			b2._check = 0.0
	_check("destroyed cover is noticed and re-planned or abandoned", hid and (CoverBrain.stat_replans > replans_before))
	map.obstacles = wall_backup

	# --- suppression of the player's cover -------------------------------------
	_check("hard cover needs explosives", not CoverSense.can_damage("Boulder", 0.0) and CoverSense.can_damage("Boulder", 0.5))
	_check("soft cover and trees always chip", CoverSense.can_damage("Cactus", 0.0) and CoverSense.can_damage("Tree", 0.0))
	_check("unknown obstacle types are left alone", not CoverSense.can_damage("Tractor", 1.0))
	var blk = CoverSense.blocker_info(map, _cc(14, 20), _cc(22, 20))
	_check("blocker_info finds the wall between a bot and the covered player", not blk.is_empty() and blk["cell"].x == 20 and blk["name"] == "Boulder")
	_check("blocker_info is empty on a clear line", CoverSense.blocker_info(map, _cc(14, 8), _cc(22, 8)).is_empty())
	var sup_tactics = SquadTacticsScript.new()
	sup_tactics._flush_active = true
	var sm = MechScript.new()
	sm.global_position = _cc(14, 20)
	sm.engagement_distance = 300.0
	sup_tactics._assign_suppressors([sm], _cc(22, 20), map)
	_check("a bot without explosives does not shoot a boulder", sm.suppress_pos == Vector2.ZERO)
	for y in range(15, 26):
		map.obstacles[Vector2i(20, y)] = "Cactus"
	sup_tactics._assign_suppressors([sm], _cc(22, 20), map)
	_check("a bot behind-the-cover shoots soft cover the player hides behind", sm.suppress_pos == _cc(20, 20))
	sup_tactics._flush_active = false
	sup_tactics._assign_suppressors([sm], _cc(22, 20), map)
	_check("suppression stops when the player leaves cover", sm.suppress_pos == Vector2.ZERO)
	map.obstacles = wall_backup

	# --- plan weighting by how much the player uses cover --------------------------
	var model = PlayerModelScript.new()
	model.cover_share = 0.1
	_check("little cover use: plan weights untouched", model.cover_plan_multipliers().is_empty())
	model.cover_share = 0.8
	var mult = model.cover_plan_multipliers()
	_check("a cover-heavy player draws more flanking and fewer swarms", mult["pincer"] > 1.0 and mult["encircle"] > 1.0 and mult["swarm"] < 1.0)
	var merged = SquadDirectorScript._merge_plan_mults({"swarm": 0.8}, mult)
	_check("cover and habit multipliers combine multiplicatively", is_equal_approx(merged["swarm"], 0.8 * mult["swarm"]) and merged["pincer"] == mult["pincer"])

	CoverSense.batcher = null
	print("CoverCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

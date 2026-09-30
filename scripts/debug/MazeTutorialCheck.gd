extends Node

const MapGeneratorScript = preload("res://scripts/core/MapGenerator.gd")
const MazeScript = preload("res://scripts/ui/MazeTutorial.gd")
const CutsceneScript = preload("res://scripts/cutscene/CutscenePlayer.gd")

class FakeMain extends Node:
	var map
	var player
	var lines: Array = []
	func show_dialogue(speaker, text, color = Color.WHITE, duration = 4.0):
		lines.append(text)

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var fm = FakeMain.new()
	add_child(fm)
	var map = MapGeneratorScript.new()
	map.map_type = "Forest"
	map.map_seed = 4242
	fm.add_child(map)
	fm.map = map
	var player = Node2D.new()
	player.add_to_group("player")
	fm.add_child(player)
	player.global_position = Vector2(150 * 32, 100 * 32)
	fm.player = player
	var before_obs = map.obstacles.duplicate()
	var before_biome = map.terrain[100][160]

	var mz = MazeScript.new()
	fm.add_child(mz)
	var finished = [false]
	mz.finished.connect(func(): finished[0] = true)
	_check("maze starts", mz.start(fm))
	_check("maze exists with path", mz.maze.get("path", []).size() >= 6)
	var boulders = 0
	for c in map.obstacles:
		if map.obstacles[c] == "Boulder" and c.x > 140 and c.x < 210:
			boulders += 1
	_check("boulder plugs placed (%d)" % boulders, boulders >= 3)
	_check("Frank speaks on start", fm.lines.size() >= 1)
	# not yet at exit
	mz._process(0.1)
	_check("not finished at the entrance", not finished[0])
	# walk to the exit
	var ex: Vector2i = mz.maze["exit"]
	player.global_position = Vector2(ex.x * 32 + 16, ex.y * 32 + 16)
	mz._process(0.1)
	_check("finishes at the exit", finished[0])
	await get_tree().process_frame
	_check("terrain restored exactly", map.obstacles.size() == before_obs.size() and map.terrain[100][160] == before_biome)
	var same = true
	for c in before_obs:
		if map.obstacles.get(c, "") != before_obs[c]:
			same = false
	_check("every original obstacle is back", same)

	# skip path: complete() without reaching the exit also restores
	var mz2 = MazeScript.new()
	fm.add_child(mz2)
	player.global_position = Vector2(150 * 32, 100 * 32)
	mz2.start(fm)
	mz2.complete()
	await get_tree().process_frame
	_check("complete() restores terrain", map.obstacles.size() == before_obs.size())

	# data: every cutscene parses and loads; manifest + tutorial references exist
	var dir = DirAccess.open("res://config/cutscenes/")
	var bad = 0
	for f in dir.get_files():
		if not f.ends_with(".json") or f == "manifest.json":
			continue
		var p = CutsceneScript.create_from_file("res://config/cutscenes/" + f)
		if p == null:
			bad += 1
			push_error("bad cutscene " + f)
		else:
			p.free()
	_check("all cutscenes load", bad == 0)
	var tut = JSON.parse_string(FileAccess.get_file_as_string("res://config/tutorial.json"))
	var missing = 0
	for s in tut["steps"]:
		if s.get("type", "") == "cinematic" and not FileAccess.file_exists("res://config/cutscenes/" + s["cutscene"]):
			missing += 1
	_check("tutorial cinematics all exist", missing == 0)
	var man = JSON.parse_string(FileAccess.get_file_as_string("res://config/cutscenes/manifest.json"))
	for w in man["waves"]:
		if not FileAccess.file_exists("res://config/cutscenes/" + man["waves"][w]):
			missing += 1
	_check("manifest files exist", missing == 0)
	print("maze tutorial check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

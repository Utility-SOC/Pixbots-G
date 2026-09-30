extends Node

# Frank's maze: a short obstacle course built next to the player with
# TerrainEditor. Teaches movement, aiming and demolition - a few connectors on
# the solution path are plugged with boulders that have to be shot out. Done
# when the player reaches the exit (or the tutorial's skip button calls
# complete()); the original terrain is restored afterwards.

const TerrainEditorScript = preload("res://scripts/core/TerrainEditor.gd")

signal finished

const MAZE_W = 41
const MAZE_H = 25
const CORRIDOR = 3
const WALL_W = 1
const EXIT_RADIUS_CELLS = 3.0
const PLUG_COUNT = 2

var main: Node
var editor
var snapshot: Dictionary = {}
var maze: Dictionary = {}
var _hints: Array = []
var _done: bool = false

func start(main_node: Node) -> bool:
	main = main_node
	var map = main.map if main.get("map") != null else null
	var player = main.player if main.get("player") != null else null
	if map == null or player == null or not is_instance_valid(player):
		return false
	editor = TerrainEditorScript.new(map)
	var pc = Vector2i(int(player.global_position.x / map.tile_size), int(player.global_position.y / map.tile_size))
	var pitch = CORRIDOR + WALL_W
	var cols = int((MAZE_W - WALL_W) / pitch)
	var rows = int((MAZE_H - WALL_W) / pitch)
	var origin = Vector2i(pc.x + 3, pc.y - ((rows / 2) * pitch + WALL_W + CORRIDOR / 2))
	origin.x = clampi(origin.x, 10, map.width - MAZE_W - 10)
	origin.y = clampi(origin.y, 10, map.height - MAZE_H - 10)
	var region = Rect2i(origin, Vector2i(MAZE_W, MAZE_H))
	snapshot = editor.snapshot(region.grow(2))
	# Open ground first so the maze isn't cut up by existing obstacles/water.
	editor.carve_rect(region.grow(2))
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	maze = editor.build_maze(region, rng, CORRIDOR, WALL_W)
	if maze.is_empty():
		editor.revert_pending()
		return false
	_plug_path(maze["path"], rng)
	editor.commit()
	_hints = [
		{"at": 0.25, "text": "Left, right, it's a maze - what do you want from me? Keep going."},
		{"at": 0.5, "text": "Halfway. See a boulder in the way? Shoot it. Fire and explosives work best."},
		{"at": 0.8, "text": "Almost there. Exit's the gap on the far wall."},
	]
	_say("Maze is up! Get to the exit on the far side - the gap in the right wall.")
	return true

# Block the passage between two rooms on the solution path with boulders
# across the full corridor width (a plugged connector, not a wall).
func _plug_path(path: Array, rng: RandomNumberGenerator) -> void:
	if path.size() < 6:
		return
	var candidates: Array = range(2, path.size() - 2)
	var plugged = 0
	var guard = 0
	while plugged < PLUG_COUNT and not candidates.is_empty() and guard < 20:
		guard += 1
		var i: int = candidates[rng.randi() % candidates.size()]
		candidates.erase(i)
		candidates = candidates.filter(func(j): return abs(j - i) > 2)
		var a: Vector2i = path[i]
		var b: Vector2i = path[i + 1]
		var mid = (a + b) / 2
		var d = b - a
		var horizontal = abs(d.x) > abs(d.y)
		var half = CORRIDOR / 2
		for k in range(-half, half + 1):
			var c = mid + (Vector2i(0, k) if horizontal else Vector2i(k, 0))
			editor.place_obstacle(c, "Boulder")
		plugged += 1

func _process(_delta: float) -> void:
	if _done or maze.is_empty() or not is_instance_valid(main.player):
		return
	var map = main.map
	var exit_c: Vector2i = maze["exit"]
	var pc = main.player.global_position / float(map.tile_size)
	var dist = Vector2(pc.x - exit_c.x, pc.y - exit_c.y).length()
	if dist <= EXIT_RADIUS_CELLS:
		complete()
		return
	var entrance: Vector2i = maze["entrance"]
	var total = Vector2(exit_c - entrance).length()
	var progress = clamp(1.0 - dist / max(1.0, total), 0.0, 1.0)
	while not _hints.is_empty() and progress >= float(_hints[0]["at"]):
		_say(_hints.pop_front()["text"])

func _say(text: String) -> void:
	if main and main.has_method("show_dialogue"):
		main.show_dialogue("Frank", text, Color(0.7, 0.9, 1.0), 4.0)

func complete() -> void:
	if _done:
		return
	_done = true
	if editor:
		editor.restore(snapshot)
		editor.commit()
	finished.emit()
	queue_free()

func _exit_tree() -> void:
	if not _done and editor:
		_done = true
		editor.restore(snapshot)
		editor.commit()

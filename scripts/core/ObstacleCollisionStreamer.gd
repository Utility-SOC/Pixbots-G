class_name ObstacleCollisionStreamer
extends Node

# Physics LOD for terrain obstacles. A big map carries ~3k StaticBody2Ds (almost all
# DestructibleObstacle boulders/cacti), and Godot's 2D physics paid for every one of them even when
# nothing was anywhere near: disabling collision on half of them was worth +9..+21 fps in the wave-34
# bench on the HD 4000. Only mechs (move_and_slide) and legacy physics projectiles actually need an
# obstacle's collision shape, and only when they are close, so this keeps shapes enabled inside a
# radius around each of those and disables the rest (PhysicsServer2D.body_set_shape_disabled: the node
# stays in the tree, keeps its hp/draw/group membership/broadphase hit-test, it just leaves the
# physics broadphase). Batch-pool projectiles hit obstacles through ProjectileBroadphase (group
# "obstacle"), not physics, so they are unaffected.
#
# Contract: anything that queries the physics space for layer 32 (Mech.OBSTACLE_LAYER) far from every
# mech/projectile will not see a sleeping obstacle. Today only mechs and Projectile nodes collide
# with it, and both are covered here.

const CELL := 256.0
const TICK := 0.2
const MECH_RADIUS := 384.0 # >= fastest mech speed * TICK + margin
const PLAYER_RADIUS := 640.0
const PROJECTILE_RADIUS := 320.0
const OBSTACLE_LAYER := 32

var enabled := true
var _buckets: Dictionary = {} # Vector2i -> Array of StaticBody2D
var _known_count := -1
var _seen: Dictionary = {} # instance_id -> true for obstacles already in the invariant
var _active_cells: Dictionary = {} # Vector2i -> true (cells whose obstacles are enabled)
var _acc := 0.0
# Stats for benches/checks.
var last_awake := 0
var last_asleep := 0
var toggles := 0
var _log := OS.get_cmdline_user_args().has("--streamlog")

func _ready() -> void:
	if _log: print("STREAMER ready enabled=%s" % enabled)

func _physics_process(delta: float) -> void:
	_acc += delta
	if _log and Engine.get_physics_frames() % 120 == 0:
		print("STREAMER pp frame=%d acc=%.2f paused=%s" % [Engine.get_physics_frames(), _acc, get_tree().paused])
	if _acc < TICK:
		return
	_acc = 0.0
	if enabled:
		refresh()
	elif _log:
		print("STREAMER tick but disabled")

static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))

# Invariant: a cell NOT in _active_cells has all its obstacles' shapes disabled; a cell in it has them
# enabled. Obstacles that appear later (map edits, new spawns) are enabled by default, so on a rebuild
# any NEW obstacle landing in a sleeping cell is put to sleep to restore the invariant.
func _rebuild_buckets() -> void:
	var seen_before := _seen
	_seen = {}
	_buckets.clear()
	var all: Array = EntityCache.get_group(&"obstacle")
	for o in all:
		if not is_instance_valid(o) or not (o is StaticBody2D) or o.collision_layer != OBSTACLE_LAYER:
			continue
		var c := _cell_of(o.global_position)
		if not _buckets.has(c):
			_buckets[c] = []
		_buckets[c].append(o)
		var id: int = o.get_instance_id()
		_seen[id] = true
		if not seen_before.has(id) and not _active_cells.has(c):
			_set_body(o, false)
	_known_count = all.size()

func _wanted_cells() -> Dictionary:
	var want := {}
	for g in [&"enemy", &"drone", &"player", &"projectile"]:
		var r := MECH_RADIUS
		if g == &"player": r = PLAYER_RADIUS
		elif g == &"projectile": r = PROJECTILE_RADIUS
		var span := ceili(r / CELL)
		for m in EntityCache.get_group(g):
			if not is_instance_valid(m) or not (m is Node2D):
				continue
			var c := _cell_of(m.global_position)
			for dx in range(-span, span + 1):
				for dy in range(-span, span + 1):
					want[Vector2i(c.x + dx, c.y + dy)] = true
	return want

func refresh() -> void:
	if EntityCache.get_group(&"obstacle").size() != _known_count:
		_rebuild_buckets()
	var want := _wanted_cells()
	# Cells that went quiet.
	for c in _active_cells.keys():
		if not want.has(c):
			_set_cell(c, false)
			_active_cells.erase(c)
	# Cells that woke up.
	for c in want:
		if _buckets.has(c) and not _active_cells.has(c):
			_set_cell(c, true)
			_active_cells[c] = true
	last_awake = 0
	last_asleep = 0
	for c in _buckets:
		if _active_cells.has(c): last_awake += _buckets[c].size()
		else: last_asleep += _buckets[c].size()
	if _log and Engine.get_physics_frames() % 300 < 12:
		print("STREAMER awake=%d asleep=%d cells=%d wanted=%d toggles=%d enabled=%s" % [last_awake, last_asleep, _buckets.size(), want.size(), toggles, enabled])

func _set_cell(c: Vector2i, awake: bool) -> void:
	for o in _buckets.get(c, []):
		if is_instance_valid(o) and not o.is_queued_for_deletion():
			_set_body(o, awake)

func _set_body(o: StaticBody2D, awake: bool) -> void:
	var rid: RID = o.get_rid()
	for i in PhysicsServer2D.body_get_shape_count(rid):
		PhysicsServer2D.body_set_shape_disabled(rid, i, not awake)
	toggles += 1

# Wake everything (Garage test range, editors, shutdown of the feature).
func wake_all() -> void:
	for c in _buckets:
		if not _active_cells.has(c):
			_set_cell(c, true)
			_active_cells[c] = true

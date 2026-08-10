class_name HexCoord
extends RefCounted

var q: int
var r: int

func _init(_q: int, _r: int):
	q = _q
	r = _r

func add(other: HexCoord) -> HexCoord:
	return HexCoord.new(q + other.q, r + other.r)

func sub(other: HexCoord) -> HexCoord:
	return HexCoord.new(q - other.q, r - other.r)

func mul(scalar: int) -> HexCoord:
	return HexCoord.new(q * scalar, r * scalar)

func to_cube() -> Vector3i:
	return Vector3i(q, r, -q - r)

static func from_cube(cube: Vector3i) -> HexCoord:
	return HexCoord.new(cube.x, cube.y)

func distance(other: HexCoord) -> int:
	var vec = sub(other)
	var cube = vec.to_cube()
	return (abs(cube.x) + abs(cube.y) + abs(cube.z)) / 2

func get_neighbors() -> Array[HexCoord]:
	var neighbors: Array[HexCoord] = []
	for dir in get_directions():
		neighbors.append(self.add(dir))
	return neighbors

func neighbor(direction_idx: int) -> HexCoord:
	var dirs = get_directions()
	return self.add(dirs[direction_idx % 6])

static var _cached_directions: Array[HexCoord] = []

# The 6 hex directions are constant - build them once and reuse instead of
# allocating 6 new HexCoord objects (+ a new array) on every single call.
# This is called from hot paths like energy-packet routing (_simulate_grid)
# and per-tile neighbor lookups, so the allocation churn was real GC pressure.
static func get_directions() -> Array[HexCoord]:
	if _cached_directions.is_empty():
		_cached_directions = [
			HexCoord.new(1, 0),   # 0: East
			HexCoord.new(0, 1),   # 1: South-East
			HexCoord.new(-1, 1),  # 2: South-West
			HexCoord.new(-1, 0),  # 3: West
			HexCoord.new(0, -1),  # 4: North-West
			HexCoord.new(1, -1)   # 5: North-East
		]
	return _cached_directions

static var _cached_direction_offsets: Array[Vector2i] = []

# Same 6 directions as get_directions() above, as raw Vector2i instead of
# HexCoord objects - for hot loops (AutoEquipSolver._solve_impl's BFS
# spanning tree, confirmed by direct profiling as ~44% of a real solve()
# call's wall-clock time) that only need a neighbor's (q,r) to check/insert
# into a Vector2i-keyed Dictionary and immediately discard it otherwise -
# HexCoord.neighbor() allocates a full new RefCounted for every one of
# those, even the ~5/6 that turn out to be already-visited and thrown away
# right after. Construct a real HexCoord only where one actually needs to
# survive (e.g. pushed onto a BFS queue as a new frontier node).
static func get_direction_offsets() -> Array[Vector2i]:
	if _cached_direction_offsets.is_empty():
		_cached_direction_offsets = [
			Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
			Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)
		]
	return _cached_direction_offsets

func _to_string() -> String:
	return "HexCoord(" + str(q) + ", " + str(r) + ")"

func equals(other: HexCoord) -> bool:
	if other == null:
		return false
	return q == other.q and r == other.r

# Standard hex-grid line-draw algorithm (cube-coordinate lerp + round) -
# used by the Garage's drag-to-paint-a-line feature (see GarageMenu.gd) to
# figure out which cells lie between where a drag paused and where it is
# now. Returns a contiguous, edge-adjacent path from `a` to `b` inclusive.
static func hex_line(a: HexCoord, b: HexCoord) -> Array[HexCoord]:
	var result: Array[HexCoord] = []
	var n = a.distance(b)
	if n == 0:
		result.append(a)
		return result
	var cube_a = Vector3(a.q, a.r, -a.q - a.r)
	var cube_b = Vector3(b.q, b.r, -b.q - b.r)
	for i in range(n + 1):
		var t = float(i) / float(n)
		result.append(_round_cube(cube_a.lerp(cube_b, t)))
	return result

static func _round_cube(cube: Vector3) -> HexCoord:
	var rx = round(cube.x)
	var ry = round(cube.y)
	var rz = round(cube.z)
	var dx = abs(rx - cube.x)
	var dy = abs(ry - cube.y)
	var dz = abs(rz - cube.z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return HexCoord.new(int(rx), int(ry))

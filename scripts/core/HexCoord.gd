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

static func get_directions() -> Array[HexCoord]:
	return [
		HexCoord.new(1, 0),   # 0: East
		HexCoord.new(0, 1),   # 1: South-East
		HexCoord.new(-1, 1),  # 2: South-West
		HexCoord.new(-1, 0),  # 3: West
		HexCoord.new(0, -1),  # 4: North-West
		HexCoord.new(1, -1)   # 5: North-East
	]

func rotate_left(center: HexCoord) -> HexCoord:
	var vec = self.sub(center)
	var cube = vec.to_cube()
	var rotated = HexCoord.from_cube(Vector3i(-cube.z, -cube.x, -cube.y))
	return center.add(rotated)

func rotate_right(center: HexCoord) -> HexCoord:
	var vec = self.sub(center)
	var cube = vec.to_cube()
	var rotated = HexCoord.from_cube(Vector3i(-cube.y, -cube.z, -cube.x))
	return center.add(rotated)

func _to_string() -> String:
	return "HexCoord(" + str(q) + ", " + str(r) + ")"

func equals(other: HexCoord) -> bool:
	if other == null:
		return false
	return q == other.q and r == other.r

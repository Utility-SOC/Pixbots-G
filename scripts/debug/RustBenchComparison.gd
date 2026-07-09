extends Node

# Standalone benchmark - NOT wired into any menu or game system. Exists only
# to get a real, in-engine GDScript timing number for the same workload
# already benchmarked in Rust and Python (see the Rust hybrid-architecture
# proof-of-concept discussion). Mirrors ComponentEquipment.gd's
# generate_procedural_shape()/_grow_primitive()/_try_add_hex() exactly, plus
# a HexCoord neighbor+distance math loop, so the three numbers are a fair
# apples-to-apples comparison of the same algorithm across languages.
#
# HOW TO RUN: create an empty scene, add a Node as the root, attach this
# script to it, and run that scene (F6). Results print to the Output panel.
# Safe to delete once you've got your number - it has no other purpose.

const DIRECTIONS = [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)
]

func _neighbor(h: Vector2i, d: int) -> Vector2i:
	return h + DIRECTIONS[d % 6]

func _distance(a: Vector2i, b: Vector2i) -> int:
	var dq = a.x - b.x
	var dr = a.y - b.y
	var dz = -dq - dr
	return (abs(dq) + abs(dr) + abs(dz)) / 2

func _try_add_hex(valid_hexes: Array, valid_set: Dictionary, h: Vector2i) -> bool:
	if abs(h.x) > 12 or abs(h.y) > 12:
		return false
	if valid_set.has(h):
		return false
	valid_hexes.append(h)
	valid_set[h] = true
	return true

func _grow_primitive(valid_hexes: Array, valid_set: Dictionary, attach: Vector2i, archetype: String, budget: int, rng: RandomNumberGenerator) -> int:
	var added = 0
	match archetype:
		"line":
			var dir = rng.randi() % 6
			var cur = attach
			for i in range(budget):
				cur = _neighbor(cur, dir)
				if _try_add_hex(valid_hexes, valid_set, cur): added += 1
		"hook":
			var dir = rng.randi() % 6
			var bend_at = max(1, int(budget * rng.randf_range(0.3, 0.6)))
			var cur = attach
			for i in range(bend_at):
				cur = _neighbor(cur, dir)
				if _try_add_hex(valid_hexes, valid_set, cur): added += 1
			var turn = 1 if rng.randf() < 0.5 else -1
			var new_dir = (dir + turn + 6) % 6
			for i in range(budget - bend_at):
				cur = _neighbor(cur, new_dir)
				if _try_add_hex(valid_hexes, valid_set, cur): added += 1
		"block":
			var frontier = [attach]
			var attempts = 0
			while added < budget and frontier.size() > 0 and attempts < budget * 20:
				attempts += 1
				var idx = rng.randi() % frontier.size()
				var cell = frontier[idx]
				var d = rng.randi() % 6
				var n = _neighbor(cell, d)
				if _try_add_hex(valid_hexes, valid_set, n):
					frontier.append(n)
					added += 1
				elif rng.randf() < 0.3:
					frontier.remove_at(idx)
	return added

const HEX_BUDGET = [10, 18, 28, 48, 72, 100]
const ARCHETYPES = ["line", "hook", "block"]

func _generate(rarity: int, is_torso: bool, rng: RandomNumberGenerator) -> Array:
	var valid_hexes: Array = []
	var valid_set: Dictionary = {}
	var budget_tier = clamp(rarity, 0, 4)
	if is_torso: budget_tier += 1
	var base_count = HEX_BUDGET[budget_tier]

	var start = Vector2i(0, 0)
	valid_hexes.append(start)
	valid_set[start] = true

	var num_primitives = 1
	match rarity:
		0: num_primitives = 1
		1: num_primitives = 2
		2: num_primitives = 3
		_: num_primitives = 4

	var remaining = base_count - 1
	for p in range(num_primitives):
		if remaining <= 0: break
		var slots_left = num_primitives - p
		var budget = max(2, int(ceil(float(remaining) / slots_left)))
		var attach = valid_hexes[rng.randi() % valid_hexes.size()]
		var archetype = ARCHETYPES[rng.randi() % 3]
		var added = _grow_primitive(valid_hexes, valid_set, attach, archetype, budget, rng)
		remaining -= added
	return valid_hexes

func _ready():
	var rng = RandomNumberGenerator.new()
	rng.seed = 12345

	var iterations = 100000
	var configs = [[2, false], [3, false], [4, false], [3, true], [4, true]]

	var t0 = Time.get_ticks_usec()
	var total_hexes = 0
	for i in range(iterations):
		var cfg = configs[i % configs.size()]
		var hexes = _generate(cfg[0], cfg[1], rng)
		total_hexes += hexes.size()
	var elapsed = (Time.get_ticks_usec() - t0) / 1000000.0

	print("GDScript: %d component shapes generated in %.4fs (%.2f us/shape, avg %.1f hexes/shape)" % [
		iterations, elapsed, elapsed * 1000000.0 / iterations, float(total_hexes) / iterations
	])

	var math_iterations = 5000000
	var t1 = Time.get_ticks_usec()
	var acc = 0
	var c = Vector2i(0, 0)
	var origin = Vector2i(0, 0)
	for i in range(math_iterations):
		c = _neighbor(c, i % 6)
		acc += _distance(c, origin)
	var elapsed2 = (Time.get_ticks_usec() - t1) / 1000000.0

	print("GDScript: %d neighbor+distance ops in %.4fs (%.2f ns/op) [checksum %d]" % [
		math_iterations, elapsed2, elapsed2 * 1000000000.0 / math_iterations, acc
	])

	get_tree().quit()

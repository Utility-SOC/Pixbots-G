class_name SimRng
extends RefCounted

# Gameplay-affecting randomness goes through here instead of global randf()/randi()/shuffle(), so a run can be
# replayed (daily seed, golden fixtures, Rust-vs-GDScript step diffs) and so adding a roll in one system does not
# shift the rolls of another: each system draws from its own NAMED stream. Streams: "solver", "combat", "loot",
# "ai", "map", "vortex" (add more as systems migrate). Purely cosmetic randomness (particles, jitter, audio
# variation) should stay on the global functions: it must not consume sim rolls.
#
# Until seed_all() is called every stream is randomized on first use, so unseeded play behaves like before.

static var _seeded: bool = false
static var _base_seed: int = 0
static var _streams: Dictionary = {}

# Make every stream deterministic from `base_seed`. Drops existing streams so the next draw restarts each one.
static func seed_all(base_seed: int) -> void:
	_seeded = true
	_base_seed = base_seed
	_streams.clear()

# Back to unseeded (randomized) behaviour.
static func unseed() -> void:
	_seeded = false
	_streams.clear()

static func stream(stream_name: String) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = _streams.get(stream_name)
	if rng == null:
		rng = RandomNumberGenerator.new()
		if _seeded:
			rng.seed = ("%d:%s" % [_base_seed, stream_name]).hash()
		else:
			rng.randomize()
		_streams[stream_name] = rng
	return rng

static func is_seeded() -> bool:
	return _seeded

# Random element of a non-empty array (replaces Array.pick_random()).
static func pick(stream_name: String, arr: Array):
	return arr[stream(stream_name).randi() % arr.size()]

# In-place Fisher-Yates shuffle (replaces Array.shuffle()).
static func shuffle(stream_name: String, arr: Array) -> void:
	var rng = stream(stream_name)
	for i in range(arr.size() - 1, 0, -1):
		var j = rng.randi() % (i + 1)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

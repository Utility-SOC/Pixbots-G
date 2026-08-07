extends Node

# Regression harness for SaveManager's script-load cache (perf plan, live
# save audit: _deserialize_tile/_deserialize_component called load(path)
# once PER TILE/COMPONENT - at a bloated wave-138 save's 71,490 loose
# tiles, that's tens of thousands of redundant lookups of the same ~40
# distinct script paths). Covers: the cache actually returns the SAME
# Script object on repeat calls (real caching, not just correctness), a
# real multi-tile deserialize still round-trips correctly through the
# cache, and a bad/missing path doesn't wedge the cache into some broken
# state for subsequent good paths.

const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- Real caching, not just a correct return value ---
	var s1 = SaveManager._load_cached("res://scripts/tiles/SplitterTile.gd")
	var s2 = SaveManager._load_cached("res://scripts/tiles/SplitterTile.gd")
	_check("_load_cached returns a real Script for a valid path", s1 != null and s1 is Script)
	_check("_load_cached returns the SAME Script instance on a repeat call (real reuse, not re-loading)", s1 == s2)
	_check("the cache actually recorded this path", SaveManager._script_load_cache.has("res://scripts/tiles/SplitterTile.gd"))

	# --- A bad path doesn't crash or wedge subsequent good lookups ---
	var bad = SaveManager._load_cached("res://scripts/tiles/DoesNotExist_NeverWill.gd")
	_check("a nonexistent script path returns null instead of crashing", bad == null)
	var s3 = SaveManager._load_cached("res://scripts/tiles/SplitterTile.gd")
	_check("a prior bad-path lookup doesn't corrupt a later good one", s3 == s1)

	# --- Real round-trip through the cache, several distinct tile types,
	# several tiles of the SAME type (proving reuse actually happens across
	# real deserialize calls, not just my own direct _load_cached calls) ---
	var splitter_a = SplitterTileScript.new()
	splitter_a.rarity = HexTile.Rarity.RARE
	splitter_a.grid_position = HexCoord.new(1, 0)
	var splitter_b = SplitterTileScript.new()
	splitter_b.rarity = HexTile.Rarity.MYTHIC
	splitter_b.grid_position = HexCoord.new(2, 0)
	var core_a = CoreTileScript.new()
	core_a.rarity = HexTile.Rarity.LEGENDARY
	core_a.grid_position = HexCoord.new(0, 0)

	var serialized = [
		SaveManager._serialize_tile(splitter_a),
		SaveManager._serialize_tile(splitter_b),
		SaveManager._serialize_tile(core_a),
	]
	var restored = []
	for d in serialized:
		restored.append(SaveManager._deserialize_tile(d))

	_check("all 3 tiles round-tripped through the cached-load deserializer", restored.size() == 3 and restored.all(func(t): return t != null))
	_check("restored Splitter A kept its rarity (RARE)", restored[0].rarity == HexTile.Rarity.RARE)
	_check("restored Splitter B kept its rarity (MYTHIC, distinct from A - proves no cross-tile contamination)", restored[1].rarity == HexTile.Rarity.MYTHIC)
	_check("restored Core kept its rarity (LEGENDARY)", restored[2].rarity == HexTile.Rarity.LEGENDARY)
	_check("the two Splitter instances are genuinely distinct objects (not aliased)", restored[0] != restored[1])
	_check("the two Splitters correctly share the exact same cached Script (same class, real cache reuse)",
		restored[0].get_script() == restored[1].get_script())

	if failures == 0:
		print("PASS: SaveManager's script-load cache reuses Script lookups correctly and a real multi-tile deserialize round-trip still works")
	get_tree().quit(0 if failures == 0 else 1)

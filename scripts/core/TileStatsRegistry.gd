extends Node

# Data-driven tiles infrastructure (Status.md queue item 1): per-tile-type
# stat overrides live at res://tiles/<TileScriptClassName>/stats.json, loaded
# lazily and cached here. Every tile's get_stat()/get_stat_by_rarity() call
# passes its CURRENT hardcoded value as the fallback default, so a missing
# (or partially-filled) stats.json is byte-identical to today's behavior -
# this is purely additive infrastructure, nothing regresses if a folder or
# key doesn't exist yet. A future optional sprite.png alongside stats.json in
# the same folder is a separate, later visual-override hook - procedural
# visuals stay the default per the locked ruling either way.

const TILES_DIR = "res://tiles/"

var _cache: Dictionary = {} # tile_type_name -> parsed stats Dictionary (or {} if none found)

func _load_stats_for(tile_type_name: String) -> Dictionary:
	if _cache.has(tile_type_name):
		return _cache[tile_type_name]

	var stats = {}
	var path = TILES_DIR + tile_type_name + "/stats.json"
	if FileAccess.file_exists(path):
		var f = FileAccess.open(path, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				stats = parsed
	_cache[tile_type_name] = stats
	return stats

# Flat scalar stat lookup - returns `default` untouched if this tile type has
# no stats.json, or the file doesn't define this particular key.
func get_stat(tile_type_name: String, key: String, default: float) -> float:
	var stats = _load_stats_for(tile_type_name)
	if stats.has(key):
		return float(stats[key])
	return default

# Per-rarity array stat lookup (rarity index 0=COMMON..4=MYTHIC). Both the
# JSON array (if present) and `default_by_rarity` (the code-side fallback,
# always supplied by the caller) must have exactly 5 entries.
func get_stat_by_rarity(tile_type_name: String, key: String, rarity: int, default_by_rarity: Array) -> float:
	var idx = clampi(rarity, 0, 4)
	var stats = _load_stats_for(tile_type_name)
	if stats.has(key):
		var arr = stats[key]
		if arr is Array and arr.size() == 5:
			return float(arr[idx])
	return float(default_by_rarity[idx])

# Dev/debug convenience: clears the cache so a stats.json edited mid-session
# gets picked up without restarting. Never called during normal play - stats
# are meant to be load-once, not hot-reloaded every frame.
func clear_cache():
	_cache.clear()

extends RefCounted

# The game's music is a numeric seed that grows. The seed fixes every random choice of the composer
# (so a track is reproducible and cacheable); the generation decides how many orchestral layers are
# stacked on top. Later generations keep the same progression and key (they build on the earlier
# music rather than replacing it) and only add voices, so the score gets more symphonic with play.

const PATH = "user://music_genome.json"
const MAX_GENERATION = 4
const WAVES_PER_GENERATION = 8

var seed_value: int = 0
var generation: int = 0
var prog_pick: int = 0
var best_wave: int = 0

static func create(rng_seed: int = -1):
	var g = load("res://scripts/audio/MusicGenome.gd").new()
	var r = RandomNumberGenerator.new()
	if rng_seed >= 0:
		r.seed = rng_seed
	else:
		r.randomize()
	g.seed_value = r.randi() & 0x7fffffff
	g.prog_pick = r.randi() & 0xffff
	return g

static func generation_for_wave(wave: int) -> int:
	return clampi(wave / WAVES_PER_GENERATION, 0, MAX_GENERATION)

# Returns true when the generation advanced (cached tracks of the old generation are then stale).
func note_wave(wave: int) -> bool:
	if wave <= best_wave:
		return false
	best_wave = wave
	var g = generation_for_wave(wave)
	if g > generation:
		generation = g
		return true
	return false

# Everything the composer needs, plain data.
func to_params() -> Dictionary:
	return {"seed": seed_value, "gen": generation, "prog": prog_pick}

# Stable id for cache keys: changes when the seed or generation does.
func tag() -> String:
	return "%d.%d" % [seed_value, generation]

func to_dict() -> Dictionary:
	return {"seed": seed_value, "gen": generation, "prog": prog_pick, "best": best_wave}

static func from_dict(d: Dictionary):
	var g = load("res://scripts/audio/MusicGenome.gd").new()
	g.seed_value = clampi(int(d.get("seed", 0)), 0, 0x7fffffff)
	g.generation = clampi(int(d.get("gen", 0)), 0, MAX_GENERATION)
	g.prog_pick = clampi(int(d.get("prog", 0)), 0, 0xffff)
	g.best_wave = maxi(int(d.get("best", 0)), 0)
	return g

static func load_or_create():
	if FileAccess.file_exists(PATH):
		var f = FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and parsed.has("seed"):
				return from_dict(parsed)
	var g = create()
	g.save()
	return g

func save() -> void:
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict()))

extends Node

# Music director. Two players crossfade (equal-power, overlapping) between pre-rendered loops, so a
# mood change never leaves a silent dip; loops are rendered on a low-priority background thread and the
# track that is playing keeps playing until the next one is READY. Likely next moods (combat from the
# garage, garage/boss from combat) are rendered ahead during idle time, so most transitions are instant.
#
# Track identity is a key: ctx | synergy | wave tier | biome voice | variant. Streams are cached in memory
# (and, via MusicGenome / the disk cache, across sessions - see MusicLibrary).

const ProceduralSynth = preload("res://scripts/audio/ProceduralSynth.gd")
const Genome = preload("res://scripts/audio/MusicGenome.gd")

const CROSSFADE_SECONDS = 1.8
const PREBAKE_DELAY_SECONDS = 4.0
const MEMORY_CACHE_MAX = 40
const DISK_CACHE_DIR = "user://music_cache"
const DISK_CACHE_MAX_FILES = 40
const SAMPLE_RATE = 22050
# Representative wave per tier: the composer's wave-dependent features (tempo creep, lead from wave 4,
# denser hats from wave 12, ...) only change at these boundaries, so one render serves the whole tier.
const WAVE_TIERS = [1, 4, 12, 30]

var current_player: AudioStreamPlayer # the player that is (or is fading in to be) the audible one
var current_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.FIRE
var is_combat: bool = false
var is_boss: bool = false
var current_wave: int = 1
var current_biome: String = ""
# What the currently-playing (or fading-in) loop was rendered for.
var current_ctx: int = ProceduralSynth.Ctx.GARAGE

var genome
var _players: Array = []
var _active: int = 0
var _current_key: String = ""
var _tracks: Dictionary = {} # key -> AudioStreamWAV
var _track_order: Array = [] # LRU order of cached keys

# Render queue (worker thread).
var _thread: Thread
var _jobs: Array = [] # {key, ctx, syn, wave, biome}
var _job_mutex := Mutex.new()
var _quitting: bool = false
var _prebake_timer: float = 0.0

# Crossfade state.
var _xf_active: bool = false
var _xf_t: float = 0.0
var _xf_out: AudioStreamPlayer
var _xf_in: AudioStreamPlayer
var _pending_key: String = "" # a swap requested while a fade was running

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	if AudioServer.get_bus_count() == 1: # Only Master exists
		AudioServer.add_bus()
		AudioServer.set_bus_name(1, "Music")
		AudioServer.add_bus()
		AudioServer.set_bus_name(2, "SFX")
	for i in range(2):
		var p = AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players.append(p)
	current_player = _players[0]
	genome = Genome.load_or_create()
	_apply_want()

func _exit_tree():
	_quitting = true
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null

# ---- Public API (unchanged) --------------------------------------------------------------------

# wave: current wave number (combat music gains layers as it rises).
func set_combat_state(combat: bool, wave: int = -1):
	if wave >= 0:
		current_wave = wave
		if genome != null and genome.note_wave(wave):
			genome.save()
			print("[Audio] Music evolved to generation %d" % genome.generation)
	if not combat:
		is_boss = false
	is_combat = combat
	_apply_want()

# Boss fights swap the wave track for the heavier boss track.
func set_boss(boss: bool):
	if is_boss != boss:
		is_boss = boss
		_apply_want()

func set_dominant_synergy(synergy: EnergyPacket.SynergyType):
	if current_synergy != synergy:
		current_synergy = synergy
		_apply_want()

# Combat music takes the map's voice (surf, fae, snow, dune, forge, crypt, farm).
func set_biome(biome_name: String):
	if current_biome != biome_name:
		current_biome = biome_name
		_apply_want()

# ---- Keys ---------------------------------------------------------------------------------------

func _wanted_ctx() -> int:
	if not is_combat:
		return ProceduralSynth.Ctx.GARAGE
	return ProceduralSynth.Ctx.BOSS if is_boss else ProceduralSynth.Ctx.COMBAT

static func wave_tier_wave(wave: int) -> int:
	var rep = WAVE_TIERS[0]
	for w in WAVE_TIERS:
		if wave >= w:
			rep = w
	return rep

func _voice_for(ctx: int, biome: String) -> String:
	return ProceduralSynth.voice_for_biome(biome) if ctx == ProceduralSynth.Ctx.COMBAT else ""

func _make_job(ctx: int, syn: int, wave: int, biome: String) -> Dictionary:
	var tier_wave = wave_tier_wave(wave) if ctx == ProceduralSynth.Ctx.COMBAT else 1
	var voice = _voice_for(ctx, biome)
	return {
		"key": "%s|%d|%d|%d|%s" % [genome.tag() if genome != null else "0", ctx, syn, tier_wave, voice],
		"ctx": ctx, "syn": syn, "wave": tier_wave, "biome": biome,
	}

func _want_job() -> Dictionary:
	return _make_job(_wanted_ctx(), current_synergy, current_wave, current_biome)

# ---- Wanted-track handling --------------------------------------------------------------------

func _apply_want():
	if _quitting:
		return
	var job = _want_job()
	var key: String = job["key"]
	if key == _current_key and not _xf_active:
		return
	if not _tracks.has(key):
		var cached = _disk_load(key)
		if cached != null:
			_remember(key, cached)
	if _tracks.has(key):
		_swap_to(key, int(job["ctx"]))
	else:
		_enqueue(job, true) # the current track keeps playing until this one is ready
	_prebake_timer = PREBAKE_DELAY_SECONDS

func _swap_to(key: String, ctx: int):
	if key == _current_key:
		return
	if _xf_active:
		_pending_key = key # one fade at a time; picked up when this one ends
		return
	var incoming: AudioStreamPlayer = _players[1 - _active]
	var outgoing: AudioStreamPlayer = _players[_active]
	incoming.stream = _tracks[key]
	incoming.volume_db = -80.0
	incoming.play()
	_touch(key)
	_current_key = key
	current_ctx = ctx
	current_player = incoming
	_active = 1 - _active
	if not outgoing.playing:
		# First track (or the old one stopped): just fade in.
		_xf_out = null
	else:
		_xf_out = outgoing
	_xf_in = incoming
	_xf_t = 0.0
	_xf_active = true

# Equal-power crossfade: out = cos, in = sin, so out^2 + in^2 == 1 at every instant - the combined
# loudness is constant and there is no dip in the middle.
static func crossfade_gains(t: float) -> Vector2:
	var x = clamp(t, 0.0, 1.0)
	return Vector2(cos(x * PI * 0.5), sin(x * PI * 0.5))

func _process(delta: float):
	if _xf_active:
		_xf_t += delta / CROSSFADE_SECONDS
		var g = crossfade_gains(_xf_t)
		_xf_in.volume_db = linear_to_db(max(g.y, 0.0001))
		if _xf_out != null:
			_xf_out.volume_db = linear_to_db(max(g.x, 0.0001))
		if _xf_t >= 1.0:
			_xf_in.volume_db = 0.0
			if _xf_out != null:
				_xf_out.stop()
				_xf_out.volume_db = -80.0
			_xf_active = false
			if _pending_key != "":
				var k = _pending_key
				_pending_key = ""
				_apply_want() # re-evaluate against the CURRENT state
	_pump_worker()
	if _prebake_timer > 0.0:
		_prebake_timer -= delta
		if _prebake_timer <= 0.0:
			_schedule_prebake()

# ---- Cache ---------------------------------------------------------------------------------------

func _touch(key: String):
	_track_order.erase(key)
	_track_order.append(key)

func _remember(key: String, stream: AudioStreamWAV):
	_tracks[key] = stream
	_touch(key)
	while _track_order.size() > MEMORY_CACHE_MAX:
		var old = _track_order.pop_front()
		if old != _current_key:
			_tracks.erase(old)

# ---- Render queue ---------------------------------------------------------------------------------

func _enqueue(job: Dictionary, urgent: bool):
	_job_mutex.lock()
	var dup = false
	for j in _jobs:
		if j["key"] == job["key"]:
			dup = true
			if urgent:
				_jobs.erase(j)
				_jobs.push_front(j)
			break
	if not dup and not _tracks.has(job["key"]) and not (not urgent and _disk_has(job["key"])):
		if urgent:
			_jobs.push_front(job)
		else:
			_jobs.push_back(job)
	_job_mutex.unlock()
	_pump_worker()

func _pump_worker():
	if _quitting:
		return
	if _thread != null and _thread.is_started() and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
	if _thread != null:
		return
	_job_mutex.lock()
	var has_jobs = not _jobs.is_empty()
	_job_mutex.unlock()
	if has_jobs:
		_thread = Thread.new()
		_thread.start(_worker_loop, Thread.PRIORITY_LOW)

func _worker_loop():
	while not _quitting:
		_job_mutex.lock()
		var job = null
		if not _jobs.is_empty():
			job = _jobs.pop_front()
		_job_mutex.unlock()
		if job == null:
			return
		print("[Audio] Rendering %s" % job["key"])
		var stream = ProceduralSynth.generate_track(int(job["ctx"]), int(job["syn"]), int(job["wave"]), func(): return _quitting, str(job["biome"]), true, genome.to_params())
		if stream == null or _quitting:
			return
		call_deferred("_on_render_done", job["key"], stream)

func _on_render_done(key: String, stream: AudioStreamWAV):
	_remember(key, stream)
	_disk_save(key, stream)
	# Only swap if this is still what the current state wants (it may have moved while baking).
	var want = _want_job()
	if want["key"] == key:
		_swap_to(key, int(want["ctx"]))
	_prebake_timer = PREBAKE_DELAY_SECONDS

# ---- Prebake ----------------------------------------------------------------------------------------

# During idle time, render the moods the player is most likely to hit next so the transition is instant:
# from the garage -> the upcoming combat track; from combat -> the garage track and the boss track.
func _schedule_prebake():
	if _quitting:
		return
	var syn = current_synergy
	var wave = current_wave
	if not is_combat:
		_enqueue(_make_job(ProceduralSynth.Ctx.COMBAT, syn, wave, current_biome), false)
		_enqueue(_make_job(ProceduralSynth.Ctx.BOSS, syn, wave, current_biome), false)
	else:
		_enqueue(_make_job(ProceduralSynth.Ctx.GARAGE, syn, wave, current_biome), false)
		if not is_boss:
			_enqueue(_make_job(ProceduralSynth.Ctx.BOSS, syn, wave, current_biome), false)
		# the next wave tier, so the tempo/lead change lands without a wait
		_enqueue(_make_job(ProceduralSynth.Ctx.COMBAT, syn, wave + 8, current_biome), false)

# ---- Disk cache (raw 16-bit PCM, keyed by genome + mood) ------------------------------------------

func _disk_path(key: String) -> String:
	return "%s/%s.pcm" % [DISK_CACHE_DIR, key.md5_text()]

func _disk_has(key: String) -> bool:
	return FileAccess.file_exists(_disk_path(key))

func _disk_load(key: String) -> AudioStreamWAV:
	if not _disk_has(key):
		return null
	var data = FileAccess.get_file_as_bytes(_disk_path(key))
	if data.size() < SAMPLE_RATE: # corrupt/truncated
		return null
	return pcm_to_stream(data)

func _disk_save(key: String, stream: AudioStreamWAV) -> void:
	DirAccess.make_dir_recursive_absolute(DISK_CACHE_DIR)
	var f = FileAccess.open(_disk_path(key), FileAccess.WRITE)
	if f:
		f.store_buffer(stream.data)
		f.close()
	_disk_trim()

# Oldest files go first once the cache is over its cap (stale generations age out this way).
func _disk_trim() -> void:
	var files: Array = []
	for fn in DirAccess.get_files_at(DISK_CACHE_DIR):
		var path = DISK_CACHE_DIR + "/" + fn
		files.append({"path": path, "t": FileAccess.get_modified_time(path)})
	if files.size() <= DISK_CACHE_MAX_FILES:
		return
	files.sort_custom(func(a, b): return a["t"] < b["t"])
	for i in range(files.size() - DISK_CACHE_MAX_FILES):
		DirAccess.remove_absolute(files[i]["path"])

static func pcm_to_stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = data.size() / 2
	return stream

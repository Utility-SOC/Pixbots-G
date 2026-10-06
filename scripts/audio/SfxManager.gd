extends Node

# Sound effects. Clips come from SfxSynth (procedural, rendered once on a worker thread at startup).
# Playback is a fixed pool of non-positional players: gain and pan-free attenuation are computed from the
# distance to the listener, duplicate sounds are rate-limited per id, and when every voice is busy the
# quietest request is dropped, so a 100-projectile volley costs a handful of voices, not a hundred.
# Heavy sounds go through the "Impact" bus, which sidechains a compressor on the Music bus: the score
# ducks under explosions and deaths and swells back.

const SfxSynth = preload("res://scripts/audio/SfxSynth.gd")

const POOL_SIZE = 20
const HEARING_RANGE = 1500.0
const PITCH_JITTER = 0.07
# Minimum seconds between two plays of the same id (kills machine-gun stacking).
const MIN_INTERVAL = {
	"kinetic": 0.05, "pierce": 0.05, "fire": 0.09, "ice": 0.07, "lightning": 0.06, "poison": 0.08,
	"explosive": 0.06, "vortex": 0.15, "vampiric": 0.08, "raw": 0.05,
	"hit": 0.035, "mech_hit": 0.05, "clang": 0.06, "boom": 0.08, "boom_small": 0.05,
	"death": 0.06, "death_boss": 0.5, "pickup": 0.05, "mine_blip": 0.12, "charge": 0.2,
}
const HEAVY = ["boom", "boom_small", "death", "death_boss", "explosive"]
const BASE_DB = {"boom": 0.0, "boom_small": -4.0, "death": -2.0, "death_boss": 0.0, "explosive": -3.0, "pickup": -6.0, "hit": -10.0, "mine_blip": -12.0}
const DEFAULT_DB = -7.0
const SYNERGY_SOUND = ["raw", "fire", "ice", "lightning", "vortex", "poison", "explosive", "kinetic", "pierce", "vampiric"]

var enabled: bool = true
var volume_db: float = 0.0
var played: int = 0
var dropped: int = 0

var _bank: Dictionary = {}
var _bank_mutex := Mutex.new()
var _thread: Thread
var _players: Array = []
var _player_end: PackedFloat64Array = PackedFloat64Array()
var _player_db: PackedFloat32Array = PackedFloat32Array()
var _last_play: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _listener_cache: Vector2 = Vector2.ZERO
var _listener_frame: int = -1

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_buses()
	for i in range(POOL_SIZE):
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
		_player_end.append(0.0)
		_player_db.append(-80.0)
	_thread = Thread.new()
	_thread.start(_render_bank, Thread.PRIORITY_LOW)

func _exit_tree():
	if _thread and _thread.is_started():
		_thread.wait_to_finish()

func _render_bank():
	var synth = SfxSynth.new()
	for id in SfxSynth.ids():
		var clip = synth.render(id)
		_bank_mutex.lock()
		_bank[id] = clip
		_bank_mutex.unlock()

func is_ready() -> bool:
	_bank_mutex.lock()
	var n = _bank.size()
	_bank_mutex.unlock()
	return n >= SfxSynth.ids().size()

# ---- Buses and ducking ------------------------------------------------------------------------

func _bus_index(name: String) -> int:
	for i in range(AudioServer.bus_count):
		if AudioServer.get_bus_name(i) == name:
			return i
	return -1

func _ensure_bus(name: String, send: String = "Master") -> int:
	var idx = _bus_index(name)
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, name)
		AudioServer.set_bus_send(idx, send)
	return idx

func _ensure_buses():
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_ensure_bus("Impact", "SFX")
	var music = _bus_index("Music")
	# One compressor on Music, keyed from the Impact bus. Skipped if already installed.
	for e in range(AudioServer.get_bus_effect_count(music)):
		if AudioServer.get_bus_effect(music, e) is AudioEffectCompressor:
			return
	var comp = AudioEffectCompressor.new()
	comp.sidechain = "Impact"
	comp.threshold = -26.0
	comp.ratio = 5.0
	comp.attack_us = 15000.0
	comp.release_ms = 320.0
	comp.gain = 0.0
	AudioServer.add_bus_effect(music, comp)

# ---- Playback -----------------------------------------------------------------------------------

# Attenuation 1.0 at the listener to 0.0 at HEARING_RANGE (quadratic falloff). null position = non-spatial.
static func attenuation(distance: float) -> float:
	var x = clampf(1.0 - distance / HEARING_RANGE, 0.0, 1.0)
	return x * x

func _listener_pos() -> Vector2:
	var f = Engine.get_process_frames()
	if f == _listener_frame:
		return _listener_cache
	_listener_frame = f
	var players = EntityCache.get_group("player")
	if players.size() > 0 and is_instance_valid(players[0]):
		_listener_cache = players[0].global_position
	return _listener_cache

# Returns true when the sound actually started.
func play(id: String, pos = null, gain_db: float = 0.0) -> bool:
	if not enabled:
		return false
	_bank_mutex.lock()
	var clip = _bank.get(id)
	_bank_mutex.unlock()
	if clip == null:
		return false
	var now = Time.get_ticks_msec() / 1000.0
	if now - float(_last_play.get(id, -10.0)) < float(MIN_INTERVAL.get(id, 0.05)):
		dropped += 1
		return false
	var db = float(BASE_DB.get(id, DEFAULT_DB)) + gain_db + volume_db
	if pos is Vector2:
		var att = attenuation(_listener_pos().distance_to(pos))
		if att <= 0.003:
			dropped += 1
			return false
		db += linear_to_db(att)
	var slot = _claim_voice(now, db)
	if slot < 0:
		dropped += 1
		return false
	var p: AudioStreamPlayer = _players[slot]
	p.stream = clip
	p.bus = "Impact" if id in HEAVY else "SFX"
	p.volume_db = db
	p.pitch_scale = 1.0 + _rng.randf_range(-PITCH_JITTER, PITCH_JITTER)
	p.play()
	_player_end[slot] = now + clip.get_length()
	_player_db[slot] = db
	_last_play[id] = now
	played += 1
	return true

# A free voice, or the quietest busy one if the new sound is louder than it; -1 = drop the request.
func _claim_voice(now: float, db: float) -> int:
	var quietest = -1
	var quietest_db = 1000.0
	for i in range(POOL_SIZE):
		if _player_end[i] <= now:
			return i
		if _player_db[i] < quietest_db:
			quietest_db = _player_db[i]
			quietest = i
	if quietest >= 0 and db > quietest_db + 3.0:
		return quietest
	return -1

# ---- Convenience entry points used by gameplay code ---------------------------------------------------

func shot(synergy: int, by_player: bool, pos = null) -> void:
	var id = SYNERGY_SOUND[clampi(synergy, 0, SYNERGY_SOUND.size() - 1)]
	play(id, pos, 0.0 if by_player else -5.0)

func impact(on_mech: bool, pos = null, hard_cover: bool = false) -> void:
	play("clang" if hard_cover else ("mech_hit" if on_mech else "hit"), pos)

func explosion(radius: float, pos = null) -> void:
	play("boom" if radius >= 120.0 else "boom_small", pos)

func death(is_boss: bool, pos = null) -> void:
	play("death_boss" if is_boss else "death", pos)

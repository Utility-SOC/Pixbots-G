class_name ProceduralSynth
extends RefCounted

# Procedural music composer. Renders one seamless 8-bar loop per call:
#   GARAGE - downtime: slow dorian pads, a low drone and sparse bell tones. No drums.
#   COMBAT - wave music: synthwave bass + pad + 16th arpeggio, kick/snare/hat,
#            a lead line from wave 4 and denser hats from wave 12.
#   BOSS   - phrygian, faster, driven distorted bass, double-time kicks, lead.
# Key comes from the dominant element, the chord progression, rhythms and lead
# phrases are re-rolled every render so each wave sounds different.
# Everything is additive-synth + one-pole filters rendered at 22.05 kHz mono
# (the Music bus does the rest). Notes wrap around the loop end so tails and
# pads cross the seam instead of clicking.

const SAMPLE_RATE: int = 22050

enum Ctx { GARAGE, COMBAT, BOSS }

const SCALE_DORIAN := [0, 2, 3, 5, 7, 9, 10]
const SCALE_MINOR := [0, 2, 3, 5, 7, 8, 10]
const SCALE_PHRYGIAN := [0, 1, 3, 5, 7, 8, 10]
const SCALE_PHRYGIAN_DOM := [0, 1, 4, 5, 7, 8, 10] # surf (Misirlou) and desert
const SCALE_LYDIAN := [0, 2, 4, 6, 7, 9, 11] # fae / woodland
const SCALE_HARM_MINOR := [0, 2, 3, 5, 7, 8, 11] # crypt
const SCALE_MIXOLYDIAN := [0, 2, 4, 5, 7, 9, 10] # dust-bowl farm

# Biome voices (combat music only): map_type -> voice. Anything not listed
# keeps the default synthwave sound.
const VOICE_BY_MAP := {
	"Water": "surf", "Forest": "fae", "Tundra": "snow", "Desert": "dune",
	"Volcano": "forge", "Dungeon": "crypt", "FightShovel": "farm",
}
const VOICE_BPM := {"surf": 150.0, "fae": 98.0, "snow": 92.0, "dune": 104.0, "forge": 96.0, "crypt": 84.0, "farm": 128.0}
const VOICE_SCALE := {
	"surf": SCALE_PHRYGIAN_DOM, "fae": SCALE_LYDIAN, "snow": SCALE_DORIAN, "dune": SCALE_PHRYGIAN_DOM,
	"forge": SCALE_PHRYGIAN, "crypt": SCALE_HARM_MINOR, "farm": SCALE_MIXOLYDIAN,
}

# Chord roots as scale-degree indices, 4 chords x 2 bars.
const PROGRESSIONS := [
	[0, 5, 2, 6], # i VI III VII
	[0, 6, 5, 6], # i VII VI VII
	[0, 2, 5, 6], # i III VI VII
	[0, 3, 5, 4], # i iv VI v
	[0, 5, 3, 6], # i VI iv VII
]
const BOSS_PROGRESSIONS := [
	[0, 1, 0, 6],
	[0, 0, 1, 5],
	[0, 6, 1, 0],
]

const BARS := 8
const STEPS_PER_BAR := 16

var _rng := RandomNumberGenerator.new()
var _cancel: Callable
var _cancelled := false
var _n: int = 0
var _step: int = 0 # samples per 16th note

var _bass := PackedFloat32Array()
var _pad := PackedFloat32Array()
var _mel := PackedFloat32Array()
var _drums := PackedFloat32Array()
var _duck := PackedFloat32Array()


# Backwards-compatible entry point (older callers/tests).
static func generate_level_loop(synergy: EnergyPacket.SynergyType, is_combat: bool, cancel_check: Callable = Callable()) -> AudioStreamWAV:
	return generate_track(Ctx.COMBAT if is_combat else Ctx.GARAGE, synergy, 1, cancel_check)


# cancel_check: polled between notes so the caller's worker thread can bail
# promptly at app quit - returns null when cancelled.
static func generate_track(ctx: int, synergy: int, wave: int, cancel_check: Callable = Callable(), biome: String = "", throttle: bool = false, genome: Dictionary = {}) -> AudioStreamWAV:
	var s = ProceduralSynth.new()
	s._throttle = throttle
	s._genome = genome
	return s._render(ctx, synergy, wave, cancel_check, biome)


static func voice_for_biome(biome: String) -> String:
	return VOICE_BY_MAP.get(biome, "")


static func loop_seconds(ctx: int, wave: int, voice: String = "") -> float:
	var bpm = _bpm_for(ctx, wave, voice)
	return BARS * 4.0 * 60.0 / bpm


static func _bpm_for(ctx: int, wave: int, voice: String = "") -> float:
	if voice != "" and ctx == Ctx.COMBAT:
		return float(VOICE_BPM.get(voice, 116.0))
	match ctx:
		Ctx.GARAGE:
			return 72.0
		Ctx.BOSS:
			return 144.0
	return 116.0 + minf(float(wave), 30.0) * 0.5


func _midi(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


# Worker-thread pacing: when rendering in the background, sleep briefly every few ms so the render
# never monopolises a core on a dual-core machine (a full render is seconds of tight GDScript).
var _throttle := false
var _genome: Dictionary = {} # MusicGenome.to_params(); empty = unseeded legacy behaviour
var _slice_start_usec := 0
const THROTTLE_SLICE_USEC = 4000
const THROTTLE_SLEEP_USEC = 3000

func _is_cancelled() -> bool:
	if _throttle:
		var now = Time.get_ticks_usec()
		if _slice_start_usec == 0:
			_slice_start_usec = now
		elif now - _slice_start_usec > THROTTLE_SLICE_USEC:
			OS.delay_usec(THROTTLE_SLEEP_USEC)
			_slice_start_usec = Time.get_ticks_usec()
	if _cancelled:
		return true
	if _cancel.is_valid() and _cancel.call():
		_cancelled = true
	return _cancelled


func _render(ctx: int, synergy: int, wave: int, cancel_check: Callable, biome: String = "") -> AudioStreamWAV:
	_cancel = cancel_check
	var gen := 0
	if _genome.is_empty():
		_rng.randomize()
	else:
		# Deterministic: same genome + same mood = same track, so it can be cached and re-rendered.
		_rng.seed = hash([int(_genome["seed"]), ctx, synergy, wave, biome])
		gen = int(_genome["gen"])
	var voice = voice_for_biome(biome) if ctx == Ctx.COMBAT else ""
	var bpm = _bpm_for(ctx, wave, voice)
	_step = int(round(60.0 / bpm / 4.0 * SAMPLE_RATE))
	_n = _step * STEPS_PER_BAR * BARS
	for buf in [_bass, _pad, _mel, _drums]:
		buf.resize(_n)
		buf.fill(0.0)
	_duck.resize(_n)
	_duck.fill(1.0)

	var scale: Array = SCALE_MINOR
	if ctx == Ctx.GARAGE:
		scale = SCALE_DORIAN
	elif ctx == Ctx.BOSS:
		scale = SCALE_PHRYGIAN
	elif voice != "":
		scale = VOICE_SCALE[voice]
	var root_midi: float = 33.0 + float((absi(synergy) * 5) % 12) # A1..G#2, element picks the key
	var progs: Array = BOSS_PROGRESSIONS if ctx == Ctx.BOSS else PROGRESSIONS
	var prog: Array = progs[(_rng.randi() if _genome.is_empty() else int(_genome["prog"])) % progs.size()]

	# Chord tones as semitone offsets from the key root, one entry per chord.
	var chords: Array = []
	for d in prog:
		var tones: Array = []
		for k in [0, 2, 4]:
			var idx: int = d + k
			var off: int = scale[idx % 7] + (12 if idx >= 7 else 0)
			tones.append(off)
		chords.append({"root": scale[d], "tones": tones})

	var chord_steps = STEPS_PER_BAR * 2 # two bars per chord

	if voice != "":
		_voice_layers(voice, chords, root_midi, scale, wave)
		_symphonic_layers(gen, ctx, chords, root_midi, scale)
		if _is_cancelled(): return null
		return _mix_to_stream(ctx)

	# --- Pad (all contexts) ---
	for c in range(chords.size()):
		var start = c * chord_steps * _step
		for off in chords[c].tones:
			if _is_cancelled(): return null
			var f = _midi(root_midi + 12.0 + off)
			var len_s = chord_steps * _step + _step * 4 # overlap into the next chord
			var amp = 0.05 if ctx == Ctx.GARAGE else 0.04
			_add_tone(_pad, start, len_s, f * 0.997, 1, amp, 0.6, 0.9, 0.0, 0.5)
			_add_tone(_pad, start, len_s, f * 1.003, 1, amp, 0.6, 0.9, 0.0, 0.5)
	_lowpass(_pad, 900.0 if ctx != Ctx.GARAGE else 650.0)

	# --- Bass ---
	for c in range(chords.size()):
		var r: float = root_midi + chords[c].root
		var start = c * chord_steps * _step
		if ctx == Ctx.GARAGE:
			if _is_cancelled(): return null
			_add_tone(_bass, start, chord_steps * _step + _step * 2, _midi(r), 0, 0.22, 0.4, 0.6, 0.0, 0.5)
		else:
			for s in range(chord_steps):
				var eighth = (s % 2 == 0)
				if ctx == Ctx.COMBAT and not eighth:
					continue
				if ctx == Ctx.BOSS and not (eighth or s % 8 == 7):
					continue
				var m = r
				if ctx == Ctx.COMBAT and s % 8 == 6:
					m += 12.0
				if ctx == Ctx.BOSS and s % 8 == 7:
					m += 1.0 if _rng.randf() < 0.5 else 0.0
				if _is_cancelled(): return null
				var st = c * chord_steps * _step + s * _step
				_add_tone(_bass, st, int(_step * (1.7 if ctx == Ctx.COMBAT else 1.2)), _midi(m), 1, 0.28, 0.01, 0.05, 3.0, 0.5)
				_add_tone(_bass, st, int(_step * 1.7), _midi(m - 12.0), 0, 0.2, 0.01, 0.05, 2.0, 0.5)
	_lowpass(_bass, 500.0 if ctx == Ctx.GARAGE else 900.0)
	if ctx == Ctx.BOSS:
		for i in range(_n):
			_bass[i] = tanh(_bass[i] * 3.0) * 0.5 # grit

	# --- Melodic layer: arp / bells / lead ---
	if ctx == Ctx.GARAGE:
		_garage_bells(chords, root_midi, scale)
	else:
		_arp(chords, root_midi, ctx)
		if ctx == Ctx.BOSS or wave >= 4:
			_lead(chords, root_midi, scale, ctx)
	_lowpass(_mel, 4500.0)
	_echo(_mel, _step * (3 if ctx != Ctx.GARAGE else 6), 0.35, 3)

	# --- Drums ---
	if ctx != Ctx.GARAGE:
		_drum_pattern(ctx, wave)
	_symphonic_layers(gen, ctx, chords, root_midi, scale)

	if _is_cancelled(): return null

	return _mix_to_stream(ctx)


# Orchestral layers that accumulate with the music's generation. Each reuses the existing progression, so a
# later generation is the earlier score with more instruments playing it.
#   1: counter-melody (soft square an octave above the chord third, one note per chord, offset)
#   2: strings (slow detuned saw swell on chord tones, bar-long attack)
#   3: brass (chord root + fifth stabs on the strong beats, combat/boss only)
#   4: choir (high sine "ah" triad that holds across the whole chord)
func _symphonic_layers(gen: int, ctx: int, chords: Array, root_midi: float, scale: Array) -> void:
	if gen <= 0:
		return
	var chord_steps = STEPS_PER_BAR * 2
	var quiet = 0.6 if ctx == Ctx.GARAGE else 1.0
	for c in range(chords.size()):
		var start = c * chord_steps * _step
		var tones: Array = chords[c].tones
		if _is_cancelled(): return
		if gen >= 1:
			var t: int = tones[1]
			var f = _midi(root_midi + 24.0 + t)
			_add_tone(_mel, start + _step * 4, _step * 12, f, 2, 0.025 * quiet, 0.08, 0.4, 0.4, 0.35)
			_add_tone(_mel, start + _step * 20, _step * 10, _midi(root_midi + 24.0 + tones[2]), 2, 0.02 * quiet, 0.08, 0.4, 0.4, 0.35)
		if gen >= 2:
			for off in tones:
				var fs = _midi(root_midi + 12.0 + off)
				_add_tone(_pad, start, chord_steps * _step + _step * 6, fs * 0.996, 1, 0.012 * quiet, 1.2, 1.0, 0.0, 0.5)
				_add_tone(_pad, start, chord_steps * _step + _step * 6, fs * 1.004, 1, 0.012 * quiet, 1.2, 1.0, 0.0, 0.5)
		if gen >= 3 and ctx != Ctx.GARAGE:
			var r: float = root_midi + chords[c].root
			for beat in [0, 8, 16, 24]:
				var st = start + beat * _step
				_add_tone(_mel, st, _step * 5, _midi(r + 12.0), 1, 0.03, 0.02, 0.2, 2.0, 0.5)
				_add_tone(_mel, st, _step * 5, _midi(r + 19.0), 1, 0.02, 0.02, 0.2, 2.0, 0.5)
		if gen >= 4:
			for off in tones:
				_add_tone(_pad, start, chord_steps * _step + _step * 8, _midi(root_midi + 36.0 + off), 0, 0.012 * quiet, 1.6, 1.4, 0.0, 0.5)
	if gen >= 2:
		_lowpass(_pad, 1400.0 if ctx != Ctx.GARAGE else 900.0)


func _mix_to_stream(ctx: int) -> AudioStreamWAV:
	var out := PackedByteArray()
	out.resize(_n * 2)
	var peak := 0.0
	var mix := PackedFloat32Array()
	mix.resize(_n)
	for i in range(_n):
		var d: float = _duck[i]
		var v: float = _bass[i] * d + _pad[i] * (0.5 + 0.5 * d) + _mel[i] + _drums[i]
		v = tanh(v * 1.3) * 0.85
		mix[i] = v
		peak = maxf(peak, absf(v))
	var norm := 1.0
	if peak > 0.001:
		# Garage sits well under the wave/boss mixes so downtime stays background.
		norm = (0.5 if ctx == Ctx.GARAGE else 0.85) / peak
	# 3 ms fade at both ends: a note/drum onset landing exactly on the loop
	# seam otherwise leaves a click, and this is inaudible as a dip.
	var fade := 64
	for i in range(fade):
		var g: float = float(i) / fade
		mix[i] *= g
		mix[_n - 1 - i] *= g
	for i in range(_n):
		var pcm := int(clampf(mix[i] * norm, -1.0, 1.0) * 32767.0)
		out[i * 2] = pcm & 0xFF
		out[i * 2 + 1] = (pcm >> 8) & 0xFF

	var stream = AudioStreamWAV.new()
	stream.data = out
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = _n
	return stream


# kind: 0 sine, 1 saw, 2 pulse. Notes wrap past the loop end.
func _add_tone(buf: PackedFloat32Array, start: int, length: int, freq: float, kind: int, amp: float, attack: float, release: float, decay: float, pw: float) -> void:
	var inc: float = freq / SAMPLE_RATE
	var phase: float = _rng.randf() if kind != 0 else 0.0
	var att: float = maxf(attack * SAMPLE_RATE, 1.0)
	var rel: float = maxf(release * SAMPLE_RATE, 1.0)
	var g: float = 1.0
	var dm: float = exp(-decay / SAMPLE_RATE) if decay > 0.0 else 1.0
	var idx: int = start % _n
	for i in range(length):
		var env: float = g
		if i < att:
			env *= float(i) / att
		var rem: int = length - i
		if rem < rel:
			env *= float(rem) / rel
		var w: float
		if kind == 0:
			w = sin(TAU * phase)
		elif kind == 1:
			w = 2.0 * phase - 1.0
		else:
			w = 1.0 if phase < pw else -1.0
		buf[idx] += w * env * amp
		phase += inc
		if phase >= 1.0:
			phase -= 1.0
		g *= dm
		idx += 1
		if idx >= _n:
			idx = 0


func _lowpass(buf: PackedFloat32Array, fc: float) -> void:
	var a: float = 1.0 - exp(-TAU * fc / SAMPLE_RATE)
	var y: float = buf[_n - 1] # seed from the loop end so the seam stays smooth
	for i in range(_n):
		y += a * (buf[i] - y)
		buf[i] = y


func _echo(buf: PackedFloat32Array, delay: int, fb: float, taps: int) -> void:
	var src := buf.duplicate()
	for t in range(1, taps + 1):
		var g: float = pow(fb, t)
		var off: int = delay * t
		for i in range(_n):
			buf[(i + off) % _n] += src[i] * g


func _arp(chords: Array, root_midi: float, ctx: int) -> void:
	var patterns := [[0, 1, 2, 3, 2, 1, 0, 1], [0, 2, 1, 3, 2, 1, 3, 2], [0, 0, 1, 2, 3, 2, 1, 0], [3, 2, 1, 0, 1, 2, 3, 2]]
	var pat: Array = patterns[_rng.randi() % patterns.size()]
	var density := 1 # play every 16th in combat; every other in boss for punch
	for c in range(chords.size()):
		var tones: Array = chords[c].tones.duplicate()
		tones.append(tones[0] + 12)
		for s in range(STEPS_PER_BAR * 2):
			if ctx == Ctx.COMBAT and s % density != 0:
				continue
			if ctx == Ctx.BOSS and s % 2 == 1 and s % 4 != 3:
				continue
			if _is_cancelled(): return
			var off: int = tones[pat[s % pat.size()]]
			var st: int = c * STEPS_PER_BAR * 2 * _step + s * _step
			_add_tone(_mel, st, int(_step * 1.6), _midi(root_midi + 24.0 + off), 2, 0.05, 0.003, 0.04, 14.0, 0.28)


func _lead(chords: Array, root_midi: float, scale: Array, ctx: int) -> void:
	var rhythms := [[0, 6, 8, 12], [0, 3, 6, 10, 12], [0, 8], [4, 8, 14], [0, 4, 6, 8, 12, 14]]
	var deg := 4 + _rng.randi() % 3
	for c in range(chords.size()):
		for bar in range(2):
			var rh: Array = rhythms[_rng.randi() % rhythms.size()]
			for k in range(rh.size()):
				if _is_cancelled(): return
				deg = clampi(deg + (_rng.randi() % 3) - 1, 2, 9)
				if _rng.randf() < 0.25:
					deg = deg + 2 if deg < 7 else deg - 2
				var off: int = scale[deg % 7] + 12 * (deg / 7)
				var step_pos: int = rh[k]
				var next_pos: int = rh[k + 1] if k + 1 < rh.size() else 16
				var len_steps: int = clampi(next_pos - step_pos, 2, 6)
				var st: int = (c * 2 + bar) * STEPS_PER_BAR * _step + step_pos * _step
				var f: float = _midi(root_midi + 24.0 + off)
				_add_tone(_mel, st, len_steps * _step, f, 1, 0.045 if ctx == Ctx.COMBAT else 0.06, 0.01, 0.08, 1.5, 0.5)
				_add_tone(_mel, st, len_steps * _step, f * 1.004, 2, 0.03, 0.01, 0.08, 1.5, 0.4)


func _garage_bells(chords: Array, root_midi: float, scale: Array) -> void:
	for bar in range(BARS):
		if _rng.randf() < 0.7:
			if _is_cancelled(): return
			var c: int = bar / 2
			var tones: Array = chords[c].tones
			var off: int = tones[_rng.randi() % tones.size()] + (12 if _rng.randf() < 0.5 else 0)
			var st: int = bar * STEPS_PER_BAR * _step + (_rng.randi() % 4) * 4 * _step
			var f: float = _midi(root_midi + 24.0 + off)
			_add_tone(_mel, st, _step * 14, f, 0, 0.07, 0.005, 0.5, 2.2, 0.5)
			_add_tone(_mel, st, _step * 10, f * 2.76, 0, 0.02, 0.005, 0.3, 4.0, 0.5) # inharmonic bell partial


func _drum_pattern(ctx: int, wave: int) -> void:
	var total_steps: int = STEPS_PER_BAR * BARS
	for s in range(total_steps):
		var bs: int = s % 16
		var st: int = s * _step
		var kick := bs % 4 == 0
		if ctx == Ctx.BOSS and (bs == 10 or bs == 14):
			kick = true
		if kick:
			_kick(st)
		if bs == 4 or bs == 12:
			_snare(st)
		var hat := bs % 4 == 2
		if wave >= 12 or ctx == Ctx.BOSS:
			hat = bs % 2 == 0 or bs % 4 == 3
		if hat:
			_hat(st, 0.5 if bs % 4 == 2 else 0.3)
	if _is_cancelled(): return


func _kick(start: int) -> void:
	var len_s: int = int(0.22 * SAMPLE_RATE)
	var phase := 0.0
	for i in range(len_s):
		var t: float = float(i) / SAMPLE_RATE
		var f: float = 42.0 + 90.0 * exp(-t * 28.0)
		phase += f / SAMPLE_RATE
		var idx: int = (start + i) % _n
		_drums[idx] += sin(TAU * phase) * exp(-t * 14.0) * 0.55
		_duck[idx] = minf(_duck[idx], 1.0 - 0.65 * exp(-t * 16.0))


func _snare(start: int) -> void:
	var len_s: int = int(0.18 * SAMPLE_RATE)
	for i in range(len_s):
		var t: float = float(i) / SAMPLE_RATE
		var n: float = _rng.randf() * 2.0 - 1.0
		var tone: float = sin(TAU * 185.0 * t)
		_drums[(start + i) % _n] += (n * exp(-t * 22.0) * 0.28 + tone * exp(-t * 30.0) * 0.18)


func _hat(start: int, vel: float) -> void:
	var len_s: int = int(0.04 * SAMPLE_RATE)
	var prev := 0.0
	for i in range(len_s):
		var t: float = float(i) / SAMPLE_RATE
		var n: float = _rng.randf() * 2.0 - 1.0
		var hp: float = n - prev # crude high-pass
		prev = n
		_drums[(start + i) % _n] += hp * exp(-t * 90.0) * 0.1 * vel


# ===========================================================================
# Biome voices (combat music). Each fills _bass/_pad/_mel/_drums directly.
# ===========================================================================

# Additive sine note: partials = [[freq_mult, amp, decay_per_sec], ...]. Stops
# early once the (decaying) note is inaudible, so long ring-outs stay cheap.
func _add_partials(buf: PackedFloat32Array, start: int, length: int, freq: float, partials: Array, amp: float, attack: float = 0.003, release: float = 0.05) -> void:
	var att: float = maxf(attack * SAMPLE_RATE, 1.0)
	var rel: float = maxf(release * SAMPLE_RATE, 1.0)
	for p in partials:
		var f: float = freq * p[0]
		if f > SAMPLE_RATE * 0.45:
			continue
		var inc: float = f / SAMPLE_RATE
		var pa: float = amp * p[1]
		var dm: float = exp(-p[2] / SAMPLE_RATE) if p[2] > 0.0 else 1.0
		var g: float = 1.0
		var phase: float = 0.0
		var idx: int = start % _n
		for i in range(length):
			if g < 0.004:
				break
			var env: float = g
			if i < att:
				env *= float(i) / att
			var rem: int = length - i
			if rem < rel:
				env *= float(rem) / rel
			buf[idx] += sin(TAU * phase) * env * pa
			phase += inc
			if phase >= 1.0:
				phase -= 1.0
			g *= dm
			idx += 1
			if idx >= _n:
				idx = 0


# Vibrato voice for flute / snake-charmer / harmonica (kind 0 sine+octave, 1 saw).
func _add_vib_tone(buf: PackedFloat32Array, start: int, length: int, freq: float, amp: float, attack: float, release: float, kind: int) -> void:
	var att: float = maxf(attack * SAMPLE_RATE, 1.0)
	var rel: float = maxf(release * SAMPLE_RATE, 1.0)
	var phase: float = 0.0
	var idx: int = start % _n
	for i in range(length):
		var t: float = float(i) / SAMPLE_RATE
		var vib: float = 1.0 + 0.006 * sin(TAU * 5.4 * t) * clampf(t / 0.25, 0.0, 1.0)
		var env: float = 1.0
		if i < att:
			env = float(i) / att
		var rem: int = length - i
		if rem < rel:
			env *= float(rem) / rel
		var w: float
		if kind == 0:
			w = sin(TAU * phase) + 0.18 * sin(TAU * phase * 2.0)
		else:
			w = 2.0 * phase - 1.0
		buf[idx] += w * env * amp
		phase += freq * vib / SAMPLE_RATE
		if phase >= 1.0:
			phase -= 1.0
		idx += 1
		if idx >= _n:
			idx = 0


func _soft_thump(start: int, amp: float, f0: float = 70.0) -> void:
	var len_s: int = int(0.28 * SAMPLE_RATE)
	var phase := 0.0
	for i in range(len_s):
		var t: float = float(i) / SAMPLE_RATE
		phase += (f0 * (1.0 + 0.8 * exp(-t * 30.0))) / SAMPLE_RATE
		_drums[(start + i) % _n] += sin(TAU * phase) * exp(-t * 11.0) * amp


func _jingle(start: int, vel: float) -> void:
	var len_s: int = int(0.12 * SAMPLE_RATE)
	var prev := 0.0
	for i in range(len_s):
		var t: float = float(i) / SAMPLE_RATE
		var n: float = _rng.randf() * 2.0 - 1.0
		var hp: float = n - prev
		prev = n
		var ring: float = sin(TAU * 3100.0 * t) + 0.7 * sin(TAU * 4300.0 * t) + 0.5 * sin(TAU * 5800.0 * t)
		_drums[(start + i) % _n] += (ring * 0.035 + hp * 0.03) * exp(-t * 26.0) * vel


func _wind() -> void:
	var y := 0.0
	var a: float = 1.0 - exp(-TAU * 450.0 / SAMPLE_RATE)
	for i in range(_n):
		y += a * ((_rng.randf() * 2.0 - 1.0) - y)
		_pad[i] += y * (0.55 + 0.45 * sin(TAU * 2.0 * float(i) / _n)) * 0.2


func _taiko(start: int, amp: float) -> void:
	var len_s: int = int(0.4 * SAMPLE_RATE)
	var phase := 0.0
	for i in range(len_s):
		var t: float = float(i) / SAMPLE_RATE
		phase += (48.0 + 70.0 * exp(-t * 22.0)) / SAMPLE_RATE
		var idx: int = (start + i) % _n
		_drums[idx] += (sin(TAU * phase) * exp(-t * 7.0) + (_rng.randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.25) * amp
		_duck[idx] = minf(_duck[idx], 1.0 - 0.55 * exp(-t * 12.0))


func _darbuka(start: int, kind: int) -> void: # 0 dum, 1 tek
	var len_s: int = int((0.2 if kind == 0 else 0.06) * SAMPLE_RATE)
	var phase := 0.0
	for i in range(len_s):
		var t: float = float(i) / SAMPLE_RATE
		var idx: int = (start + i) % _n
		if kind == 0:
			phase += (95.0 + 90.0 * exp(-t * 30.0)) / SAMPLE_RATE
			_drums[idx] += sin(TAU * phase) * exp(-t * 14.0) * 0.45
		else:
			var n: float = _rng.randf() * 2.0 - 1.0
			_drums[idx] += (n * 0.18 + sin(TAU * 720.0 * t) * 0.14) * exp(-t * 55.0)


func _chord_step(c: int, s: int) -> int:
	return (c * STEPS_PER_BAR * 2 + s) * _step


func _voice_layers(voice: String, chords: Array, root_midi: float, scale: Array, wave: int) -> void:
	match voice:
		"surf": _v_surf(chords, root_midi, scale, wave)
		"fae": _v_fae(chords, root_midi, scale, wave)
		"snow": _v_snow(chords, root_midi, scale, wave)
		"dune": _v_dune(chords, root_midi, scale, wave)
		"forge": _v_forge(chords, root_midi, scale, wave)
		"crypt": _v_crypt(chords, root_midi, scale, wave)
		"farm": _v_farm(chords, root_midi, scale, wave)


func _scale_note(scale: Array, deg: int) -> int:
	return scale[posmod(deg, 7)] + 12 * int(floor(float(deg) / 7.0))


# Surf guitar: palm-muted bass, offbeat chord scratches, tremolo-picked twangy
# lead with a descending run into each chord, spring-reverb tail, driving kit.
func _v_surf(chords: Array, rm: float, scale: Array, wave: int) -> void:
	for c in range(chords.size()):
		var r: float = rm + chords[c].root
		for s in range(32):
			if _is_cancelled(): return
			var st = _chord_step(c, s)
			if s % 2 == 0:
				_add_tone(_bass, st, int(_step * 1.6), _midi(r), 1, 0.26, 0.004, 0.03, 10.0, 0.5)
			if s % 4 == 2:
				for off in chords[c].tones:
					_add_tone(_mel, st, int(_step * 0.9), _midi(rm + 24.0 + off), 2, 0.03, 0.002, 0.03, 26.0, 0.35)
		# Tremolo-picked held note (first half bar) then a run down the scale (bar 2).
		var d0: int = [0, 2, 4, 5][_rng.randi() % 4]
		var held: float = rm + 24.0 + _scale_note(scale, d0 + 7)
		for k in range(8):
			_add_tone(_mel, _chord_step(c, k), int(_step * 1.4), _midi(held), 2, 0.05, 0.002, 0.04, 14.0, 0.3)
		for k in range(8):
			var dd: int = 9 - k
			_add_tone(_mel, _chord_step(c, 16 + k), int(_step * 1.3), _midi(rm + 24.0 + _scale_note(scale, dd)), 2, 0.05, 0.002, 0.04, 12.0, 0.3)
		for k in range(4):
			_add_tone(_mel, _chord_step(c, 24 + k * 2), int(_step * 3.0), _midi(held), 2, 0.05, 0.002, 0.05, 6.0, 0.3)
	_lowpass(_bass, 800.0)
	_lowpass(_mel, 5200.0)
	_echo(_mel, int(0.035 * SAMPLE_RATE), 0.55, 4) # spring reverb
	_drum_pattern(Ctx.COMBAT, wave)


# Woodland fae: harp arpeggios, glockenspiel bells, airy sine pad, flute lead,
# shaker and soft hand drum. Lydian, no hard kick.
func _v_fae(chords: Array, rm: float, scale: Array, wave: int) -> void:
	var harp := [[1.0, 1.0, 1.7], [2.0, 0.4, 3.4], [3.0, 0.18, 6.0]]
	var bell := [[1.0, 1.0, 2.0], [2.76, 0.4, 2.8], [5.4, 0.2, 3.6]]
	for c in range(chords.size()):
		if _is_cancelled(): return
		var tones: Array = chords[c].tones
		var span: Array = [tones[0], tones[1], tones[2], tones[0] + 12, tones[1] + 12, tones[2] + 12, tones[0] + 24, tones[2] + 12]
		for s in range(0, 32, 2):
			if _rng.randf() < 0.14:
				continue
			var off: int = span[(s / 2) % span.size()]
			_add_partials(_mel, _chord_step(c, s), int(_step * 12.0), _midi(rm + 12.0 + off), harp, 0.07, 0.002, 0.08)
		for off in tones:
			_add_tone(_pad, _chord_step(c, 0), 32 * _step + _step * 4, _midi(rm + 12.0 + off), 0, 0.04, 0.9, 1.0, 0.0, 0.5)
		for bar in range(2):
			if _rng.randf() < 0.65:
				var n: int = tones[_rng.randi() % 3] + 24
				_add_partials(_mel, _chord_step(c, bar * 16 + 8), int(_step * 20.0), _midi(rm + 24.0 + n), bell, 0.06, 0.002, 0.2)
	if wave >= 4:
		for c in range(chords.size()):
			var deg: int = 7 + _rng.randi() % 3
			for k in range(3):
				if _is_cancelled(): return
				deg = clampi(deg + (_rng.randi() % 3) - 1, 5, 11)
				_add_vib_tone(_mel, _chord_step(c, k * 10 + 2), int(_step * 8.0), _midi(rm + 24.0 + _scale_note(scale, deg)), 0.05, 0.08, 0.25, 0)
	_lowpass(_pad, 1500.0)
	_echo(_mel, _step * 4, 0.42, 3)
	for s in range(STEPS_PER_BAR * BARS):
		if s % 2 == 0:
			_hat(s * _step, 0.5)
		if s % 8 == 0:
			_soft_thump(s * _step, 0.22, 95.0)


# Snow: celesta/music-box arps, glassy pad, bell melody, sleigh-bell gallop,
# distant wind, and a soft heartbeat thump. Dorian, sparse, spacious.
func _v_snow(chords: Array, rm: float, scale: Array, wave: int) -> void:
	var celesta := [[1.0, 1.0, 3.5], [4.0, 0.3, 7.0], [6.0, 0.12, 10.0]]
	var bell := [[1.0, 1.0, 2.0], [2.76, 0.4, 3.0], [5.4, 0.2, 4.0]]
	for c in range(chords.size()):
		if _is_cancelled(): return
		var tones: Array = chords[c].tones
		var span: Array = [tones[0], tones[2], tones[1], tones[2], tones[0] + 12, tones[1], tones[2], tones[1] + 12]
		for s in range(0, 32, 2):
			if _rng.randf() < 0.3:
				continue
			_add_partials(_mel, _chord_step(c, s), int(_step * 9.0), _midi(rm + 24.0 + span[(s / 2) % span.size()]), celesta, 0.06, 0.002, 0.06)
		_add_tone(_pad, _chord_step(c, 0), 32 * _step + _step * 4, _midi(rm + 12.0 + tones[0]), 0, 0.045, 0.9, 1.0, 0.0, 0.5)
		_add_tone(_pad, _chord_step(c, 0), 32 * _step + _step * 4, _midi(rm + 12.0 + tones[1]), 0, 0.035, 0.9, 1.0, 0.0, 0.5)
		_add_tone(_pad, _chord_step(c, 0), 32 * _step + _step * 4, _midi(rm + 24.0 + tones[2]), 0, 0.03, 0.9, 1.0, 0.0, 0.5)
		for bar in range(2):
			if _rng.randf() < 0.55:
				var deg: int = 7 + _rng.randi() % 5
				_add_partials(_mel, _chord_step(c, bar * 16 + (_rng.randi() % 3) * 4), int(_step * 18.0), _midi(rm + 24.0 + _scale_note(scale, deg)), bell, 0.07, 0.002, 0.2)
			_add_tone(_bass, _chord_step(c, bar * 16), _step * 14, _midi(rm + chords[c].root), 0, 0.2, 0.02, 0.3, 0.0, 0.5)
	_lowpass(_pad, 1700.0)
	_lowpass(_bass, 400.0)
	_echo(_mel, _step * 3, 0.4, 4)
	_wind()
	for s in range(STEPS_PER_BAR * BARS):
		var bs: int = s % 16
		if bs % 4 == 0 or bs % 4 == 3:
			_jingle(s * _step, 1.0 if bs % 4 == 0 else 0.6)
		if bs == 0 or bs == 8:
			_soft_thump(s * _step, 0.3, 62.0)


# Desert: oud ostinato with grace notes, droning pad, snake-charmer lead and a
# maqsum darbuka groove. Phrygian dominant.
func _v_dune(chords: Array, rm: float, scale: Array, wave: int) -> void:
	for c in range(chords.size()):
		var r: float = rm + chords[c].root
		for f in [0.0, 7.0]:
			_add_tone(_pad, _chord_step(c, 0), 32 * _step + _step * 4, _midi(r + 12.0 + f), 1, 0.03, 0.6, 0.8, 0.0, 0.5)
		_add_tone(_bass, _chord_step(c, 0), 32 * _step, _midi(r), 0, 0.18, 0.2, 0.4, 0.0, 0.5)
		var deg: int = 0
		for s in range(0, 32, 2):
			if _is_cancelled(): return
			deg = clampi(deg + (_rng.randi() % 3) - 1, -1, 5)
			var note: float = rm + chords[c].root + 12.0 + _scale_note(scale, deg + 0)
			if s % 8 == 6:
				_add_tone(_mel, _chord_step(c, s) - _step, int(_step * 1.2), _midi(note + 1.0), 1, 0.05, 0.002, 0.03, 18.0, 0.5) # grace note
			_add_tone(_mel, _chord_step(c, s), int(_step * 3.0), _midi(note), 1, 0.08, 0.003, 0.05, 6.0, 0.5)
	if wave >= 4:
		for c in range(chords.size()):
			var d: int = 7 + _rng.randi() % 3
			for k in range(3):
				d = clampi(d + (_rng.randi() % 3) - 1, 6, 10)
				_add_vib_tone(_mel, _chord_step(c, k * 10 + 4), int(_step * 7.0), _midi(rm + 12.0 + _scale_note(scale, d)), 0.045, 0.05, 0.15, 0)
	_lowpass(_pad, 600.0)
	_lowpass(_mel, 2600.0)
	_echo(_mel, _step * 3, 0.3, 3)
	for s in range(STEPS_PER_BAR * BARS):
		var bs: int = s % 16
		if bs == 0 or bs == 8 or bs == 10:
			_darbuka(s * _step, 0)
		if bs == 4 or bs == 6 or bs == 12 or bs == 14:
			_darbuka(s * _step, 1)


# Volcano forge: low-brass swells, taiko, anvil rings, sub rumble. Phrygian.
func _v_forge(chords: Array, rm: float, scale: Array, wave: int) -> void:
	var anvil := [[1.0, 1.0, 10.0], [2.4, 0.6, 12.0], [3.9, 0.4, 14.0], [5.3, 0.3, 16.0]]
	for c in range(chords.size()):
		var r: float = rm + chords[c].root
		for f in [0.0, 7.0]:
			_add_tone(_pad, _chord_step(c, 0), 32 * _step + _step * 4, _midi(r + 12.0 + f) * 0.998, 1, 0.05, 0.35, 0.5, 0.0, 0.5)
			_add_tone(_pad, _chord_step(c, 0), 32 * _step + _step * 4, _midi(r + 12.0 + f) * 1.002, 1, 0.05, 0.35, 0.5, 0.0, 0.5)
		for s in range(0, 32, 4):
			_add_tone(_bass, _chord_step(c, s), int(_step * 3.0), _midi(r), 1, 0.3, 0.01, 0.06, 3.0, 0.5)
		if wave >= 4:
			var deg: int = 4
			for k in range(4):
				deg = clampi(deg + (_rng.randi() % 3) - 1, 2, 7)
				_add_tone(_mel, _chord_step(c, k * 8 + 2), _step * 6, _midi(rm + 12.0 + _scale_note(scale, deg)), 1, 0.05, 0.03, 0.12, 1.5, 0.5)
	_add_tone(_bass, 0, _n - 1, _midi(rm - 12.0), 0, 0.12, 0.5, 0.5, 0.0, 0.5) # sub rumble drone
	_lowpass(_pad, 700.0)
	_lowpass(_bass, 650.0)
	_lowpass(_mel, 1800.0)
	for i in range(_n):
		_bass[i] = tanh(_bass[i] * 2.4) * 0.55
	for s in range(STEPS_PER_BAR * BARS):
		var bs: int = s % 16
		if bs == 0:
			_taiko(s * _step, 0.9)
		elif bs == 6 or bs == 8 or bs == 11:
			_taiko(s * _step, 0.55)
		if bs == 4 or bs == 12:
			_add_partials(_drums, s * _step, int(_step * 5.0), 880.0, anvil, 0.07, 0.001, 0.04)
		if bs % 4 == 2:
			_hat(s * _step, 0.35)


# Dungeon crypt: organ drone, tolling bell, water drips, heartbeat. Harmonic minor.
func _v_crypt(chords: Array, rm: float, scale: Array, wave: int) -> void:
	var toll := [[1.0, 1.0, 1.2], [2.0, 0.6, 1.5], [2.76, 0.5, 2.0], [5.4, 0.2, 3.0]]
	var organ := [[1.0, 1.0, 0.0], [2.0, 0.45, 0.0]]
	for c in range(chords.size()):
		if _is_cancelled(): return
		var r: float = rm + chords[c].root
		for f in [0.0, 7.0]:
			_add_partials(_pad, _chord_step(c, 0), 32 * _step + _step * 4, _midi(r + 12.0 + f), organ, 0.04, 0.6, 0.8)
		_add_partials(_mel, _chord_step(c, 0), _step * 40, _midi(r + 12.0), toll, 0.11, 0.003, 0.3)
		_add_tone(_bass, _chord_step(c, 0), 32 * _step, _midi(r - 12.0), 0, 0.2, 0.3, 0.5, 0.0, 0.5)
	for k in range(10):
		var st: int = (_rng.randi() % (STEPS_PER_BAR * BARS)) * _step
		_add_tone(_mel, st, int(_step * 4.0), _rng.randf_range(1500.0, 3300.0), 0, 0.035, 0.001, 0.05, 20.0, 0.5)
	_lowpass(_pad, 1200.0)
	_echo(_mel, _step * 5, 0.45, 4)
	for s in range(0, STEPS_PER_BAR * BARS, 16):
		_soft_thump(s * _step, 0.32, 58.0)
		_soft_thump((s + 3) * _step, 0.22, 58.0)
	if wave >= 8:
		for s in range(0, STEPS_PER_BAR * BARS, 8):
			_soft_thump((s + 8) * _step, 0.18, 52.0)


# Farm: banjo forward-roll, upright-bass pluck, stomp/clap, harmonica lead.
func _v_farm(chords: Array, rm: float, scale: Array, wave: int) -> void:
	var roll := [0, 2, 1, 2, 0, 2, 1, 2]
	for c in range(chords.size()):
		if _is_cancelled(): return
		var tones: Array = chords[c].tones.duplicate()
		var r: float = rm + chords[c].root
		for s in range(32):
			var off: int = tones[roll[s % 8]]
			_add_tone(_mel, _chord_step(c, s), int(_step * 2.0), _midi(rm + 24.0 + off), 2, 0.04, 0.002, 0.03, 15.0, 0.2)
		for s in range(0, 32, 4):
			var note: float = r if (s / 4) % 2 == 0 else r + 7.0
			_add_tone(_bass, _chord_step(c, s), int(_step * 3.0), _midi(note), 1, 0.3, 0.004, 0.05, 5.0, 0.5)
		if wave >= 4:
			var deg: int = 7 + _rng.randi() % 3
			for k in range(3):
				deg = clampi(deg + (_rng.randi() % 3) - 1, 5, 10)
				_add_vib_tone(_mel, _chord_step(c, k * 10 + 2), int(_step * 6.0), _midi(rm + 24.0 + _scale_note(scale, deg)), 0.035, 0.02, 0.1, 1)
	_lowpass(_bass, 700.0)
	_lowpass(_mel, 3800.0)
	_echo(_mel, _step * 3, 0.25, 2)
	_drum_pattern(Ctx.COMBAT, 1)

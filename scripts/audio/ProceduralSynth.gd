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
static func generate_track(ctx: int, synergy: int, wave: int, cancel_check: Callable = Callable()) -> AudioStreamWAV:
	var s = ProceduralSynth.new()
	return s._render(ctx, synergy, wave, cancel_check)


static func loop_seconds(ctx: int, wave: int) -> float:
	var bpm = _bpm_for(ctx, wave)
	return BARS * 4.0 * 60.0 / bpm


static func _bpm_for(ctx: int, wave: int) -> float:
	match ctx:
		Ctx.GARAGE:
			return 72.0
		Ctx.BOSS:
			return 144.0
	return 116.0 + minf(float(wave), 30.0) * 0.5


func _midi(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)


func _is_cancelled() -> bool:
	if _cancelled:
		return true
	if _cancel.is_valid() and _cancel.call():
		_cancelled = true
	return _cancelled


func _render(ctx: int, synergy: int, wave: int, cancel_check: Callable) -> AudioStreamWAV:
	_cancel = cancel_check
	_rng.randomize()
	var bpm = _bpm_for(ctx, wave)
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
	var root_midi: float = 33.0 + float((absi(synergy) * 5) % 12) # A1..G#2, element picks the key
	var progs: Array = BOSS_PROGRESSIONS if ctx == Ctx.BOSS else PROGRESSIONS
	var prog: Array = progs[_rng.randi() % progs.size()]

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

	if _is_cancelled(): return null

	# --- Mix ---
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

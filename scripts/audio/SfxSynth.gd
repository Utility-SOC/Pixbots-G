extends RefCounted

# Procedural sound-effect synthesis (no audio assets, same rule as the visuals). Every sound is a short
# mono 16-bit loop-free clip rendered once at startup from a fixed seed, so the bank is deterministic.
# Recipes are built from a few primitives: exponential envelopes, swept sines, filtered noise, partials.

const RATE = 22050

var _rng := RandomNumberGenerator.new()

static func ids() -> Array:
	return ["kinetic", "pierce", "fire", "ice", "lightning", "poison", "explosive", "vortex", "vampiric", "raw",
		"hit", "mech_hit", "clang", "boom", "boom_small", "death", "death_boss", "pickup", "mine_blip", "charge"]

func render(id: String) -> AudioStreamWAV:
	_rng.seed = hash(id)
	var s: PackedFloat32Array
	match id:
		"kinetic": s = _kinetic()
		"pierce": s = _pierce()
		"fire": s = _fire()
		"ice": s = _ice()
		"lightning": s = _lightning()
		"poison": s = _poison()
		"explosive": s = _boom(0.35, 90.0, 0.7)
		"vortex": s = _vortex()
		"vampiric": s = _vampiric()
		"raw": s = _raw()
		"hit": s = _hit()
		"mech_hit": s = _mech_hit()
		"clang": s = _clang()
		"boom": s = _boom(0.8, 70.0, 1.0)
		"boom_small": s = _boom(0.3, 110.0, 0.8)
		"death": s = _death(0.6, 1.0)
		"death_boss": s = _death(1.3, 1.6)
		"pickup": s = _pickup()
		"mine_blip": s = _tone_burst(1000.0, 0.05, 0.4)
		"charge": s = _charge()
		_: s = _tone_burst(440.0, 0.05, 0.3)
	return _to_stream(s)

# --- primitives -------------------------------------------------------------------------------

func _buf(seconds: float) -> PackedFloat32Array:
	var b = PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b

# Smooth edges (2 ms) so no clip ever clicks, whatever the recipe does.
func _to_stream(b: PackedFloat32Array) -> AudioStreamWAV:
	var n = b.size()
	var peak = 0.0001
	for v in b:
		peak = maxf(peak, absf(v))
	var norm = 0.9 / peak
	var edge = 44
	var out = PackedByteArray()
	out.resize(n * 2)
	for i in range(n):
		var g = 1.0
		if i < edge:
			g = float(i) / edge
		elif n - 1 - i < edge:
			g = float(n - 1 - i) / edge
		out.encode_s16(i * 2, int(clampf(b[i] * norm * g, -1.0, 1.0) * 32767.0))
	var st = AudioStreamWAV.new()
	st.data = out
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	return st

func _env(t: float, attack: float, decay: float) -> float:
	var a = clampf(t / maxf(attack, 0.0001), 0.0, 1.0)
	return a * exp(-t / maxf(decay, 0.0001))

# Sine whose frequency glides from f0 to f1 over the clip (exponentially).
func _sweep(b: PackedFloat32Array, f0: float, f1: float, amp: float, attack: float, decay: float, start: float = 0.0) -> void:
	var n = b.size()
	var s0 = int(start * RATE)
	var phase = 0.0
	var len_s = float(n - s0) / RATE
	for i in range(s0, n):
		var t = float(i - s0) / RATE
		var f = f0 * pow(f1 / f0, clampf(t / maxf(len_s, 0.001), 0.0, 1.0))
		phase += TAU * f / RATE
		b[i] += sin(phase) * amp * _env(t, attack, decay)

func _noise(b: PackedFloat32Array, amp: float, attack: float, decay: float, cutoff: float, start: float = 0.0, cutoff_end: float = -1.0) -> void:
	var n = b.size()
	var s0 = int(start * RATE)
	var lp = 0.0
	var len_s = float(n - s0) / RATE
	for i in range(s0, n):
		var t = float(i - s0) / RATE
		var fc = cutoff if cutoff_end < 0.0 else lerpf(cutoff, cutoff_end, clampf(t / maxf(len_s, 0.001), 0.0, 1.0))
		var a = clampf(TAU * fc / RATE, 0.0, 1.0)
		lp += a * (_rng.randf_range(-1.0, 1.0) - lp)
		b[i] += lp * amp * _env(t, attack, decay)

func _partial(b: PackedFloat32Array, f: float, amp: float, decay: float, start: float = 0.0) -> void:
	var s0 = int(start * RATE)
	for i in range(s0, b.size()):
		var t = float(i - s0) / RATE
		b[i] += sin(TAU * f * t) * amp * _env(t, 0.002, decay)

# --- recipes ---------------------------------------------------------------------------------

func _tone_burst(f: float, seconds: float, amp: float) -> PackedFloat32Array:
	var b = _buf(seconds)
	_partial(b, f, amp, seconds * 0.5)
	return b

func _kinetic() -> PackedFloat32Array:
	var b = _buf(0.18)
	_sweep(b, 220.0, 55.0, 0.9, 0.002, 0.05)
	_noise(b, 0.5, 0.001, 0.012, 4000.0)
	return b

func _pierce() -> PackedFloat32Array:
	var b = _buf(0.12)
	_sweep(b, 2400.0, 1000.0, 0.6, 0.001, 0.03)
	_noise(b, 0.15, 0.001, 0.01, 8000.0)
	return b

func _fire() -> PackedFloat32Array:
	var b = _buf(0.3)
	_noise(b, 0.9, 0.04, 0.09, 500.0, 0.0, 2600.0)
	_sweep(b, 120.0, 80.0, 0.25, 0.02, 0.1)
	return b

func _ice() -> PackedFloat32Array:
	var b = _buf(0.3)
	_partial(b, 2093.0, 0.5, 0.07)
	_partial(b, 3136.0, 0.35, 0.05, 0.015)
	_partial(b, 4186.0, 0.2, 0.04, 0.03)
	_noise(b, 0.08, 0.001, 0.01, 9000.0)
	return b

func _lightning() -> PackedFloat32Array:
	var b = _buf(0.2)
	var phase = 0.0
	for i in range(b.size()):
		var t = float(i) / RATE
		var f = 300.0 + 900.0 * sin(t * 90.0) + _rng.randf_range(-250.0, 250.0)
		phase += TAU * absf(f) / RATE
		b[i] += signf(sin(phase)) * 0.3 * _env(t, 0.001, 0.05)
	_noise(b, 0.5, 0.001, 0.03, 7000.0)
	return b

func _poison() -> PackedFloat32Array:
	var b = _buf(0.35)
	for k in range(3):
		var st = 0.0 + k * 0.09 + _rng.randf_range(0.0, 0.02)
		var f0 = _rng.randf_range(250.0, 400.0)
		var sub = _buf(0.12)
		_sweep(sub, f0, f0 * 2.2, 0.6, 0.004, 0.03)
		var s0 = int(st * RATE)
		for i in range(sub.size()):
			if s0 + i < b.size():
				b[s0 + i] += sub[i]
	return b

func _boom(seconds: float, f: float, amp: float) -> PackedFloat32Array:
	var b = _buf(seconds)
	_sweep(b, f * 1.6, f * 0.4, amp, 0.004, seconds * 0.35)
	_noise(b, 0.9 * amp, 0.003, seconds * 0.3, 900.0, 0.0, 200.0)
	_noise(b, 0.4 * amp, 0.001, 0.03, 5000.0)
	return b

func _vortex() -> PackedFloat32Array:
	var b = _buf(0.4)
	var phase = 0.0
	for i in range(b.size()):
		var t = float(i) / RATE
		var f = 200.0 + 60.0 * sin(t * TAU * 9.0) - 80.0 * t
		phase += TAU * f / RATE
		b[i] += sin(phase) * 0.7 * _env(t, 0.04, 0.2)
	_noise(b, 0.15, 0.05, 0.2, 700.0)
	return b

func _vampiric() -> PackedFloat32Array:
	var b = _buf(0.3)
	for i in range(b.size()):
		var t = float(i) / RATE
		b[i] += sin(TAU * 110.0 * t) * (0.6 + 0.4 * sin(TAU * 18.0 * t)) * _env(t, 0.01, 0.12)
	_sweep(b, 300.0, 700.0, 0.2, 0.02, 0.1, 0.05)
	return b

func _raw() -> PackedFloat32Array:
	var b = _buf(0.08)
	for i in range(b.size()):
		var t = float(i) / RATE
		b[i] += (1.0 if sin(TAU * 620.0 * t) > 0.0 else -1.0) * 0.3 * _env(t, 0.001, 0.025)
	return b

func _hit() -> PackedFloat32Array:
	var b = _buf(0.07)
	_noise(b, 0.9, 0.001, 0.012, 3500.0)
	_sweep(b, 500.0, 200.0, 0.3, 0.001, 0.015)
	return b

func _mech_hit() -> PackedFloat32Array:
	var b = _buf(0.16)
	_sweep(b, 160.0, 70.0, 0.8, 0.002, 0.04)
	_noise(b, 0.6, 0.001, 0.02, 2200.0)
	return b

func _clang() -> PackedFloat32Array:
	var b = _buf(0.35)
	_partial(b, 820.0, 0.5, 0.12)
	_partial(b, 1340.0, 0.4, 0.09)
	_partial(b, 2110.0, 0.3, 0.06)
	_noise(b, 0.3, 0.001, 0.01, 6000.0)
	return b

func _death(seconds: float, weight: float) -> PackedFloat32Array:
	var b = _buf(seconds)
	_sweep(b, 260.0 * weight, 35.0, 0.8, 0.005, seconds * 0.4)
	_noise(b, 0.8, 0.005, seconds * 0.3, 1800.0, 0.0, 150.0)
	_boom_tail(b, seconds)
	return b

func _boom_tail(b: PackedFloat32Array, seconds: float) -> void:
	_sweep(b, 90.0, 30.0, 0.5, 0.05, seconds * 0.5, seconds * 0.15)

func _pickup() -> PackedFloat32Array:
	var b = _buf(0.3)
	_partial(b, 784.0, 0.5, 0.08)
	_partial(b, 1175.0, 0.45, 0.1, 0.07)
	_partial(b, 1568.0, 0.3, 0.12, 0.14)
	return b

func _charge() -> PackedFloat32Array:
	var b = _buf(0.35)
	_sweep(b, 200.0, 900.0, 0.5, 0.02, 0.4)
	return b

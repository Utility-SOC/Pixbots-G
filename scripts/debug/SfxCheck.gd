extends Node

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	const SfxSynth = preload("res://scripts/audio/SfxSynth.gd")
	var synth = SfxSynth.new()
	var t0 = Time.get_ticks_msec()
	for id in SfxSynth.ids():
		var a = synth.render(id)
		var b = SfxSynth.new().render(id)
		_check("%s renders deterministically" % id, a.data == b.data and a.data.size() > 200)
		var peak = 0
		var n = a.data.size() / 2
		for i in range(0, n, 3):
			peak = max(peak, absi(a.data.decode_s16(i * 2)))
		_check("%s audible and unclipped (peak %d)" % [id, peak], peak > 8000 and peak < 32700)
		_check("%s short enough (%.2fs)" % [id, a.get_length()], a.get_length() <= 1.5)
		_check("%s starts and ends at silence" % id, absi(a.data.decode_s16(0)) < 400 and absi(a.data.decode_s16((n - 1) * 2)) < 400)
	print("bank render ms: %d" % (Time.get_ticks_msec() - t0))
	# attenuation
	var SfxM = load("res://scripts/audio/SfxManager.gd")
	_check("attenuation full at 0, zero at range", SfxM.attenuation(0.0) == 1.0 and SfxM.attenuation(SfxM.HEARING_RANGE) == 0.0 and SfxM.attenuation(SfxM.HEARING_RANGE * 0.5) < 0.3)
	# autoload plays, rate-limits, and ducks
	var waited = 0
	while not Sfx.is_ready() and waited < 200:
		await get_tree().create_timer(0.05).timeout
		waited += 1
	_check("autoload bank ready", Sfx.is_ready())
	var p0 = Sfx.played
	_check("first shot plays", Sfx.play("kinetic"))
	_check("immediate repeat is rate-limited", not Sfx.play("kinetic"))
	_check("different id still plays", Sfx.play("ice"))
	_check("far-away sound is dropped", not Sfx.play("hit", Vector2(99999, 99999)))
	_check("played counter advanced", Sfx.played >= p0 + 2)
	# voice cap: flood with distinct ids/gains must never exceed the pool
	var started = 0
	for i in range(60):
		Sfx.volume_db = 0.0
		for id in ["boom", "death", "pickup", "clang", "fire", "vortex", "lightning", "poison"]:
			Sfx._last_play.erase(id)
			if Sfx.play(id, null, float(i % 5)):
				started += 1
	_check("flood stays within the voice pool (%d started)" % started, started <= 8 * 60 and Sfx.dropped > 0)
	# music ducking is wired: Music bus has a compressor sidechained to Impact
	var music = AudioServer.get_bus_index("Music")
	var found = false
	for e in range(AudioServer.get_bus_effect_count(music)):
		var fx = AudioServer.get_bus_effect(music, e)
		if fx is AudioEffectCompressor and str(fx.sidechain) == "Impact":
			found = true
	_check("Music bus ducks under the Impact bus", found and AudioServer.get_bus_index("Impact") >= 0)
	print("sfx check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

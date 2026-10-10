extends Node

# Measures the Music-bus sidechain ducking for real: a steady tone plays on the Music bus, a heavy Impact sound fires,
# and the Music bus level is sampled before/during/after. Prints the depth and timing so the compressor can be tuned
# by numbers instead of by ear. Asserts the music actually dips and then recovers.

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _tone() -> AudioStreamWAV:
	var rate = 22050
	var n = rate
	var d = PackedByteArray()
	d.resize(n * 2)
	for i in range(n):
		d.encode_s16(i * 2, int(sin(TAU * 220.0 * float(i) / rate) * 16000.0))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = d
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = n
	return w

func _level(bus: int) -> float:
	return maxf(AudioServer.get_bus_peak_volume_left_db(bus, 0), AudioServer.get_bus_peak_volume_right_db(bus, 0))

func _ready():
	var waited = 0
	while not Sfx.is_ready() and waited < 200:
		await get_tree().create_timer(0.05).timeout
		waited += 1
	var music = AudioServer.get_bus_index("Music")
	# Optional tuning overrides for experiments: -- --thr=-20 --ratio=3 --release=400 --attack=15000
	for a in OS.get_cmdline_user_args():
		for e in range(AudioServer.get_bus_effect_count(music)):
			var c = AudioServer.get_bus_effect(music, e)
			if c is AudioEffectCompressor:
				if a.begins_with("--thr="): c.threshold = float(a.split("=")[1])
				elif a.begins_with("--ratio="): c.ratio = float(a.split("=")[1])
				elif a.begins_with("--release="): c.release_ms = float(a.split("=")[1])
				elif a.begins_with("--attack="): c.attack_us = float(a.split("=")[1])
	ProceduralMusic.stop()
	AudioManager.process_mode = Node.PROCESS_MODE_DISABLED
	for p in AudioManager._players:
		p.stop()
	var tone = AudioStreamPlayer.new()
	tone.stream = _tone()
	tone.bus = "Music"
	tone.volume_db = -6.0
	add_child(tone)
	tone.play()
	await get_tree().create_timer(0.6).timeout
	var base = _level(music)
	print("music level before: %.1f dB" % base)
	_check("a steady tone is audible on the Music bus", base > -40.0)

	var lows: Array = []
	var t_min = 0.0
	var lo = 99.0
	Sfx.explosion(200.0)
	var t = 0.0
	while t < 1.6:
		await get_tree().create_timer(0.02).timeout
		t += 0.02
		var l = _level(music)
		lows.append(l)
		if l < lo:
			lo = l
			t_min = t
	var depth = base - lo
	var after = lows[lows.size() - 1]
	var recovered_at = -1.0
	for i in range(lows.size()):
		if (i * 0.02) > t_min and lows[i] >= base - 1.0:
			recovered_at = i * 0.02
			break
	print("DUCK depth=%.1f dB deepest_at=%.2fs recovered_at=%.2fs end=%.1f dB" % [depth, t_min, recovered_at, after])
	_check("a heavy impact ducks the music audibly (%.1f dB)" % depth, depth >= 4.0)
	_check("...but does not mute it (<= 15 dB)", depth <= 15.0)
	_check("the music is back within 1.2 s", recovered_at > 0.0 and recovered_at <= 1.2)
	print("SfxDuckingCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

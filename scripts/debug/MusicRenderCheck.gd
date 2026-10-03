extends Node

# Renders every music context, asserts sane output (non-silent, not clipped,
# seamless loop seam, within a render-time budget) and saves WAVs to
# ~/pixbots_music_samples for listening.

const Synth = preload("res://scripts/audio/ProceduralSynth.gd")
var failures := 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var dir = OS.get_environment("HOME") + "/pixbots_music_samples"
	DirAccess.make_dir_recursive_absolute(dir)
	var cases = [
		["garage", Synth.Ctx.GARAGE, 1, 3],
		["combat_w1", Synth.Ctx.COMBAT, 1, 0],
		["combat_w15", Synth.Ctx.COMBAT, 15, 6],
		["boss", Synth.Ctx.BOSS, 20, 2],
	]
	for c in cases:
		var t0 = Time.get_ticks_msec()
		var st: AudioStreamWAV = Synth.generate_track(c[1], c[3], c[2])
		var ms = Time.get_ticks_msec() - t0
		var d: PackedByteArray = st.data
		var n = d.size() / 2
		var peak = 0
		var sumsq = 0.0
		var clipped = 0
		for i in range(n):
			var v = d.decode_s16(i * 2)
			peak = maxi(peak, absi(v))
			sumsq += float(v) * float(v)
			if absi(v) >= 32700:
				clipped += 1
		var rms = sqrt(sumsq / n) / 32768.0
		var seam = absi(d.decode_s16((n - 1) * 2) - d.decode_s16(0))
		var secs = float(n) / st.mix_rate
		print("%s: %.1fs loop, render %d ms, peak %d, rms %.3f, clipped %d, seam jump %d" % [c[0], secs, ms, peak, rms, clipped, seam])
		_check(c[0] + " is not silent", rms > 0.03)
		_check(c[0] + " peak stays below full-scale clipping", clipped < n / 500)
		_check(c[0] + " loop seam is smooth (<12% of full scale)", seam < 4000)
		_check(c[0] + " render under 15s", ms < 15000)
		st.save_to_wav(dir + "/" + c[0] + ".wav")
	print("music render check done, failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

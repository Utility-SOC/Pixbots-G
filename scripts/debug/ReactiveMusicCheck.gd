extends Node

# Regression harness for the reactive-music wiring: set_combat_state(true)
# is called immediately at startup, while AudioManager's _ready() ambient
# generation thread is almost certainly still baking its 16s loop. The old
# code silently dropped requests that arrived mid-bake; the fix regenerates
# for the current state when the in-flight bake lands. Combat loops are 8s
# and ambient loops 16s (see ProceduralSynth.generate_level_loop), so the
# playing stream's byte length tells us which one actually won.

var elapsed := 0.0

func _ready():
	AudioManager.set_combat_state(true)

func _process(delta):
	elapsed += delta
	var stream = AudioManager.current_player.stream
	if stream is AudioStreamWAV and stream.data.size() > 0:
		var seconds = stream.data.size() / (2.0 * stream.mix_rate)
		if abs(seconds - 8.0) < 0.1:
			print("PASS: combat loop (%.1fs) playing despite the request landing mid-bake" % seconds)
			get_tree().quit(0)
			return
	if elapsed > 30.0:
		var desc = "no stream"
		if stream is AudioStreamWAV:
			desc = "%.1fs loop" % (stream.data.size() / (2.0 * stream.mix_rate))
		push_error("FAIL: combat loop never took over within 30s (currently: %s)" % desc)
		get_tree().quit(1)

extends Node

# Regression harness for the reactive-music wiring: set_combat_state(true)
# is called immediately at startup, while AudioManager's _ready() ambient
# generation thread is almost certainly still baking its 16s loop. The old
# code silently dropped requests that arrived mid-bake; the fix regenerates
# for the current state when the in-flight bake lands. AudioManager.current_ctx
# records which context the playing stream was rendered for.

var elapsed := 0.0

func _ready():
	AudioManager.set_combat_state(true)

func _process(delta):
	elapsed += delta
	var stream = AudioManager.current_player.stream
	if stream is AudioStreamWAV and stream.data.size() > 0 and AudioManager.current_ctx == ProceduralSynth.Ctx.COMBAT:
		var seconds = stream.data.size() / (2.0 * stream.mix_rate)
		print("PASS: combat loop (%.1fs) playing despite the request landing mid-bake" % seconds)
		get_tree().quit(0)
		return
	if elapsed > 30.0:
		push_error("FAIL: combat loop never took over within 30s (ctx now %d)" % AudioManager.current_ctx)
		get_tree().quit(1)

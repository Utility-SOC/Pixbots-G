extends Node
const ProceduralSynth = preload("res://scripts/audio/ProceduralSynth.gd")

var current_player: AudioStreamPlayer
var current_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.FIRE
var is_combat: bool = false
var is_boss: bool = false
var current_wave: int = 1
# What the currently-playing (or last-requested) loop was rendered for.
var current_ctx: int = ProceduralSynth.Ctx.GARAGE

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	if AudioServer.get_bus_count() == 1: # Only Master exists
		AudioServer.add_bus()
		AudioServer.set_bus_name(1, "Music")
		AudioServer.add_bus()
		AudioServer.set_bus_name(2, "SFX")
		
	current_player = AudioStreamPlayer.new()
	current_player.bus = "Music"
	add_child(current_player)
	_generate_and_play()

func _wanted_ctx() -> int:
	if not is_combat:
		return ProceduralSynth.Ctx.GARAGE
	return ProceduralSynth.Ctx.BOSS if is_boss else ProceduralSynth.Ctx.COMBAT

# wave: current wave number (combat music gains layers as it rises). Every
# combat start re-renders so each wave gets a fresh progression.
func set_combat_state(combat: bool, wave: int = -1):
	if wave >= 0:
		current_wave = wave
	if not combat:
		is_boss = false
	var changed = is_combat != combat
	is_combat = combat
	if changed or combat:
		_generate_and_play()

# Boss fights swap the wave track for the heavier boss track.
func set_boss(boss: bool):
	if is_boss != boss:
		is_boss = boss
		if is_combat:
			_generate_and_play()

func set_dominant_synergy(synergy: EnergyPacket.SynergyType):
	if current_synergy != synergy:
		current_synergy = synergy
		_generate_and_play()

var _thread: Thread
var _quitting: bool = false

func _exit_tree():
	# The generator thread captures `self` for the call_deferred handoff; if
	# it outlives this node (app quit mid-generation) it fires into a freed
	# instance and the engine tears down utility functions under its feet.
	# Signal it to bail, then block until it actually has.
	_quitting = true
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null

func _generate_and_play():
	print("[Audio] Generating new procedural loop. Synergy: ", current_synergy, " Combat: ", is_combat)
	
	if _thread and _thread.is_alive():
		# Can't easily cancel a thread, so just let it finish if one is running
		return
		
	if _thread:
		_thread.wait_to_finish()
		
	_thread = Thread.new()
	_thread.start(_generate_thread.bind([current_synergy, _wanted_ctx(), current_wave]))

func _generate_thread(args: Array):
	var syn = args[0]
	var ctx = args[1]
	var wave = args[2]
	var stream = ProceduralSynth.generate_track(ctx, syn, wave, func(): return _quitting)
	if stream == null or _quitting:
		return
	call_deferred("_on_generate_finished", stream, syn, ctx)

func _on_generate_finished(stream: AudioStreamWAV, generated_syn: EnergyPacket.SynergyType, generated_ctx: int):
	if _thread:
		_thread.wait_to_finish()
		_thread = null

	# Fade the old loop out (0.6s) before the new one comes in, so a mood
	# change reads as a transition instead of a hard cut.
	if current_player.playing:
		var tween = create_tween()
		tween.tween_property(current_player, "volume_db", -40.0, 0.6)
		await tween.finished

	current_ctx = generated_ctx
	current_player.stream = stream
	current_player.volume_db = -30.0
	current_player.play()
	var fade_in = create_tween()
	fade_in.tween_property(current_player, "volume_db", 0.0, 0.8)

	# State moved while this loop was baking (set_combat_state/
	# set_dominant_synergy early-return when a thread is alive rather than
	# stacking threads) - kick off a fresh generation for the CURRENT state
	# so e.g. a wave-start combat cue isn't silently dropped.
	if generated_syn != current_synergy or generated_ctx != _wanted_ctx():
		_generate_and_play()

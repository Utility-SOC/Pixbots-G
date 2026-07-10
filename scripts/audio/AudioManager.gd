extends Node
const ProceduralSynth = preload("res://scripts/audio/ProceduralSynth.gd")

var current_player: AudioStreamPlayer
var current_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.FIRE
var is_combat: bool = false

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

func set_combat_state(combat: bool):
	if is_combat != combat:
		is_combat = combat
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
	_thread.start(_generate_thread.bind([current_synergy, is_combat]))

func _generate_thread(args: Array):
	var syn = args[0]
	var combat = args[1]
	var stream = ProceduralSynth.generate_level_loop(syn, combat, func(): return _quitting)
	if stream == null or _quitting:
		return
	call_deferred("_on_generate_finished", stream)

func _on_generate_finished(stream: AudioStreamWAV):
	if _thread:
		_thread.wait_to_finish()
		_thread = null
		
	# Brief fade to prevent popping
	if current_player.playing:
		var tween = create_tween()
		tween.tween_property(current_player, "volume_db", -40.0, 0.1)
		await tween.finished
		
	current_player.stream = stream
	current_player.volume_db = 0.0
	current_player.play()

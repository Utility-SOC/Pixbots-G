extends Node

# Writes every procedural sound to ~/pixbots_sfx_preview/<id>.wav so they can be auditioned outside the game.
func _ready():
	const SfxSynth = preload("res://scripts/audio/SfxSynth.gd")
	var dir = OS.get_environment("HOME") + "/pixbots_sfx_preview"
	DirAccess.make_dir_recursive_absolute(dir)
	for id in SfxSynth.ids():
		SfxSynth.new().render(id).save_to_wav("%s/%s.wav" % [dir, id])
	print("wrote %d clips to %s" % [SfxSynth.ids().size(), dir])
	get_tree().quit()

extends Node

# Exercises SettingsMenu's new Profile tab + SaveManager.set_pilot_name
# round trip. Safe to delete once validated.

const SettingsMenu = preload("res://scripts/ui/SettingsMenu.gd")

func _ready():
	var menu = SettingsMenu.new()
	add_child(menu)
	print("edit_pilot_name.text after open: '", menu.edit_pilot_name.text, "'")

	SaveManager.set_pilot_name("  Test Pilot  ")
	print("SaveManager.pilot_name after set: '", SaveManager.pilot_name, "' (expect trimmed 'Test Pilot')")

	SaveManager.set_pilot_name("")
	print("SaveManager.pilot_name after empty set: '", SaveManager.pilot_name, "' (expect fallback 'Unknown Pilot')")

	menu._load_settings()
	print("edit_pilot_name.text after reload: '", menu.edit_pilot_name.text, "'")

	get_tree().quit()

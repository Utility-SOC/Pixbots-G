class_name SquadProfileManager
extends Node

const DEFAULT_PROFILE_PATH = "user://ai_profiles/"

func _ready():
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("ai_profiles"):
		dir.make_dir("ai_profiles")

func save_profile(profile_name: String, templates: Array[SquadTemplate]):
	var save_path = DEFAULT_PROFILE_PATH + profile_name + ".json"
	
	var profile_data = {
		"profile_name": profile_name,
		"version": "1.0",
		"templates": []
	}
	
	for template in templates:
		profile_data["templates"].append(template.to_dict())
		
	var json_string = JSON.stringify(profile_data, "\t")
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Successfully saved AI Profile to: ", save_path)
	else:
		push_error("Failed to save AI Profile: ", save_path)

func load_profile(profile_name: String) -> Array[SquadTemplate]:
	var load_path = DEFAULT_PROFILE_PATH + profile_name + ".json"
	
	# Fallback to res:// if user profile doesn't exist (e.g., default community mods)
	if not FileAccess.file_exists(load_path):
		load_path = "res://config/" + profile_name + ".json"
		if not FileAccess.file_exists(load_path):
			push_error("Profile not found: ", profile_name)
			return []
			
	var file = FileAccess.open(load_path, FileAccess.READ)
	if not file:
		return []
		
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("JSON Parse Error: ", json.get_error_message())
		return []
		
	var data = json.data
	var templates: Array[SquadTemplate] = []
	
	if data.has("templates"):
		for t_data in data["templates"]:
			var template = SquadTemplate.new()
			template.from_dict(t_data)
			templates.append(template)
			
	return templates

func export_to_clipboard(templates: Array[SquadTemplate]):
	var profile_data = {"templates": []}
	for t in templates:
		profile_data["templates"].append(t.to_dict())
	DisplayServer.clipboard_set(JSON.stringify(profile_data))
	print("Profile exported to clipboard! Ready to share.")

class_name SquadProfileManager
extends Node

const DEFAULT_PROFILE_PATH = "user://ai_profiles/"

func _ready():
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("ai_profiles"):
		dir.make_dir("ai_profiles")

func has_profile(profile_name: String) -> bool:
	return FileAccess.file_exists(DEFAULT_PROFILE_PATH + profile_name + ".json") \
		or FileAccess.file_exists("res://config/" + profile_name + ".json")

# solver_profiles rides along in the same file under its own key, so a
# saved/shared profile carries BOTH halves of the AI's learning: squad
# compositions (SquadTemplate) and loadout-building preferences
# (SolverProfile). Older files without the key still load fine.
func save_profile(profile_name: String, templates: Array[SquadTemplate], solver_profiles: Array = []):
	var save_path = DEFAULT_PROFILE_PATH + profile_name + ".json"

	var profile_data = {
		"profile_name": profile_name,
		"version": "1.1",
		"templates": [],
		"solver_profiles": []
	}

	for template in templates:
		profile_data["templates"].append(template.to_dict())
	for p in solver_profiles:
		profile_data["solver_profiles"].append(p.to_dict())

	var json_string = JSON.stringify(profile_data, "\t")
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(json_string)
		file.close()
		print("Successfully saved AI Profile to: ", save_path)
	else:
		push_error("Failed to save AI Profile: ", save_path)

# Shared file-read/parse step for load_profile/load_solver_profiles - the
# two loaders read the same file, so the path-fallback and JSON handling
# live once here instead of twice.
func _read_profile_data(profile_name: String) -> Dictionary:
	var load_path = DEFAULT_PROFILE_PATH + profile_name + ".json"

	# Fallback to res:// if user profile doesn't exist (e.g., default community mods)
	if not FileAccess.file_exists(load_path):
		load_path = "res://config/" + profile_name + ".json"
		if not FileAccess.file_exists(load_path):
			push_error("Profile not found: ", profile_name)
			return {}

	var file = FileAccess.open(load_path, FileAccess.READ)
	if not file:
		return {}

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("JSON Parse Error: ", json.get_error_message())
		return {}

	return json.data if json.data is Dictionary else {}

func load_profile(profile_name: String) -> Array[SquadTemplate]:
	var data = _read_profile_data(profile_name)
	return _templates_from_data(data)

func load_solver_profiles(profile_name: String) -> Array:
	var data = _read_profile_data(profile_name)
	return _solver_profiles_from_data(data)

func _templates_from_data(data: Dictionary) -> Array[SquadTemplate]:
	var templates: Array[SquadTemplate] = []
	if data.has("templates"):
		for t_data in data["templates"]:
			var template = SquadTemplate.new()
			template.from_dict(t_data)
			templates.append(template)
	return templates

func _solver_profiles_from_data(data: Dictionary) -> Array:
	var profiles: Array = []
	if data.has("solver_profiles"):
		for p_data in data["solver_profiles"]:
			var p = SolverProfile.new()
			p.from_dict(p_data)
			profiles.append(p)
	return profiles

func export_to_clipboard(templates: Array[SquadTemplate], solver_profiles: Array = []):
	var profile_data = {"templates": [], "solver_profiles": []}
	for t in templates:
		profile_data["templates"].append(t.to_dict())
	for p in solver_profiles:
		profile_data["solver_profiles"].append(p.to_dict())
	DisplayServer.clipboard_set(JSON.stringify(profile_data))
	print("Profile exported to clipboard! Ready to share.")

# Counterpart to export_to_clipboard - parse a shared profile back out of
# the clipboard. Returns {"templates": [...], "solver_profiles": [...]}
# (either may be empty), or {} if the clipboard isn't a valid profile.
func import_from_clipboard() -> Dictionary:
	var text = DisplayServer.clipboard_get()
	if text.strip_edges() == "":
		return {}
	var json = JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		push_error("Clipboard does not contain a valid AI profile.")
		return {}
	return {
		"templates": _templates_from_data(json.data),
		"solver_profiles": _solver_profiles_from_data(json.data),
	}

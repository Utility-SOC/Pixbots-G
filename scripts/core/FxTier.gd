extends RefCounted

# Optional-visuals tier ("safe FX"): scorch decals, the shallow-water tint and biome weather are switched
# off when it is on. It is on when
#   - PIXBOTS_SAFE_FX=1 is set (the launcher's --safe flag), or
#   - the previous run did not exit cleanly: a marker file is written when a session starts and removed
#     on a clean quit, so a GPU crash (Vulkan device lost, signal 4) leaves it behind and the next launch
#     starts in safe mode and says so.
# PIXBOTS_FULL_FX=1 (the launcher's --full-fx flag) overrides both. Headless runs ignore the marker so test
# processes that get killed never flip the tier for later ones.

const MARKER = "user://run_in_progress.marker"

static var _initialised := false
static var _auto_safe := false

static func _init_state() -> void:
	if _initialised:
		return
	_initialised = true
	if DisplayServer.get_name() == "headless":
		return
	if FileAccess.file_exists(MARKER):
		_auto_safe = true
		print("[FX] The last run did not exit cleanly (possible GPU crash): starting with optional visuals OFF. Launch with --full-fx to override.")
	var f = FileAccess.open(MARKER, FileAccess.WRITE)
	if f:
		f.store_string(str(Time.get_unix_time_from_system()))

static func safe() -> bool:
	_init_state()
	if OS.get_environment("PIXBOTS_FULL_FX") == "1":
		return false
	return _auto_safe or OS.get_environment("PIXBOTS_SAFE_FX") == "1"

# Call on a clean quit.
static func end_session() -> void:
	if FileAccess.file_exists(MARKER):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(MARKER))

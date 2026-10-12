class_name RendererPref
extends RefCounted

# Which renderer the game starts with. Godot fixes the renderer at startup, so the choice is persisted and takes
# effect on the NEXT launch. Two places apply it: pixbots-launch.sh (reads the same setting, passes
# --rendering-method) and an override.cfg that this class keeps in sync, so runs without the launcher obey it too.
#   "auto"   OpenGL (gl_compatibility) on GPUs whose Vulkan driver is known-incomplete (Mesa ANV on Intel Ivy Bridge /
#            Haswell / Bay Trail: Vulkan hangs the HD 4000 in the Garage), Vulkan Forward+ elsewhere.
#   "vulkan" always Forward+.   "opengl" always Compatibility.
# Stored in user://settings.cfg [Display] Renderer (see SaveManager.set_renderer_pref).

const AUTO := "auto"
const VULKAN := "vulkan"
const OPENGL := "opengl"
const VALUES := [AUTO, VULKAN, OPENGL]
const NAMES := ["Auto (recommended)", "Vulkan (Forward+)", "OpenGL (Compatibility)"]
const METHOD_VULKAN := "forward_plus"
const METHOD_OPENGL := "gl_compatibility"
const OVERRIDE_KEY := "renderer/rendering_method"

# Mesa names these "Intel(R) HD Graphics 4000 (IVB GT2)", "... (HSW GT2)", "... (BYT)".
const WEAK_ADAPTER_PATTERN := "\\b(IVB|HSW|BYT)\\b|Bay Trail|HD Graphics (2000|2500|3000|4000|4200|4400|4600|5000)\\b"

static func normalize(pref: String) -> String:
	return pref if pref in VALUES else AUTO

# Linux only: the weak drivers are Mesa's. Windows runs d3d12 per project.godot.
static func is_weak_vulkan(adapter_name: String, os_name: String = "Linux") -> bool:
	if os_name != "Linux" and os_name != "FreeBSD" and os_name != "NetBSD" and os_name != "OpenBSD":
		return false
	var re := RegEx.new()
	re.compile(WEAK_ADAPTER_PATTERN)
	return re.search(adapter_name) != null

# The rendering method a pref resolves to on this hardware.
static func method_for(pref: String, adapter_name: String, os_name: String = "Linux") -> String:
	match normalize(pref):
		VULKAN: return METHOD_VULKAN
		OPENGL: return METHOD_OPENGL
	return METHOD_OPENGL if is_weak_vulkan(adapter_name, os_name) else METHOD_VULKAN

# override.cfg lives in the project folder when run from source and beside the executable when exported.
static func override_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://override.cfg")
	return OS.get_executable_path().get_base_dir().path_join("override.cfg")

# Makes override.cfg request `method` (Vulkan = no key, so the project default applies). Other keys in the file are
# kept; an emptied file is removed. Returns true if the file's content changed.
static func sync_override(method: String, path: String = "") -> bool:
	if path == "":
		path = override_path()
	var config := ConfigFile.new()
	config.load(path) # missing file is fine: starts empty
	var current = config.get_value("rendering", OVERRIDE_KEY, "")
	if method == METHOD_OPENGL:
		if current == METHOD_OPENGL:
			return false
		config.set_value("rendering", OVERRIDE_KEY, METHOD_OPENGL)
		config.save(path)
		return true
	if current == "":
		return false
	config.erase_section_key("rendering", OVERRIDE_KEY)
	if config.get_sections().is_empty():
		DirAccess.remove_absolute(path)
	else:
		config.save(path)
	return true

# Boot / Settings hook: resolve the pref for this GPU and bring override.cfg in line. Skipped headless (checks and
# benches pass their own --rendering-method and must not touch the file). Returns the method that will be used next
# launch ("" when skipped).
static func apply(pref: String) -> String:
	if DisplayServer.get_name() == "headless":
		return ""
	var method := method_for(pref, RenderingServer.get_video_adapter_name(), OS.get_name())
	sync_override(method)
	return method

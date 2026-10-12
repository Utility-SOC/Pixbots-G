extends Node

# RendererPref: weak-Vulkan detection, pref -> rendering method resolution, and override.cfg syncing (on a scratch file).

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	var ivb = "Intel(R) HD Graphics 4000 (IVB GT2)"
	_check("Ivy Bridge is weak on Linux", RendererPref.is_weak_vulkan(ivb, "Linux"))
	_check("Haswell is weak on Linux", RendererPref.is_weak_vulkan("Intel(R) HD Graphics 4600 (HSW GT2)", "Linux"))
	_check("Bay Trail is weak on Linux", RendererPref.is_weak_vulkan("Intel(R) HD Graphics (BYT)", "Linux"))
	_check("Skylake is not weak", not RendererPref.is_weak_vulkan("Intel(R) HD Graphics 530 (SKL GT2)", "Linux"))
	_check("Arc is not weak", not RendererPref.is_weak_vulkan("Intel(R) Arc(tm) A380 Graphics (DG2)", "Linux"))
	_check("NVIDIA is not weak", not RendererPref.is_weak_vulkan("NVIDIA GeForce GTX 1060", "Linux"))
	_check("Windows is never weak", not RendererPref.is_weak_vulkan(ivb, "Windows"))

	_check("auto + weak GPU -> opengl", RendererPref.method_for("auto", ivb) == "gl_compatibility")
	_check("auto + good GPU -> vulkan", RendererPref.method_for("auto", "NVIDIA GeForce GTX 1060") == "forward_plus")
	_check("vulkan pref wins on a weak GPU", RendererPref.method_for("vulkan", ivb) == "forward_plus")
	_check("opengl pref wins on a good GPU", RendererPref.method_for("opengl", "NVIDIA GeForce GTX 1060") == "gl_compatibility")
	_check("unknown pref falls back to auto", RendererPref.normalize("bogus") == "auto" and RendererPref.method_for("bogus", ivb) == "gl_compatibility")

	var path = "user://renderer_pref_check_override.cfg"
	DirAccess.remove_absolute(path)
	_check("vulkan on a missing file changes nothing", not RendererPref.sync_override("forward_plus", path) and not FileAccess.file_exists(path))
	_check("opengl writes the override", RendererPref.sync_override("gl_compatibility", path))
	var c = ConfigFile.new()
	c.load(path)
	_check("override holds gl_compatibility", c.get_value("rendering", "renderer/rendering_method", "") == "gl_compatibility")
	_check("writing it again is a no-op", not RendererPref.sync_override("gl_compatibility", path))
	c.set_value("display", "window/size/borderless", true)
	c.save(path)
	_check("vulkan removes the key", RendererPref.sync_override("forward_plus", path))
	c = ConfigFile.new()
	c.load(path)
	_check("other keys are kept", c.get_value("display", "window/size/borderless", false) == true and not c.has_section_key("rendering", "renderer/rendering_method"))
	c.erase_section("display")
	c.save(path)
	c.set_value("rendering", "renderer/rendering_method", "gl_compatibility")
	c.save(path)
	RendererPref.sync_override("forward_plus", path)
	_check("an emptied override file is removed", not FileAccess.file_exists(path))
	DirAccess.remove_absolute(path)

	_check("apply is skipped headless", DisplayServer.get_name() != "headless" or RendererPref.apply("opengl") == "")

	print("RendererPrefCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

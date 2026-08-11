extends SceneTree

# One-off tool (headless-safe: pure image/file I/O, no rendering needed):
# takes mech_icon_candidate.png (produced by RenderMechIconTool.gd) and
# builds:
#  - res://icon.ico - a real multi-resolution Windows icon (16/32/48/256px,
#    nearest-neighbor resized to keep the pixel art crisp instead of
#    blurring it the way GDI+'s default bicubic resize would), used by
#    export_presets.cfg's Windows Desktop preset for the actual .exe icon.
#  - res://icon.png - replaces icon.svg as the Godot project icon
#    (project.godot's config/icon), also updated by this script.
#
# ICO format: 6-byte ICONDIR header + one 16-byte ICONDIRENTRY per image,
# followed by the images themselves as raw PNG bytes each (the "PNG in
# ICO" format Windows Vista+ accepts for any listed size, not just 256px -
# avoids hand-rolling BMP/DIB encoding entirely).

const SOURCE_PATH = "res://mech_icon_candidate.png"
const ICO_OUTPUT_PATH = "res://icon.ico"
const PROJECT_ICON_OUTPUT_PATH = "res://icon.png"
const ICO_SIZES = [16, 32, 48, 256]

func _init():
	var src = Image.load_from_file(ProjectSettings.globalize_path(SOURCE_PATH))
	if src == null:
		push_error("Could not load " + SOURCE_PATH)
		quit(1)
		return
	src.convert(Image.FORMAT_RGBA8)

	var entries: Array = [] # [{size, png_bytes}]
	for size in ICO_SIZES:
		var resized = src.duplicate()
		resized.resize(size, size, Image.INTERPOLATE_NEAREST)
		entries.append({"size": size, "bytes": resized.save_png_to_buffer()})

	var ico_bytes = _build_ico(entries)
	var f = FileAccess.open(ICO_OUTPUT_PATH, FileAccess.WRITE)
	if not f:
		push_error("Could not open " + ICO_OUTPUT_PATH + " for writing")
		quit(1)
		return
	f.store_buffer(ico_bytes)
	f.close()
	print("Wrote " + ICO_OUTPUT_PATH + " (" + str(ico_bytes.size()) + " bytes, sizes " + str(ICO_SIZES) + ")")

	# Project icon: a modest, clean size (project icons don't need 512px).
	var proj_icon = src.duplicate()
	proj_icon.resize(128, 128, Image.INTERPOLATE_NEAREST)
	var err = proj_icon.save_png(PROJECT_ICON_OUTPUT_PATH)
	if err != OK:
		push_error("Failed to save " + PROJECT_ICON_OUTPUT_PATH + ": " + str(err))
		quit(1)
		return
	print("Wrote " + PROJECT_ICON_OUTPUT_PATH)

	quit(0)

func _build_ico(entries: Array) -> PackedByteArray:
	var out = PackedByteArray()
	# ICONDIR
	out.append_array(_u16le(0))       # reserved
	out.append_array(_u16le(1))       # type: 1 = icon
	out.append_array(_u16le(entries.size()))

	var header_size = 6 + 16 * entries.size()
	var offset = header_size
	# ICONDIRENTRY per image
	for e in entries:
		var dim = e.size if e.size < 256 else 0 # 0 means 256 per the spec
		out.append(dim)               # width
		out.append(dim)                # height
		out.append(0)                  # color count (0 = no palette)
		out.append(0)                  # reserved
		out.append_array(_u16le(1))    # color planes
		out.append_array(_u16le(32))   # bits per pixel
		out.append_array(_u32le(e.bytes.size()))
		out.append_array(_u32le(offset))
		offset += e.bytes.size()

	for e in entries:
		out.append_array(e.bytes)

	return out

func _u16le(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF])

func _u32le(v: int) -> PackedByteArray:
	return PackedByteArray([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF])

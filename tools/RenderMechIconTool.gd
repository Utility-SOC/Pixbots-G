extends Node

# One-off tool (not a regression check): renders the player's actual saved
# mech build through the real in-game MechRenderer and saves a PNG, for use
# as a candidate app icon. Reuses the exact rig-building approach
# ChampionCard._render_sprite_portrait() already proved out for the PvP
# trading-card feature (SubViewport + Camera2D + a throwaway Mech with the
# save's real components equipped onto it) - just at a higher resolution
# and writing straight to disk instead of embedding into a card PNG.
#
# MUST run non-headless (real GPU rendering required, see
# ChampionCard._render_sprite_portrait's own comment on RenderingServer.
# get_rendering_device() returning null under --headless).
#
# Two things the raw capture needs cleaning up, neither ever root-caused
# to a specific line of game code despite extensive isolation (removing
# GPUParticles2D, MechStatusBars, every Area2D/CollisionShape2D in the
# tree, disabling debug_collisions_hint): an unexplained pale-green ring
# around the mech, and vp.transparent_bg not actually producing real
# per-pixel alpha (background comes back solid opaque black instead) -
# ChampionCard's own card background is ALSO near-black, so this may be a
# pre-existing quirk in that proven code path too, just never visible
# there. Rather than keep chasing root cause, this detects both the flat
# background color and the ring's color by sampling/matching, crops
# tightly to whatever's left (the real mech pixels), and recomposites onto
# a clean chosen backdrop.

const MechScript = preload("res://scripts/entities/Mech.gd")

const OUTPUT_PATH = "user://mech_icon_candidate.png"
const SNAPSHOT_SIZE = 512
const FINAL_SIZE = 512
const PADDING_FRAC = 0.08
const BACKDROP_COLOR = Color(0.09, 0.09, 0.12, 1.0) # matches ChampionCard's own card background

func _ready():
	# Safety net: if anything above goes wrong in a way that doesn't reach
	# a quit() call, force-close after 15s instead of sitting open
	# indefinitely on the screen (happened once already - a parse error in
	# this same file left the window idling forever with nothing to run).
	get_tree().create_timer(15.0).timeout.connect(func():
		push_error("Safety timeout hit - something didn't reach quit(). Force-closing.")
		get_tree().quit(1)
	)

	if not RenderingServer.get_rendering_device():
		push_error("No real rendering device - must run this WITHOUT --headless.")
		get_tree().quit(1)
		return

	get_tree().debug_collisions_hint = false

	var save_path = "user://saves/autosave.json"
	if not FileAccess.file_exists(save_path):
		push_error("No autosave.json found at " + save_path)
		get_tree().quit(1)
		return
	var f = FileAccess.open(save_path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if not (data is Dictionary) or not data.has("components"):
		push_error("autosave.json has no 'components' field.")
		get_tree().quit(1)
		return

	var rig = MechScript.new()
	rig.is_player = false
	add_child(rig)

	for slot in rig.components.keys().duplicate():
		var old = rig.unequip_component(slot)
		if old:
			old.queue_free()

	for slot_str in data["components"]:
		var comp = SaveManager._deserialize_component(data["components"][slot_str])
		if comp:
			rig.equip_component(comp)
	rig._recalculate_grid()
	rig._renderer._rebuild_visuals()

	if rig.has_node("AIStateLabel_DEBUG"):
		rig.get_node("AIStateLabel_DEBUG").visible = false

	var vp = SubViewport.new()
	vp.size = Vector2i(SNAPSHOT_SIZE, SNAPSHOT_SIZE)
	vp.transparent_bg = true
	vp.world_2d = World2D.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)

	remove_child(rig)
	vp.add_child(rig)

	var cam = Camera2D.new()
	cam.zoom = Vector2(1.4, 1.4)
	rig.add_child(cam)
	cam.make_current()

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var vp_tex = vp.get_texture()
	var img = vp_tex.get_image() if vp_tex else null
	if img == null:
		push_error("Capture failed - no image came back from the viewport.")
		get_tree().quit(1)
		return

	var bg_sample = img.get_pixel(2, 2)
	print("Sampled background color: " + str(bg_sample))

	# Diagnostic: scan a horizontal line through the vertical center and
	# print distinct opaque colors, to get the ring's EXACT color instead
	# of guessing from eyeballing screenshots.
	var seen: Dictionary = {}
	for x in range(img.get_width()):
		var c = img.get_pixel(x, img.get_height() / 2)
		if c.a > 0.5:
			var key = "%.2f,%.2f,%.2f" % [c.r, c.g, c.b]
			seen[key] = seen.get(key, 0) + 1
	for key in seen:
		if seen[key] > 2:
			print("Color %s: %d px" % [key, seen[key]])

	var cropped = _crop_and_pad(img, bg_sample)
	if cropped == null:
		push_error("Nothing survived - can't auto-crop.")
		get_tree().quit(1)
		return

	var err = cropped.save_png(OUTPUT_PATH)
	if err != OK:
		push_error("Failed to save PNG: " + str(err))
		get_tree().quit(1)
		return

	print("Saved mech icon candidate to: " + ProjectSettings.globalize_path(OUTPUT_PATH))
	get_tree().quit(0)

const RING_COLOR = Color(0.13, 0.60, 0.33) # sampled directly from a real capture
static var RING_DIR: Vector3 = Vector3(0.13, 0.60, 0.33).normalized()
const RING_HUE_COS_THRESHOLD = 0.985 # how close a pixel's color direction must be to RING_DIR

func _is_excluded(c: Color, bg: Color) -> bool:
	var d_bg = sqrt(pow(c.r - bg.r, 2) + pow(c.g - bg.g, 2) + pow(c.b - bg.b, 2))
	if d_bg < 0.06:
		return true
	# The ring is a stroke over a pure-black background, so every anti-
	# aliased edge pixel is just RING_COLOR scaled toward black (same hue,
	# lower magnitude) - a direction/cosine check catches the whole
	# gradient, not just pixels close to the one exact sampled color.
	var v = Vector3(c.r, c.g, c.b)
	if v.length() > 0.03:
		var cos_sim = v.normalized().dot(RING_DIR)
		if cos_sim > RING_HUE_COS_THRESHOLD:
			return true
	return false

func _crop_and_pad(img: Image, bg: Color) -> Image:
	var w = img.get_width()
	var h = img.get_height()
	var min_x = w
	var min_y = h
	var max_x = -1
	var max_y = -1
	for y in range(h):
		for x in range(w):
			var c = img.get_pixel(x, y)
			if c.a > 0.05 and not _is_excluded(c, bg):
				min_x = min(min_x, x)
				min_y = min(min_y, y)
				max_x = max(max_x, x)
				max_y = max(max_y, y)
	if max_x < min_x:
		return null
	print("Content bounding box: (%d,%d) to (%d,%d)" % [min_x, min_y, max_x, max_y])

	var content_w = max_x - min_x + 1
	var content_h = max_y - min_y + 1
	var content = img.get_region(Rect2i(min_x, min_y, content_w, content_h))
	content = content.duplicate()
	for y in range(content_h):
		for x in range(content_w):
			var c = content.get_pixel(x, y)
			if _is_excluded(c, bg):
				content.set_pixel(x, y, Color(0, 0, 0, 0))

	var target_content_size = int(FINAL_SIZE * (1.0 - PADDING_FRAC * 2.0))
	var scale_factor = float(target_content_size) / float(max(content_w, content_h))
	var new_w = max(1, int(round(content_w * scale_factor)))
	var new_h = max(1, int(round(content_h * scale_factor)))
	content.resize(new_w, new_h, Image.INTERPOLATE_NEAREST)

	var final_img = Image.create(FINAL_SIZE, FINAL_SIZE, false, Image.FORMAT_RGBA8)
	final_img.fill(BACKDROP_COLOR)
	var offset_x = (FINAL_SIZE - new_w) / 2
	var offset_y = (FINAL_SIZE - new_h) / 2
	final_img.blend_rect(content, Rect2i(Vector2i.ZERO, Vector2i(new_w, new_h)), Vector2i(offset_x, offset_y))
	return final_img

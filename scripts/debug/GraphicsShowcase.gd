extends Node

# Graphics showcase fixture: walk through everything visual that was added, in the real renderer.
#   godot --path . res://scripts/debug/GraphicsShowcase.tscn
# Tab switches between MAPS, PIECES and SHOP.
#   MAPS    a real generated map you can fly over: Left/Right map type (classic, Hilly/Mountains, all the Hyper twins), Up/Down war era
#           (prewar / skirmish / no man's land / apocalypse), R new seed, WASD or arrows pan, mouse wheel or Q/E zoom, F fit the whole
#           map, C jump to the player start. Weather (sandstorms, blizzards), hazards, heights and decor are all live.
#   PIECES  the whole set-piece library as a gallery at the chosen era: Up/Down era, PageUp/PageDown page, Left/Right theme filter.
#   SHOP    the three game-shop backdrops: Left/Right to cycle.
# Esc quits.

const MapGen = preload("res://scripts/core/MapGenerator.gd")
const MODES = ["MAPS", "PIECES", "SHOP"]

var mode: int = 0
var era_index: int = 0
var type_index: int = 0
var seed_value: int = 2026
var map = null
var cam: Camera2D
var hud: Label
var gallery: Node2D
var shop_rect: TextureRect
var shop_index: int = 0
var piece_page: int = 0
var theme_index: int = -1 # -1 = all
var _types: Array = []
var _busy: bool = false

func _ready():
	_types = MapTypes.classic_names() + ["Tundra", "Desert", "Forest", "Volcano", "Tabletop", "FightShovel", "Dungeon"]
	var named = MapTypes.names()
	_types = named # classic MapTypes, then their Hyper twins
	for t in ["Tabletop", "FightShovel", "Dungeon", "Tundra", "Desert", "Forest", "Volcano", "Normal"]:
		_types.append(t)
	cam = Camera2D.new()
	cam.zoom = Vector2(0.25, 0.25)
	add_child(cam)
	var layer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	hud = Label.new()
	hud.position = Vector2(12, 8)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_constant_override("outline_size", 5)
	hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	layer.add_child(hud)
	gallery = PieceGallery.new()
	gallery.owner_ref = self
	gallery.visible = false
	add_child(gallery)
	shop_rect = TextureRect.new()
	shop_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	shop_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shop_rect.visible = false
	layer.add_child(shop_rect)
	_set_mode(0)

func _set_mode(m: int) -> void:
	mode = m
	gallery.visible = mode == 1
	shop_rect.visible = mode == 2
	if map != null and is_instance_valid(map):
		map.visible = mode == 0
	cam.enabled = mode == 0
	if mode == 0 and map == null:
		_generate()
	if mode == 1:
		gallery.queue_redraw()
	if mode == 2:
		shop_rect.texture = ShopBackdrop.make(ShopBackdrop.KINDS[shop_index])
	_update_hud()

func _generate() -> void:
	if _busy:
		return
	_busy = true
	hud.text = "Generating %s (%s) ..." % [_types[type_index], MapTypes.ERAS[era_index]]
	await get_tree().process_frame
	if map != null and is_instance_valid(map):
		map.queue_free()
		await get_tree().process_frame
	map = MapGen.new()
	map.map_type = _types[type_index]
	map.era_override = MapTypes.ERAS[era_index] if MapTypes.has(_types[type_index]) else ""
	map.map_seed = seed_value
	add_child(map)
	await get_tree().process_frame
	_fit()
	_busy = false
	_update_hud()

func _fit() -> void:
	if map == null:
		return
	var size_px = Vector2(map.width, map.height) * map.tile_size
	cam.position = size_px / 2.0
	var vp = get_viewport().get_visible_rect().size
	var z = minf(vp.x / size_px.x, vp.y / size_px.y) * 0.95
	cam.zoom = Vector2(z, z)

func _update_hud() -> void:
	var keys = "[Tab] mode  [Esc] quit"
	match mode:
		0:
			var info = ""
			if map != null and is_instance_valid(map):
				info = "%dx%d  pieces %d  decor %d  zones %d  heights %s  era %s" % [map.width, map.height, map.ruin_specs.size(), map.decor.size(), map.zones.size(), str(map.has_heights), map.era if map.era != "" else "-"]
			hud.text = "MAPS  %s  [%d/%d]   era: %s\n%s\n[Left/Right] type  [Up/Down] era  [R] new seed  [WASD] pan  [wheel/Q/E] zoom  [F] fit  [C] player start   %s" % [_types[type_index], type_index + 1, _types.size(), MapTypes.ERAS[era_index], info, keys]
		1:
			hud.text = "PIECES  era: %s  theme: %s  page %d\n[Up/Down] era  [Left/Right] theme  [PgUp/PgDn] page   %s" % [MapTypes.ERAS[era_index], "all" if theme_index < 0 else _themes()[theme_index], piece_page + 1, keys]
		2:
			hud.text = "SHOP  %s\n[Left/Right] backdrop   %s" % [ShopBackdrop.KINDS[shop_index], keys]

func _themes() -> Array:
	var t := {}
	for n in SetPieces.PIECES:
		t[SetPieces.PIECES[n]["theme"]] = true
	var out = t.keys()
	out.sort()
	return out

func piece_names() -> Array:
	var out: Array = []
	var themes = _themes()
	for n in SetPieces.PIECES:
		if theme_index < 0 or SetPieces.PIECES[n]["theme"] == themes[theme_index]:
			out.append(n)
	out.sort_custom(func(a, b): return SetPieces.PIECES[a]["theme"] + a < SetPieces.PIECES[b]["theme"] + b)
	return out

func _process(delta: float) -> void:
	if mode != 0 or _busy:
		return
	var v = Vector2.ZERO
	if Input.is_key_pressed(KEY_A): v.x -= 1
	if Input.is_key_pressed(KEY_D): v.x += 1
	if Input.is_key_pressed(KEY_W): v.y -= 1
	if Input.is_key_pressed(KEY_S): v.y += 1
	if v != Vector2.ZERO:
		cam.position += v.normalized() * 1500.0 / cam.zoom.x * delta
	var z = 0.0
	if Input.is_key_pressed(KEY_Q): z -= 1
	if Input.is_key_pressed(KEY_E): z += 1
	if z != 0.0:
		var nz = clampf(cam.zoom.x * (1.0 + z * 1.2 * delta), 0.03, 2.5)
		cam.zoom = Vector2(nz, nz)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and mode == 0:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom = Vector2.ONE * clampf(cam.zoom.x * 1.15, 0.03, 2.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom = Vector2.ONE * clampf(cam.zoom.x / 1.15, 0.03, 2.5)
	if not (event is InputEvent and event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_ESCAPE: get_tree().quit()
		KEY_TAB: _set_mode((mode + 1) % MODES.size())
		KEY_F: if mode == 0: _fit()
		KEY_C:
			if mode == 0 and map != null:
				cam.position = Vector2(map.width, map.height) * map.tile_size / 2.0
				cam.zoom = Vector2(0.8, 0.8)
		KEY_R:
			if mode == 0:
				seed_value += 1
				_generate()
		KEY_LEFT: _step(-1)
		KEY_RIGHT: _step(1)
		KEY_UP: _era(-1)
		KEY_DOWN: _era(1)
		KEY_PAGEUP: if mode == 1: piece_page = maxi(0, piece_page - 1); gallery.queue_redraw(); _update_hud()
		KEY_PAGEDOWN: if mode == 1: piece_page += 1; gallery.queue_redraw(); _update_hud()

func _step(d: int) -> void:
	match mode:
		0:
			type_index = posmod(type_index + d, _types.size())
			_generate()
		1:
			theme_index = clampi(theme_index + d, -1, _themes().size() - 1)
			piece_page = 0
			gallery.queue_redraw()
			_update_hud()
		2:
			shop_index = posmod(shop_index + d, ShopBackdrop.KINDS.size())
			shop_rect.texture = ShopBackdrop.make(ShopBackdrop.KINDS[shop_index])
			_update_hud()

func _era(d: int) -> void:
	era_index = posmod(era_index + d, MapTypes.ERAS.size())
	if mode == 0:
		_generate()
	elif mode == 1:
		gallery.queue_redraw()
		_update_hud()

# The set-piece gallery: every catalogued piece drawn at its middle size in the chosen era, with its name and theme.
class PieceGallery extends Node2D:
	var owner_ref
	const CELL = Vector2(190, 150)
	func _draw():
		if owner_ref == null:
			return
		var vp = get_viewport().get_visible_rect().size
		draw_rect(Rect2(Vector2.ZERO, vp), Color(0.22, 0.27, 0.2))
		var names: Array = owner_ref.piece_names()
		var cols = maxi(1, int(vp.x / CELL.x))
		var rows = maxi(1, int((vp.y - 70.0) / CELL.y))
		var per_page = cols * rows
		var pages = maxi(1, int(ceil(float(names.size()) / float(per_page))))
		owner_ref.piece_page = clampi(owner_ref.piece_page, 0, pages - 1)
		var font = ThemeDB.fallback_font
		var era = MapTypes.ERAS[owner_ref.era_index]
		for i in range(per_page):
			var idx = owner_ref.piece_page * per_page + i
			if idx >= names.size():
				break
			var n: String = names[idx]
			var p: Dictionary = SetPieces.PIECES[n]
			var tiles = Vector2(int((p["min"][0] + p["max"][0]) / 2), int((p["min"][1] + p["max"][1]) / 2))
			var fp = tiles * 32.0
			var style = SetPieces.evolved(n, era)
			var rects = SetPieceEra.apply(SetPieceArt.rects(style, fp, 777), fp, era, 5)
			var origin = Vector2(float(i % cols) * CELL.x + 10.0, 70.0 + float(i / cols) * CELL.y)
			var sc = minf((CELL.x - 20.0) / fp.x, (CELL.y - 34.0) / fp.y)
			sc = minf(sc, 1.6)
			for r in rects:
				draw_rect(Rect2(origin + r[0].position * sc, r[0].size * sc), r[1])
			draw_string(font, origin + Vector2(0, CELL.y - 20.0), "%s%s" % [n, (" -> " + style) if style != n else ""], HORIZONTAL_ALIGNMENT_LEFT, CELL.x - 12.0, 13, Color.WHITE)
			draw_string(font, origin + Vector2(0, CELL.y - 6.0), "%s  %dx%d" % [p["theme"], int(tiles.x), int(tiles.y)], HORIZONTAL_ALIGNMENT_LEFT, CELL.x - 12.0, 11, Color(0.75, 0.85, 0.75))
		draw_string(font, Vector2(12, vp.y - 8.0), "page %d / %d   (%d pieces)" % [owner_ref.piece_page + 1, pages, names.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

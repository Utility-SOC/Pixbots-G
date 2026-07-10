extends CanvasLayer

# Minimap overlay (FEATURE_ROADMAP.md group 1).
#   U           - show/hide
#   drag        - move it anywhere on screen
#   mouse wheel - zoom (from whole-map overview down to local tactical view)
#   drag the bottom-right grip - resize the panel
#
# The biome background is baked from MapGenerator.terrain at 1px per tile
# (400x250 = tiny), rebaked periodically so debug-menu map swaps show up.
# Entity dots redraw at a throttled 12Hz while visible (see REDRAW_HZ
# below) - full 60Hz precision is imperceptible at minimap scale: player
# (white), enemies (red), loot (gold), extraction marker (green, pulsing).

var view: MinimapView

# Entity dots (player/enemies/loot/extraction marker) don't need 60Hz
# precision to read well on a 220x150 panel - a dot drifting a few px
# between repaints is imperceptible. Redrawing every single frame was pure
# waste (plus a redundant get_nodes_in_group("loot"/"enemy") scan per
# frame, on top of whatever else in the game already walks those groups).
# 12Hz keeps it visually smooth while cutting that cost by ~80%.
const REDRAW_HZ = 12.0
var _redraw_timer: float = 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 6 # above the HUD (5), below debug menu (100) / war room (99)

	view = MinimapView.new()
	view.position = Vector2(get_viewport().get_visible_rect().size.x - 250, 60)
	view.size = Vector2(220, 150)
	view.clip_contents = true
	add_child(view)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_U:
			view.visible = not view.visible
			if view.visible:
				view.bake_map()
				view.queue_redraw() # repaint immediately on open, don't wait for the throttle

func _process(delta):
	if not view.visible:
		return
	_redraw_timer -= delta
	if _redraw_timer <= 0.0:
		_redraw_timer = 1.0 / REDRAW_HZ
		view.queue_redraw()

class MinimapView:
	extends Control

	const GRIP = 14.0          # px hot-zone in the bottom-right corner for resizing
	const MIN_SIZE = Vector2(120, 90)
	const MAX_SIZE = Vector2(600, 450)

	var map_tex: ImageTexture = null
	var _baked_map_instance_id: int = 0
	var _rebake_timer: float = 0.0

	var zoom: float = 0.0      # px per world unit; 0 = "fit whole map", set on first draw
	var _dragging := false
	var _resizing := false
	var _drag_offset := Vector2.ZERO

	func _get_map() -> Node:
		var maps = get_tree().get_nodes_in_group("map_generator")
		return maps[0] if maps.size() > 0 else null

	func _get_player() -> Node:
		var players = get_tree().get_nodes_in_group("player")
		return players[0] if players.size() > 0 else null

	func _fit_zoom(map) -> float:
		var world_size = Vector2(map.width, map.height) * map.tile_size
		return min(size.x / world_size.x, size.y / world_size.y)

	func bake_map():
		var map = _get_map()
		if not map or map.terrain.is_empty():
			return
		var img = Image.create(map.width, map.height, false, Image.FORMAT_RGBA8)
		for y in range(map.height):
			var row = map.terrain[y]
			for x in range(map.width):
				img.set_pixel(x, y, map._get_biome_color(row[x]))
		# Obstacles as darker specks so forests/ruins read as cover, not empty ground
		for pos in map.obstacles:
			if pos.x >= 0 and pos.y >= 0 and pos.x < map.width and pos.y < map.height:
				img.set_pixel(pos.x, pos.y, img.get_pixel(pos.x, pos.y).darkened(0.45))
		map_tex = ImageTexture.create_from_image(img)
		_baked_map_instance_id = map.get_instance_id()

	func _process(delta):
		if not visible:
			return
		# Rebake if the map node changed or periodically (debug-menu map
		# regeneration reuses the same node, so a timer is the cheap way to
		# catch biome swaps without MapGenerator needing a signal).
		_rebake_timer -= delta
		var map = _get_map()
		if map and (map.get_instance_id() != _baked_map_instance_id or _rebake_timer <= 0.0):
			bake_map()
			_rebake_timer = 5.0

	func _world_to_px(world: Vector2, center: Vector2) -> Vector2:
		return (world - center) * zoom + size / 2.0

	func _draw():
		var map = _get_map()
		var player = _get_player()

		# Frame + backdrop
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.08, 0.85))

		if map and map_tex and player and is_instance_valid(player):
			if zoom <= 0.0:
				zoom = _fit_zoom(map)
			var min_zoom = _fit_zoom(map)
			zoom = clamp(zoom, min_zoom, 0.15)

			# Keep the view centered on the player, clamped so we don't pan
			# past the map edges once zoomed in.
			var world_size = Vector2(map.width, map.height) * map.tile_size
			var view_world = size / zoom
			var center = player.global_position
			center.x = clamp(center.x, min(view_world.x / 2.0, world_size.x / 2.0), max(world_size.x - view_world.x / 2.0, world_size.x / 2.0))
			center.y = clamp(center.y, min(view_world.y / 2.0, world_size.y / 2.0), max(world_size.y - view_world.y / 2.0, world_size.y / 2.0))

			# Map background: 1 texture pixel = 1 tile = tile_size world units
			var src = Rect2(
				(center - view_world / 2.0) / map.tile_size,
				view_world / map.tile_size
			)
			draw_texture_rect_region(map_tex, Rect2(Vector2.ZERO, size), src)

			# --- Jammer fields (drawn before entity dots so dots stay
			# legible on top) - the actual organic blob boundary, not a
			# plain circle, distinctly colored player-blue vs. enemy-red.
			# Shows every active field unconditionally, matching the
			# no-fog-of-war precedent the enemy dots below already set.
			for field in EntityCache.get_group("jammer_field"):
				if not is_instance_valid(field):
					continue
				var col = Color(0.3, 0.6, 1.0, 0.35) if field.owner_is_player else Color(0.85, 0.25, 0.3, 0.35)
				var pts := PackedVector2Array()
				for local_pt in field.boundary_points:
					pts.append(_world_to_px(field.global_position + local_pt, center))
				if pts.size() >= 3:
					draw_colored_polygon(pts, col)
					draw_polyline(pts + PackedVector2Array([pts[0]]), col.lightened(0.35), 1.5, true)

			# --- Entity dots ---
			for loot in EntityCache.get_group("loot"):
				if is_instance_valid(loot):
					draw_circle(_world_to_px(loot.global_position, center), 2.0, Color(1.0, 0.85, 0.2))

			for enemy in EntityCache.get_group("enemy"):
				if is_instance_valid(enemy):
					draw_circle(_world_to_px(enemy.global_position, center), 3.0, Color(1.0, 0.25, 0.2))

			var main = get_tree().current_scene
			if main and main.get("extraction_marker") != null and is_instance_valid(main.extraction_marker):
				var pulse = 3.0 + sin(Time.get_ticks_msec() / 150.0) * 1.5
				draw_circle(_world_to_px(main.extraction_marker.global_position, center), pulse, Color(0.3, 1.0, 0.4))

			draw_circle(_world_to_px(player.global_position, center), 4.0, Color.WHITE)
		else:
			draw_string(ThemeDB.fallback_font, Vector2(10, size.y / 2.0), "No map data", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.6, 0.6))

		# Border + resize grip
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.4, 0.45, 0.5, 0.9), false, 1.5)
		var g = size - Vector2(GRIP, GRIP)
		draw_line(g + Vector2(GRIP * 0.3, GRIP), g + Vector2(GRIP, GRIP * 0.3), Color(0.6, 0.65, 0.7), 1.5)
		draw_line(g + Vector2(GRIP * 0.65, GRIP), g + Vector2(GRIP, GRIP * 0.65), Color(0.6, 0.65, 0.7), 1.5)

	func _gui_input(event):
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				zoom *= 1.25
				accept_event()
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				zoom /= 1.25
				accept_event()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					if event.position.x > size.x - GRIP and event.position.y > size.y - GRIP:
						_resizing = true
					else:
						_dragging = true
						_drag_offset = event.position
				else:
					_dragging = false
					_resizing = false
				accept_event()
		elif event is InputEventMouseMotion:
			if _resizing:
				size = clamp(size + event.relative, MIN_SIZE, MAX_SIZE)
				queue_redraw() # keep the border/backdrop snappy despite the throttled passive redraw
				accept_event()
			elif _dragging:
				position += event.relative
				accept_event()

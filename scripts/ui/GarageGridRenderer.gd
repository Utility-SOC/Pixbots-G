class_name GarageGridRenderer
extends Control

const HexCoord = preload("res://scripts/core/HexCoord.gd")
const HexTile = preload("res://scripts/core/HexTile.gd")
const EnergyPacket = preload("res://scripts/core/EnergyPacket.gd")
const ComponentEquipment = preload("res://scripts/core/ComponentEquipment.gd")

var hex_size: float = 40.0
var camera_offset: Vector2 = Vector2.ZERO
var zoom: float = 1.0

var hex_grid: Node # HexGridComponent
var show_static_paths: bool = true
var time_elapsed: float = 0.0
var menu_parent: Node # GarageMenu
var active_component: ComponentEquipment

var hovered_hex: HexCoord = null
var is_panning: bool = false
var pan_start_pos: Vector2 = Vector2.ZERO
var camera_start_pos: Vector2 = Vector2.ZERO

var active_packets: Array[EnergyPacket] = []
var simulation_step: int = 0
var tooltip_label: Label
var stats_label: Label

# Colors
const COLOR_BG = Color(0.1, 0.1, 0.15)
const COLOR_GRID = Color(0.2, 0.2, 0.25)
const COLOR_HOVER = Color(0.8, 0.8, 0.4, 0.5)

signal tooltip_requested(tile, position)
signal tooltip_cleared()
signal tile_clicked(tile)

func _ready():
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Create Tooltip
	tooltip_label = Label.new()
	tooltip_label.add_theme_stylebox_override("normal", _create_panel_style(Color(0.1, 0.1, 0.1, 0.9)))
	tooltip_label.hide()
	add_child(tooltip_label)
	
	resized.connect(func():
		if camera_offset == Vector2.ZERO:
			camera_offset = size / 2.0
	)

func setup(grid_component: Node, parent_menu: Node):
	hex_grid = grid_component
	menu_parent = parent_menu
	camera_offset = size / 2.0 # Center

func _process(delta):
	time_elapsed += delta
	# Interpolate active packets for smooth animation
	for pkt in active_packets:
		if pkt.has_meta("anim_progress"):
			var progress = pkt.get_meta("anim_progress")
			if progress < 1.0:
				progress += 2.0 * delta # _simulate_step takes 0.5s, so 2.0x makes it finish right on time
				pkt.set_meta("anim_progress", min(progress, 1.0))
	queue_redraw()

func _gui_input(event: InputEvent):
	if event is InputEventMouseMotion:
		var old_hover = hovered_hex
		hovered_hex = _pixel_to_hex(event.position)
		
		if hovered_hex != old_hover:
			if hovered_hex and hex_grid and hex_grid.has_tile(hovered_hex):
				tooltip_requested.emit(hex_grid.get_tile(hovered_hex), event.global_position)
			else:
				tooltip_cleared.emit()
			queue_redraw()
			
		if is_panning:
			camera_offset = camera_start_pos + (event.position - pan_start_pos)
			queue_redraw()
			
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_panning = true
				pan_start_pos = event.position
				camera_start_pos = camera_offset
			else:
				is_panning = false
		
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(1.1, event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(0.9, event.position)
			
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if hovered_hex and hex_grid and hex_grid.has_tile(hovered_hex):
					var tile = hex_grid.get_tile(hovered_hex)
					tile_clicked.emit(tile)
				else:
					is_panning = true
					pan_start_pos = event.position
					camera_start_pos = camera_offset
			else:
				is_panning = false
					
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				is_panning = true
				pan_start_pos = event.position
				camera_start_pos = camera_offset
			else:
				is_panning = false
				if event.position.distance_to(pan_start_pos) < 5.0:
					# Remove tile
					if hovered_hex and hex_grid and hex_grid.has_tile(hovered_hex):
						var tile = hex_grid.get_tile(hovered_hex)
						if active_component and active_component.slot_type == load("res://scripts/core/HexTile.gd").BodySlot.TORSO and hovered_hex.q == 0 and hovered_hex.r == 0:
							print("Cannot remove Core!")
						else:
							hex_grid.remove_tile(hovered_hex)
							menu_parent._add_to_inventory(tile)
							tooltip_cleared.emit()
							queue_redraw()
				
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_E:
			if hovered_hex and hex_grid and hex_grid.has_tile(hovered_hex):
				var tile = hex_grid.get_tile(hovered_hex)
				if tile.has_method("rotate"):
					tile.rotate(true) # Clockwise
					queue_redraw()
					if hovered_hex and hex_grid and hex_grid.has_tile(hovered_hex):
						tooltip_requested.emit(hex_grid.get_tile(hovered_hex), get_global_mouse_position())

func _zoom(factor: float, mouse_pos: Vector2):
	var old_zoom = zoom
	zoom = clamp(zoom * factor, 0.5, 3.0)
	var real_factor = zoom / old_zoom
	camera_offset = mouse_pos + (camera_offset - mouse_pos) * real_factor
	queue_redraw()

func _draw():
	if not hex_grid: return
	
	# Draw background
		# draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG) # Removed to allow mostly transparent background
	
	var valid_coords = []
	if active_component:
		valid_coords = active_component.valid_hexes
	else:
		# Fallback if somehow no active component
		for q in range(3):
			for r in range(3):
				valid_coords.append(HexCoord.new(q, r))
				
	# 0. Draw procedural outline behind grid
	for coord in valid_coords:
		_draw_hex_filled_scaled(coord, Color(0.2, 0.3, 0.4, 0.3), 1.15)
				
	# 1. Draw empty grid slots with hatching
	for coord in valid_coords:
		_draw_hex_hatched(coord, Color(0.1, 0.1, 0.1, 0.6))
		_draw_hex_outline(coord, COLOR_GRID, 1.0)
		
	# 2. Draw actual tiles
	var tiles = hex_grid.get_all_tiles()
	for tile in tiles:
		_draw_tile(tile)
		
	# 3. Draw hover highlight
	if hovered_hex and hovered_hex in valid_coords:
		_draw_hex_filled(hovered_hex, COLOR_HOVER)
		
	# 4. Draw Simulation Packets
	for pkt in active_packets:
		_draw_packet(pkt)

func _draw_tile(tile: HexTile):
	if not tile.grid_position: return
	
	# Dark solid base instead of base_color
	_draw_hex_filled(tile.grid_position, Color(0.15, 0.15, 0.15, 0.95))
	
	# Rarity Outline
	var rarity_color = Color.WHITE
	match tile.rarity:
		HexTile.Rarity.COMMON: rarity_color = Color(0.5, 0.5, 0.5)
		HexTile.Rarity.UNCOMMON: rarity_color = Color(0.4, 0.8, 1.0)
		HexTile.Rarity.RARE: rarity_color = Color(0.4, 1.0, 0.4)
		HexTile.Rarity.LEGENDARY: rarity_color = Color(1.0, 0.5, 0.0)
	
	_draw_hex_outline(tile.grid_position, rarity_color, 2.0)
	
	var center = _hex_to_pixel(tile.grid_position)
	
	_draw_descriptive_icon(tile, center)
	
	if show_static_paths:
		_draw_static_paths(tile, center)

func _draw_arrow(center: Vector2, direction: int, color: Color):
	var angle = direction * (PI / 3.0)
	var arrow_len = hex_size * zoom * 0.7
	var end_pt = center + Vector2(cos(angle), sin(angle)) * arrow_len
	draw_line(center, end_pt, color, 2.0, true)
	draw_circle(end_pt, 3.0, color)

func _draw_packet(packet: EnergyPacket):
	var source_hex = packet.get_meta("source_hex")
	var target_hex = packet.get_meta("target_hex")
	var progress = packet.get_meta("anim_progress", 1.0)
	
	if typeof(source_hex) == TYPE_NIL:
		source_hex = packet.position
	if typeof(target_hex) == TYPE_NIL:
		target_hex = packet.position
		
	var source_px = _hex_to_pixel(source_hex)
	var target_px = _hex_to_pixel(target_hex)
	
	var pos = source_px.lerp(target_px, progress)
		
	var dominant = packet.get_dominant_synergy()
	var color = Color(1, 1, 1)
	if dominant != EnergyPacket.SynergyType.RAW:
		color = Color(1, 0.5, 0.5) # simplify for now
		
	var scale = 1.0
	if not packet.is_active:
		# If it's being consumed, calculate its progress towards the sink
		if progress > 0.0:
			var visual_prog = progress
			scale = 1.0 - visual_prog
			color = color.lerp(Color(0.2, 1.0, 0.2), visual_prog)
		
	# Outer glow
	draw_circle(pos, 15.0 * zoom * scale, color * Color(1,1,1,0.3))
	# Core
	draw_circle(pos, 8.0 * zoom * scale, color)
	
	if scale > 0.2:
		var font = ThemeDB.fallback_font
		draw_string(font, pos + Vector2(-10, 20), str(int(packet.magnitude)), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)

func _hex_to_pixel(hex: HexCoord) -> Vector2:
	var x = hex_size * sqrt(3.0) * (hex.q + hex.r / 2.0)
	var y = hex_size * 3.0 / 2.0 * hex.r
	return Vector2(x, y) * zoom + camera_offset

func _pixel_to_hex(pos: Vector2) -> HexCoord:
	var pt = (pos - camera_offset) / zoom
	var q = (sqrt(3.0) / 3.0 * pt.x - 1.0 / 3.0 * pt.y) / hex_size
	var r = (2.0 / 3.0 * pt.y) / hex_size
	return _hex_round(q, r, -q - r)

func _hex_round(frac_q: float, frac_r: float, frac_s: float) -> HexCoord:
	var q = int(round(frac_q))
	var r = int(round(frac_r))
	var s = int(round(frac_s))
	var q_diff = abs(q - frac_q)
	var r_diff = abs(r - frac_r)
	var s_diff = abs(s - frac_s)
	if q_diff > r_diff and q_diff > s_diff:
		q = -r - s
	elif r_diff > s_diff:
		r = -q - s
	return HexCoord.new(q, r)

func _draw_hex_outline(coord: HexCoord, color: Color, width: float = 1.0):
	var center = _hex_to_pixel(coord)
	var pts = PackedVector2Array()
	for i in range(6):
		var angle = deg_to_rad(60 * i - 30)
		pts.append(center + Vector2(cos(angle), sin(angle)) * hex_size * zoom)
	pts.append(pts[0])
	draw_polyline(pts, color, width, true)

func _draw_hex_filled(coord: HexCoord, color: Color):
	var center = _hex_to_pixel(coord)
	var pts = PackedVector2Array()
	for i in range(6):
		var angle = deg_to_rad(60 * i - 30)
		pts.append(center + Vector2(cos(angle), sin(angle)) * hex_size * zoom)
	draw_polygon(pts, PackedColorArray([color, color, color, color, color, color]))

func _draw_hex_filled_scaled(coord: HexCoord, color: Color, scale: float):
	var center = _hex_to_pixel(coord)
	var pts = PackedVector2Array()
	for i in range(6):
		var angle = deg_to_rad(60 * i - 30)
		pts.append(center + Vector2(cos(angle), sin(angle)) * hex_size * zoom * scale)
	draw_polygon(pts, PackedColorArray([color, color, color, color, color, color]))

func _create_panel_style(color: Color) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _draw_hex_hatched(coord: HexCoord, color: Color):
	var center = _hex_to_pixel(coord)
	var r = hex_size * zoom
	# Draw a few diagonal lines
	for i in range(-2, 3):
		var offset = i * (r * 0.3)
		var p1 = center + Vector2(-r, -r + offset)
		var p2 = center + Vector2(r, r + offset)
		# Clip to hex approx
		if p1.distance_to(center) < r * 1.5 and p2.distance_to(center) < r * 1.5:
			draw_line(p1, p2, color, 2.0, true)

func _get_synergy_color(syn: int) -> Color:
	match syn:
		1: return Color(1.0, 0.2, 0.2) # FIRE
		2: return Color(0.2, 0.5, 1.0) # ICE
		3: return Color(0.9, 0.9, 0.2) # LIGHTNING
		4: return Color(0.8, 0.2, 0.8) # VORTEX
		5: return Color(0.2, 0.8, 0.2) # POISON
		6: return Color(1.0, 0.6, 0.2) # EXPLOSION
		7: return Color(0.8, 0.8, 0.8) # KINETIC
		8: return Color(0.4, 0.9, 0.9) # PIERCE
		9: return Color(0.9, 0.1, 0.3) # VAMPIRIC
		_: return Color(1.0, 0.2, 0.2) # RAW / Default

func _draw_descriptive_icon(tile: HexTile, center: Vector2):
	var type = tile.tile_type
	var base = Color(1.0, 0.7, 0.1, 0.9) # Distinctive amber
	
	var hs = hex_size * zoom
	
	if type == "Core Reactor":
		draw_circle(center, hs * 0.4, base)
		draw_circle(center, hs * 0.2, Color(1.0, 0.85, 0.4))
		var active = range(6)
		if "active_faces" in tile:
			active = tile.active_faces
		for i in active:
			var angle = deg_to_rad(60 * i)
			draw_line(center, center + Vector2(cos(angle), sin(angle)) * hs * 0.6, base, 3.0, true)
			
	elif type == "Splitter":
		var default_travel_dir = 3
		var entry_face = (default_travel_dir + 3) % 6
		if tile.has_method("get_exit_directions"):
			var exits = tile.get_exit_directions(entry_face)
			for ex in exits:
				var angle = ex * (PI / 3.0)
				draw_line(center, center + Vector2(cos(angle), sin(angle)) * hs * 0.7, base, 4.0, true)
				draw_circle(center + Vector2(cos(angle), sin(angle)) * hs * 0.7, 4.0, base)
			draw_circle(center, hs * 0.2, base)
			
	elif type == "Amplifier":
		var w = hs * 0.4
		draw_line(center - Vector2(w, 0), center + Vector2(w, 0), base, 4.0, true)
		draw_line(center - Vector2(0, w), center + Vector2(0, w), base, 4.0, true)
	elif type == "Weapon Mount":
		var synergies = {}
		var total_power = 0.0
		if "pending_packets" in tile and tile.pending_packets.size() > 0:
			var pkt = tile.pending_packets[0].packet
			synergies = pkt.synergies.duplicate()
		
		if synergies.is_empty():
			synergies[0] = 1.0 # RAW
			total_power = 1.0
		else:
			for k in synergies:
				total_power += synergies[k]
				
		# Determine dominant synergy for shape
		var dominant_syn = 0
		var max_p = -1.0
		for k in synergies:
			if synergies[k] > max_p:
				max_p = synergies[k]
				dominant_syn = k
				
		# Color cycling based on ratios
		var cycle_time = fmod(time_elapsed * 0.5, 1.0) # 2 seconds per full cycle
		var current_color = Color.WHITE
		var accum = 0.0
		for k in synergies:
			var ratio = synergies[k] / total_power
			if cycle_time >= accum and cycle_time <= accum + ratio:
				current_color = _get_synergy_color(k)
				break
			accum += ratio
			
		# Fallback if precision error
		if current_color == Color.WHITE:
			current_color = _get_synergy_color(dominant_syn)
			
		var throb = (sin(time_elapsed * 5.0) + 1.0) * 0.5
		var radius = hs * 0.4 + (throb * hs * 0.2)
		
		# Hatched background
		_draw_hex_hatched(tile.grid_position, current_color * Color(1,1,1,0.5))
		
		# Draw outer glow
		draw_circle(center, radius, current_color * Color(1,1,1,0.4))
		
		# Draw the procedural shape based on dominant synergy
		var p_scale = (0.5 + throb * 0.5) * hs * 0.05
		var pts = PackedVector2Array()
		
		if dominant_syn == 7: # KINETIC
			pts.append(center + Vector2(10, 0) * p_scale)
			pts.append(center + Vector2(-5, 5) * p_scale)
			pts.append(center + Vector2(-2, 0) * p_scale)
			pts.append(center + Vector2(-5, -5) * p_scale)
		elif dominant_syn == 2: # ICE
			pts.append(center + Vector2(12, 0) * p_scale)
			pts.append(center + Vector2(0, 6) * p_scale)
			pts.append(center + Vector2(-8, 3) * p_scale)
			pts.append(center + Vector2(-4, 0) * p_scale)
			pts.append(center + Vector2(-8, -3) * p_scale)
			pts.append(center + Vector2(0, -6) * p_scale)
		elif dominant_syn == 1: # FIRE
			for i in range(16):
				var a = i * PI / 8.0
				pts.append(center + Vector2(cos(a), sin(a)) * 6.0 * p_scale)
		else:
			# Default (RAW/Others) - Hexagon or square
			for i in range(4):
				var a = i * PI / 2.0 + PI/4.0
				pts.append(center + Vector2(cos(a), sin(a)) * 8.0 * p_scale)
				
		draw_polygon(pts, PackedColorArray([current_color]))
		
	elif type.ends_with("Link"):
		var w = hs * 0.3
		draw_rect(Rect2(center - Vector2(w, w), Vector2(w*2, w*2)), Color(0.8, 0.6, 0.1), false, 3.0)
		draw_circle(center, w * 0.5, Color(0.8, 0.6, 0.1))
		
	else:
		# Generic conduit path
		var default_travel_dir = 3
		var entry_face = (default_travel_dir + 3) % 6
		if tile.has_method("get_exit_direction"):
			var ex = tile.get_exit_direction(entry_face)
			var in_angle = entry_face * (PI / 3.0)
			var out_angle = ex * (PI / 3.0)
			draw_line(center + Vector2(cos(in_angle), sin(in_angle)) * hs * 0.7, center, base, 4.0, true)
			draw_line(center, center + Vector2(cos(out_angle), sin(out_angle)) * hs * 0.7, base, 4.0, true)
		else:
			draw_circle(center, hs * 0.2, base)

func _draw_static_paths(tile: HexTile, center: Vector2):
	if tile.tile_type == "Amplifier":
		return # Omnidirectional pass-through, static paths are misleading
		
	var hs = hex_size * zoom
	var default_travel_dir = 3
	var main_menu = get_tree().current_scene
	if main_menu and main_menu.get_node_or_null("GarageMenu"):
		var garage = main_menu.get_node("GarageMenu")
		if garage.active_component and garage.active_component.slot_type == load("res://scripts/core/HexTile.gd").BodySlot.ARM_L:
			default_travel_dir = 3
			
	var entry_face = (default_travel_dir + 3) % 6
	var exits = []
	if tile.has_method("get_exit_directions"):
		exits = tile.get_exit_directions(entry_face)
	elif tile.has_method("get_exit_direction"):
		exits.append(tile.get_exit_direction(entry_face))
		
	var base_color = Color(1.0, 0.7, 0.1, 0.5)
	for ex in exits:
		var angle = ex * (PI / 3.0)
		var end_pt = center + Vector2(cos(angle), sin(angle)) * hs
		# Draw dashed line
		for i in range(5):
			var t1 = i / 5.0
			var t2 = (i + 0.5) / 5.0
			draw_line(center.lerp(end_pt, t1), center.lerp(end_pt, t2), base_color, 2.0, true)

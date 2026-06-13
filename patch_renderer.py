import os
import re

file_path = "j:/pixel_bots/godot/scripts/ui/GarageGridRenderer.gd"

with open(file_path, "r") as f:
    content = f.read()

# Add new variables
content = content.replace("var hex_grid: Node # HexGridComponent", 
"""var hex_grid: Node # HexGridComponent
var show_static_paths: bool = true
var time_elapsed: float = 0.0""")

# Update _process
content = content.replace("func _process(delta):", 
"""func _process(delta):
\ttime_elapsed += delta""")

# Update _draw background
content = content.replace("draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG)", 
"\t# draw_rect(Rect2(Vector2.ZERO, size), COLOR_BG) # Removed to allow mostly transparent background")

# Update valid coords rendering to be outline instead of filled
content = content.replace("""\t# 0. Draw procedural sprite (80% transparent behind grid)
\tfor coord in valid_coords:
\t\t# Draw a slightly inflated filled hex to merge them into one visual 'part'
\t\t_draw_hex_filled_scaled(coord, Color(0.3, 0.4, 0.5, 0.2), 1.15)""", 
"""\t# 0. Draw procedural outline behind grid
\tfor coord in valid_coords:
\t\t_draw_hex_filled_scaled(coord, Color(0.2, 0.3, 0.4, 0.3), 1.15)""")

content = content.replace("""\t# 1. Draw empty grid slots
\tfor coord in valid_coords:
\t\t_draw_hex_outline(coord, COLOR_GRID, 1.0)""", 
"""\t# 1. Draw empty grid slots with hatching
\tfor coord in valid_coords:
\t\t_draw_hex_hatched(coord, Color(0.1, 0.1, 0.1, 0.6))
\t\t_draw_hex_outline(coord, COLOR_GRID, 1.0)""")

# Add the drawing functions
drawing_funcs = """

func _draw_hex_hatched(coord: HexCoord, color: Color):
\tvar center = _hex_to_pixel(coord)
\tvar r = hex_size * zoom
\t# Draw a few diagonal lines
\tfor i in range(-2, 3):
\t\tvar offset = i * (r * 0.3)
\t\tvar p1 = center + Vector2(-r, -r + offset)
\t\tvar p2 = center + Vector2(r, r + offset)
\t\t# Clip to hex approx
\t\tif p1.distance_to(center) < r * 1.5 and p2.distance_to(center) < r * 1.5:
\t\t\tdraw_line(p1, p2, color, 2.0, true)

func _get_synergy_color(syn: int) -> Color:
\tmatch syn:
\t\t1: return Color(1.0, 0.2, 0.2) # FIRE
\t\t2: return Color(0.2, 0.5, 1.0) # ICE
\t\t3: return Color(0.9, 0.9, 0.2) # LIGHTNING
\t\t4: return Color(0.8, 0.2, 0.8) # VORTEX
\t\t5: return Color(0.2, 0.8, 0.2) # POISON
\t\t6: return Color(1.0, 0.6, 0.2) # EXPLOSION
\t\t7: return Color(0.8, 0.8, 0.8) # KINETIC
\t\t8: return Color(0.4, 0.9, 0.9) # PIERCE
\t\t9: return Color(0.9, 0.1, 0.3) # VAMPIRIC
\t\t_: return Color(1.0, 0.2, 0.2) # RAW / Default

func _draw_descriptive_icon(tile: HexTile, center: Vector2):
\tvar type = tile.tile_type
\tvar base = Color(0.8, 0.2, 0.2, 0.9) # Distinctive bright red
\t
\tvar hs = hex_size * zoom
\t
\tif type == "Core Reactor":
\t\tdraw_circle(center, hs * 0.4, base)
\t\tdraw_circle(center, hs * 0.2, Color(1, 0.5, 0.5))
\t\tfor i in range(6):
\t\t\tvar angle = deg_to_rad(60 * i)
\t\t\tdraw_line(center, center + Vector2(cos(angle), sin(angle)) * hs * 0.6, base, 3.0, true)
\t\t\t
\telif type == "Splitter":
\t\tvar default_travel_dir = 3
\t\tvar entry_face = (default_travel_dir + 3) % 6
\t\tif tile.has_method("get_exit_directions"):
\t\t\tvar exits = tile.get_exit_directions(entry_face)
\t\t\tfor ex in exits:
\t\t\t\tvar angle = ex * (PI / 3.0)
\t\t\t\tdraw_line(center, center + Vector2(cos(angle), sin(angle)) * hs * 0.7, base, 4.0, true)
\t\t\t\tdraw_circle(center + Vector2(cos(angle), sin(angle)) * hs * 0.7, 4.0, base)
\t\t\tdraw_circle(center, hs * 0.2, base)
\t\t\t
\telif type == "Amplifier":
\t\tvar w = hs * 0.4
\t\tdraw_line(center - Vector2(w, 0), center + Vector2(w, 0), base, 4.0, true)
\t\tdraw_line(center - Vector2(0, w), center + Vector2(0, w), base, 4.0, true)
\t\t
\telif type == "Weapon Mount":
\t\tvar syn = 0
\t\tif "pending_packets" in tile and tile.pending_packets.size() > 0:
\t\t\tsyn = tile.pending_packets[0].packet.get_dominant_synergy()
\t\tvar syn_color = _get_synergy_color(syn)
\t\t
\t\tvar throb = (sin(time_elapsed * 5.0) + 1.0) * 0.5
\t\tvar radius = hs * 0.4 + (throb * hs * 0.2)
\t\t
\t\t# Hatched background
\t\t_draw_hex_hatched(tile.grid_position, syn_color * Color(1,1,1,0.5))
\t\t
\t\t# Glowing center
\t\tdraw_circle(center, radius, syn_color * Color(1,1,1,0.6))
\t\tdraw_circle(center, radius * 0.6, syn_color)
\t\t
\telif type.ends_with("Link"):
\t\tvar w = hs * 0.3
\t\tdraw_rect(Rect2(center - Vector2(w, w), Vector2(w*2, w*2)), Color(0.8, 0.6, 0.1), false, 3.0)
\t\tdraw_circle(center, w * 0.5, Color(0.8, 0.6, 0.1))
\t\t
\telse:
\t\t# Generic conduit path
\t\tvar default_travel_dir = 3
\t\tvar entry_face = (default_travel_dir + 3) % 6
\t\tif tile.has_method("get_exit_direction"):
\t\t\tvar ex = tile.get_exit_direction(entry_face)
\t\t\tvar in_angle = entry_face * (PI / 3.0)
\t\t\tvar out_angle = ex * (PI / 3.0)
\t\t\tdraw_line(center + Vector2(cos(in_angle), sin(in_angle)) * hs * 0.7, center, base, 4.0, true)
\t\t\tdraw_line(center, center + Vector2(cos(out_angle), sin(out_angle)) * hs * 0.7, base, 4.0, true)
\t\telse:
\t\t\tdraw_circle(center, hs * 0.2, base)

func _draw_static_paths(tile: HexTile, center: Vector2):
\tvar hs = hex_size * zoom
\tvar default_travel_dir = 3
\tvar main_menu = get_tree().current_scene
\tif main_menu and main_menu.get_node_or_null("GarageMenu"):
\t\tvar garage = main_menu.get_node("GarageMenu")
\t\tif garage.active_component and garage.active_component.slot_type == load("res://scripts/core/HexTile.gd").BodySlot.ARM_L:
\t\t\tdefault_travel_dir = 3
\t\t\t
\tvar entry_face = (default_travel_dir + 3) % 6
\tvar exits = []
\tif tile.has_method("get_exit_directions"):
\t\texits = tile.get_exit_directions(entry_face)
\telif tile.has_method("get_exit_direction"):
\t\texits.append(tile.get_exit_direction(entry_face))
\t\t
\tvar base_color = Color(1.0, 0.2, 0.2, 0.5)
\tfor ex in exits:
\t\tvar angle = ex * (PI / 3.0)
\t\tvar end_pt = center + Vector2(cos(angle), sin(angle)) * hs
\t\t# Draw dashed line
\t\tfor i in range(5):
\t\t\tvar t1 = i / 5.0
\t\t\tvar t2 = (i + 0.5) / 5.0
\t\t\tdraw_line(center.lerp(end_pt, t1), center.lerp(end_pt, t2), base_color, 2.0, true)
"""

# Replace _draw_tile
content = re.sub(
    r"func _draw_tile\(tile: HexTile\):.*?(?=\nfunc _draw_arrow)",
    """func _draw_tile(tile: HexTile):
\tif not tile.grid_position: return
\t
\t# Dark solid base instead of base_color
\t_draw_hex_filled(tile.grid_position, Color(0.15, 0.15, 0.15, 0.95))
\t
\t# Rarity Outline
\tvar rarity_color = Color.WHITE
\tmatch tile.rarity:
\t\tHexTile.Rarity.COMMON: rarity_color = Color(0.5, 0.5, 0.5)
\t\tHexTile.Rarity.UNCOMMON: rarity_color = Color(0.4, 0.8, 1.0)
\t\tHexTile.Rarity.RARE: rarity_color = Color(0.4, 1.0, 0.4)
\t\tHexTile.Rarity.LEGENDARY: rarity_color = Color(1.0, 0.5, 0.0)
\t
\t_draw_hex_outline(tile.grid_position, rarity_color, 2.0)
\t
\tvar center = _hex_to_pixel(tile.grid_position)
\t
\t_draw_descriptive_icon(tile, center)
\t
\tif show_static_paths:
\t\t_draw_static_paths(tile, center)
""",
    content,
    flags=re.DOTALL
)

content += drawing_funcs

with open(file_path, "w") as f:
    f.write(content)
print("GarageGridRenderer.gd patched successfully.")

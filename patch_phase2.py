import os
import re

file_path = "j:/pixel_bots/godot/scripts/ui/GarageGridRenderer.gd"

with open(file_path, "r") as f:
    content = f.read()

replacement = """	elif type == "Weapon Mount":
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
				
		draw_polygon(pts, PackedColorArray([current_color, current_color, current_color, current_color, current_color, current_color, current_color, current_color, current_color, current_color, current_color, current_color, current_color, current_color, current_color, current_color]))"""

# Use regex to replace the Weapon Mount block
pattern = r"\s*elif type == \"Weapon Mount\":\s*var syn = 0.*?draw_circle\(center, radius \* 0\.6, syn_color\)"
content = re.sub(pattern, "\n" + replacement, content, flags=re.DOTALL)

with open(file_path, "w") as f:
    f.write(content)

print("GarageGridRenderer.gd patched for Phase 2 successfully.")

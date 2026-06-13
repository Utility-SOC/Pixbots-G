class_name MechRenderer
extends Node2D

const HexCoord = preload("res://scripts/core/HexCoord.gd")

var components: Dictionary = {}
var drawn_parts: Dictionary = {}

func _ready():
	_rebuild_visuals()

func _process(_delta):
	queue_redraw()

func _draw():
	var mech = get_parent()
	if not mech or not "hp" in mech: return
	
	var bar_width = 40.0
	var bar_height = 4.0
	var y_offset = -40.0
	
	# Draw background
	draw_rect(Rect2(-bar_width/2, y_offset, bar_width, bar_height), Color.BLACK)
	
	# Draw HP
	var hp_pct = clamp(mech.hp / max(1.0, mech.max_hp), 0.0, 1.0)
	var hp_color = Color.GREEN if mech.is_player else Color.RED
	draw_rect(Rect2(-bar_width/2, y_offset, bar_width * hp_pct, bar_height), hp_color)
	
	# Draw Shield
	if mech.max_shield_hp > 0:
		var shld_pct = clamp(mech.shield_hp / max(1.0, mech.max_shield_hp), 0.0, 1.0)
		draw_rect(Rect2(-bar_width/2, y_offset - bar_height - 1, bar_width * shld_pct, bar_height), Color(0.2, 0.6, 1.0))

func _rebuild_visuals():
	# Clear existing
	for child in get_children():
		child.queue_free()
	drawn_parts.clear()
	
	for slot in components.keys():
		var comp = components[slot]
		var color = Color(0.3, 0.4, 0.5)
		var rarity_mult = 1.0 + (comp.rarity * 0.05) # Reduced scale inflation
		
		# Generate a deterministic random seed
		var rng = RandomNumberGenerator.new()
		rng.seed = hash(comp.component_name) + comp.rarity
		

		if comp.slot_type == load("res://scripts/core/HexTile.gd").BodySlot.TORSO:
			_draw_torso(null, color, rng, rarity_mult, comp.rarity)
		elif comp.slot_type == load("res://scripts/core/HexTile.gd").BodySlot.ARM_L:
			_draw_arm(null, color, true, rng, rarity_mult, comp.rarity)
		elif comp.slot_type == load("res://scripts/core/HexTile.gd").BodySlot.ARM_R:
			_draw_arm(null, color, false, rng, rarity_mult, comp.rarity)
		elif comp.slot_type == load("res://scripts/core/HexTile.gd").BodySlot.LEG_L:
			_draw_leg(null, color, true, rng, rarity_mult, comp.rarity)
		elif comp.slot_type == load("res://scripts/core/HexTile.gd").BodySlot.LEG_R:
			_draw_leg(null, color, false, rng, rarity_mult, comp.rarity)
		elif comp.slot_type == load("res://scripts/core/HexTile.gd").BodySlot.HEAD:
			_draw_head(null, color, rng, rarity_mult, comp.rarity)
				
	# Draw standard parts for any slots that weren't overridden by tiles
	var default_color = Color(0.3, 0.4, 0.5)
	var rng_def = RandomNumberGenerator.new()
	rng_def.seed = 12345
	
	if not drawn_parts.has("Torso"):
		_draw_torso(null, default_color, rng_def, 1.0, 0)
	if not drawn_parts.has("Arm_true"):
		_draw_arm(null, default_color, true, rng_def, 1.0, 0)
	if not drawn_parts.has("Arm_false"):
		_draw_arm(null, default_color, false, rng_def, 1.0, 0)
	if not drawn_parts.has("Leg_true"):
		_draw_leg(null, default_color, true, rng_def, 1.0, 0)
	if not drawn_parts.has("Leg_false"):
		_draw_leg(null, default_color, false, rng_def, 1.0, 0)
	if not drawn_parts.has("Head"):
		_draw_head(null, default_color, rng_def, 1.0, 0)

# -----------------------------------------------------------------------------
# SHAPE DEFINITIONS
# -----------------------------------------------------------------------------

func _draw_torso(tile, color, rng, scale_mult, rarity):
	var w = 18.0 * scale_mult
	var h = 22.0 * scale_mult
	var pts = PackedVector2Array([
		Vector2(-w*0.8, -h), Vector2(w*0.8, -h), 
		Vector2(w, -h*0.3), Vector2(w*0.6, h), 
		Vector2(-w*0.6, h), Vector2(-w, -h*0.3)
	])
	
	# Add some random jaggedness
	for i in range(pts.size()):
		pts[i] += Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
		
	var body_slot = tile.body_slot if tile else load("res://scripts/core/HexTile.gd").BodySlot.TORSO
	_render_mechanical_part(pts, color, Vector2.ZERO, "Torso", body_slot, rarity)
	
	# Core Reactor Glow
	var core_poly = Polygon2D.new()
	core_poly.color = color * 1.5 # Overbright
	var ring = PackedVector2Array()
	for i in range(8):
		var a = i * (PI / 4.0)
		ring.append(Vector2(cos(a), sin(a)) * 8.0 * scale_mult)
	core_poly.polygon = ring
	add_child(core_poly)

func _draw_arm(tile, color, is_left, rng, scale_mult, rarity):
	var sign = -1.0 if is_left else 1.0
	var offset = Vector2(24.0 * sign, -5.0)
	
	var w = 8.0 * scale_mult
	var h = 28.0 * scale_mult
	
	var pts = PackedVector2Array()
	var is_weapon = (tile != null and tile.category == load("res://scripts/core/HexTile.gd").TileCategory.OUTPUT)
	if is_weapon:
		# Weapon/Gun arm
		pts.append_array([
			Vector2(-w, -h*0.5), Vector2(w, -h*0.5),
			Vector2(w, h*0.2), Vector2(w*0.4, h*0.8), Vector2(w*0.4, h),
			Vector2(-w*0.4, h), Vector2(-w*0.4, h*0.8), Vector2(-w, h*0.2)
		])
	else:
		# Structural/Shield arm
		pts.append_array([
			Vector2(-w*1.5, -h*0.3), Vector2(w*1.5, -h*0.3),
			Vector2(w, h*0.8), Vector2(-w, h*0.8)
		])
	
	# Mirror geometry if left
	if is_left:
		for i in range(pts.size()):
			pts[i].x *= -1
			
	var slot = load("res://scripts/core/HexTile.gd").BodySlot.ARM_L if is_left else load("res://scripts/core/HexTile.gd").BodySlot.ARM_R
	var body_slot = tile.body_slot if tile else slot
	var part = _render_mechanical_part(pts, color, offset, "Arm_" + str(is_left), body_slot, rarity)
	
	# Rotate weapons slightly outward
	part.rotation = deg_to_rad(15.0 * sign)

func _draw_leg(tile, color, is_left, rng, scale_mult, rarity):
	var sign = -1.0 if is_left else 1.0
	var offset = Vector2(14.0 * sign, 20.0)
	
	var w = 10.0 * scale_mult
	var h = 24.0 * scale_mult
	
	var pts = PackedVector2Array([
		Vector2(-w*0.8, -h*0.5), Vector2(w*0.8, -h*0.5),
		Vector2(w, h*0.5), Vector2(w*1.2, h),
		Vector2(-w*1.2, h), Vector2(-w, h*0.5)
	])
	
	if is_left:
		for i in range(pts.size()):
			pts[i].x *= -1
			
	var slot = load("res://scripts/core/HexTile.gd").BodySlot.LEG_L if is_left else load("res://scripts/core/HexTile.gd").BodySlot.LEG_R
	var body_slot = tile.body_slot if tile else slot
	_render_mechanical_part(pts, color, offset, "Leg_" + str(is_left), body_slot, rarity)

func _draw_head(tile, color, rng, scale_mult, rarity):
	var offset = Vector2(0, -26.0)
	var w = 12.0 * scale_mult
	var h = 10.0 * scale_mult
	
	var pts = PackedVector2Array([
		Vector2(-w*0.6, -h), Vector2(w*0.6, -h),
		Vector2(w, h), Vector2(-w, h)
	])
	
	var body_slot = tile.body_slot if tile else load("res://scripts/core/HexTile.gd").BodySlot.HEAD
	var container = _render_mechanical_part(pts, color, offset, "Head", body_slot, rarity)
	
	# Visor
	var visor = Polygon2D.new()
	visor.color = color * 1.5
	visor.polygon = PackedVector2Array([
		Vector2(-w*0.8, h*0.2), Vector2(w*0.8, h*0.2),
		Vector2(w*0.6, h*0.6), Vector2(-w*0.6, h*0.6)
	])
	visor.position = offset
	container.add_child(visor)

# -----------------------------------------------------------------------------
# CORE RENDER PIPELINE
# -----------------------------------------------------------------------------

func _render_mechanical_part(pts: PackedVector2Array, energy_color: Color, offset: Vector2, part_name: String, body_slot: int, rarity: int = 0) -> Node2D:
	var container = Node2D.new()
	container.position = offset
	container.name = part_name
	
	# Complex Edges for RARE and LEGENDARY
	if rarity >= load("res://scripts/core/HexTile.gd").Rarity.RARE:
		var new_pts = PackedVector2Array()
		for i in range(pts.size()):
			var p1 = pts[i]
			var p2 = pts[(i+1)%pts.size()]
			new_pts.append(p1)
			# Add a small notch in the middle of each edge
			var mid = (p1 + p2) / 2.0
			var normal = (p2 - p1).orthogonal().normalized()
			# Normal points OUTWARDS if points are clockwise. If counter-clockwise, it points INWARDS.
			# Let's just perturb the midpoint towards the center to create a panel gap
			var center = Vector2.ZERO
			for p in pts: center += p
			center /= pts.size()
			var to_center = (center - mid).normalized()
			new_pts.append(mid + to_center * 3.0) 
		pts = new_pts
	
	# 1. Energy Sub-layer (Glow/Bleed)
	var energy_base = Polygon2D.new()
	energy_base.polygon = pts
	energy_base.color = energy_color
	container.add_child(energy_base)
	
	# Optional: Particles for high rarity components
	if rarity >= load("res://scripts/core/HexTile.gd").Rarity.UNCOMMON:
		var particles = CPUParticles2D.new()
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINTS
		particles.emission_points = pts
		particles.amount = 8 + (rarity * 4)
		particles.lifetime = 1.0
		particles.gravity = Vector2(0, -10)
		particles.scale_amount_min = 1.0
		particles.scale_amount_max = 2.5
		particles.color = energy_color
		container.add_child(particles)
	
	# 2. Armor Super-layer (Directional Shaded Metal)
	var armor_base = Polygon2D.new()
	var base_armor_color = Color(0.3, 0.35, 0.38) # Slate metal grey
	if rarity >= load("res://scripts/core/HexTile.gd").Rarity.LEGENDARY:
		base_armor_color = Color(0.18, 0.20, 0.23) # Darker, sleeker for legendary
	armor_base.color = base_armor_color
	
	# Shrink the armor slightly so the energy bleeds out the edges
	var shrunk_pts = _shrink_polygon(pts, 3.0)
	armor_base.polygon = shrunk_pts
	container.add_child(armor_base)
	
	# Greebling (Extra armor plates) for UNCOMMON+
	if rarity >= load("res://scripts/core/HexTile.gd").Rarity.UNCOMMON:
		var plate1 = Polygon2D.new()
		plate1.color = base_armor_color.lightened(0.15)
		plate1.polygon = _shrink_polygon(pts, 6.0)
		container.add_child(plate1)
		
		if rarity >= load("res://scripts/core/HexTile.gd").Rarity.RARE:
			var plate2 = Polygon2D.new()
			plate2.color = base_armor_color.darkened(0.1)
			plate2.polygon = _shrink_polygon(pts, 9.0)
			container.add_child(plate2)
			
	# Energy Lines for RARE+
	if rarity >= load("res://scripts/core/HexTile.gd").Rarity.RARE:
		var center_poly = _shrink_polygon(pts, 12.0)
		if center_poly.size() > 0:
			var line = Line2D.new()
			line.points = center_poly
			line.add_point(center_poly[0]) # close loop
			line.width = 1.5
			line.default_color = energy_color.lightened(0.4)
			container.add_child(line)
	
	# 3. Highlight / Shadow lines (Faux 3D bevel)
	for i in range(shrunk_pts.size()):
		var p1 = shrunk_pts[i]
		var p2 = shrunk_pts[(i + 1) % shrunk_pts.size()]
		var edge_normal = (p2 - p1).orthogonal().normalized()
		
		# If normal points up/left, it's a highlight. Down/right is shadow.
		var light_dir = Vector2(-0.5, -0.8).normalized()
		var dot = edge_normal.dot(light_dir)
		
		var line = Line2D.new()
		line.add_point(p1)
		line.add_point(p2)
		line.width = 2.0
		
		if dot > 0.2:
			line.default_color = Color(0.6, 0.65, 0.7) # Highlight
		elif dot < -0.2:
			line.default_color = Color(0.1, 0.15, 0.18) # Shadow
		else:
			line.default_color = Color(0.2, 0.25, 0.28) # Mid-tone
			
		container.add_child(line)

	# 4. Physical Hitbox (Area2D)
	var area = load("res://scripts/entities/PartHitbox.gd").new()
	area.name = "Hitbox"
	area.mech = get_parent()
	area.body_slot = body_slot
	area.collision_layer = get_parent().collision_layer
	area.collision_mask = 0 # It just receives hits
	
	var shape = CollisionPolygon2D.new()
	shape.polygon = pts
	area.add_child(shape)
	container.add_child(area)

	add_child(container)
	drawn_parts[part_name] = container
	return container

func _shrink_polygon(pts: PackedVector2Array, amount: float) -> PackedVector2Array:
	var center = Vector2.ZERO
	for p in pts:
		center += p
	center /= pts.size()
	
	var new_pts = PackedVector2Array()
	for p in pts:
		var dir = (p - center).normalized()
		new_pts.append(p - dir * amount)
	return new_pts

func _get_synergy_color(tile) -> Color:
	if "output_synergy" in tile:
		return _color_from_synergy(tile.output_synergy)
	
	# Weapon mounts usually take energy, maybe they have a requested synergy?
	# For now, default to kinetic or base
	var base_color = Color(0.2, 0.4, 0.8) # Base Blue
	if tile.category == HexTile.TileCategory.OUTPUT:
		base_color = Color(0.8, 0.2, 0.2) # Red Weapons
	return base_color

func _color_from_synergy(syn: int) -> Color:
	match syn:
		1: return Color(1.0, 0.8, 0.2) # Kinetic
		2: return Color(1.0, 0.3, 0.0) # Fire
		3: return Color(0.2, 0.8, 0.2) # Poison
		4: return Color(0.3, 0.3, 1.0) # Lightning
		5: return Color(0.6, 0.1, 0.6) # Vampire
		6: return Color(0.1, 0.8, 0.8) # Vortex
	return Color(0.8, 0.8, 0.8)

func rotate_arms(target_global_pos: Vector2, mech_global_pos: Vector2):
	var dir = mech_global_pos.direction_to(target_global_pos)
	var angle = dir.angle()
	
	# The default angle is down (PI/2). We want the arm to point at the target.
	# Depending on how the arm was drawn (pointing down by default), we adjust.
	# We drew the arms pointing DOWN (h is positive Y).
	var target_rot = angle - PI/2.0
	
	if drawn_parts.has("Arm_true"):
		# Smoothly rotate left arm
		var arm_l = drawn_parts["Arm_true"]
		arm_l.rotation = lerp_angle(arm_l.rotation, target_rot, 0.1)
		
	if drawn_parts.has("Arm_false"):
		# Smoothly rotate right arm
		var arm_r = drawn_parts["Arm_false"]
		arm_r.rotation = lerp_angle(arm_r.rotation, target_rot, 0.1)

func animate_legs(velocity: Vector2, time: float):
	var speed = velocity.length()
	if speed < 10.0:
		# Return to idle
		if drawn_parts.has("Leg_true"):
			drawn_parts["Leg_true"].rotation = lerp_angle(drawn_parts["Leg_true"].rotation, 0.0, 0.1)
		if drawn_parts.has("Leg_false"):
			drawn_parts["Leg_false"].rotation = lerp_angle(drawn_parts["Leg_false"].rotation, 0.0, 0.1)
		return
		
	# Swing legs back and forth based on time and speed
	var swing = sin(time * speed * 0.02) * 0.4
	
	if drawn_parts.has("Leg_true"):
		drawn_parts["Leg_true"].rotation = swing
	if drawn_parts.has("Leg_false"):
		drawn_parts["Leg_false"].rotation = -swing


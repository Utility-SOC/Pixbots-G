class_name Projectile
extends Area2D

const EnergyPacket = preload("res://scripts/core/EnergyPacket.gd")

var base_speed: float = 500.0
var final_speed: float = 500.0
var damage: float = 10.0
var direction: Vector2 = Vector2.ZERO
var target_direction: Vector2 = Vector2.ZERO
var synergies: Dictionary = {}

var ratios: Dictionary = {}
var total_power: float = 0.0
var final_color: Color = Color.WHITE

var stat_modifiers: Dictionary = {}

# Modifiers
var pierce_count: int = 1
var is_homing: bool = false
var time_alive: float = 0.0

var visual_node: Node2D
var helix_particles: Array = []
var fired_by_player: bool = true

func _ready():
	# Calculate total power
	for k in synergies:
		total_power += synergies[k]
	if total_power <= 0:
		total_power = 1.0
		ratios[EnergyPacket.SynergyType.RAW] = 1.0
	else:
		for k in synergies:
			ratios[k] = synergies[k] / total_power
			
	_calculate_stats()
	_build_visuals()
	
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(8, 8) * scale # Scale is set in _calculate_stats
	shape.shape = rect
	add_child(shape)
	
	collision_layer = 0
	if fired_by_player:
		collision_mask = 4 | 1 # Enemy (Layer 3) + World (Layer 1)
	else:
		collision_mask = 8 | 1 # Player (Layer 4) + World (Layer 1)
	
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	
	# EXPLOSION DETONATION
	var timer = Timer.new()
	timer.wait_time = _get_lifetime()
	timer.one_shot = true
	timer.timeout.connect(func():
		if ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0) > 0.1:
			_trigger_explosion()
		queue_free()
	)
	add_child(timer)
	timer.start()

func _get_lifetime() -> float:
	var base_life = 4.0
	if ratios.has(EnergyPacket.SynergyType.FIRE):
		base_life = lerp(base_life, 0.4, ratios[EnergyPacket.SynergyType.FIRE]) # Very short lifetime for fire
		if ratios.has(EnergyPacket.SynergyType.KINETIC):
			# Kinetic stretches the fire plume length
			base_life += 1.0 * ratios[EnergyPacket.SynergyType.KINETIC]
	return max(0.1, base_life)

func _calculate_stats():
	# Organic Stat Scaling
	var r_raw = ratios.get(EnergyPacket.SynergyType.RAW, 0.0)
	var r_kin = ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)
	var r_ice = ratios.get(EnergyPacket.SynergyType.ICE, 0.0)
	var r_exp = ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0)
	var r_prc = ratios.get(EnergyPacket.SynergyType.PIERCE, 0.0)
	var r_psn = ratios.get(EnergyPacket.SynergyType.POISON, 0.0)
	
	# Base Speed
	var spd_mod = 0.0
	spd_mod += 800.0 * r_kin
	spd_mod += 400.0 * r_prc
	spd_mod -= 250.0 * r_psn
	spd_mod -= 200.0 * r_ice
	final_speed = base_speed + spd_mod
	if final_speed < 50.0: final_speed = 50.0
	
	# Size/Mass
	var s_mod = 1.0 + r_raw # RAW directly increases volume
	s_mod += 1.5 * r_ice # ICE adds crystalline mass
	s_mod += 2.0 * r_exp # EXPLOSION adds volatility/size
	s_mod -= 0.5 * r_prc # PIERCE makes it sleek
	scale = Vector2(s_mod, s_mod)
	
	# Base Damage Multiplier from RAW
	damage *= (1.0 + r_raw * 1.5)
	
	# Pierce Count (PIERCE sets base to high, otherwise 1)
	if r_prc > 0.0:
		pierce_count = 1 + int(4.0 * r_prc)
	else:
		pierce_count = 1
		
	# Homing check
	if ratios.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0) > 0.05:
		is_homing = true
		
	# Apply Component Stat Modifiers
	if stat_modifiers.has("dmg_mult"): damage *= stat_modifiers["dmg_mult"]
	if stat_modifiers.has("spd_mult"): final_speed *= stat_modifiers["spd_mult"]
	
	# Apply Elemental Multipliers from Components based on ratios
	if stat_modifiers.has("kin_mult") and r_kin > 0: damage *= lerp(1.0, stat_modifiers["kin_mult"], r_kin)
	if stat_modifiers.has("fire_mult") and ratios.has(EnergyPacket.SynergyType.FIRE): damage *= lerp(1.0, stat_modifiers["fire_mult"], ratios[EnergyPacket.SynergyType.FIRE])
	if stat_modifiers.has("ice_mult") and r_ice > 0: damage *= lerp(1.0, stat_modifiers["ice_mult"], r_ice)
	if stat_modifiers.has("vtx_mult") and ratios.has(EnergyPacket.SynergyType.VORTEX): damage *= lerp(1.0, stat_modifiers["vtx_mult"], ratios[EnergyPacket.SynergyType.VORTEX])
	if stat_modifiers.has("ltg_mult") and ratios.has(EnergyPacket.SynergyType.LIGHTNING): damage *= lerp(1.0, stat_modifiers["ltg_mult"], ratios[EnergyPacket.SynergyType.LIGHTNING])
	if stat_modifiers.has("psn_mult") and r_psn > 0: damage *= lerp(1.0, stat_modifiers["psn_mult"], r_psn)
	if stat_modifiers.has("exp_mult") and r_exp > 0: damage *= lerp(1.0, stat_modifiers["exp_mult"], r_exp)
	if stat_modifiers.has("prc_mult") and r_prc > 0: damage *= lerp(1.0, stat_modifiers["prc_mult"], r_prc)
	if stat_modifiers.has("vmp_mult") and ratios.has(EnergyPacket.SynergyType.VAMPIRIC): damage *= lerp(1.0, stat_modifiers["vmp_mult"], ratios[EnergyPacket.SynergyType.VAMPIRIC])
		
	# Color Blending
	final_color = Color(0,0,0,0)
	for k in ratios:
		var c = Color.WHITE
		match k:
			EnergyPacket.SynergyType.FIRE: c = Color(1.0, 0.3, 0.0)
			EnergyPacket.SynergyType.ICE: c = Color(0.2, 0.8, 1.0)
			EnergyPacket.SynergyType.KINETIC: c = Color(1.0, 1.0, 1.0)
			EnergyPacket.SynergyType.VORTEX: c = Color(0.5, 0.0, 1.0)
			EnergyPacket.SynergyType.LIGHTNING: c = Color(1.0, 0.9, 0.2)
			EnergyPacket.SynergyType.POISON: c = Color(0.2, 0.8, 0.2)
			EnergyPacket.SynergyType.EXPLOSION: c = Color(1.0, 0.5, 0.0)
			EnergyPacket.SynergyType.PIERCE: c = Color(0.0, 1.0, 0.5)
			EnergyPacket.SynergyType.VAMPIRIC: c = Color(0.8, 0.0, 0.3)
		final_color += c * ratios[k]
	if final_color.a == 0:
		final_color = Color.WHITE

func _build_visuals():
	visual_node = Node2D.new()
	add_child(visual_node)
	
	# Determine dominant and secondary synergies for shape generation
	var sorted_synergies = []
	for k in synergies:
		sorted_synergies.append({"type": k, "power": synergies[k]})
	sorted_synergies.sort_custom(func(a, b): return a.power > b.power)
	
	var dominant = -1
	var secondary = -1
	if sorted_synergies.size() > 0: dominant = sorted_synergies[0].type
	if sorted_synergies.size() > 1: secondary = sorted_synergies[1].type
	
	# Procedural Shape based on Dominant Element
	var p_scale = 1.0 + log(1.0 + total_power / 200.0) * 0.5
	p_scale = min(p_scale, 3.0) # Maximum reasonable scale limit
	
	if dominant == EnergyPacket.SynergyType.KINETIC:
		# Sharp, aerodynamic shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(10, 0), Vector2(-5, 5), Vector2(-2, 0), Vector2(-5, -5)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.FIRE:
		# Volatile, spherical shape
		var circ = Polygon2D.new()
		var pts = PackedVector2Array()
		for i in range(16):
			var a = i * PI / 8.0
			pts.append(Vector2(cos(a), sin(a)) * 4.0 * p_scale)
		circ.polygon = pts
		circ.color = final_color
		visual_node.add_child(circ)
	elif dominant == EnergyPacket.SynergyType.ICE:
		# Crystalline, jagged shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(8, 0), Vector2(0, 4), Vector2(-5, 2), Vector2(-3, 0), Vector2(-5, -2), Vector2(0, -4)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.POISON:
		# Teardrop shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(8, 0), Vector2(-2, 4), Vector2(-5, 2), Vector2(-5, -2), Vector2(-2, -4)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.LIGHTNING:
		# Zig-zag bolt shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(8, -2), Vector2(2, 4), Vector2(0, 0), Vector2(-6, 4), Vector2(-2, -4), Vector2(0, 0)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.EXPLOSION:
		# Spiky burst shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(6, 0), Vector2(2, 2), Vector2(0, 6), Vector2(-2, 2),
			Vector2(-6, 0), Vector2(-2, -2), Vector2(0, -6), Vector2(2, -2)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.PIERCE:
		# Needle shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(12, 0), Vector2(-6, 2), Vector2(-4, 0), Vector2(-6, -2)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
	elif dominant == EnergyPacket.SynergyType.VORTEX:
		# Diamond shape for vortex core
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(5, 0), Vector2(0, 5), Vector2(-5, 0), Vector2(0, -5)
		])
		poly.color = final_color
		poly.scale = Vector2.ONE * p_scale
		visual_node.add_child(poly)
		
		# Purple spiral
		var spiral = Line2D.new()
		var s_pts = PackedVector2Array()
		for i in range(30):
			var a = i * PI / 4.0
			var r = i * 0.4
			s_pts.append(Vector2(cos(a), sin(a)) * r)
		spiral.points = s_pts
		spiral.width = 1.5
		spiral.default_color = Color(0.6, 0.2, 0.9) # Bright purple
		spiral.scale = Vector2.ONE * p_scale
		visual_node.add_child(spiral)
	else:
		# Default fallback shape
		var rect = ColorRect.new()
		rect.size = Vector2(5, 5) * p_scale
		rect.position = -rect.size/2.0
		rect.color = final_color
		visual_node.add_child(rect)
		
	# Secondary Element modifies properties
	if secondary == EnergyPacket.SynergyType.POISON:
		# Toxic trail
		var trail = CPUParticles2D.new()
		trail.amount = 20
		trail.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		trail.emission_sphere_radius = 4.0
		trail.gravity = Vector2(0, 10)
		trail.color = Color(0.2, 0.8, 0.2, 0.5)
		trail.lifetime = 0.5
		trail.local_coords = false
		visual_node.add_child(trail)
	elif secondary == EnergyPacket.SynergyType.PIERCE:
		# Add a glowing core
		var core = Polygon2D.new()
		core.polygon = PackedVector2Array([
			Vector2(5, 0), Vector2(0, 2), Vector2(-5, 0), Vector2(0, -2)
		])
		core.color = Color(1.0, 1.0, 1.0, 0.8)
		core.scale = Vector2.ONE * p_scale
		visual_node.add_child(core)
		
	# Setup helix for multi-synergy combos
	if sorted_synergies.size() >= 2:
		for k in synergies:
			if k != EnergyPacket.SynergyType.RAW:
				var h = Sprite2D.new()
				h.modulate = _get_color_for_synergy(k)
				h.scale = Vector2(0.5, 0.5)
				visual_node.add_child(h)
				helix_particles.append({
					"node": h,
					"phase": helix_particles.size() * PI,
					"speed": 10.0 + ratios[k] * 10.0,
					"radius": (8.0 + ratios[k] * 12.0) * p_scale
				})
	
	# Kinetic Trail (Line2D)
	if ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0) > 0.1:
		var trail = Line2D.new()
		trail.width = 4.0
		trail.default_color = final_color * Color(1,1,1,0.5)
		trail.set_meta("is_trail", true)
		visual_node.add_child(trail)
		
	# Vortex Helix Orbs
	if ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0) > 0.05:
		for i in range(3):
			var orb = ColorRect.new()
			orb.size = Vector2(4, 4)
			orb.position = -orb.size/2.0
			orb.color = _get_color_for_synergy(EnergyPacket.SynergyType.VORTEX)
			visual_node.add_child(orb)
			helix_particles.append({
				"node": orb,
				"phase": i * (PI * 2.0 / 3.0),
				"speed": 15.0,
				"radius": 8.0
			})

func _get_color_for_synergy(syn: int) -> Color:
	match syn:
		EnergyPacket.SynergyType.KINETIC: return Color(0.8, 0.8, 0.8)
		EnergyPacket.SynergyType.FIRE: return Color(1.0, 0.4, 0.0)
		EnergyPacket.SynergyType.ICE: return Color(0.4, 0.8, 1.0)
		EnergyPacket.SynergyType.POISON: return Color(0.2, 0.8, 0.2)
		EnergyPacket.SynergyType.LIGHTNING: return Color(1.0, 0.9, 0.2)
		EnergyPacket.SynergyType.PIERCE: return Color(0.9, 0.9, 0.9)
		EnergyPacket.SynergyType.VORTEX: return Color(0.5, 0.1, 0.8)
		_: return Color(0.5, 0.5, 0.5)

func _process(delta):
	pass

func _physics_process(delta: float):
	time_alive += delta
	var space_state = get_world_2d().direct_space_state
	
	var r_kin = ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)
	var r_vamp = ratios.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0)
	var r_ice = ratios.get(EnergyPacket.SynergyType.ICE, 0.0)
	var r_fire = ratios.get(EnergyPacket.SynergyType.FIRE, 0.0)
	var r_prc = ratios.get(EnergyPacket.SynergyType.PIERCE, 0.0)
	var r_psn = ratios.get(EnergyPacket.SynergyType.POISON, 0.0)
	var r_vtx = ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0)
	var r_ltg = ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0)
	
	# 1. MASS / INERTIA (ICE & RAW)
	# Heavy objects resist steering. Pierce ignores friction but doesn't affect mass steering resistance.
	var steering_resistance = 1.0 + (3.0 * r_ice) # Ice makes it very hard to turn
	
	# 2. VAMPIRIC TERMINAL HOMING ("The Hunter")
	var active_homing_target = null
	if is_homing:
		var closest = null
		var min_dist = 400.0 + (300.0 * r_vamp)
		var query = PhysicsShapeQueryParameters2D.new()
		var shape = CircleShape2D.new()
		shape.radius = min_dist
		query.shape = shape
		query.transform = global_transform
		query.collision_mask = 4 if collision_mask & 4 else 8
		var results = space_state.intersect_shape(query)
		for res in results:
			var col = res["collider"]
			if col.has_method("apply_damage"):
				var d = global_position.distance_to(col.global_position)
				if d < min_dist:
					min_dist = d
					closest = col
		if closest:
			active_homing_target = closest
			target_direction = (closest.global_position - global_position).normalized()
	
	# 3. KINETIC STEERING ("The Straightener") & VAMPIRIC OVERRIDE
	var current_speed = final_speed
	
	if active_homing_target != null:
		# Vampiric smoothly forces a curve to guarantee hit
		var turn_speed = (8.0 * r_vamp) / steering_resistance
		direction = direction.lerp(target_direction, turn_speed * delta).normalized()
	elif target_direction != Vector2.ZERO:
		var turn_speed = 0.5 # Passive drift
		if r_kin > 0.0:
			turn_speed += (6.0 * r_kin)
		turn_speed /= steering_resistance
		direction = direction.lerp(target_direction, turn_speed * delta).normalized()
	
	# 4. FIRE DECELERATION ("The Plume") vs PIERCE / KINETIC
	# Pierce grants infinite mass/0 drag. Kinetic actively pushes through drag.
	if r_fire > 0.0:
		var drag_coefficient = 800.0 * r_fire
		drag_coefficient *= (1.0 - r_prc) # Pierce cancels drag organically
		drag_coefficient = max(0.0, drag_coefficient - (500.0 * r_kin)) # Kinetic fights it
		
		current_speed = max(50.0, final_speed - drag_coefficient * time_alive)
	
	# 5. POISON GRAVITY LOB ("The Mortar")
	var gravity_velocity = Vector2.ZERO
	if r_psn > 0.0:
		gravity_velocity = Vector2(0, 400.0 * r_psn * time_alive) # Accelerates downwards over time
	
	# ORGANIC VELOCITY ACCUMULATION
	var ortho = Vector2(-direction.y, direction.x)
	var velocity = (direction * current_speed) + gravity_velocity
	var visual_offset = Vector2.ZERO
	
	# 6. VORTEX SWIRL ("The Swirler")
	# Applies a strong tangential force that oscillates, moving the projectile itself.
	if r_vtx > 0.0:
		var swirl_amplitude = 250.0 * r_vtx
		var swirl_freq = 6.0
		var swirl_vel = ortho * cos(time_alive * swirl_freq) * swirl_amplitude
		velocity += swirl_vel
		
		if r_vtx > 0.1:
			_pull_nearby_items(delta)
	
	# 7. LIGHTNING ZIG-ZAG ("The Arc")
	# Lightning snaps instantly along the path, modeled as a square wave offset.
	if r_ltg > 0.0:
		var wave_sign = sign(fmod(time_alive * 20.0, 2.0) - 1.0)
		visual_offset += ortho * wave_sign * (30.0 * r_ltg)
	
	# APPLY PHYSICS
	position += velocity * delta
	
	# APPLY VISUALS
	visual_node.position = visual_offset
	# If poison gravity is dominating, point downwards
	if gravity_velocity.length() > (direction * current_speed).length():
		visual_node.rotation = velocity.angle()
	else:
		visual_node.rotation = direction.angle()
	
	# Update Helix Particles
	if helix_particles.size() > 0:
		for p in helix_particles:
			var angle = time_alive * p["speed"] + p["phase"]
			p["node"].position = Vector2(cos(angle)*p["radius"]*0.5, sin(angle)*p["radius"])
			
	# Update trails
	for child in visual_node.get_children():
		if child.has_meta("is_trail"):
			child.add_point(Vector2(-velocity.length() * 0.02, 0))
			if child.get_point_count() > 10:
				child.remove_point(0)
func _pull_nearby_items(delta: float):
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 150.0 + 100.0 * ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0)
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = 16 | 4 
	var results = space_state.intersect_shape(query)
	for res in results:
		var col = res["collider"]
		if col.has_method("pull_towards"):
			col.pull_towards(global_position, delta)
		elif col is CharacterBody2D: # Pull enemies strongly
			var p_dir = (global_position - col.global_position).normalized()
			# Overpower their movement entirely
			var pull_strength = 600.0 * ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0)
			col.velocity = col.velocity.lerp(p_dir * pull_strength, 10.0 * delta)
			# Physically drag them if they are close enough to ignore friction
			col.global_position = col.global_position.lerp(global_position, 2.0 * delta * ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0))

func _on_body_entered(body: Node2D):
	if body.get_class() == "CharacterBody2D" and body.has_method("apply_part_damage"):
		return
	_handle_hit(body)

func _on_area_entered(area: Area2D):
	_handle_hit(area)

func _handle_hit(target: Node2D):
	if not target.has_method("apply_damage"):
		return
		
	var dominant_str = "RAW"
	var max_ratio = 0.0
	for k in ratios:
		if ratios[k] > max_ratio:
			max_ratio = ratios[k]
			match k:
				EnergyPacket.SynergyType.FIRE: dominant_str = "FIRE"
				EnergyPacket.SynergyType.ICE: dominant_str = "ICE"
				EnergyPacket.SynergyType.KINETIC: dominant_str = "KINETIC"
				EnergyPacket.SynergyType.VORTEX: dominant_str = "VORTEX"
				EnergyPacket.SynergyType.LIGHTNING: dominant_str = "LIGHTNING"
				EnergyPacket.SynergyType.POISON: dominant_str = "POISON"
				EnergyPacket.SynergyType.EXPLOSION: dominant_str = "EXPLOSION"
				EnergyPacket.SynergyType.PIERCE: dominant_str = "PIERCE"
				EnergyPacket.SynergyType.VAMPIRIC: dominant_str = "VAMPIRIC"
				
	# Apply Base Damage
	target.apply_damage(damage, dominant_str)
	
	# Apply Status Effects
	if ratios.get(EnergyPacket.SynergyType.FIRE, 0.0) > 0.1 and target.has_method("apply_status"):
		target.apply_status("burning", 3.0 * ratios[EnergyPacket.SynergyType.FIRE])
	if ratios.get(EnergyPacket.SynergyType.ICE, 0.0) > 0.1 and target.has_method("apply_status"):
		target.apply_status("frozen", 3.0 * ratios[EnergyPacket.SynergyType.ICE])
		
	# Vampiric Heal
	if ratios.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0) > 0.1:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0 and players[0].has_method("apply_damage"):
			players[0].apply_damage(-damage * 0.3 * ratios[EnergyPacket.SynergyType.VAMPIRIC])
			
	# Explosion AoE
	if ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0) > 0.1:
		_trigger_explosion()
		
	# --- BIOME SYNERGIES ---
	var maps = get_tree().get_nodes_in_group("map_generator")
	if maps.size() > 0:
		var map = maps[0]
		if map.has_method("get_biome_at_world_pos"):
			var biome = map.get_biome_at_world_pos(global_position)
			
			# Lightning + Water = Massive AoE
			if ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) > 0.1 and biome == map.BiomeType.WATER:
				_trigger_biome_explosion(400.0, damage * 2.0, "lightning")
				
			# Fire + Forest = Burn Trees
			if ratios.get(EnergyPacket.SynergyType.FIRE, 0.0) > 0.1 and biome == map.BiomeType.FOREST:
				_trigger_biome_explosion(200.0, damage * 1.5, "fire")
				# If we hit an obstacle directly, destroy it
				var obs = map.get_node_or_null("Obstacles")
				if obs and target.get_parent() == obs:
					target.queue_free()
	
	pierce_count -= 1
	if pierce_count <= 0:
		queue_free()

func _trigger_explosion():
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 100.0 * ratios[EnergyPacket.SynergyType.EXPLOSION]
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = collision_mask
	var results = space_state.intersect_shape(query)
	for res in results:
		var col = res["collider"]
		if col.has_method("apply_damage"):
			col.apply_damage(damage * 0.5)

func _trigger_biome_explosion(radius: float, dmg: float, type: String):
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = radius
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = collision_mask
	var results = space_state.intersect_shape(query)
	for res in results:
		var col = res["collider"]
		if col.has_method("apply_damage"):
			col.apply_damage(dmg)
			if type == "fire" and col.has_method("apply_status"):
				col.apply_status("burning", 5.0)

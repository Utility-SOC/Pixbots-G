class_name Projectile
extends Area2D


const Trail2D = preload("res://scripts/visuals/Trail2D.gd")
const FireTrail2D = preload("res://scripts/visuals/FireTrail2D.gd")

var base_speed: float = 500.0
var final_speed: float = 500.0
var damage: float = 10.0
var is_crit: bool = false
var direction: Vector2 = Vector2.ZERO
var target_direction: Vector2 = Vector2.ZERO
var synergies: Dictionary = {}
var weapon_rarity: int = 0

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
var source_mech: Node2D = null

# Lightning zig-zag state - jagged, held-and-snapped offsets rather than a
# smooth wave, so it actually reads as a bolt (see the LIGHTNING ZIG-ZAG
# section of _physics_process()).
var _lightning_segment_index: int = -1
var _lightning_prev_offset: float = 0.0
var _lightning_target_offset: float = 0.0

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
		if not is_queued_for_deletion():
			queue_free()
	)
	add_child(timer)
	timer.start()
	
	# OFF-SCREEN CULLING FOR PERFORMANCE
	var vis_notifier = VisibleOnScreenNotifier2D.new()
	vis_notifier.rect = Rect2(-10, -10, 20, 20)
	vis_notifier.screen_exited.connect(func():
		# Add a tiny delay to ensure trail can finish or it doesn't clip immediately at edge
		if not is_queued_for_deletion():
			queue_free()
	)
	add_child(vis_notifier)

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
	
	# Size/Mass (ratio-driven only - magnitude-driven size lives entirely in
	# _build_visuals()'s p_scale below. An earlier pass also added a
	# magnitude factor HERE, which multiplied against p_scale instead of
	# replacing/adding to it - two compounding exponential-ish curves
	# instead of one produced the "comically big" shapes. One authoritative
	# place for magnitude scaling now.)
	var s_mod = 1.0 + r_raw # RAW directly increases volume
	s_mod += 1.5 * r_ice # ICE adds crystalline mass
	s_mod += 2.0 * r_exp # EXPLOSION adds volatility/size
	s_mod -= 0.5 * r_prc # PIERCE makes it sleek
	scale = Vector2(s_mod, s_mod)
	
	# Base Damage Multiplier
	# RAW gives max raw damage, but other elements still give baseline scaling 
	# so that converting RAW into elements doesn't cripple your DPS.
	var base_mult = 1.0 + (r_raw * 1.5) + ((1.0 - r_raw) * 1.0)
	damage *= base_mult
	
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
		
	# Color Blending - Keep vibrancy by picking dominant color and boosting
	final_color = Color(0,0,0,0)
	var max_r = 0.0
	var dom_t = -1
	for k in ratios:
		if k == EnergyPacket.SynergyType.RAW and ratios.size() > 1:
			continue
		if ratios[k] > max_r:
			max_r = ratios[k]
			dom_t = k
	if dom_t != -1:
		final_color = EnergyPacket.get_color_for_synergy(dom_t)
		# Boost vibrancy slightly for additive blending
		final_color = final_color * 1.5
		final_color.a = 1.0
	else:
		final_color = Color.WHITE

	if weapon_rarity == 4: # Mythic
		final_color = Color(0.2, 0.9, 0.9, 1.0) # Shiny teal

	# Chromatic intensity scales with magnitude the same way size does - a
	# massive combined blast should visually READ as more powerful, not
	# just bigger. Additive blending (see _build_visuals) makes an
	# overbright color actually glow harder rather than just clip to white.
	var intensity = 1.0 + sqrt(total_power / 500.0) * 0.3
	final_color = final_color * intensity
	final_color.a = 1.0

func _build_visuals():
	visual_node = Node2D.new()
	add_child(visual_node)
	var add_mat = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	visual_node.material = add_mat
	
	# Determine dominant and secondary synergies for shape generation
	var sorted_synergies = []
	for k in synergies:
		if k == EnergyPacket.SynergyType.RAW and synergies.size() > 1:
			continue # Ignore RAW if we have other synergies
		sorted_synergies.append({"type": k, "power": synergies[k]})
	sorted_synergies.sort_custom(func(a, b): return a.power > b.power)
	
	var dominant = -1
	var secondary = -1
	if sorted_synergies.size() > 0: dominant = sorted_synergies[0].type
	if sorted_synergies.size() > 1: secondary = sorted_synergies[1].type
	
	# Procedural Shape based on Dominant Element - this is the ONE place
	# magnitude drives visual size (see _calculate_stats() for why it's not
	# also duplicated there anymore). Log growth is gentle/self-limiting on
	# its own (only reaches ~4.3 even at the 150,000 magnitude ceiling), so
	# this cap is mostly just a hard safety ceiling, not the thing actually
	# doing the limiting day to day.
	var p_scale = 1.0 + log(1.0 + total_power / 200.0) * 0.5
	p_scale = min(p_scale, 5.0)
	
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
		# Spreading fire trail
		var fire_trail = FireTrail2D.new()
		fire_trail.scale_amount_min *= p_scale
		fire_trail.scale_amount_max *= p_scale
		# Use MIX instead of ADD so the black soot is visible
		var mix_mat = CanvasItemMaterial.new()
		mix_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
		fire_trail.material = mix_mat
		visual_node.add_child(fire_trail)
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
	elif dominant == EnergyPacket.SynergyType.VAMPIRIC:
		# Blood drop shape
		var poly = Polygon2D.new()
		poly.polygon = PackedVector2Array([
			Vector2(8, 0), Vector2(-4, 6), Vector2(-2, 0), Vector2(-4, -6)
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
	elif dominant == EnergyPacket.SynergyType.RAW or dominant == -1:
		# Glowing Raw Energy Sphere
		var circ = Polygon2D.new()
		var pts = PackedVector2Array()
		for i in range(16):
			var a = i * PI / 8.0
			pts.append(Vector2(cos(a), sin(a)) * 5.0 * p_scale)
		circ.polygon = pts
		circ.color = final_color
		visual_node.add_child(circ)
		
	# Secondary Element modifies properties
	if secondary == EnergyPacket.SynergyType.POISON:
		# Toxic trail
		var trail = GPUParticles2D.new()
		trail.amount = 20
		var process_mat = ParticleProcessMaterial.new()
		process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		process_mat.emission_sphere_radius = 4.0
		process_mat.gravity = Vector3(0, 10, 0)
		process_mat.color = Color(0.2, 0.8, 0.2, 0.5)
		trail.process_material = process_mat
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
				var h = Polygon2D.new()
				var pts = PackedVector2Array()
				for i in range(8):
					var a = i * PI / 4.0
					pts.append(Vector2(cos(a), sin(a)) * 2.0)
				h.polygon = pts
				h.color = EnergyPacket.get_color_for_synergy(k)
				visual_node.add_child(h)
				helix_particles.append({
					"node": h,
					"phase": helix_particles.size() * PI,
					"speed": 10.0 + ratios[k] * 10.0,
					"radius": (8.0 + ratios[k] * 12.0) * p_scale
				})
	
	# Kinetic Trail
	if ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0) > 0.1:
		var trail = Trail2D.new()
		trail.width = 4.0
		trail.default_color = final_color * Color(1,1,1,0.5)
		visual_node.add_child(trail)
		
	# Vortex Helix Orbs
	if ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0) > 0.05:
		for i in range(3):
			var orb = Polygon2D.new()
			var pts = PackedVector2Array()
			for j in range(8):
				var a = j * PI / 4.0
				pts.append(Vector2(cos(a), sin(a)) * 2.0)
			orb.polygon = pts
			orb.color = EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.VORTEX)
			visual_node.add_child(orb)
			helix_particles.append({
				"node": orb,
				"phase": i * (PI * 2.0 / 3.0),
				"speed": 15.0,
				"radius": 8.0
			})

	# Apply glowing material to all visuals
	var mat = visual_node.material
	for child in visual_node.get_children():
		if child is CanvasItem and child.material == null:
			child.material = mat
			
	if weapon_rarity == 4: # Mythic
		var glow = Polygon2D.new()
		glow.name = "MythicGlow"
		var pts = PackedVector2Array()
		for i in range(16):
			var a = i * PI / 8.0
			pts.append(Vector2(cos(a), sin(a)) * 12.0 * p_scale)
		glow.polygon = pts
		glow.color = Color(0.2, 1.0, 1.0, 0.2)
		visual_node.add_child(glow)


func _process(delta):
	if weapon_rarity == 4 and visual_node:
		var glow = visual_node.get_node_or_null("MythicGlow")
		if glow:
			glow.scale = Vector2.ONE * (1.0 + sin(time_alive * 8.0) * 0.15)
			glow.color.a = 0.2 + sin(time_alive * 5.0) * 0.1

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
	if is_homing or r_vamp > 0.0:
		var closest = null
		var min_dist = 400.0 + (300.0 * r_vamp)
		if r_ltg > 0.0 and r_vamp > 0.0:
			min_dist += 500.0 * r_ltg # Lightning + Vampiric massively increases targeting range
			
		var query = PhysicsShapeQueryParameters2D.new()
		var shape = CircleShape2D.new()
		shape.radius = min_dist
		query.shape = shape
		query.transform = global_transform
		query.collision_mask = 4 if collision_mask & 4 else 8
		var results = space_state.intersect_shape(query)
		
		# If Kinetic + Vampiric, look for FURTHEST target to maximize pierce potential
		if r_kin > 0.0 and r_vamp > 0.0:
			var max_dist = 0.0
			for res in results:
				var col = res["collider"]
				if col.has_method("apply_damage"):
					var d = global_position.distance_to(col.global_position)
					if d > max_dist:
						max_dist = d
						closest = col
		else:
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
		var turn_speed = (8.0 * r_vamp) / steering_resistance
		if r_kin > 0.0:
			# Kinetic makes it turn slower but move faster (already handled by speed/resistance)
			pass
		direction = direction.lerp(target_direction, turn_speed * delta).normalized()
		
		# If Kinetic + Vampiric, grant pierce based on kinetic ratio
		if r_kin > 0.0 and r_vamp > 0.0:
			r_prc = max(r_prc, 0.5) # Force granting pierce
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
	# Was a smooth sin(t*40)*cos(t*25) beat pattern, which reads as a slow
	# side-to-side wobble rather than a bolt. Real lightning is jagged and
	# irregular, so instead we hold a random lateral offset for a short
	# segment, then snap-lerp to the next one - sharp direction changes,
	# no smooth oscillation.
	if r_ltg > 0.0:
		var segment_length = 0.045
		var segment_index = int(time_alive / segment_length)
		if segment_index != _lightning_segment_index:
			_lightning_segment_index = segment_index
			_lightning_prev_offset = _lightning_target_offset
			var seed = int(hash(get_instance_id())) ^ segment_index
			_lightning_target_offset = (float(abs(seed) % 2000) / 1000.0) - 1.0 # deterministic pseudo-random in [-1, 1]
		var seg_t = clamp(fmod(time_alive, segment_length) / segment_length, 0.0, 1.0)
		# Ease sharply so it snaps rather than glides between segments
		seg_t = seg_t * seg_t
		var lightning_wave = lerp(_lightning_prev_offset, _lightning_target_offset, seg_t)
		visual_offset += ortho * lightning_wave * (26.0 * r_ltg)
	
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
func _pull_nearby_items(delta: float):
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 150.0 + 100.0 * ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0)
	query.shape = shape
	query.transform = global_transform
	
	# Always pull Loot (16), Enemies (4), and Player (8)
	query.collision_mask = 16 | 4 | 8
		
	var results = space_state.intersect_shape(query)
	for res in results:
		var col = res["collider"]
		if col == self: continue
		
		var pull_mult = 3.0 # Targets get pulled 300% as hard
		if "is_player" in col:
			if fired_by_player and col.is_player:
				pull_mult = 0.05 # Shooter is barely affected
			elif not fired_by_player and not col.is_player:
				pull_mult = 0.05 # Shooter is barely affected
				
		var pull_strength = 600.0 * ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0) * pull_mult
		
		if col.has_method("pull_towards"):
			col.pull_towards(global_position, delta, pull_strength)
		elif col is CharacterBody2D: # Fallback
			var p_dir = (global_position - col.global_position).normalized()
			var lerp_weight = 10.0 * delta
			if lerp_weight > 1.0: lerp_weight = 1.0
			col.velocity = col.velocity.lerp(p_dir * pull_strength, lerp_weight)

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
	
	# Massive Damage Screen Shake on Hit
	if fired_by_player and target.is_in_group("enemy") and damage >= 10000000.0:
		var cam = get_tree().get_first_node_in_group("camera")
		if cam and cam.has_method("shake"):
			var intensity = clamp(damage / 5000000.0, 1.5, 5.0)
			cam.shake(intensity, 0.4)
	
	if is_crit and target.get_parent():
		var lbl = Label.new()
		lbl.text = "CRIT!"
		lbl.modulate = Color(1.0, 0.2, 0.2)
		lbl.scale = Vector2(1.5, 1.5)
		lbl.z_index = 100
		lbl.global_position = target.global_position + Vector2(-20, -40)
		target.get_parent().add_child(lbl)
		var tw = lbl.create_tween()
		tw.tween_property(lbl, "global_position", lbl.global_position + Vector2(0, -60), 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.8).set_ease(Tween.EASE_IN)
		tw.tween_callback(lbl.queue_free)
		
	if is_instance_valid(source_mech) and source_mech.has_signal("dealt_damage") and target != source_mech:
		source_mech.dealt_damage.emit(damage)
	
	# Apply Status Effects
	if ratios.get(EnergyPacket.SynergyType.FIRE, 0.0) > 0.1 and target.has_method("apply_status"):
		target.apply_status("burning", 3.0 * ratios[EnergyPacket.SynergyType.FIRE])
	if ratios.get(EnergyPacket.SynergyType.ICE, 0.0) > 0.1 and target.has_method("apply_status"):
		target.apply_status("frozen", 3.0 * ratios[EnergyPacket.SynergyType.ICE])
		
	# Lightning Arcing - chains through multiple enemies in sequence (not
	# just one jump), each hop dealing falloff damage. Hop count and jump
	# radius both scale with how much of the packet was actually Lightning.
	var r_ltg = ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0)
	if r_ltg > 0.05 and target.is_in_group("enemy"):
		var max_hops = 1 + int(round(4.0 * r_ltg)) # up to 5 hops at 100% lightning
		var jump_radius = 350.0 * r_ltg
		var already_hit: Array = [target]
		var chain_from_pos = global_position
		var chain_damage = damage * 0.5

		for hop in range(max_hops):
			var space_state = get_world_2d().direct_space_state
			var query = PhysicsShapeQueryParameters2D.new()
			var shape = CircleShape2D.new()
			shape.radius = jump_radius
			query.shape = shape
			query.transform = Transform2D(0, chain_from_pos)
			query.collision_mask = 4 if collision_mask & 4 else 8
			var results = space_state.intersect_shape(query)

			var closest = null
			var min_dist = shape.radius
			for res in results:
				var col = res["collider"]
				if col in already_hit: continue
				if col.has_method("apply_damage") and col.is_in_group("enemy"):
					var d = chain_from_pos.distance_to(col.global_position)
					if d < min_dist:
						min_dist = d
						closest = col

			if not closest:
				break

			_draw_lightning_arc(chain_from_pos - global_position, closest.global_position - global_position)
			closest.apply_damage(chain_damage, "LIGHTNING")

			already_hit.append(closest)
			chain_from_pos = closest.global_position
			chain_damage *= 0.7 # each additional hop falls off
			
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

# Draws one jagged bolt segment between two points, LOCAL to visual_node
# (i.e. relative to the projectile's own position at the moment of the
# hit). Used per-hop by the lightning chain above. Multiple offset
# midpoints (not just one) so it reads as an actual bolt rather than a
# single bent line.
func _draw_lightning_arc(from_local: Vector2, to_local: Vector2):
	var arc = Line2D.new()
	arc.width = 4.0
	arc.default_color = EnergyPacket.get_color_for_synergy(EnergyPacket.SynergyType.LIGHTNING)

	var span = to_local - from_local
	var length = span.length()
	var ortho = Vector2(-span.y, span.x).normalized() if length > 0.01 else Vector2.RIGHT

	var points = PackedVector2Array([from_local])
	if length > 30.0:
		var segments = clamp(int(length / 40.0), 1, 5)
		for i in range(1, segments):
			var t = float(i) / segments
			var jitter = ortho * randf_range(-length * 0.18, length * 0.18)
			points.append(from_local.lerp(to_local, t) + jitter)
	points.append(to_local)
	arc.points = points

	visual_node.add_child(arc)
	var tw = arc.create_tween()
	tw.tween_property(arc, "modulate:a", 0.0, 0.2)
	tw.tween_callback(arc.queue_free)

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

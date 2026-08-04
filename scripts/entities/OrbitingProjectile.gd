class_name OrbitingProjectile
extends Area2D

const LIFETIME = 14.0

var source_mech: Node = null
var damage: float = 0.0
var synergies: Dictionary = {}
var by_player: bool = true
var orbit_time: float = 0.0
var base_angle: float = 0.0
var is_active: bool = true
var dominant_synergy: int = EnergyPacket.SynergyType.RAW

var _trail_timer: float = 0.0
var _lash_timer: float = 0.0

func setup(p_source: Node, p_damage: float, p_synergies: Dictionary, p_by_player: bool, p_angle_offset: float = 0.0):
	source_mech = p_source
	damage = p_damage
	synergies = p_synergies
	by_player = p_by_player
	base_angle = p_angle_offset

	# Highest-magnitude synergy drives the orbit style (EnergyPacket.
	# get_dominant_synergy is an instance method on a packet; here we only
	# have the bare synergies Dictionary, so run the same scan directly).
	dominant_synergy = EnergyPacket.SynergyType.RAW
	var max_val = -1.0
	for k in synergies:
		if synergies[k] > max_val:
			max_val = synergies[k]
			dominant_synergy = k

func _ready():
	collision_layer = 0
	collision_mask = 4 if by_player else 8 # Enemies if by player, Player if enemy
	
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 14.0
	col.shape = shape
	add_child(col)
	
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

	var timer = get_tree().create_timer(LIFETIME)
	timer.timeout.connect(queue_free)

	# Registers with the SAME live-count census every other weapon's
	# saturation tiers key off (ProjectileManager.consolidation_factor()/
	# lite_visuals()) - this class predates that system and never joined it,
	# so a screen full of orbiting projectiles was invisible to it: other
	# weapons' consolidation never accounted for the load these add, and
	# these themselves never got the flight-math batching treatment either.
	# _prepare_flight_request below opts out of the batching half (orbital
	# motion isn't a linear flight path the Rust batch understands) while
	# still being counted for saturation purposes.
	ProjectileManager.register(self)

func _exit_tree():
	ProjectileManager.unregister(self)

# Never batched (see _ready's comment) - registering only for the live-
# count census, not the flight-math dispatch.
func _prepare_flight_request(_delta: float):
	return null

func _process(delta: float):
	if not is_instance_valid(source_mech):
		queue_free()
		return
		
	orbit_time += delta
	_update_orbital_position(delta)
	_handle_synergy_effects(delta)
	queue_redraw()

func _update_orbital_position(delta: float):
	var center = source_mech.global_position
	var target_pos = center
	
	match dominant_synergy:
		EnergyPacket.SynergyType.KINETIC, EnergyPacket.SynergyType.PIERCE:
			# Fast, tight elliptical orbit spinning rapidly around the Mech
			var speed = 4.5
			var angle = base_angle + orbit_time * speed
			var rx = 120.0 + 35.0 * cos(orbit_time * 2.5)
			var ry = 75.0 + 25.0 * sin(orbit_time * 2.5)
			target_pos = center + Vector2(cos(angle) * rx, sin(angle) * ry)
			
		EnergyPacket.SynergyType.VORTEX:
			# Eccentric Bezier-blob orbit with fluid, organic distance shifts
			var speed = 2.2
			var angle = base_angle + orbit_time * speed
			var r = 110.0 + 45.0 * sin(orbit_time * 1.8) + 25.0 * cos(orbit_time * 3.3)
			target_pos = center + Vector2(cos(angle), sin(angle)) * r
			
		EnergyPacket.SynergyType.LIGHTNING:
			# Orbiting bolt stays close (75px). Lashes out when enemy nearby.
			var speed = 3.0
			var angle = base_angle + orbit_time * speed
			target_pos = center + Vector2(cos(angle), sin(angle)) * 75.0
			_lash_timer -= delta
			if _lash_timer <= 0.0:
				_lash_timer = 0.35 # rate-limit: per-frame lashes would melt anything in range
				_check_lightning_lash()
			
		EnergyPacket.SynergyType.POISON:
			# Sweeping orbit leaving decaying poison trails behind it
			var speed = 2.0
			var angle = base_angle + orbit_time * speed
			var r = 130.0 + 20.0 * sin(orbit_time * 1.4)
			target_pos = center + Vector2(cos(angle), sin(angle)) * r
			
		_:
			# Default smooth circular/elliptical orbital defense
			var speed = 2.8
			var angle = base_angle + orbit_time * speed
			target_pos = center + Vector2(cos(angle), sin(angle)) * 105.0
			
	global_position = target_pos

func _handle_synergy_effects(delta: float):
	if dominant_synergy == EnergyPacket.SynergyType.POISON:
		_trail_timer += delta
		if _trail_timer >= 0.2:
			_trail_timer = 0.0
			_spawn_poison_pool()

func _spawn_poison_pool():
	var world = get_parent()
	if not world: return
	var OilSlickScript = load("res://scripts/hazards/OilSlickHazard.gd")
	if OilSlickScript:
		var pool = OilSlickScript.new()
		pool.global_position = global_position
		# Temporary trail marker, not a permanent map decal - OilSlickHazard
		# defaults to permanent (lifetime 0.0) for MapGenerator's sparse
		# placement; this spawns one every 0.2s for up to this projectile's
		# whole 14s LIFETIME, which left permanent would leak dozens of
		# un-freed nodes per shot (real report: FPS collapsing well after
		# combat ended, from the accumulated leftovers, not anything
		# currently happening).
		pool.lifetime = 5.0
		world.add_child(pool)

func _check_lightning_lash():
	var space = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 220.0
	query.shape = circle
	query.transform = global_transform
	query.collision_mask = 4 if by_player else 8
	
	var results = space.intersect_shape(query)
	for res in results:
		var col = res["collider"]
		if col != source_mech and col.has_method("apply_damage"):
			col.apply_damage(damage * 0.4, "LIGHTNING", source_mech)

func _on_body_entered(body: Node2D):
	if body == source_mech: return
	if body.has_method("apply_damage"):
		body.apply_damage(damage, EnergyPacket.element_name(dominant_synergy), source_mech)
		queue_free()

func _on_area_entered(area: Area2D):
	# Intercept and destroy incoming enemy projectiles
	if area is Projectile and area.get("fired_by_player") != by_player:
		area.queue_free()
		queue_free()

func _draw():
	var color = EnergyPacket.get_color_blend(synergies) if not synergies.is_empty() else Color(0.2, 0.8, 1.0)
	draw_circle(Vector2.ZERO, 14.0, Color(color.r, color.g, color.b, 0.4))
	draw_circle(Vector2.ZERO, 9.0, Color(color.r, color.g, color.b, 0.85))
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 1.0, 0.95))

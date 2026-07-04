class_name Mech
extends CharacterBody2D

const CoreTile = preload("res://scripts/tiles/CoreTile.gd")
const ComponentEquipment = preload("res://scripts/core/ComponentEquipment.gd")
const ComponentLinkTile = preload("res://scripts/tiles/ComponentLinkTile.gd")
const JumpjetResidue = preload("res://scripts/attacks/JumpjetResidue.gd")
# Explicit preload rather than relying on the global class_name cache -
# SolverProfile is used below as a bare type hint (var spawn_profile:
# SolverProfile), which needs this to resolve reliably even if the editor's
# global script class cache hasn't been refreshed since the file was added.
const SolverProfile = preload("res://scripts/ai/SolverProfile.gd")

var max_hp: float = 100.0
var hp: float = 100.0
var shield_hp: float = 0.0
var max_shield_hp: float = 0.0
var shield_synergies: Dictionary = {}
var dominant_shield_synergy: String = ""

var shield_recharge_delay: float = 3.0
var time_since_last_hit: float = 0.0
var shield_recharge_rate: float = 0.0
var has_shield_generator: bool = false

var current_move_speed: float = 200.0
var base_move_speed: float = 200.0
var combat_role: String = "melee"

var status_effects: Dictionary = {}
var stat_modifiers: Dictionary = {}
# Element of the most recent damaging hit - reported by die() as the
# player's kill method (see SquadDirector.log_player_kill).
var last_damage_element: String = "RAW"
# Where a VORTEX hit is dragging us toward (see "vortexed" status).
var vortex_drag_point: Vector2 = Vector2.ZERO
# Mythic tile modes collected during _recalculate_grid:
var magnet_repel_mode: bool = false   # Mythic Magnet flipped to Repel
var jumpjet_blink_mode: bool = false  # Mythic Jumpjet set to Blink
var _blink_cooldown: float = 0.0
var jumpjet_rarity: int = -1
var jumpjet_energy = null
var actuator_energy = null

# --- Cloak (Ambusher backpack ability) ---
# Capacity/recharge-rate are sized once per _recalculate_grid() from
# CloakTile energy (same pattern as the shield generator); the actual
# charge/drain while playing is a simple runtime timer, independent of the
# hex-grid packet simulation (unlike jumpjet_energy, which only refills on
# equip changes - not something we want cloak to inherit).
var has_cloak_generator: bool = false
var max_cloak_charge: float = 0.0
var cloak_charge: float = 0.0
var cloak_recharge_rate: float = 0.0
var cloak_recharge_delay: float = 1.0
var cloak_drain_rate: float = 0.0
var is_cloaked: bool = false
var time_since_cloak_break: float = 999.0

# --- Jammer Module (equippable pulse ability - distinct from the JammerMech
# role, which is a whole separate continuous-aura mech class) ---
var has_jammer_module: bool = false
var jammer_pulse_radius: float = 0.0
var jammer_pulse_interval: float = 8.0
var jammer_effect_duration: float = 2.0
var jammer_mode: int = 0 # 0 = VISION (blackout player screen), 1 = SYNERGY (mute one element)
var jammer_target_synergy: int = 0
var jammer_pulse_timer: float = 0.0

# --- Heal Beacon (Support backpack ability) ---
var has_healer: bool = false
var heal_pulse_power: float = 0.0
var heal_pulse_radius: float = 0.0
var heal_pulse_interval: float = 4.0
var heal_pulse_timer: float = 0.0

# Synergies actively muted on THIS mech by an enemy Jammer Module, mapped to
# remaining duration. Consulted when firing to suppress that element.
var jammed_synergies: Dictionary = {}

signal vision_jammed(duration: float)

func apply_shield_energy(amount: float):
	max_shield_hp += amount # Max shield grows based on energy it processes!
	shield_hp = max_shield_hp

var is_player: bool = false
var is_firing_outward: bool = false
var last_aim_position: Vector2 = Vector2.ZERO

var current_jammer_debuff: float = 1.0 # 1.0 is no debuff. 0.1 is 90% power reduction

var jumpjet_trail = null
var jumpjet_residue_timer: float = 0.0
var magnet_visual: Line2D = null


var fire_cooldown: float = 0.0
var fire_rate: float = 0.25 # 4 shots per second

var components: Dictionary = {} # Dict of HexTile.BodySlot -> ComponentEquipment
var is_grid_dirty: bool = true
var precalculated_weapons: Array = []
var _renderer: Node2D = null # cached MechRenderer child, set in _ready()

var is_drowning: bool = false
var drown_timer: float = 1.0

var current_path: PackedVector2Array = []
var path_update_timer: float = 0.0

# Advanced AI Tactics
var target: Node2D = null
var speed_modifier: float = 1.0
var engagement_distance: float = 200.0 # How close to get before strafing
var rotational_direction: float = 1.0 # 1.0 for clockwise, -1.0 for counter-clockwise
var base_speed: float = 150.0

var separate_arm_firing: bool = false
var base_rarity: int = 0 # HexTile.Rarity.COMMON
# Set by SquadDirector before add_child() (same pattern as combat_role/
# base_rarity below) so build_loadout_for_role() can hand it to
# AutoEquipSolver. Null means "use the solver's old fixed-priority
# behavior" - safe default for anything that doesn't set this.
var spawn_profile: SolverProfile = null
var is_boss: bool = false
var total_magnetic_power: float = 0.0
# -1 = attract loot of any rarity (default). Set by a Mythic Magnet's
# min_attract_rarity filter - see MagnetTile.gd.
var min_loot_attract_rarity: int = -1
var visual_seed: int = 0

signal dealt_damage(amount: float)
signal died()
signal fled_to_wild(bot: Node)

var is_dead: bool = false


func apply_jammer_debuff(power_multiplier: float):
	# Take the most severe debuff if multiple jammers are present
	current_jammer_debuff = min(current_jammer_debuff, power_multiplier)

func _ready():
	# Build default body
	equip_component(ComponentEquipment.create_starter_torso(combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_arm(true, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_arm(false, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_leg(true, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_leg(false, combat_role if not is_player else "", base_rarity))
	equip_component(ComponentEquipment.create_starter_head(combat_role if not is_player else "", base_rarity))
	equip_component(_create_role_backpack(combat_role if not is_player else "", base_rarity))

	if not is_player:
		visual_seed = randi()
	
	if not is_player:
		build_loadout_for_role(combat_role)
	
	# Attach Visual Renderer
	var renderer = load("res://scripts/visuals/MechRenderer.gd").new()
	renderer.name = "MechRenderer"
	add_child(renderer)
	_renderer = renderer

	# Pass the full components dict so the renderer can draw each piece
	renderer.components = components
	renderer._rebuild_visuals()
	
	# Collision shape - sized to match this mech's actual visual scale
	# (role-based, e.g. scout renders ~0.8x, brawler ~1.2x, boss up to 1.8x
	# before the extra mega/regular boss node-scale on top) rather than
	# every role sharing the same fixed 40x40 box regardless of how big or
	# small it actually looks on screen.
	var hitbox_scale = renderer.get_role_scale(combat_role, is_player)
	var collision = CollisionShape2D.new()
	var shape = RectangleShape2D.new()
	shape.size = Vector2(40, 40) * hitbox_scale
	collision.shape = shape
	add_child(collision)
	
	if is_player:
		collision_layer = 8 # Layer 4 (Player)
		collision_mask = 1 | 2 | 4 | 16 # Env, Water, Enemy, Loot
	else:
		collision_layer = 4 # Layer 3 (Enemy)
		collision_mask = 1 | 2 | 8 # Env, Water, Player
		# NOTE: this was previously missing entirely, which silently broke
		# every system that looks up get_nodes_in_group("enemy"): Main.gd's
		# enemy cleanup on player death, Projectile.gd's lightning-arc
		# targeting, and now the Heal Beacon's ally lookup.
		add_to_group("enemy")

# Special-ability backpacks for specific roles (cloak for ambushers, an
# occasional jammer module for scouts, heal beacon for support). Falls back
# to the plain default backpack otherwise. Kept as a thin dispatcher so
# adding a new role ability later is a one-line match arm.
func _create_role_backpack(role: String, p_rarity: int) -> ComponentEquipment:
	match role:
		"ambusher":
			if randf() < 0.85: # not guaranteed, keeps some loot variety
				return ComponentEquipment.create_cloak_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON))
		"scout":
			if randf() < 0.25: # infrequent, per design request
				return ComponentEquipment.create_jammer_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON))
		"support":
			return ComponentEquipment.create_support_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON))
		"commander":
			return ComponentEquipment.create_command_backpack(max(p_rarity, HexTile.Rarity.RARE))
	return ComponentEquipment.create_starter_backpack(role, p_rarity)

func equip_component(comp: ComponentEquipment):
	if comp.slot_type == HexTile.BodySlot.TORSO:
		var h0 = HexCoord.new(0, 0)
		var has_core = false
		if comp.hex_grid.has_tile(h0):
			var existing = comp.hex_grid.get_tile(h0)
			if existing and existing.tile_type == "Core Reactor":
				has_core = true
			else:
				comp.hex_grid.remove_tile(h0)
		if not has_core:
			var core_tile = load("res://scripts/tiles/CoreTile.gd").new()
			core_tile.body_slot = HexTile.BodySlot.TORSO
			comp.hex_grid.add_tile(h0, core_tile)
			
	components[comp.slot_type] = comp
	add_child(comp)
	is_grid_dirty = true
	
func unequip_component(slot: HexTile.BodySlot) -> ComponentEquipment:
	if components.has(slot):
		var comp = components[slot]
		components.erase(slot)
		remove_child(comp)
		is_grid_dirty = true
		return comp
	return null

func _physics_process(delta: float):
	current_jammer_debuff = 1.0 # Reset every frame, JammerMech will re-apply it before we shoot if near
	
	if is_drowning:
		drown_timer -= delta
		scale = Vector2.ONE * (drown_timer)
		modulate.a = drown_timer
		if drown_timer <= 0:
			die()
		return
		
	update_status_effects(delta)

	if fire_cooldown > 0:
		fire_cooldown -= delta

	_tick_weapon_charges(delta)
	_update_heat(delta)
		
	time_since_last_hit += delta
	if has_shield_generator and max_shield_hp > 0 and time_since_last_hit >= shield_recharge_delay:
		if shield_hp < max_shield_hp:
			shield_hp = min(max_shield_hp, shield_hp + shield_recharge_rate * delta)

	_update_cloak(delta)
	_update_jammer_module(delta)
	_update_healer(delta)

	if is_player:
		_handle_player_input(delta)
		velocity += external_force
		move_and_slide()
		var lerp_weight = 10.0 * delta
		if lerp_weight > 1.0: lerp_weight = 1.0
		external_force = external_force.lerp(Vector2.ZERO, lerp_weight)
		
		# Magnet Logic
		if total_magnetic_power > 0.0:
			var pull_radius = 150.0 + (total_magnetic_power * 10.0)
			_update_magnet_visual(pull_radius)

			# Mythic Repel mode: the same field, inverted - shoves enemies
			# outward. Loot attraction below still works either way (repel
			# pushes threats, not your paycheck).
			if magnet_repel_mode:
				for enemy in get_tree().get_nodes_in_group("enemy"):
					if not is_instance_valid(enemy):
						continue
					var d = enemy.global_position.distance_to(global_position)
					if d < pull_radius and "external_force" in enemy:
						var away = (enemy.global_position - global_position).normalized()
						enemy.external_force += away * (600.0 + total_magnetic_power * 10.0) * delta

			var loot_nodes = get_tree().get_nodes_in_group("loot")
			for loot in loot_nodes:
				if min_loot_attract_rarity >= 0 and loot.has_method("get_rarity") and loot.get_rarity() < min_loot_attract_rarity:
					continue # Mythic Magnet filter - not shiny enough to bother with
				if loot.global_position.distance_to(global_position) < pull_radius:
					# Pull strength scales with power
					loot.pull_towards(global_position, delta * (0.5 + total_magnetic_power * 0.02))
		elif magnet_visual:
			magnet_visual.visible = false
		
		# Drowning check
		if not Input.is_action_pressed("ui_select"):
			_check_drowning()
		
		if _renderer:
			_renderer.rotate_arms(get_global_mouse_position(), global_position)
			_renderer.animate_legs(velocity, Time.get_ticks_msec() / 1000.0)
	else:
		_execute_ai_tactics(delta)
		velocity += external_force
		move_and_slide()
		var lerp_weight = 10.0 * delta
		if lerp_weight > 1.0: lerp_weight = 1.0
		external_force = external_force.lerp(Vector2.ZERO, lerp_weight)
		
		var is_jumping = false
		if components.has(HexTile.BodySlot.BACKPACK):
			if components[HexTile.BodySlot.BACKPACK].component_name == "Jetpack":
				is_jumping = true
		if not is_jumping:
			_check_drowning()
		
		if target:
			if _renderer:
				_renderer.rotate_arms(target.global_position, global_position)
				_renderer.animate_legs(velocity, Time.get_ticks_msec() / 1000.0)

var external_force: Vector2 = Vector2.ZERO

func pull_towards(target_pos: Vector2, delta: float, strength: float = 600.0):
	var dir = (target_pos - global_position).normalized()
	external_force += dir * strength * delta

# Visual feedback for how far the Magnet is currently reaching - previously
# the pull radius had zero on-screen representation, so there was no way to
# tell how strong/far a magnet build actually was without guessing from feel.
# Gold tint when a Mythic Magnet's rarity filter is active, cyan otherwise.
func _update_magnet_visual(pull_radius: float):
	if not magnet_visual:
		magnet_visual = Line2D.new()
		magnet_visual.z_index = -1
		var pts = PackedVector2Array()
		for i in range(33):
			var a = i * TAU / 32.0
			pts.append(Vector2(cos(a), sin(a)))
		magnet_visual.points = pts
		add_child(magnet_visual)

	magnet_visual.visible = true
	magnet_visual.scale = Vector2.ONE * pull_radius
	var is_filtered = min_loot_attract_rarity >= 0
	var base_color = Color(1.0, 0.85, 0.2) if is_filtered else Color(0.3, 0.9, 1.0)
	var pulse = 0.35 + sin(Time.get_ticks_msec() / 200.0) * 0.15
	magnet_visual.default_color = Color(base_color.r, base_color.g, base_color.b, pulse)
	# The node itself is scaled up to pull_radius to draw the ring at the
	# right size, which would also scale up the line width - counteract
	# that so the ring reads as a consistent ~2px outline regardless of how
	# large the pull radius is.
	magnet_visual.width = 2.0 / max(1.0, pull_radius)

func _check_drowning():
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = global_position
	query.collision_mask = 2 # Water layer
	var result = space_state.intersect_point(query)
	if result.size() > 0:
		# Locked design rule (FEATURE_ROADMAP.md): a mech with jumpjets never
		# drowns - the jets kick on automatically the moment it's over water
		# (including spawning directly onto it) and stay on until dry land.
		if _has_jumpjets():
			_force_jumpjets_on()
			return
		is_drowning = true
		velocity = Vector2.ZERO
	elif _water_hover_active:
		_water_hover_active = false
		if jumpjet_trail:
			for p in jumpjet_trail.get_children():
				p.emitting = false

# Trail creation, shared between sprint (player input) and water-hover
# (both player and AI) - was inlined in _handle_player_input, which meant
# AI mechs could never show a jet trail at all.
func _ensure_jumpjet_trail():
	if jumpjet_trail != null:
		return
	jumpjet_trail = Node2D.new()
	jumpjet_trail.show_behind_parent = true

	var p_l = CPUParticles2D.new()
	p_l.local_coords = false
	p_l.lifetime = 0.5
	p_l.explosiveness = 0.0
	p_l.spread = 180.0
	p_l.initial_velocity_min = 10.0
	p_l.initial_velocity_max = 30.0
	p_l.scale_amount_min = 4.0
	p_l.scale_amount_max = 8.0
	p_l.amount = 10
	p_l.position = Vector2(-14, 44) # Left foot
	jumpjet_trail.add_child(p_l)

	var p_r = p_l.duplicate()
	p_r.position = Vector2(14, 44) # Right foot
	jumpjet_trail.add_child(p_r)

	add_child(jumpjet_trail)

func _has_jumpjets() -> bool:
	if jumpjet_rarity >= 0:
		return true
	if jumpjet_energy and jumpjet_energy.magnitude > 0:
		return true
	if components.has(HexTile.BodySlot.BACKPACK):
		if components[HexTile.BodySlot.BACKPACK].component_name == "Jetpack":
			return true
	return false

# Auto-hover over water: light the jet trail so the save reads visually
# ("why am I not drowning?" - because your jets are visibly firing).
# Runs after _handle_player_input in the frame, so it wins over the
# sprint-off branch while over water; _check_drowning's elif above hands
# control back to the normal sprint logic once on dry land.
var _water_hover_active: bool = false

func _force_jumpjets_on():
	_water_hover_active = true
	_ensure_jumpjet_trail()
	var new_color = EnergyPacket.get_color_blend(jumpjet_energy.synergies) if jumpjet_energy else Color.WHITE
	for p in jumpjet_trail.get_children():
		if p.color != new_color: p.color = new_color
		p.emitting = true

func _handle_player_input(delta: float):
	if jumpjet_energy and jumpjet_energy.magnitude > 0:
		jumpjet_energy.magnitude *= exp(-2.0 * delta) # Decay energy smoothly
		if jumpjet_energy.magnitude < 0.1: jumpjet_energy.magnitude = 0.0
		
	if actuator_energy and actuator_energy.magnitude > 0:
		actuator_energy.magnitude *= exp(-2.0 * delta) # Decay energy smoothly
		if actuator_energy.magnitude < 0.1: actuator_energy.magnitude = 0.0

	# Simple WASD movement
	var input_dir = Vector2.ZERO
	input_dir.x = Input.get_axis("ui_left", "ui_right")
	input_dir.y = Input.get_axis("ui_up", "ui_down")
	
	if input_dir.length() > 0:
		input_dir = input_dir.normalized()
		
	# Calculate base walk multiplier from Actuators
	var actuator_mult = 1.0
	if actuator_energy and actuator_energy.magnitude > 0:
		actuator_mult += (actuator_energy.magnitude / 200.0)
		actuator_mult = min(actuator_mult, 3.5) # User requested max 3.5x for actuator

	# Calculate sprint multiplier from Jumpjets
	var sprint_mult = 0.0
	if Input.is_key_pressed(KEY_SHIFT):
		sprint_mult = 0.5 # Base sprint is +0.5x speed
		if jumpjet_energy and jumpjet_energy.magnitude > 0:
			sprint_mult += (jumpjet_energy.magnitude / 200.0)
			sprint_mult = min(sprint_mult, 2.5) # Up to +2.5x from jumpjets, so jumpjets alone = 3.5x walking speed max
			
		if is_player:
			_ensure_jumpjet_trail()

			var new_color = EnergyPacket.get_color_blend(jumpjet_energy.synergies) if jumpjet_energy else Color.WHITE
			for p in jumpjet_trail.get_children():
				if p.color != new_color: p.color = new_color
				p.emitting = true
				
			if jumpjet_energy and jumpjet_energy.magnitude > 0:
				jumpjet_residue_timer -= delta
				if jumpjet_residue_timer <= 0.0:
					jumpjet_residue_timer = 0.15 # Spawn residue periodically
					var residue = JumpjetResidue.new()
					residue.global_position = global_position
					var dmg = max(10.0, jumpjet_energy.magnitude * 0.1)
					residue.setup(dmg, jumpjet_energy.synergies)
					get_parent().add_child(residue)
	else:
		if jumpjet_trail:
			for p in jumpjet_trail.get_children():
				p.emitting = false

	# Combine multipliers and enforce absolute cap
	var total_mult = actuator_mult + sprint_mult
	total_mult = min(total_mult, 3.8) # User requested max 3.8x for both combined
	
	var actual_move_speed = current_move_speed * total_mult
	var target_vel = input_dir * actual_move_speed
	
	# Scale acceleration much slower to give a feeling of weight
	var accel = 600.0
	if jumpjet_rarity >= 0:
		accel += (jumpjet_rarity * 150.0)
	
	if target_vel == Vector2.ZERO:
		velocity = velocity.move_toward(Vector2.ZERO, accel * delta)
	else:
		velocity = velocity.move_toward(target_vel, accel * delta)
	
	# JumpJets automatically hover over Water (Mask 2) and some obstacles
	if jumpjet_rarity >= 0:
		collision_mask = 1 | 4 | 16 # Only collide with walls/obstacles, Enemy, Loot
	else:
		collision_mask = 1 | 2 | 4 | 16 # Collide with water too
		
	# Mouse Aiming
	var mouse_pos = get_global_mouse_position()
	
	# Firing logic
	var is_left_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var is_right_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	
	# 1/2/3 ARE the fire buttons for the big charged shots (and only those).
	# Edge-triggered: one press = one big hit, if it's ready. The mouse
	# never fires these; they never fire from the mouse. See _fire_charged.
	for key_pair in [[KEY_1, "1"], [KEY_2, "2"], [KEY_3, "3"]]:
		var held = Input.is_key_pressed(key_pair[0])
		if held and not _terakey_held.get(key_pair[1], false):
			_fire_charged(key_pair[1], mouse_pos)
		_terakey_held[key_pair[1]] = held

	# Mythic Jumpjet Blink: Space teleports toward the cursor, capped range,
	# landing snapped to valid ground, on a cooldown.
	if jumpjet_blink_mode:
		_blink_cooldown -= delta
		if Input.is_action_just_pressed("ui_select") and _blink_cooldown <= 0.0:
			_blink_cooldown = 3.0
			var to_cursor = get_global_mouse_position() - global_position
			if to_cursor.length() > 4.0:
				var dest = global_position + to_cursor.normalized() * min(to_cursor.length(), 240.0)
				var maps = get_tree().get_nodes_in_group("map_generator")
				if maps.size() > 0 and maps[0].has_method("get_valid_spawn_position"):
					dest = maps[0].get_valid_spawn_position(dest)
				_ensure_jumpjet_trail()
				for p in jumpjet_trail.get_children():
					p.emitting = true
				global_position = dest
	
	var is_firing = false
	if is_left_pressed and is_right_pressed and not separate_arm_firing:
		_shoot(mouse_pos, true, true, delta)
		is_firing = true
	elif is_left_pressed:
		_shoot(mouse_pos, true, true, delta)
		is_firing = true
	elif is_right_pressed:
		if separate_arm_firing:
			_shoot(mouse_pos, true, false, delta)
		else:
			_shoot(mouse_pos, false, false, delta)
		is_firing = true
		
	# NOTE: no release-fire anymore. Under the pre-prime model charge builds
	# passively, so the old "fire partial charge on mouse release" behavior
	# turned into constant unprompted spray (charge crossed the 10% floor
	# while idling and the next mouse-up frame fired it). Releasing the
	# mouse now does nothing; charge just holds at cap until you shoot.

# Passive background charging - the "pre-prime" model. Every weapon's
# accumulator charge builds all the time, whether or not anyone is holding
# the trigger, capped at one full shot. _shoot() then releases on demand
# like a completely normal gun, and the 1/2/3 keys become an optional
# early dump (fire a partial charge NOW) rather than the only release.
func _tick_weapon_charges(delta: float):
	for data in precalculated_weapons:
		var mount = data.mount
		var required = data.packet.charge_required
		if data.get("bank_mode", "") == "bank":
			if mount.bank_current_charge < required:
				mount.bank_current_charge = min(required, mount.bank_current_charge + delta / max(0.01, fire_rate))
			if mount.bank_current_charge >= required:
				mount.bank_primed = true
				# AI never clicks a mouse: auto-release the bank when full.
				if not is_player:
					var packet_to_fire = data.packet.copy()
					packet_to_fire.magnitude *= current_jammer_debuff
					for k in packet_to_fire.synergies:
						packet_to_fire.synergies[k] *= current_jammer_debuff
					_apply_synergy_jamming(packet_to_fire)
					mount._fire_combined_projectile(self, packet_to_fire, data.step)
					mount.bank_current_charge = 0.0
					heat = max(0.0, heat - required * 0.6) # AI vents on auto-release too
		else:
			if mount.current_charge < required:
				mount.current_charge = min(required, mount.current_charge + delta / max(0.01, fire_rate))

func _shoot(target_pos: Vector2, is_outward: bool, fire_left_arm: bool = true, delta: float = 0.0):
	last_aim_position = target_pos
	is_firing_outward = is_outward

	if is_grid_dirty:
		_recalculate_grid()

	var was_cloaked = is_cloaked
	var fired_a_shot = false

	for data in precalculated_weapons:
		if is_player and separate_arm_firing and data.slot_type != HexTile.BodySlot.BACKPACK:
			if fire_left_arm and data.slot_type == HexTile.BodySlot.ARM_R:
				continue
			if not fire_left_arm and data.slot_type == HexTile.BodySlot.ARM_L:
				continue

		var mount = data.mount
		var bank_mode = data.get("bank_mode", "")
		var required_charge = data.packet.charge_required

		# Charging happens passively in _tick_weapon_charges(). The mouse
		# fires ONLY normal entries - the big charged shot belongs to its
		# 1/2/3 key exclusively (_fire_charged). Two independent weapons
		# sharing one barrel.
		if bank_mode == "bank":
			continue

		if mount.current_charge < required_charge:
			continue

		# While the big shot is still charging, the accumulator siphons
		# HALF of every normal shot's payload. Once the bank sits full
		# (waiting on its key), the siphon stops - full-strength fire.
		var siphon = 1.0
		if bank_mode == "normal":
			var bank_required = float(data.get("bank_required", 0.0))
			if bank_required > 0.0 and mount.bank_current_charge < bank_required:
				siphon = 0.5

		var packet_to_fire = data.packet.copy()
		# The "almost as if there were no accumulator": normal fire pays
		# the small quality tax (shrinks with accumulator rarity/level).
		var tax = data.packet.accumulator_quality * current_jammer_debuff * siphon
		packet_to_fire.magnitude *= tax
		for k in packet_to_fire.synergies:
			packet_to_fire.synergies[k] *= tax
		_apply_synergy_jamming(packet_to_fire)
		if was_cloaked:
			packet_to_fire.magnitude *= 2.5

		mount._fire_combined_projectile(self, packet_to_fire, data.step)
		mount.current_charge -= required_charge
		# Thermal venting: firing sheds heat proportional to the volley
		heat = max(0.0, heat - required_charge * 0.6)
		fired_a_shot = true

	if fired_a_shot and was_cloaked:
		_break_cloak()

# Last-frame state of the 1/2/3 keys for edge detection (one press = one
# big shot, see _fire_charged / _handle_player_input).
var _terakey_held: Dictionary = {}

# Fire the big charged accumulator shot bound to `key`. This is the ONLY
# player-side release path for bank entries: press once, it fires if fully
# charged; if it isn't ready yet you get a charge readout instead of a
# wasted squib. No quality tax here - the big hit always lands full value.
func _fire_charged(key: String, target_pos: Vector2):
	last_aim_position = target_pos
	is_firing_outward = true

	for data in precalculated_weapons:
		if data.get("bank_mode", "") != "bank":
			continue
		if data.packet.trigger_key != key:
			continue
		var mount = data.mount
		var required = data.packet.charge_required

		if mount.bank_current_charge < required:
			_show_floating_text("Charging %d%%" % int(100.0 * mount.bank_current_charge / max(0.001, required)), Color(0.6, 0.8, 1.0))
			continue

		var packet_to_fire = data.packet.copy()
		packet_to_fire.magnitude *= current_jammer_debuff
		for k in packet_to_fire.synergies:
			packet_to_fire.synergies[k] *= current_jammer_debuff
		_apply_synergy_jamming(packet_to_fire)
		if is_cloaked:
			packet_to_fire.magnitude *= 2.5
			_break_cloak()

		mount._fire_combined_projectile(self, packet_to_fire, 0)
		mount.bank_current_charge = 0.0
		heat = max(0.0, heat - required * 0.6) # big shot = big heat dump

# --- Lightweight heat, v1 (FEATURE_ROADMAP.md group 5, locked spec) --------
# No live packet simulation: heat is ONE scalar per mech, derived from the
# static grid sim. Everything is proportional to totals (Natalia's ruling):
#   - generation rate ~ sum of charge_required across armed weapons
#   - venting ~ the volley just released
#   - volatility severity ~ current heat
# ICE-dominant circuits actively cool (can fully solve heat); LIGHTNING-
# heavy circuits arc into adjacent tiles when hot; hitting the cap knocks
# out an Accumulator via the existing disable/reboot machinery.
const HEAT_CAPACITY = 100.0
var heat: float = 0.0
var heat_rate: float = 0.0      # computed in _recalculate_grid
var heat_ice_frac: float = 0.0
var heat_ltg_frac: float = 0.0
var _heat_arc_timer: float = 0.0

func _update_heat(delta: float):
	if precalculated_weapons.is_empty():
		heat = max(0.0, heat - 10.0 * delta)
		return

	# Generation minus constant ambient dissipation. heat_rate can already
	# be negative (ICE cooling), so heavily iced builds pin to 0 here.
	heat = clamp(heat + (heat_rate - 2.0) * delta, 0.0, HEAT_CAPACITY)

	# LIGHTNING volatility: above 70% heat, lightning-heavy storage arcs
	# into the grid - severity proportional to current heat.
	if heat > HEAT_CAPACITY * 0.7 and heat_ltg_frac > 0.3:
		_heat_arc_timer -= delta
		if _heat_arc_timer <= 0.0:
			_heat_arc_timer = 2.0
			_heat_arc_damage()

	if heat >= HEAT_CAPACITY:
		_overheat()

func _heat_arc_damage():
	# Shock a random tile in a random component - reuses the standard
	# take_damage -> disable/reboot pipeline, no new failure states.
	var comps = components.values()
	if comps.is_empty():
		return
	var comp = comps[randi() % comps.size()]
	var tiles = comp.hex_grid.get_all_tiles()
	if tiles.is_empty():
		return
	var tile = tiles[randi() % tiles.size()]
	tile.take_damage(heat * 0.1) # proportional to heat, not flat
	if is_player:
		_show_floating_text("ARC!", Color(1.0, 1.0, 0.3))

func _overheat():
	# Knock out one Accumulator (the thing storing all that energy) via the
	# existing disable machinery, shed a big chunk of heat, carry on.
	for comp in components.values():
		for tile in comp.hex_grid.get_all_tiles():
			if tile.tile_type == "Accumulator" and not tile.is_disabled:
				tile.take_damage(tile.hp + 1.0)
				heat = HEAT_CAPACITY * 0.55
				if is_player:
					_show_floating_text("OVERHEAT!", Color(1.0, 0.35, 0.2))
				is_grid_dirty = true
				return
	# No accumulator to sacrifice: vent hard instead (raw/kinetic builds
	# shouldn't really get here - they generate almost nothing).
	heat = HEAT_CAPACITY * 0.4

# _shoot_release() is gone. Under the old hold-to-charge model it fired
# the partial charge when the mouse was released; under the pre-prime model
# (passive charging) it fired unprompted every idle frame the moment charge
# crossed its 10% floor - the "shooting randomly" playtest bug. Partial
# releases are now exclusively the hold-1/2/3 dump in _shoot().

func _recalculate_grid():
	precalculated_weapons.clear()
	max_shield_hp = 0.0 # Reset shield HP
	has_shield_generator = false
	shield_recharge_delay = 3.0
	shield_recharge_rate = 0.0
	base_move_speed = 150.0 # Reset base speed for Jumpjets to calculate
	jumpjet_rarity = -1
	magnet_repel_mode = false
	jumpjet_blink_mode = false

	if jumpjet_energy == null:
		jumpjet_energy = EnergyPacket.new(0.0, null)
	jumpjet_energy.magnitude = 0.0
	jumpjet_energy.synergies.clear()

	# Reset cloak/jammer-module/healer capability flags; they get rebuilt
	# below from whatever tiles are actually equipped this recalculation.
	has_cloak_generator = false
	max_cloak_charge = 0.0
	cloak_recharge_rate = 0.0
	cloak_recharge_delay = 1.0
	has_jammer_module = false
	has_healer = false
	heal_pulse_power = 0.0

	total_magnetic_power = 0.0
	min_loot_attract_rarity = -1
	stat_modifiers.clear()
	
	# Aggregate all component stat modifiers
	for comp in components.values():
		if comp.get("stat_modifiers"):
			for k in comp.stat_modifiers:
				if stat_modifiers.has(k):
					stat_modifiers[k] += comp.stat_modifiers[k] - 1.0 # Additive percentage bonuses
				else:
					stat_modifiers[k] = comp.stat_modifiers[k]
	
	if not components.has(HexTile.BodySlot.TORSO):
		return
		
	var torso = components[HexTile.BodySlot.TORSO]
	
	# Collect energy from ALL generators in the Torso
	var initial_packets: Array[EnergyPacket] = []
	for coord in torso.hex_grid.grid.keys():
		var t = torso.hex_grid.get_tile(coord)
		if t.has_method("generate_energy"):
			var pkts = t.generate_energy(torso.hex_grid)
			for p in pkts:
				p.position = HexCoord.new(coord.x, coord.y)
			initial_packets.append_array(pkts)
	
	# PHASE 1: Route through Torso grid
	_simulate_grid(torso.hex_grid, initial_packets)
	
	# PHASE 2: Collect transferred packets from Sinks and route into peripheral grids
	var peripheral_transfer = _collect_transfers(torso)
	# Simulate HEAD and BACKPACK first so they can return energy
	var return_pkts: Array[EnergyPacket] = []
	for accessory_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
		if peripheral_transfer.has(accessory_slot) and components.has(accessory_slot):
			var accessory_comp = components[accessory_slot]
			var a_pkts = peripheral_transfer[accessory_slot]
			_route_to_peripheral(a_pkts, accessory_comp)
			
			for coord in accessory_comp.hex_grid.grid.keys():
				var t = accessory_comp.hex_grid.get_tile(coord)
				if t.has_method("generate_energy"):
					var pkts = t.generate_energy(accessory_comp.hex_grid)
					for p in pkts:
						p.position = HexCoord.new(coord.x, coord.y)
					a_pkts.append_array(pkts)
					
			_simulate_grid(accessory_comp.hex_grid, a_pkts)
			
			# Collect return packets
			var accessory_return = _collect_transfers(accessory_comp)
			if accessory_return.has(HexTile.BodySlot.TORSO):
				return_pkts.append_array(accessory_return[HexTile.BodySlot.TORSO])

	if return_pkts.size() > 0:
		var return_pos = HexCoord.new(0, 0)
		var return_tile = null
		# Find the Accessory Return node
		for coord_v in torso.hex_grid.grid.keys():
			var t = torso.hex_grid.grid[coord_v]
			if t.tile_type == "Accessory Return":
				return_pos = HexCoord.new(coord_v.x, coord_v.y)
				return_tile = t
				break
		
		var final_return_pkts: Array[EnergyPacket] = []
		for pkt in return_pkts:
			if return_tile:
				# Process it through the Return Link
				var out = return_tile.process_energy(pkt, 0, torso.hex_grid)
				for p in out:
					p.position = return_pos
					p.is_active = true
					final_return_pkts.append(p)
			else:
				pkt.position = return_pos
				pkt.is_active = true
				final_return_pkts.append(pkt)
				
		# Re-simulate Torso with returned energy!
		_simulate_grid(torso.hex_grid, final_return_pkts)
		
		# Add any new transfers from Torso back into the peripheral pools
		var second_transfers = _collect_transfers(torso)
		for slot in second_transfers:
			if not peripheral_transfer.has(slot):
				peripheral_transfer[slot] = []
			peripheral_transfer[slot].append_array(second_transfers[slot])

	# Simulate remaining peripherals (Arms, Legs)
	for slot in components.keys():
		if slot == HexTile.BodySlot.HEAD or slot == HexTile.BodySlot.BACKPACK or slot == HexTile.BodySlot.TORSO: 
			continue # Already simulated
			
		var comp = components[slot]
		var pkts: Array[EnergyPacket] = []
		if peripheral_transfer.has(slot):
			pkts.append_array(peripheral_transfer[slot])
			_route_to_peripheral(pkts, comp)
			
		for coord in comp.hex_grid.grid.keys():
			var t = comp.hex_grid.get_tile(coord)
			if t.has_method("generate_energy"):
				var generated = t.generate_energy(comp.hex_grid)
				for p in generated:
					p.position = HexCoord.new(coord.x, coord.y)
				pkts.append_array(generated)
				
		_simulate_grid(comp.hex_grid, pkts)
			
	for comp in components.values():
		for tile in comp.hex_grid.get_all_tiles():
			if (tile.tile_type == "Weapon Mount" or tile.tile_type == "Accessory Return" or tile.tile_type == "Torso Return") and "pending_packets" in tile and tile.pending_packets.size() > 0:
				# Accumulator split-fire model (Natalia's locked design):
				# whenever accumulators feed this mount - routed THROUGH the
				# circuit (packet.acc_*_mult) or sitting adjacent (bank) -
				# the mount gets TWO fully independent weapons:
				#   - NORMAL entry: the un-boosted packet. Mouse-fired,
				#     behaves almost as if no accumulator existed (small
				#     quality tax) - EXCEPT that while the big shot is still
				#     charging, the accumulator siphons HALF the payload.
				#     Once the big shot sits full, the siphon stops and
				#     normal shots return to full strength.
				#   - BANK entry: the big charged shot. Charges passively,
				#     fired ONLY by pressing its 1/2/3 key - one press, one
				#     big hit. Clicking never touches it.
				var bank_charge = 0.0
				var bank_amplify = 0.0
				var bank_quality = 1.0
				if tile.tile_type == "Weapon Mount" and tile.grid_position:
					var bank = _get_adjacent_accumulator_bonus(comp.hex_grid, tile.grid_position)
					bank_charge = bank.charge
					bank_amplify = bank.amplify
					bank_quality = bank.quality

				# Detect routed-through accumulators via the recorded mults
				var probe = tile.pending_packets[0].packet
				for i in range(1, tile.pending_packets.size()):
					if tile.pending_packets[i].packet.acc_damage_mult > probe.acc_damage_mult:
						probe = tile.pending_packets[i].packet
				var has_routed_acc = probe.acc_damage_mult > 1.001

				if bank_charge > 0.0 or has_routed_acc:
					var combined = tile.pending_packets[0].packet.copy()
					for i in range(1, tile.pending_packets.size()):
						combined.merge(tile.pending_packets[i].packet)
					# Adjacent (bank) accumulators tax normal fire the same
					# way routed-through ones do - worst neighbor wins.
					combined.accumulator_quality = min(combined.accumulator_quality, bank_quality)

					# Bank entry: the big charged shot. Boosts from routed
					# accumulators (acc_damage_mult) and adjacent bank
					# accumulators (bank_amplify) combine; charge time is the
					# base cost scaled by acc_charge_mult plus the adjacency
					# bank's own charge. Fired ONLY by pressing its 1/2/3 key
					# (_fire_charged); AI auto-releases on full
					# (_tick_weapon_charges). The mouse never fires this.
					var enhanced = combined.copy()
					enhanced.amplify(combined.acc_damage_mult * (1.0 + bank_amplify))
					enhanced.charge_required = combined.charge_required * combined.acc_charge_mult + bank_charge
					enhanced.trigger_key = combined.trigger_key if combined.trigger_key != "None" else "1"

					# Normal-fire entry: the base (unamplified) packet, at
					# whatever charge_required routing naturally gave it.
					# While the bank below is still charging, _shoot() halves
					# this entry's payload (the accumulator is siphoning);
					# bank_required is stashed here so _shoot can tell.
					precalculated_weapons.append({
						"mount": tile,
						"packet": combined.copy(),
						"step": 0,
						"slot_type": comp.slot_type,
						"bank_mode": "normal",
						"bank_required": enhanced.charge_required
					})

					precalculated_weapons.append({
						"mount": tile,
						"packet": enhanced,
						"step": 0,
						"slot_type": comp.slot_type,
						"bank_mode": "bank"
					})
				else:
					var step_groups = {}
					for item in tile.pending_packets:

						var step = item.step
						if not step_groups.has(step):
							step_groups[step] = item.packet.copy()
						else:
							step_groups[step].merge(item.packet)

					for step in step_groups:
						precalculated_weapons.append({
							"mount": tile,
							"packet": step_groups[step],
							"step": step,
							"slot_type": comp.slot_type
						})
				tile.clear_pending()
				
			if tile.has_method("get_speed_bonus"):
				base_move_speed += tile.get_speed_bonus()
				
			if tile.has_method("get_magnetic_power"):
				total_magnetic_power += tile.get_magnetic_power()

			if tile.has_method("get_min_attract_rarity"):
				var filter_rarity = tile.get_min_attract_rarity()
				if filter_rarity >= 0:
					# Most permissive combination if multiple magnets disagree
					min_loot_attract_rarity = filter_rarity if min_loot_attract_rarity < 0 else min(min_loot_attract_rarity, filter_rarity)

			# Mythic Magnet in Repel mode / Mythic Jumpjet in Blink mode
			if tile.tile_type == "Magnet" and tile.rarity == HexTile.Rarity.MYTHIC and tile.get("repel_mode") == true:
				magnet_repel_mode = true
			if tile.tile_type == "Jumpjet" and tile.rarity == HexTile.Rarity.MYTHIC and int(tile.get("mythic_mode")) == 1:
				jumpjet_blink_mode = true
				
			if tile.tile_type == "Shield Generator" and tile.has_method("get_shield_energy"):
				has_shield_generator = true
				var shield_energy = tile.get_shield_energy()
				# Scale directly 1:1 with energy to allow tanking own hits
				max_shield_hp += shield_energy
				# Mythic takes .25s, Legendary takes 0.5s, Rare takes 1.0s, Uncommon 2.0s, Common 3.0s
				if tile.rarity == HexTile.Rarity.MYTHIC:
					shield_recharge_delay = min(shield_recharge_delay, 0.25)
				elif tile.rarity == HexTile.Rarity.LEGENDARY:
					shield_recharge_delay = min(shield_recharge_delay, 0.5)
				elif tile.rarity == HexTile.Rarity.RARE:
					shield_recharge_delay = min(shield_recharge_delay, 1.0)
				elif tile.rarity == HexTile.Rarity.UNCOMMON:
					shield_recharge_delay = min(shield_recharge_delay, 2.0)
				else:
					shield_recharge_delay = min(shield_recharge_delay, 3.0)
					
				# Rapidly recharge (e.g. fully recharge in 2 seconds)
				shield_recharge_rate += max_shield_hp * 0.5
				
				if tile.has_method("get_shield_synergies"):
					var syns = tile.get_shield_synergies()
					for k in syns:
						if shield_synergies.has(k):
							shield_synergies[k] += syns[k]
						else:
							shield_synergies[k] = syns[k]

			if tile.tile_type == "Cloak Generator" and tile.has_method("get_cloak_energy"):
				has_cloak_generator = true
				var cloak_energy_amount = tile.get_cloak_energy()
				max_cloak_charge += cloak_energy_amount
				var duration = tile.get_cloak_duration() if tile.has_method("get_cloak_duration") else 3.0
				var recharge_time = tile.get_recharge_time() if tile.has_method("get_recharge_time") else 6.0
				cloak_drain_rate = max_cloak_charge / max(0.1, duration)
				cloak_recharge_rate += max_cloak_charge / max(0.1, recharge_time)

			if tile.tile_type == "Jammer Module" and tile.has_method("get_jam_energy"):
				if not has_jammer_module: # first module found sets the profile
					has_jammer_module = true
					tile.get_jam_energy() # consume so it doesn't pile up unread
					jammer_pulse_radius = tile.get_pulse_radius()
					jammer_pulse_interval = tile.get_pulse_interval()
					jammer_effect_duration = tile.get_effect_duration()
					jammer_mode = tile.jam_mode
					jammer_target_synergy = tile.target_synergy
					if jammer_pulse_timer <= 0.0:
						jammer_pulse_timer = jammer_pulse_interval

			if tile.tile_type == "Heal Beacon" and tile.has_method("get_heal_energy"):
				has_healer = true
				heal_pulse_power += tile.get_heal_energy() * 0.1
				heal_pulse_radius = tile.get_pulse_radius()
				heal_pulse_interval = tile.get_pulse_interval()

	# Find dominant shield synergy
	var max_syn_val = 0.0
	for k in shield_synergies:
		if shield_synergies[k] > max_syn_val:
			max_syn_val = shield_synergies[k]
			dominant_shield_synergy = str(k)
				
	# Keep shield HP within bounds
	shield_hp = min(shield_hp, max_shield_hp)
	if not has_shield_generator:
		shield_hp = 0.0

	# Heat profile of this circuit (see the heat block near _update_heat):
	# generation proportional to total armed charge_required; ICE share
	# actively cools (2x weight, so ~50% ice storage fully solves heat);
	# LIGHTNING share drives the hot-arcing volatility.
	heat_rate = 0.0
	var _syn_totals: Dictionary = {}
	var _syn_sum: float = 0.0
	for data in precalculated_weapons:
		heat_rate += data.packet.charge_required * 0.03
		for k in data.packet.synergies:
			_syn_totals[k] = _syn_totals.get(k, 0.0) + data.packet.synergies[k]
			_syn_sum += data.packet.synergies[k]
	heat_ice_frac = (_syn_totals.get(EnergyPacket.SynergyType.ICE, 0.0) / _syn_sum) if _syn_sum > 0.0 else 0.0
	heat_ltg_frac = (_syn_totals.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) / _syn_sum) if _syn_sum > 0.0 else 0.0
	heat_rate *= (1.0 - 2.0 * heat_ice_frac)

	# Enemies deploy mostly pre-primed (70-100% charged): a fresh squad
	# shouldn't spend its opening seconds unable to shoot, and the player
	# shouldn't get a free alpha-strike window on every spawn. Once only -
	# mid-fight grid recalcs (damage, jamming) must NOT re-fill charges.
	if not is_player and not _spawn_primed:
		_spawn_primed = true
		for data in precalculated_weapons:
			var frac = randf_range(0.7, 1.0)
			if data.get("bank_mode", "") == "bank":
				data.mount.bank_current_charge = data.packet.charge_required * frac
			else:
				data.mount.current_charge = data.packet.charge_required * frac

	is_grid_dirty = false

var _spawn_primed: bool = false

# Sums get_bank_charge()/get_bank_amplify() from every Accumulator tile
# directly hex-adjacent to `coord` within `grid` - see AccumulatorTile.gd
# and the capacitor-bank branch in the precalculated_weapons loop above.
func _get_adjacent_accumulator_bonus(grid: HexGridComponent, coord: HexCoord) -> Dictionary:
	var total_charge = 0.0
	var total_amplify = 0.0
	var worst_quality = 1.0
	for d in range(6):
		var n = coord.neighbor(d)
		if grid.has_tile(n):
			var neighbor_tile = grid.get_tile(n)
			if neighbor_tile.tile_type == "Accumulator" and neighbor_tile.has_method("get_bank_charge"):
				total_charge += neighbor_tile.get_bank_charge()
				total_amplify += neighbor_tile.get_bank_amplify()
				if neighbor_tile.has_method("get_quality_factor"):
					worst_quality = min(worst_quality, neighbor_tile.get_quality_factor())
	return {"charge": total_charge, "amplify": total_amplify, "quality": worst_quality}

func _collect_transfers(comp) -> Dictionary:
	var result = {}
	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type.ends_with("Link") or t.tile_type == "Accessory Return" or t.tile_type == "Torso Return":
			if t.has_method("get_pending_transfers"):
				var transfer_pkts = t.get_pending_transfers()
				if transfer_pkts.size() > 0:
					if not result.has(t.target_slot):
						result[t.target_slot] = []
					result[t.target_slot].append_array(transfer_pkts)
	return result

func _route_to_peripheral(pkts: Array, comp):
	for pkt in pkts:
		var opp_dir = (pkt.direction + 3) % 6
		pkt.position = HexCoord.new(0, 0).neighbor(opp_dir)
		pkt.is_active = true

func _simulate_grid(grid: HexGridComponent, starting_packets: Array):
	var active_packets: Array[EnergyPacket] = []
	for pkt in starting_packets:
		if pkt.position == null:
			pkt.position = HexCoord.new(0, 0)
		pkt.traversal_steps = 0
		active_packets.append(pkt)
		
	var steps = 0
	# Max 100 routing steps to prevent infinite loops from closed circuits
	while active_packets.size() > 0 and steps < 100:
		steps += 1
		var next_packets: Array[EnergyPacket] = []
		
		for p in active_packets:
			if not p.is_active: continue
			var dir = p.direction
			var next_pos = p.position.neighbor(dir)
			
			if grid.has_tile(next_pos):
				var tile = grid.get_tile(next_pos)
				p.traversal_steps += 1
				if "sync_adjustment" in tile:
					p.traversal_steps += tile.sync_adjustment
					p.traversal_steps = max(0, p.traversal_steps)
					
				var out_pkts = tile.process_energy(p, (dir + 3) % 6, grid)
				for out in out_pkts:
					out.position = next_pos
					out.traversal_steps = p.traversal_steps
				next_packets.append_array(out_pkts)
			else:
				var comp = grid.get_parent()
				var is_valid_empty = false
				if comp and "valid_hexes" in comp:
					for h in comp.valid_hexes:
						if h.q == next_pos.q and h.r == next_pos.r:
							is_valid_empty = true
							break
							
				if is_valid_empty:
					# Pass straight through empty hex with 5% energy loss
					var pass_p = p.copy()
					pass_p.position = next_pos
					pass_p.traversal_steps += 1
					pass_p.magnitude *= 0.95
					for k in pass_p.synergies.keys():
						pass_p.synergies[k] *= 0.95
					next_packets.append(pass_p)
				else:
					# Edge bounce: reflect 180 degrees
					var bounce_p = p.copy()
					bounce_p.direction = (dir + 3) % 6
					bounce_p.position = p.position # Stay on the current tile
					bounce_p.traversal_steps = p.traversal_steps
					next_packets.append(bounce_p)
		
		var merged_packets = {}
		for p in next_packets:
			if not p.is_active: continue
			# Merge packets arriving at same tile with same direction
			var key = str(p.position.q) + "_" + str(p.position.r) + "_" + str(p.direction)
			if merged_packets.has(key):
				merged_packets[key].merge(p)
			else:
				merged_packets[key] = p
				
		active_packets.assign(merged_packets.values())

func _execute_ai_tactics(delta):
	if not target:
		var players = get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			target = players[0]
			
	if target:
		var dist = global_position.distance_to(target.global_position)
		var dir = global_position.direction_to(target.global_position)
		
		path_update_timer -= delta
		if path_update_timer <= 0:
			path_update_timer = 0.5 + randf_range(0, 0.2)
			var maps = get_tree().get_nodes_in_group("map_generator")
			if maps.size() > 0:
				var map = maps[0]
				var start_grid = Vector2i(
					clamp(floor(global_position.x / map.tile_size), 0, map.width - 1),
					clamp(floor(global_position.y / map.tile_size), 0, map.height - 1)
				)
				var end_grid = Vector2i(
					clamp(floor(target.global_position.x / map.tile_size), 0, map.width - 1),
					clamp(floor(target.global_position.y / map.tile_size), 0, map.height - 1)
				)
				if not map.astar_grid.is_point_solid(end_grid):
					current_path = map.astar_grid.get_id_path(start_grid, end_grid)
					for i in range(current_path.size()):
						var p = current_path[i]
						current_path[i] = Vector2(p.x * map.tile_size + map.tile_size/2.0, p.y * map.tile_size + map.tile_size/2.0)
		
		if current_path.size() > 1:
			var next_point = current_path[1]
			if global_position.distance_to(next_point) < 10.0:
				current_path.remove_at(0)
				if current_path.size() > 1:
					next_point = current_path[1]
					
			var path_dir = global_position.direction_to(next_point)
			
			if dist > engagement_distance:
				# Approach full speed
				velocity = path_dir * current_move_speed * speed_modifier
			else:
				# Reached engagement distance, strafe/orbit at half speed
				var tangent = Vector2(-dir.y, dir.x) * rotational_direction
				# Raycast to prevent strafing into walls
				var space_state = get_world_2d().direct_space_state
				var query = PhysicsRayQueryParameters2D.create(global_position, global_position + tangent * 50.0, 1)
				if space_state.intersect_ray(query):
					rotational_direction *= -1 # Reverse orbit
					tangent = Vector2(-dir.y, dir.x) * rotational_direction
					
				velocity = tangent * current_move_speed * (speed_modifier * 0.5)
		else:
			# Fallback if no path (or too close)
			if dist > engagement_distance:
				velocity = dir * current_move_speed * speed_modifier
			else:
				var tangent = Vector2(-dir.y, dir.x) * rotational_direction
				velocity = tangent * current_move_speed * (speed_modifier * 0.5)
			
		# AI combat shooting (out of range = hold charge, same as the player)
		if dist < engagement_distance + 150.0:
			_shoot(target.global_position, true, true, delta)
var elemental_resistances: Dictionary = {}

# Shared shield-mitigation step used by both apply_damage() and
# apply_part_damage() (previously duplicated verbatim in both - a fix to
# one would silently desync from the other). Mutates shield_hp directly and
# returns the amount of damage that should still be applied to HP/parts
# (0.0 if the shield fully absorbed the hit).
func _apply_shield_mitigation(amount: float, element: String) -> float:
	if shield_hp <= 0 or amount <= 0:
		return amount

	# RPG Shield Logic
	if element == "LIGHTNING":
		amount *= 1.5 # Base 1.5x against any shield

	var shield_str = ""
	var syn_id = 0
	if typeof(dominant_shield_synergy) == TYPE_INT:
		syn_id = dominant_shield_synergy
	elif typeof(dominant_shield_synergy) == TYPE_STRING and dominant_shield_synergy != "":
		syn_id = int(dominant_shield_synergy)

	if syn_id == 1: shield_str = "FIRE"
	elif syn_id == 2: shield_str = "ICE"
	elif syn_id == 3: shield_str = "POISON"
	elif syn_id == 4: shield_str = "LIGHTNING"
	elif syn_id == 5: shield_str = "VORTEX"
	elif syn_id == 6: shield_str = "VAMPIRIC"

	if shield_str != "":
		if element == "FIRE" and shield_str == "ICE": amount *= 2.0
		elif element == "ICE" and shield_str == "FIRE": amount *= 2.0
		elif element == "POISON" and shield_str == "VAMPIRIC": amount *= 2.0
		elif element == "VAMPIRIC" and shield_str == "POISON": amount *= 2.0
		elif element == "KINETIC" and shield_str == "LIGHTNING": amount *= 2.0
		elif element == "LIGHTNING" and shield_str == "KINETIC": amount *= 2.0
		elif element == "VORTEX" and shield_str == "KINETIC": amount *= 2.0

	shield_hp -= amount
	if shield_hp < 0:
		var overflow = -shield_hp
		shield_hp = 0
		return overflow
	return 0.0 # Shields absorbed all damage

func apply_damage(amount: float, element: String = "RAW"):
	if elemental_resistances.has(element):
		amount *= elemental_resistances[element]

	# PIERCE "rent" status: torn armor takes +20% from everything while
	# the rend lasts (applied to damage only, never to heals).
	if amount > 0 and status_effects.has("rent"):
		amount *= 1.2

	if not is_player:
		var main = get_tree().current_scene
		# SquadDirector lives under Main.world (the pixel-viewport game
		# world), not directly under Main itself - see Main.gd's
		# _setup_pixel_viewport() for why.
		if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
			main.world.get_node("SquadDirector").log_player_damage(amount, element)

	if amount > 0:
		time_since_last_hit = 0.0
		_break_cloak()
		# Remember what element is currently hurting us - if this hit kills
		# us, die() reports it to the director as the kill method
		# (feeds pierce-overuse counter-pressure, see SquadDirector).
		last_damage_element = element

	amount = _apply_shield_mitigation(amount, element)
	# NOTE: this used to be `if amount <= 0: return`, which was correct for
	# "shields fully absorbed a positive hit" (mitigation returns exactly
	# 0.0 for that case) but ALSO silently swallowed every heal - a heal
	# comes in as a negative amount, passes through mitigation unchanged
	# (shields don't interact with negative amounts), and a negative number
	# is always <= 0, so every single heal (Vampiric lifesteal, Heal
	# Beacon's self-heal path if it's ever routed through here, etc.) was
	# quietly doing nothing. Only an EXACT zero means "shields absorbed it
	# all, nothing left to apply" - that's the only case that should bail.
	if amount == 0.0:
		return

	if amount < 0:
		_show_floating_text("+%d" % int(round(-amount)), Color(0.3, 1.0, 0.4))
	elif amount >= 1.0:
		# Skip tiny continuous-tick damage (burning ticks ~0.08/frame) so
		# the display doesn't turn into a wall of flickering micro-numbers.
		_show_floating_text(str(int(round(amount))), Color(1.0, 0.9, 0.3) if is_player else Color(1.0, 1.0, 1.0))

	hp -= amount
	if hp <= 0:
		die()

# Shared floating-text popup for damage/heal numbers - used from here and
# from _emit_heal_pulse() (which sets hp directly and bypasses this
# function entirely, so it calls this separately).
func _show_floating_text(text: String, color: Color):
	var parent = get_parent()
	if not parent:
		return
	var lbl = Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.z_index = 90
	lbl.global_position = global_position + Vector2(randf_range(-12, 12), -30)
	parent.add_child(lbl)
	var tw = lbl.create_tween()
	tw.tween_property(lbl, "global_position", lbl.global_position + Vector2(randf_range(-6, 6), -40), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.tween_callback(lbl.queue_free)

func apply_part_damage(slot: int, amount: float, element: String = "RAW"):
	amount = _apply_shield_mitigation(amount, element)
	if amount <= 0:
		return # Shields absorbed all part damage

	if not components.has(slot): return
	var comp = components[slot]
	
	# Apply damage to a random tile in that component's grid
	var tiles = comp.hex_grid.get_all_tiles()
	if tiles.size() > 0:
		var hit_tile = tiles[randi() % tiles.size()]
		hit_tile.take_damage(amount)
		
	# Apply a small fraction of locational damage to global structure HP
	apply_damage(amount * 0.2, element)

func apply_status(effect_name: String, duration: float):
	status_effects[effect_name] = duration

func update_status_effects(delta: float):
	current_move_speed = base_move_speed

	var effects_to_remove = []
	for effect in status_effects:
		status_effects[effect] -= delta

		# Handle active effects - full elemental status suite (group 3).
		# Movement effects multiply onto current_move_speed (which was just
		# reset to base above), damage effects tick per second.
		if effect == "frozen":
			current_move_speed = base_move_speed * 0.4 # 60% slow
		elif effect == "burning":
			apply_damage(5.0 * delta) # 5 damage per second
		elif effect == "poisoned":
			apply_damage(4.0 * delta)
			current_move_speed *= 0.8
		elif effect == "bleeding":
			apply_damage(6.0 * delta)
		elif effect == "paralyzed":
			current_move_speed = 0.0 # LIGHTNING lockup
		elif effect == "immobilized":
			current_move_speed = 0.0 # heavy VAMPIRIC pin
		elif effect == "staggered":
			current_move_speed *= 0.5
		elif effect == "concussed":
			current_move_speed *= 0.1
		elif effect == "vortexed":
			# Dragged toward the impact point stored by the projectile
			pull_towards(vortex_drag_point, delta, 500.0)
		# ("rent" has no per-frame effect - it's consumed as a +20% damage
		# amplifier inside apply_damage.)

		# Check if expired
		if status_effects[effect] <= 0:
			effects_to_remove.append(effect)

	for effect in effects_to_remove:
		status_effects.erase(effect)

	if is_cloaked:
		current_move_speed *= 1.25 # Sneaking in fast while unseen

	if not jammed_synergies.is_empty():
		var synergies_to_clear = []
		for syn_id in jammed_synergies:
			jammed_synergies[syn_id] -= delta
			if jammed_synergies[syn_id] <= 0:
				synergies_to_clear.append(syn_id)
		for syn_id in synergies_to_clear:
			jammed_synergies.erase(syn_id)

# --- Cloak -------------------------------------------------------------

func _update_cloak(delta: float):
	if not has_cloak_generator:
		if is_cloaked or modulate.a < 1.0:
			is_cloaked = false
			modulate.a = 1.0
		return

	time_since_cloak_break += delta

	if is_cloaked:
		cloak_charge = max(0.0, cloak_charge - cloak_drain_rate * delta)
		if cloak_charge <= 0.0:
			_break_cloak()
	elif time_since_cloak_break >= cloak_recharge_delay:
		cloak_charge = min(max_cloak_charge, cloak_charge + cloak_recharge_rate * delta)

		var wants_cloak = false
		if is_player:
			wants_cloak = InputMap.has_action("cloak") and Input.is_action_pressed("cloak")
		elif target:
			# Ambush AI: stay cloaked while closing in, reveal once at striking range
			wants_cloak = global_position.distance_to(target.global_position) > engagement_distance * 0.9

		if wants_cloak and cloak_charge >= max_cloak_charge * 0.3:
			is_cloaked = true

	var target_alpha = 0.3 if is_cloaked else 1.0
	# Was 8.0 - converged in under half a second, way too snappy for a
	# "cloak" to read as anything more than a quick flicker. This is a
	# genuinely slow fade now (~2-2.5s to fully settle).
	modulate.a = lerp(modulate.a, target_alpha, 1.2 * delta)

	# The "big distorted circle" visual: a heat-haze shimmer bubble around
	# the cloaked mech (screen-UV displacement shader). Fades in/out with
	# the cloak. Doubles as the ambusher counterplay tell - a player who
	# learns the shimmer can spot an incoming cloaked ambusher.
	_update_cloak_distortion(delta)

const CLOAK_DISTORTION_RADIUS = 80.0
const CLOAK_SHADER_CODE = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 2.0;
	// 1.0 at the middle, 0 at the rim - the bubble has a soft edge
	float mask = smoothstep(1.0, 0.55, dist);
	// Wobbling ripple rings drifting through the bubble
	float ripple = sin(dist * 22.0 - TIME * 4.0) + sin(centered.x * 18.0 + TIME * 2.3);
	vec2 dir = dist > 0.001 ? centered / dist : vec2(0.0);
	vec2 offset = dir * ripple * 0.012 * strength * mask;
	vec4 scene = texture(screen_tex, SCREEN_UV + offset);
	// Slight cool tint so the bubble reads even over flat terrain
	scene.rgb = mix(scene.rgb, scene.rgb * vec3(0.92, 0.97, 1.05), mask * strength);
	COLOR = vec4(scene.rgb, mask * min(1.0, strength * 3.0));
}"""

var _cloak_distortion: ColorRect = null
var _cloak_distortion_strength: float = 0.0

func _ensure_cloak_distortion():
	if _cloak_distortion and is_instance_valid(_cloak_distortion):
		return
	if not get_parent():
		return
	_cloak_distortion = ColorRect.new()
	_cloak_distortion.size = Vector2.ONE * CLOAK_DISTORTION_RADIUS * 2.0
	_cloak_distortion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh = Shader.new()
	sh.code = CLOAK_SHADER_CODE
	var mat = ShaderMaterial.new()
	mat.shader = sh
	_cloak_distortion.material = mat
	# Sibling of the mech, NOT a child: children inherit modulate, so a
	# child bubble would fade out with the cloaking mech - i.e. disappear
	# exactly when it's supposed to be the only visible tell. As a sibling
	# it keeps full opacity and just follows the mech's position.
	get_parent().add_child(_cloak_distortion)
	tree_exiting.connect(func():
		if _cloak_distortion and is_instance_valid(_cloak_distortion):
			_cloak_distortion.queue_free()
	)

func _update_cloak_distortion(delta: float):
	var target = 1.0 if is_cloaked else 0.0
	_cloak_distortion_strength = lerp(_cloak_distortion_strength, target, 1.2 * delta)

	if _cloak_distortion_strength < 0.02:
		if _cloak_distortion and is_instance_valid(_cloak_distortion):
			_cloak_distortion.visible = false
		return

	_ensure_cloak_distortion()
	if not _cloak_distortion:
		return
	_cloak_distortion.visible = true
	_cloak_distortion.global_position = global_position - _cloak_distortion.size / 2.0
	_cloak_distortion.material.set_shader_parameter("strength", _cloak_distortion_strength)

func _break_cloak():
	if not is_cloaked:
		return
	is_cloaked = false
	time_since_cloak_break = 0.0

# Returns the ambush damage multiplier for the shot currently being fired,
# and consumes/breaks the cloak as a side effect. Call this exactly once per
# actual shot fired, right where the projectile is spawned.
func _consume_ambush_bonus() -> float:
	if is_cloaked:
		_break_cloak()
		return 2.5 # Reward for landing the opening shot while unseen
	return 1.0

# --- Jammer Module (equippable pulse ability) --------------------------

func _update_jammer_module(delta: float):
	if not has_jammer_module:
		return
	jammer_pulse_timer -= delta
	if jammer_pulse_timer <= 0.0:
		jammer_pulse_timer = jammer_pulse_interval
		_emit_jammer_pulse()

func _emit_jammer_pulse():
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p = players[0]
	if global_position.distance_to(p.global_position) <= jammer_pulse_radius:
		if jammer_mode == 0:
			if p.has_method("apply_vision_jam"):
				p.apply_vision_jam(jammer_effect_duration)
		else:
			if p.has_method("apply_synergy_jam"):
				p.apply_synergy_jam(jammer_target_synergy, jammer_effect_duration)

	var visual_class = load("res://scripts/attacks/PulseRingVisual.gd")
	if visual_class:
		var v = visual_class.new()
		v.global_position = global_position
		v.setup(jammer_pulse_radius, Color(0.6, 0.15, 0.85, 1.0))
		if get_parent():
			get_parent().add_child(v)

func apply_vision_jam(duration: float):
	if is_player:
		vision_jammed.emit(duration)

func apply_synergy_jam(synergy_id: int, duration: float):
	jammed_synergies[synergy_id] = max(jammed_synergies.get(synergy_id, 0.0), duration)

# Mutes any jammed synergy's contribution to an outgoing packet. Called once
# per actual shot fired, right before the packet leaves the mech.
func _apply_synergy_jamming(packet: EnergyPacket):
	if jammed_synergies.is_empty():
		return
	for syn_id in jammed_synergies:
		if packet.synergies.has(syn_id):
			var suppressed = packet.synergies[syn_id] * 0.9
			packet.magnitude = max(0.0, packet.magnitude - suppressed)
			packet.synergies[syn_id] *= 0.1

# --- Heal Beacon (Support ability) --------------------------------------

func _update_healer(delta: float):
	if not has_healer or is_player:
		return
	heal_pulse_timer -= delta
	if heal_pulse_timer <= 0.0:
		heal_pulse_timer = heal_pulse_interval
		_emit_heal_pulse()

func _emit_heal_pulse():
	var allies = get_tree().get_nodes_in_group("enemy")
	for ally in allies:
		if ally == self or not is_instance_valid(ally) or not ("hp" in ally):
			continue
		if global_position.distance_to(ally.global_position) > heal_pulse_radius:
			continue
		var healed = min(ally.max_hp, ally.hp + heal_pulse_power) - ally.hp
		ally.hp += healed
		if healed >= 1.0 and ally.has_method("_show_floating_text"):
			ally._show_floating_text("+%d" % int(round(healed)), Color(0.3, 1.0, 0.4))

	var self_healed = min(max_hp, hp + heal_pulse_power * 0.5) - hp
	hp += self_healed
	if self_healed >= 1.0:
		_show_floating_text("+%d" % int(round(self_healed)), Color(0.3, 1.0, 0.4))

	var visual_class = load("res://scripts/attacks/PulseRingVisual.gd")
	if visual_class:
		var v = visual_class.new()
		v.global_position = global_position
		v.setup(heal_pulse_radius, Color(0.2, 0.9, 0.5, 1.0))
		if get_parent():
			get_parent().add_child(v)

# Drained-husk terrain from VAMPIRIC kills. Globally capped so a vampiric
# build can't pave the whole map - oldest husk crumbles when the cap hits.
func _spawn_corpse_obstacle():
	var existing = get_tree().get_nodes_in_group("corpse_obstacle")
	if existing.size() >= 12 and is_instance_valid(existing[0]):
		existing[0].queue_free()

	var husk = StaticBody2D.new()
	husk.add_to_group("corpse_obstacle")
	husk.collision_layer = 1 # world obstacle: blocks movement and shots
	husk.collision_mask = 0

	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	husk.add_child(shape)

	var poly = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(-14, -6), Vector2(-4, -12), Vector2(10, -8),
		Vector2(14, 4), Vector2(6, 12), Vector2(-10, 10)
	])
	poly.color = Color(0.32, 0.28, 0.33) # drained grey-violet
	husk.add_child(poly)

	var timer = Timer.new()
	timer.wait_time = 10.0
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(husk.queue_free)
	husk.add_child(timer)

	husk.global_position = global_position
	# Deferred: die() runs mid-physics, and adding a StaticBody during a
	# physics flush is exactly the kind of thing Godot errors about.
	get_parent().call_deferred("add_child", husk)

func die():
	if is_dead or is_queued_for_deletion():
		return
	is_dead = true

	# Report the killing element to the director (kill-method telemetry for
	# pierce-overuse counter-pressure). Approximation: we don't track the
	# damage SOURCE, so AI friendly-fire kills also count - acceptable noise
	# since the overwhelming majority of enemy deaths are player kills.
	if not is_player:
		var main_scene = get_tree().current_scene
		if main_scene and "world" in main_scene and main_scene.world and main_scene.world.has_node("SquadDirector"):
			main_scene.world.get_node("SquadDirector").log_player_kill(last_damage_element)

	# VAMPIRIC kills leave a drained husk that blocks movement and shots
	# for a while - terrain you make out of your enemies (group 3 spec).
	if not is_player and last_damage_element == "VAMPIRIC" and get_parent():
		_spawn_corpse_obstacle()

	# LootManager is an autoload singleton (see project.godot) - use it directly
	# instead of instantiating a throwaway copy (was also why the 25th-wave
	# guaranteed-legendary-drop check always failed: a fresh instance's
	# current_wave defaulted to 1, so `current_wave % 25 == 0` never fired).
	LootManager.generate_loot_for_mech(self)

	died.emit()
	
	var is_over_water = false
	var maps = get_tree().get_nodes_in_group("map_generator")
	if maps.size() > 0:
		var map = maps[0]
		var grid_pos = Vector2i(floor(global_position.x / map.tile_size), floor(global_position.y / map.tile_size))
		if grid_pos.x >= 0 and grid_pos.x < map.width and grid_pos.y >= 0 and grid_pos.y < map.height:
			if map.terrain[grid_pos.y][grid_pos.x] == map.BiomeType.WATER:
				is_over_water = true
				
	if is_over_water:
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		var tween = create_tween()
		tween.tween_property(self, "scale", Vector2(0.2, 0.2), 1.0).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(self, "global_position", global_position + Vector2(0, 20), 1.0)
		tween.parallel().tween_property(self, "modulate:a", 0.0, 1.0)
		tween.tween_callback(queue_free)
	else:
		queue_free()

func build_loadout_for_role(role_name: String):
	var inventory = []
	
	var add_tile = func(path, rarity, synergy=0):
		var tile = load(path).new()
		tile.rarity = rarity
		if synergy > 0 and "secondary_synergy" in tile:
			tile.secondary_synergy = synergy
		inventory.append(tile)
		
	match role_name:
		"sniper":
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", HexTile.Rarity.RARE)
			add_tile.call("res://scripts/tiles/CatalystTile.gd", HexTile.Rarity.RARE)
			add_tile.call("res://scripts/tiles/DirectionalConduitTile.gd", HexTile.Rarity.COMMON)
		"brawler":
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.UNCOMMON)
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.UNCOMMON)
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", HexTile.Rarity.UNCOMMON)
		"flamethrower":
			add_tile.call("res://scripts/tiles/InfuserTile.gd", HexTile.Rarity.RARE, 1) # FIRE
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.UNCOMMON)
			add_tile.call("res://scripts/tiles/SplitterTile.gd", HexTile.Rarity.COMMON)
		"ambusher":
			add_tile.call("res://scripts/tiles/InfuserTile.gd", HexTile.Rarity.RARE, 4) # KINETIC
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", HexTile.Rarity.UNCOMMON)
		"scout":
			pass # Uses basic conduits if they were available, fallback empty solver handles it
		"commander":
			# Weapons are secondary for a Commander - the Command Suite
			# backpack is the payload. Feed the solver defensive parts.
			add_tile.call("res://scripts/tiles/ShieldTile.gd", HexTile.Rarity.RARE)
			add_tile.call("res://scripts/tiles/AccumulatorTile.gd", HexTile.Rarity.RARE)

	# Give the solver something to actually work with: an Infuser it can
	# configure toward the spawn profile's counter-element/Pierce priority.
	# Without this, a profile could only ever reorder whatever flavor tiles
	# the role already hardcodes above - it couldn't introduce a genuinely
	# new counter-element into a role that doesn't normally use one.
	if spawn_profile != null:
		add_tile.call("res://scripts/tiles/InfuserTile.gd", HexTile.Rarity.UNCOMMON)

	var solver = load("res://scripts/core/AutoEquipSolver.gd").new()

	if components.has(HexTile.BodySlot.TORSO):
		inventory = solver.solve(components[HexTile.BodySlot.TORSO], inventory, spawn_profile)
	if components.has(HexTile.BodySlot.ARM_R):
		inventory = solver.solve(components[HexTile.BodySlot.ARM_R], inventory, spawn_profile)
	if components.has(HexTile.BodySlot.ARM_L):
		inventory = solver.solve(components[HexTile.BodySlot.ARM_L], inventory, spawn_profile)

	_recalculate_grid()


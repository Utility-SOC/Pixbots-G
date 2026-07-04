class_name HexTile
extends Resource

enum TileCategory {
	CONDUIT, PROCESSOR, STORAGE, ROUTER, CONVERTER, OUTPUT, SPECIAL
}

enum Rarity {
	COMMON, UNCOMMON, RARE, LEGENDARY, MYTHIC
}

enum BodySlot {
	NONE, TORSO, ARM_L, ARM_R, LEG_L, LEG_R, HEAD, BACKPACK
}

@export var tile_type: String = "Base"
@export var category: TileCategory = TileCategory.CONDUIT
@export var rarity: Rarity = Rarity.COMMON:
	set(val):
		rarity = val
		_roll_sync_adjustment()
		
@export var body_slot: BodySlot = BodySlot.NONE
@export var level: int = 1
@export var is_blocked: bool = false

var grid_position: HexCoord = null
var base_color: Color = Color.GRAY
var sync_adjustment: int = 0

func _roll_sync_adjustment():
	sync_adjustment = 0
	if rarity == Rarity.RARE:
		if randf() < 0.4:
			sync_adjustment = 1 if randf() < 0.5 else -1
	elif rarity == Rarity.LEGENDARY:
		if randf() < 0.8:
			var rolls = [1, -1, 2, -2]
			sync_adjustment = rolls[randi() % rolls.size()]

var max_hp: float = 30.0
var hp: float = 30.0
var is_disabled: bool = false
var disable_timer: float = 0.0
var times_disabled: int = 0
var time_since_last_hit: float = 0.0

func take_damage(amount: float):
	hp -= amount
	time_since_last_hit = 0.0
	if hp <= 0 and not is_disabled:
		is_disabled = true
		var base_cooldown = 3.0
		disable_timer = base_cooldown + (times_disabled * 2.0)
		times_disabled += 1
		hp = 0

func process_durability(delta: float):
	time_since_last_hit += delta
	if time_since_last_hit >= 5.0 and times_disabled > 0 and not is_disabled:
		times_disabled = 0
	
	if is_disabled:
		disable_timer -= delta
		if disable_timer <= 0:
			is_disabled = false
			hp = max_hp # Fully restored on reboot

func _init(_type: String = "Base", _category: TileCategory = TileCategory.CONDUIT):
	tile_type = _type
	category = _category

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if is_disabled:
		# Degraded capacity: acts as a straight pass-through, ignoring the tile's special logic
		return [packet]
	# Base implementation just passes it through
	return [packet]

func get_exit_direction(entry_direction: int) -> int:
	return (entry_direction + 3) % 6

func can_enter_from(direction: int) -> bool:
	return not is_blocked

# --- Shared "acts as a weapon mount" behavior -----------------------------
# Both WeaponMountTile and ComponentLinkTile (when it's wired as an
# Accessory/Torso Return "vent" with nowhere else to route energy) can end
# up firing projectiles - this used to be copy-pasted near-verbatim in both
# files (plus a third, fully orphaned copy in the now-deleted
# ComponentLinkTile_methods.gd). Living here once means a fix like the
# muzzle-position recalculation below applies to every tile type that fires,
# not just whichever copy happened to get updated.
const _ProjectileClass = preload("res://scripts/entities/Projectile.gd")

func _get_power_multiplier() -> float:
	var mult = 1.0
	if rarity == Rarity.UNCOMMON: mult = 1.2
	elif rarity == Rarity.RARE: mult = 1.5
	elif rarity == Rarity.LEGENDARY: mult = 3.0
	elif rarity == Rarity.MYTHIC: mult = 5.0
	return mult * (1.0 + (level - 1) * 0.1)

func get_muzzle_position(mech) -> Vector2:
	var renderer = mech.get_node_or_null("MechRenderer")
	if not renderer:
		return mech.global_position

	var is_left = (body_slot == BodySlot.ARM_L)
	var is_right = (body_slot == BodySlot.ARM_R)

	if is_left and renderer.drawn_parts.has("Arm_true"):
		var arm = renderer.drawn_parts["Arm_true"]
		var h = 28.0 * (1.0 + rarity * 0.15)
		return arm.global_position + Vector2(0, h).rotated(arm.global_rotation)
	elif is_right and renderer.drawn_parts.has("Arm_false"):
		var arm = renderer.drawn_parts["Arm_false"]
		var h = 28.0 * (1.0 + rarity * 0.15)
		return arm.global_position + Vector2(0, h).rotated(arm.global_rotation)

	return mech.global_position

func _fire_combined_projectile(mech, packet: EnergyPacket, step: int, _pattern_child: bool = false, _extra_angle: float = 0.0):
	if not _ProjectileClass: return

	# MYTHIC Weapon Mount firing patterns: split the volley into a shotgun
	# spread or a 360-degree radial burst by recursively firing scaled-down
	# child packets. _pattern_child guards recursion; step-staggered shots
	# keep their normal behavior (patterns only apply to instant volleys).
	if not _pattern_child and step == 0 and "mythic_pattern" in self and rarity == Rarity.MYTHIC:
		var pattern = int(get("mythic_pattern"))
		if pattern == 1: # Shotgun: 5 pellets, 40% payload each, +/-24 deg
			for i in range(5):
				var pellet = packet.copy()
				pellet.amplify(0.4)
				_fire_combined_projectile(mech, pellet, 0, true, deg_to_rad(-24.0 + 12.0 * i))
			return
		elif pattern == 2: # Radial burst: 8 shots, 50% payload, full circle
			for i in range(8):
				var shard = packet.copy()
				shard.amplify(0.5)
				_fire_combined_projectile(mech, shard, 0, true, TAU * float(i) / 8.0)
			return
		# pattern 3 (Beam) falls through - single projectile, tuned below.

	var proj = _ProjectileClass.new()
	var base_damage = packet.magnitude * _get_damage_multiplier() * _get_power_multiplier()

	var is_crit = (packet.magnitude >= EnergyPacket.MAX_MAGNITUDE) or (randf() < 0.05)
	if is_crit:
		base_damage *= 2.0

	proj.fired_by_player = mech.get("is_player") == true
	proj.source_mech = mech
	proj.damage = base_damage
	proj.is_crit = is_crit
	proj.synergies = packet.synergies.duplicate()
	if "stat_modifiers" in mech:
		proj.stat_modifiers = mech.stat_modifiers.duplicate()
	proj.set("weapon_rarity", rarity)
	if "aoe_bonus" in proj:
		proj.aoe_bonus = packet.aoe_bonus
	# Beam pattern: concentrated - faster, piercing, modest damage bonus
	if not _pattern_child and "mythic_pattern" in self and rarity == Rarity.MYTHIC and int(get("mythic_pattern")) == 3:
		proj.damage *= 1.2
		proj.base_speed *= 2.5
		proj.pierce_count = max(proj.pierce_count, 4)
	proj.global_position = get_muzzle_position(mech)

	var aim_pos = mech.get("last_aim_position") if "last_aim_position" in mech else mech.global_position + Vector2(0, -100)
	var muzzle_pos = get_muzzle_position(mech)

	var base_direction = (aim_pos - muzzle_pos).normalized()
	if base_direction == Vector2.ZERO:
		base_direction = Vector2(0, -1)

	if "target_direction" in proj:
		proj.target_direction = base_direction

	# Determine the "straight forward" direction based on which component we are in
	var forward_dir = 4 # Default South (Down) for Torso/Legs/Backpack
	if body_slot == BodySlot.ARM_L:
		forward_dir = 3 # West
	elif body_slot == BodySlot.ARM_R:
		forward_dir = 0 # East
	elif body_slot == BodySlot.HEAD:
		forward_dir = 1 # Northeast (Up)

	var entry_dir = packet.direction
	var diff = (entry_dir - forward_dir + 6) % 6
	var angle_offset = 0.0

	if diff == 1: angle_offset = deg_to_rad(15)
	elif diff == 5: angle_offset = deg_to_rad(-15)
	elif diff == 2: angle_offset = deg_to_rad(35)
	elif diff == 4: angle_offset = deg_to_rad(-35)
	elif diff == 3: angle_offset = deg_to_rad(180)

	proj.direction = base_direction.rotated(angle_offset + _extra_angle)

	if step > 0:
		var delay = (step * 0.05) # 50ms per step
		var timer = Timer.new()
		timer.wait_time = delay
		timer.one_shot = true
		timer.timeout.connect(func():
			if is_instance_valid(mech) and is_instance_valid(proj):
				# Recalculate muzzle position/direction right before firing so a
				# staggered multi-step shot doesn't spawn from a stale position
				# (previously only WeaponMountTile did this - Accessory/Torso
				# Return "vent" shots via ComponentLinkTile did not, which is
				# the "vomiting" bug where delayed vented shots could appear to
				# spawn in the wrong place).
				var new_muzzle_pos = get_muzzle_position(mech)
				proj.global_position = new_muzzle_pos

				var new_aim_pos = mech.get("last_aim_position") if "last_aim_position" in mech else mech.global_position + Vector2(0, -100)
				var new_base_dir = (new_aim_pos - new_muzzle_pos).normalized()
				if new_base_dir == Vector2.ZERO:
					new_base_dir = Vector2(0, -1)
				if "target_direction" in proj:
					proj.target_direction = new_base_dir
				proj.direction = new_base_dir.rotated(angle_offset)

				if mech.get_parent():
					mech.get_parent().add_child(proj)
			elif is_instance_valid(proj):
				proj.queue_free()
			timer.queue_free()
		)
		mech.add_child(timer)
		timer.start()
	else:
		if mech.get_parent():
			mech.get_parent().add_child(proj)
		else:
			mech.add_child(proj)

# WeaponMountTile has an explicit @export damage_multiplier; other tiles
# that fire (like ComponentLinkTile acting as a Return "vent") don't, so
# default to 1.0 rather than requiring every firing tile to declare one.
func _get_damage_multiplier() -> float:
	if "damage_multiplier" in self:
		return get("damage_multiplier")
	return 1.0

# Specific variants can be created as subclasses extending HexTile

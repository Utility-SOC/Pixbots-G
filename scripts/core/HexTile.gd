class_name HexTile
extends Resource

enum TileCategory {
	CONDUIT, PROCESSOR, STORAGE, ROUTER, CONVERTER, OUTPUT, SPECIAL
}

enum Rarity {
	COMMON, UNCOMMON, RARE, LEGENDARY, MYTHIC
}

enum BodySlot {
	NONE, TORSO, ARM_L, ARM_R, LEG_L, LEG_R, HEAD, BACKPACK, DRONE
}
# DRONE is deliberately NOT a slot that ever appears in a Mech's own
# `components` dict - it's the slot_type of the small standalone
# ComponentEquipment owned by a DroneBayTile (see DroneBayTile.gd), which
# gets equipped onto the Drone's OWN separate Mech-like node (Drone.gd) when
# it's spawned into the world. Keeping it out of the main mech's
# `components`/_recalculate_grid() loop is what lets the drone's weapon fire
# from the drone's own flying position instead of the main mech's.

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

# Multi-cell footprint (relative to grid_position, the tile's "anchor")
# - empty for every tile except LanceMountTile, the first (and so far only)
# tile to ever span more than one hex. See HexGridComponent.add_tile/
# remove_tile/get_all_tiles for how this gets stored/deduped. Only ever
# populated AT PLACEMENT time (see GarageInventoryPanel._drop_footprint_tile)
# - a tile sitting in inventory always has this empty, which is why "is this
# a multi-cell tile TYPE" checks must use get_footprint_size() below, never
# this array's current size.
var footprint_offsets: Array = []

# How many hexes this tile's class occupies once placed. 1 for every normal
# tile; overridden by LanceMountTile to 3. Checked BEFORE placement (e.g. to
# decide drag/drop behavior for a tile still sitting in inventory), when
# footprint_offsets above is always still empty.
func get_footprint_size() -> int:
	return 1

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

# Set by Mech._roll_component_disable() for a catastrophic ("grave enough")
# hit instead of the normal timed disable/reboot cycle below - the tile stays
# fully offline with no self-recovery until a Garage repair clears it
# (see GarageMenu._on_repair_all). Distinct from the ordinary is_disabled
# timer so a routine knockout doesn't accidentally become permanent.
var power_lost: bool = false

func take_damage(amount: float):
	hp -= amount
	time_since_last_hit = 0.0
	if hp <= 0 and not is_disabled:
		is_disabled = true
		var base_cooldown = 3.0
		disable_timer = base_cooldown + (times_disabled * 2.0)
		times_disabled += 1
		hp = 0

# Relative disable-roll risk by component type - see Mech._roll_component_disable
# for how this is used. Splitters are the juiciest target (routing hub, losing
# one collapses a lot of downstream packet flow), Reflector/Resonator/Amplifier
# are valuable-but-secondary, everything else is comparatively low priority.
func get_disable_risk() -> float:
	match tile_type:
		"Splitter":
			return 1.0
		"Reflector", "Resonator", "Amplifier":
			return 0.55
		_:
			return 0.2

# Mass contribution for the melee/ramming physics pillar (see Mech._recalculate_grid
# for where these get summed into total_mass, and update_status_effects for the
# resulting movement-speed penalty/bonus). Base default covers any tile type
# that doesn't override this below; subclasses override with a value that's
# rationally in line with what the part actually is - power sources and
# propulsion/actuator hardware are heavy, routing/link tiles are nearly weightless.
func get_weight() -> float:
	return 3.0

func process_durability(delta: float):
	time_since_last_hit += delta
	if time_since_last_hit >= 5.0 and times_disabled > 0 and not is_disabled:
		times_disabled = 0

	if power_lost:
		return # Only a Garage repair brings this back - see take_damage/power_lost above

	if is_disabled:
		disable_timer -= delta
		if disable_timer <= 0:
			is_disabled = false
			hp = max_hp # Fully restored on reboot

func _init(_type: String = "Base", _category: TileCategory = TileCategory.CONDUIT):
	tile_type = _type
	category = _category

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
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

# Weapon Mount Capacity (Natalia: "especially at higher rarities would have
# more capacity before firing, so instead of getting 100 projectiles in a
# split second from a heavily fuelled shotgun, it could just have 10% as
# many projectiles, but much bigger"). Shotgun/Radial Burst used to always
# fire a fixed pellet count (5 / 8) no matter how invested the mount was -
# a dense capacitor-bank grid with many such mounts firing at once really
# could produce ~100 total projectiles in one volley. A mount's power
# multiplier (rarity AND level - patterns only unlock at Mythic today, so
# level is the practical lever within that) now scales its pellet count
# DOWN as it grows, with each remaining pellet's payload scaled UP by the
# same factor - total output per volley is unchanged, just redistributed
# across fewer, proportionally bigger shots. This is also a direct answer
# to "too many projectiles tanks performance": the mounts most likely to
# spam a screen full of pellets (heavily leveled Mythic ones) are exactly
# the ones this eases off the hardest.
const SHOTGUN_MAX_PELLETS = 5
const SHOTGUN_MIN_PELLETS = 2
const RADIAL_MAX_PELLETS = 8
const RADIAL_MIN_PELLETS = 4

func _pattern_pellet_count(max_pellets: int, min_pellets: int) -> int:
	# _get_power_multiplier() is 5.0 at a fresh Mythic level-1 mount (the
	# baseline every pattern already assumes) and grows further with level
	# upgrades - capacity_factor stays 1.0 (full pellet count) at that
	# baseline, then eases the count down as the mount gets more invested.
	var capacity_factor = _get_power_multiplier() / 5.0
	return clamp(int(round(max_pellets / capacity_factor)), min_pellets, max_pellets)

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
	# child packets. _pattern_child guards recursion (children are marked
	# true and skip this whole check, so no fractal explosion risk).
	# Previously also required step == 0 ("this packet took zero hex-hops
	# from the Core"), which on any grid where the mount isn't the Core's
	# immediate neighbor - i.e. almost every non-trivial build, and
	# essentially every dense Mythic-tier one - meant the pattern silently
	# never fired at all, degrading to a single normal shot regardless of
	# the mode selected. Beam (pattern 3, below) never had this restriction,
	# confirming it was an oversight specific to Shotgun/Radial rather than
	# an intentional "patterns only apply to instant volleys" design call.
	if not _pattern_child and "mythic_pattern" in self and rarity == Rarity.MYTHIC:
		var pattern = int(get("mythic_pattern"))
		if pattern == 4: # Mortar: remote payload at the aim point (see MortarShell.gd)
			_fire_mortar(mech, packet)
			return
		if pattern == 1: # Shotgun: up to 5 pellets, +/-24 deg spread
			var pellet_count = _pattern_pellet_count(SHOTGUN_MAX_PELLETS, SHOTGUN_MIN_PELLETS)
			var per_pellet_amplify = (SHOTGUN_MAX_PELLETS * 0.4) / float(pellet_count)
			var angle_step = 48.0 / max(1, pellet_count - 1)
			for i in range(pellet_count):
				var pellet = packet.copy()
				pellet.amplify(per_pellet_amplify)
				var angle_deg = -24.0 + angle_step * i if pellet_count > 1 else 0.0
				_fire_combined_projectile(mech, pellet, 0, true, deg_to_rad(angle_deg))
			return
		elif pattern == 2: # Radial burst: up to 8 shots, full circle
			var shard_count = _pattern_pellet_count(RADIAL_MAX_PELLETS, RADIAL_MIN_PELLETS)
			var per_shard_amplify = (RADIAL_MAX_PELLETS * 0.5) / float(shard_count)
			for i in range(shard_count):
				var shard = packet.copy()
				shard.amplify(per_shard_amplify)
				_fire_combined_projectile(mech, shard, 0, true, TAU * float(i) / shard_count)
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
	if "proc_synergies" in proj:
		proj.proc_synergies = packet.proc_synergies.duplicate()
	if "stat_modifiers" in mech:
		proj.stat_modifiers = mech.stat_modifiers.duplicate()
	proj.set("weapon_rarity", rarity)
	if "aoe_bonus" in proj:
		proj.aoe_bonus = packet.aoe_bonus
	if "is_banked_shot" in proj and "is_banked_shot" in packet:
		proj.is_banked_shot = packet.is_banked_shot
	# Per-mount visual signature (Utility-SOC: "easier to tell which
	# projectile is coming from which weapon mount") - a stable hash of
	# this mount's own (body_slot, grid_position), NOT anything about the
	# packet/synergy, so the same mount always reads the same accent color
	# shot after shot regardless of what's flowing through it.
	if "mount_signature_hue" in proj and grid_position:
		var sig_hash = (int(body_slot) * 97 + grid_position.q * 31 + grid_position.r * 17)
		proj.mount_signature_hue = float(((sig_hash % 360) + 360) % 360) / 360.0
	# Beam pattern: concentrated - faster, piercing, modest damage bonus, and
	# now real extended range (previously got no range advantage at all
	# despite being the piercing sniper mode). is_beam also forces
	# angle_offset to 0 below - a Beam is supposed to ALWAYS go dead-on at
	# the mouse; it was inheriting the same entry_dir-vs-forward_dir spread
	# offset every other pattern uses (meant to simulate multi-barrel firing
	# angles), which could aim it anywhere from 15 to a full 180 degrees off
	# depending on how the mount happened to be wired into the grid - that
	# was the actual "unreliable" bug, not RNG.
	var is_beam = not _pattern_child and "mythic_pattern" in self and rarity == Rarity.MYTHIC and int(get("mythic_pattern")) == 3
	if is_beam:
		proj.damage *= 1.2
		proj.base_speed *= 2.5
		proj.pierce_count = max(proj.pierce_count, 4)
		if "is_beam_shot" in proj:
			proj.is_beam_shot = true
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

	if not is_beam:
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

# Mortar pattern: the payload is delivered AT the aim position (travel
# time + ground telegraph + elemental AoE) instead of fired along a line.
# Speed constant sets how long targets get to react per unit distance.
const MORTAR_SPEED = 420.0

func _fire_mortar(mech, packet: EnergyPacket):
	var world = mech.get_parent()
	if not world:
		return
	var target_pos: Vector2 = mech.get("last_aim_position") if "last_aim_position" in mech else mech.global_position + Vector2(0, -100)
	var muzzle = get_muzzle_position(mech)
	# Pierce payoff: a full-pierce shell arrives ~3x faster than a RAW one
	# over the same distance - previously flight_time was purely a function
	# of distance, so no synergy investment had any effect on how fast a
	# mortar actually landed (elemental impact effects already fire for
	# real on landing via _detonate()'s reused Projectile._handle_hit()
	# pipeline - that part didn't need building). PIERCE, not KINETIC - it's
	# already the velocity stat everywhere else (see Projectile.gd's
	# _calculate_stats: "PIERCE is the velocity stat... KINETIC's whole
	# budget moved to range instead"), so a "zoomy mortar" is a pierce
	# build's payoff, matching that existing identity split.
	var total_mag = 0.0
	for k in packet.synergies:
		total_mag += packet.synergies[k]
	var pierce_ratio = (packet.synergies.get(EnergyPacket.SynergyType.PIERCE, 0.0) / total_mag) if total_mag > 0.0 else 0.0
	var effective_mortar_speed = MORTAR_SPEED * (1.0 + pierce_ratio * 2.0)
	var flight_time = clamp(muzzle.distance_to(target_pos) / effective_mortar_speed, 0.12, 2.2)
	var dmg = packet.magnitude * _get_damage_multiplier() * _get_power_multiplier()
	var shell = load("res://scripts/attacks/MortarShell.gd").new()
	shell.setup(muzzle, target_pos, flight_time, dmg, packet.synergies.duplicate(), mech.get("is_player") == true, mech)
	world.add_child(shell)

# WeaponMountTile has an explicit @export damage_multiplier; other tiles
# that fire (like ComponentLinkTile acting as a Return "vent") don't, so
# default to 1.0 rather than requiring every firing tile to declare one.
func _get_damage_multiplier() -> float:
	if "damage_multiplier" in self:
		return get("damage_multiplier")
	return 1.0

# Specific variants can be created as subclasses extending HexTile

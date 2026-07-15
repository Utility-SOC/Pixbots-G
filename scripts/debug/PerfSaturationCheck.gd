extends Node

# Regression harness for the projectile-saturation performance tiers
# (playtest: rational high-difficulty weaponsfire was hitting 1-3 fps):
#   - ProjectileManager tier functions key off live projectile count
#   - HexTile._fire_combined_projectile merges every K volleys into ONE
#     projectile under saturation, preserving total packet energy
#   - the damage/CRIT popup budget caps Label spam
#   - and the boss-shape fix: a Mythic torso's procedural shape must
#     actually SPEND its 100-hex budget (was terminating at a fixed
#     primitive count - "many fewer hexes than it should have").

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

func _count_projectiles(world: Node) -> int:
	var n = 0
	for c in world.get_children():
		if c.is_in_group("projectile"):
			n += 1
	return n

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	var mech = MechScript.new()
	mech.is_player = true
	world.add_child(mech)
	mech.set_physics_process(false)
	mech.last_aim_position = Vector2(500, 0)

	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	mount.body_slot = HexTile.BodySlot.TORSO

	# --- 1. Unsaturated: factor 1, every volley spawns ---------------------
	if ProjectileManager.consolidation_factor() != 1 or ProjectileManager.lite_visuals():
		push_error("FAIL: empty screen should be factor 1 / full visuals")
		failures += 1
	mount._fire_combined_projectile(mech, EnergyPacket.new(50.0, null), 0)
	var single_count = _count_projectiles(world)
	if single_count != 1:
		push_error("FAIL: unsaturated fire spawned %d projectiles, expected 1" % single_count)
		failures += 1
	else:
		print("1) unsaturated: factor 1, one volley = one projectile")

	# --- 2. Saturate with dummies: tiers respond ---------------------------
	var dummies: Array = []
	for i in range(200):
		var d = Node2D.new()
		world.add_child(d)
		ProjectileManager.register(d)
		dummies.append(d)
	if not ProjectileManager.lite_visuals() or ProjectileManager.consolidation_factor() != 2:
		push_error("FAIL: at 200+ live, expected lite visuals + factor 2 (got factor %d)" % ProjectileManager.consolidation_factor())
		failures += 1
	else:
		print("2) 200 live: lite visuals on, consolidation factor 2")

	# --- 3. Consolidation: two volleys -> one merged projectile ------------
	var before = _count_projectiles(world)
	mount._fire_combined_projectile(mech, EnergyPacket.new(50.0, null), 0)
	var after_first = _count_projectiles(world)
	mount._fire_combined_projectile(mech, EnergyPacket.new(50.0, null), 0)
	var after_second = _count_projectiles(world)
	if after_first != before or after_second != before + 1:
		push_error("FAIL: consolidation spawned %d then %d new (expected 0 then 1)" % [after_first - before, after_second - before])
		failures += 1
	else:
		# The merged shot must carry BOTH volleys' energy: damage formula is
		# magnitude * damage_mult * power_mult (x2 if the 5% crit rolled).
		var merged = null
		for c in world.get_children():
			if c.is_in_group("projectile"):
				merged = c # last one added is fine; all others are from step 1
		var expected_single = 50.0 * mount._get_damage_multiplier() * mount._get_power_multiplier()
		if merged.damage < expected_single * 1.9:
			push_error("FAIL: merged damage %f < 2 volleys' worth (%f)" % [merged.damage, expected_single * 2.0])
			failures += 1
		else:
			print("3) two saturated volleys -> one projectile carrying both packets (dmg %.0f >= %.0f)" % [merged.damage, expected_single * 1.9])

	# --- 4. Floater budget --------------------------------------------------
	# Fresh window: earlier fires may have spent some budget via CRIT rolls.
	ProjectileManager._floater_window_start = 0.0
	var normal_allowed = 0
	for i in range(20):
		if ProjectileManager.request_floater(false):
			normal_allowed += 1
	var crit_allowed = 0
	for i in range(20):
		if ProjectileManager.request_floater(true):
			crit_allowed += 1
	if normal_allowed != ProjectileManager.FLOATER_CAP_NORMAL or crit_allowed != (ProjectileManager.FLOATER_CAP_CRIT - ProjectileManager.FLOATER_CAP_NORMAL):
		push_error("FAIL: floater budget wrong (normal %d, crit-after %d)" % [normal_allowed, crit_allowed])
		failures += 1
	else:
		print("4) floater budget: %d normal, crits keep the reserve up to %d" % [normal_allowed, ProjectileManager.FLOATER_CAP_CRIT])

	for d in dummies:
		ProjectileManager.unregister(d)
		d.queue_free()

	# --- 5. Mythic boss torso spends its hex budget -------------------------
	var worst = 999999
	for i in range(10):
		var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.MYTHIC)
		torso.role_variant = "brawler"
		torso.generate_procedural_shape()
		worst = min(worst, torso.valid_hexes.size())
		torso.free()
	if worst < 90:
		push_error("FAIL: a Mythic procedural torso rolled only %d hexes (budget 100)" % worst)
		failures += 1
	else:
		print("5) 10 Mythic procedural torsos: worst roll %d/100 hexes" % worst)

	if failures == 0:
		print("PASS: saturation tiers, volley consolidation, floater budget, torso hex budget")
	get_tree().quit(0 if failures == 0 else 1)

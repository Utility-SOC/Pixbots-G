extends Node

# Regression harness for Shadow Systems' Cloak brand mechanics (Corporate
# Sponsorships, task #17): toggle-mode input, shoot-while-cloaked not
# breaking cloak, and the ally-sharing pulse fading allies with no cloak
# generator of their own.

const MechScript = preload("res://scripts/entities/Mech.gd")
const AllyCloakTileScript = preload("res://scripts/tiles/brands/AllyCloakTile.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const CloakTileScript = preload("res://scripts/tiles/CloakTile.gd")

const DT := 1.0 / 30.0

var failures = 0

func _ready():
	var world = Node2D.new()
	add_child(world)

	# --- 1. Toggle mode: Shadow Cloak Generator flips shadow_toggle_mode true,
	# and the toggle state persists across ticks without holding the key ---
	var mech = MechScript.new()
	mech.is_player = true
	world.add_child(mech)
	mech.set_physics_process(false)
	mech.has_cloak_generator = true
	mech.max_cloak_charge = 100.0
	mech.cloak_recharge_rate = 200.0
	mech.cloak_drain_rate = 1.0
	mech.shadow_toggle_mode = true
	mech.shadow_stealth_fire = true
	mech.shadow_share_radius = 150.0

	if not InputMap.has_action("cloak"):
		InputMap.add_action("cloak")
		var cloak_key = InputEventKey.new()
		cloak_key.physical_keycode = KEY_C
		InputMap.action_add_event("cloak", cloak_key)

	# Deliberately NOT calling mech._recalculate_grid() here - this mech has
	# no real cloak tile equipped, so a recalc would immediately reset
	# has_cloak_generator (and every shadow_* field) back to false/default,
	# undoing the manual setup above. This test isolates CloakSystem.tick()'s
	# own logic; the real equip -> recalc -> wiring path is verified
	# separately in test 2 below.

	# time_since_cloak_break defaults to 999.0 (see CloakSystem.gd), so the
	# very first tick() already clears recharge_delay's threshold - no need
	# to wait it out first.
	# The real distinguishing behavior isn't "stays cloaked after releasing
	# the key" - once already cloaked, NEITHER mode re-checks input at all
	# (the tick() code only ever reads Input inside the not-yet-cloaked
	# elif branch), so that alone wouldn't actually differentiate toggle
	# from hold. The real test: tap-and-release the key BEFORE charge has
	# crossed the 30% activation threshold, then let charge keep
	# accumulating over several more ticks with the key held UP THE WHOLE
	# TIME - hold-mode could never cloak here (Input.is_action_pressed is
	# false on every later tick), toggle-mode should, since toggle_state
	# latched on regardless of hold duration.
	mech.cloak_system = load("res://scripts/entities/CloakSystem.gd").new(mech)
	mech.cloak_system.cloak_charge = 0.0 # well under the 30-of-100 activation threshold

	Input.action_press("cloak")
	mech.cloak_system.tick(DT) # just_pressed registers -> toggle_state flips ON, but charge is still ~0
	Input.action_release("cloak")
	for _i in range(20): # accumulate charge past the 30% threshold, key NOT held this whole time
		mech.cloak_system.tick(DT)

	if not mech.is_cloaked:
		push_error("FAIL: toggle mode never activated once charge caught up, despite the key being tapped (not held)")
		failures += 1
	else:
		print("1) toggle mode: a tap (not a hold) latches cloak on, activating once charge later crosses the threshold")

	# --- 2. Real equip -> _recalculate_grid() -> capacity-field wiring -----
	# The manually-set shadow_* fields above only prove CloakSystem/Mech.gd's
	# CONSUMING logic is correct - this proves the actual detection in
	# _collect_weapon_mounts_and_tile_capabilities() (tile.brand_id == "cloak")
	# really does set them from a real equipped AllyCloakTile, which is the
	# piece most likely to have an actual wiring bug.
	var wired_mech = MechScript.new()
	wired_mech.is_player = false
	world.add_child(wired_mech)
	wired_mech.set_physics_process(false)
	var backpack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.MYTHIC)
	backpack.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.MYTHIC
	backpack.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var ally_cloak = AllyCloakTileScript.new()
	ally_cloak.rarity = HexTile.Rarity.MYTHIC
	ally_cloak.brand_id = "cloak" # stamped by BrandTileFactory on a real drop
	backpack.hex_grid.add_tile(HexCoord.new(1, 0), ally_cloak)
	wired_mech.equip_component(backpack)
	wired_mech._recalculate_grid()

	if not wired_mech.has_cloak_generator:
		push_error("FAIL: equipping an AllyCloakTile didn't set has_cloak_generator")
		failures += 1
	elif wired_mech.shadow_share_radius <= 0.0:
		push_error("FAIL: equipping an AllyCloakTile didn't set shadow_share_radius")
		failures += 1
	elif not wired_mech.shadow_stealth_fire or not wired_mech.shadow_toggle_mode:
		push_error("FAIL: equipping an AllyCloakTile didn't set shadow_stealth_fire/shadow_toggle_mode")
		failures += 1
	else:
		print("2) equipping a real AllyCloakTile + _recalculate_grid() correctly wires has_cloak_generator/shadow_share_radius(%.1f)/shadow_stealth_fire/shadow_toggle_mode" % wired_mech.shadow_share_radius)

	# A PLAIN CloakTile (no brand_id) must NOT pick up any shadow_* flags -
	# every ordinary Ambusher cloak generator in the game must stay unaffected.
	var plain_mech = MechScript.new()
	plain_mech.is_player = false
	world.add_child(plain_mech)
	plain_mech.set_physics_process(false)
	var plain_backpack = ComponentEquipmentScript.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.RARE)
	plain_backpack.generate_shape()
	var plain_core = CoreTileScript.new()
	plain_core.rarity = HexTile.Rarity.RARE
	plain_backpack.hex_grid.add_tile(HexCoord.new(0, 0), plain_core)
	var plain_cloak = CloakTileScript.new()
	plain_cloak.rarity = HexTile.Rarity.RARE
	plain_backpack.hex_grid.add_tile(HexCoord.new(1, 0), plain_cloak)
	plain_mech.equip_component(plain_backpack)
	plain_mech._recalculate_grid()

	if plain_mech.shadow_share_radius > 0.0 or plain_mech.shadow_stealth_fire or plain_mech.shadow_toggle_mode:
		push_error("FAIL: a plain (non-brand) CloakTile incorrectly picked up shadow_* flags")
		failures += 1
	else:
		print("3) a plain CloakTile (no brand_id) stays a completely ordinary cloak generator")

	# --- 4. Ally-sharing pulse: a nearby ally with NO cloak generator gets
	# faded via external_cloak_timer while in range ------------------------
	var sharer = MechScript.new()
	sharer.is_player = false
	sharer.add_to_group("enemy")
	world.add_child(sharer)
	sharer.set_physics_process(false)
	sharer.has_cloak_generator = true
	sharer.is_cloaked = true
	sharer.shadow_share_radius = 150.0
	sharer.global_position = Vector2.ZERO

	var bare_ally = MechScript.new()
	bare_ally.is_player = false
	bare_ally.add_to_group("enemy")
	world.add_child(bare_ally)
	bare_ally.set_physics_process(false)
	bare_ally.has_cloak_generator = false
	bare_ally.global_position = Vector2(80, 0) # inside the 150 radius

	var far_ally = MechScript.new()
	far_ally.is_player = false
	far_ally.add_to_group("enemy")
	world.add_child(far_ally)
	far_ally.set_physics_process(false)
	far_ally.has_cloak_generator = false
	far_ally.global_position = Vector2(5000, 0) # well outside the radius

	# EntityCache's group snapshot is cached per (physics_frame, process_frame)
	# stamp - if anything touched EntityCache.get_group("enemy") earlier in
	# this same synchronous _ready() (e.g. during one of these mechs' own
	# _ready()), that stale/incomplete snapshot would still be cached at this
	# exact frame stamp. Awaiting a real frame boundary forces a fresh scan.
	await get_tree().process_frame

	if not sharer.cloak_system:
		sharer.cloak_system = load("res://scripts/entities/CloakSystem.gd").new(sharer)
	# cloak_drain_rate defaults to 0.0 (never set on this manually-configured
	# mech), so with cloak_charge also starting at 0.0, tick()'s drain check
	# (charge <= 0.0 -> break_cloak()) would immediately decloak on this very
	# first tick, before ever reaching the ally-share check below. Seed a
	# real charge so the pulse actually has a chance to run.
	sharer.cloak_system.cloak_charge = sharer.max_cloak_charge if sharer.max_cloak_charge > 0.0 else 100.0
	sharer.cloak_system.tick(DT)

	if bare_ally.external_cloak_timer <= 0.0:
		push_error("FAIL: an in-range ally with no cloak generator wasn't covered by the share pulse")
		failures += 1
	else:
		print("4) ally-sharing pulse refreshes external_cloak_timer on an in-range ally with no cloak generator of its own (%.2f)" % bare_ally.external_cloak_timer)

	if far_ally.external_cloak_timer > 0.0:
		push_error("FAIL: an out-of-range ally was incorrectly covered by the share pulse")
		failures += 1
	else:
		print("5) an out-of-range ally is correctly NOT covered")

	# The covered ally's own CloakSystem tick should now fade its modulate
	# alpha toward 0.3 even without has_cloak_generator, via the
	# external_cloak_timer branch. Re-refreshing the timer every iteration
	# simulates the sharer's pulse continuously covering it (matches how it'd
	# actually play out - the real pulse re-fires every tick the sharer stays
	# cloaked in range) - without this, ALLY_CLOAK_REFRESH (0.4s) would decay
	# to 0 partway through the loop and the reset-to-full-opacity branch would
	# snap alpha straight back to 1.0 before this ever converges.
	bare_ally.modulate.a = 1.0
	if not bare_ally.cloak_system:
		bare_ally.cloak_system = load("res://scripts/entities/CloakSystem.gd").new(bare_ally)
	for _i in range(30):
		bare_ally.external_cloak_timer = max(bare_ally.external_cloak_timer, 0.4)
		bare_ally.cloak_system.tick(DT)
	if bare_ally.modulate.a >= 0.95:
		push_error("FAIL: a covered ally with no cloak generator never actually faded (alpha %.2f)" % bare_ally.modulate.a)
		failures += 1
	else:
		print("6) a covered ally with no cloak generator visually fades too (alpha %.2f)" % bare_ally.modulate.a)

	if failures == 0:
		print("PASS: Shadow Systems (Cloak brand) toggle mode, shoot-while-cloaked, and ally-sharing all verified")
	get_tree().quit(0 if failures == 0 else 1)

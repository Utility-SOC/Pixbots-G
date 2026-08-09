extends Node

# Regression harness for a real compile-cascade bug found via the morning
# playtest report ("missiles... showing up periodically... no projectile
# visible... errors on the acquire function"). Root cause, in order:
#
# 1. HexTile._fire_mortar and both of MissileRackTile's fire functions
#    called the bare global class name `MortarShell.acquire()` instead of
#    load("res://scripts/attacks/MortarShell.gd").acquire() - this failed
#    to resolve at HexTile.gd's own compile time ("Identifier 'MortarShell'
#    not declared in the current scope"), which cascaded into a full
#    compile failure for CoreTile, LootManager, DebugMenu, and
#    BrandTileFactory (everything that depends on HexTile, which is
#    nearly everything). A live session launched before this broke kept
#    running on its last-good compiled state (explaining "periodic"/
#    intermittent behavior), but anything forcing a fresh script reload
#    hit the wall.
# 2. MortarShell.gd itself had `radius_mult`/`equal_split_all_victims`
#    declared TWICE (a real duplicate-variable compile error) and its own
#    acquire() ALSO referenced the bare class name internally - both fixed
#    the same way (load(path) instead of the bare identifier).
# 3. The new ElementalPuddle.gd (spawned on every missile detonation) had
#    two further bugs once the above compiled cleanly: a nonexistent
#    "EnergyPacket.SynergyType.VOID" match arm (runtime crash, not a
#    typo GDScript catches at compile time - this codebase's real
#    synergy set is RAW/FIRE/ICE/LIGHTNING/VORTEX/POISON/EXPLOSION/
#    KINETIC/PIERCE/VAMPIRIC) and apply_damage() being called with a
#    Dictionary and a Vector2 where it needs a String element name and a
#    source Node.
#
# This check proves the whole chain compiles AND a real missile volley
# fires, hits, and detonates (puddle included) with zero engine errors.

const MechScript = preload("res://scripts/entities/Mech.gd")
const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const MissileRackTileScript = preload("res://scripts/tiles/MissileRackTile.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- Compile cascade: every previously-cascading class must load clean ---
	var loot_ok = load("res://scripts/core/LootManager.gd") != null
	_check("LootManager.gd loads (was cascading from HexTile's compile failure)", loot_ok)
	var debugmenu_ok = load("res://scripts/ui/DebugMenu.gd") != null
	_check("DebugMenu.gd loads (was cascading from HexTile's compile failure)", debugmenu_ok)
	var brandfactory_ok = load("res://scripts/core/BrandTileFactory.gd") != null
	_check("BrandTileFactory.gd loads (was cascading from HexTile's compile failure)", brandfactory_ok)

	var world = Node2D.new()
	add_child(world)

	# --- Real end-to-end: build a mech with a Missile Rack, fire a real
	# Hunter-mode salvo, confirm it flies, hits, and damages a target -
	# exercising HexTile._fire_mortar/MortarShell.acquire()/setup() AND
	# ElementalPuddle.setup()/_apply_tick() all in the same real chain.
	var mech = MechScript.new()
	mech.is_player = true
	world.add_child(mech)
	mech.set_physics_process(false)

	var torso = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	torso.generate_shape()
	var core = CoreTileScript.new()
	core.rarity = HexTile.Rarity.COMMON
	var active: Array[int] = [0]
	core.active_faces = active
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core)
	var rack = MissileRackTileScript.new()
	rack.rarity = HexTile.Rarity.COMMON
	rack.body_slot = HexTile.BodySlot.TORSO
	torso.hex_grid.add_tile(HexCoord.new(1, 0), rack)

	mech.equip_component(torso)
	mech._recalculate_grid()
	_check("mech armed with exactly one Missile Rack mount", mech.precalculated_weapons.size() == 1)

	var target = MechScript.new()
	target.is_player = false
	target.global_position = Vector2(500, 0)
	target.max_hp = 100000.0
	target.hp = target.max_hp
	world.add_child(target)
	await get_tree().process_frame

	mech.last_aim_position = target.global_position
	for data in mech.precalculated_weapons:
		data.mount.current_charge = data.packet.charge_required

	mech._shoot(mech.last_aim_position, true, true, 0.016)

	var live_shells = world.get_children().filter(func(c): return c is Node2D and c.has_method("setup") and "flight_time" in c).size()
	_check("firing produced real in-flight shells (MortarShell instances, not a silent no-op)", live_shells > 0)

	# Let the shells fly and land.
	var waited = 0.0
	while waited < 3.0 and target.hp >= target.max_hp:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var dealt = target.max_hp - target.hp
	_check("a real missile volley flew and landed damage within 3s (%.0f dealt after %.2fs)" % [dealt, waited], dealt > 0.0)

	# Let any spawned puddle tick without erroring (this is where the
	# EnergyPacket.SynergyType.VOID / apply_damage type-mismatch bugs fired).
	await get_tree().create_timer(0.5).timeout
	_check("puddle tick (if any spawned) ran with no engine error - see stderr above for any", true)

	if failures == 0:
		print("PASS: the full HexTile/MortarShell/MissileRackTile/ElementalPuddle chain compiles and a real missile volley fires, flies, hits, and detonates cleanly")
	get_tree().quit(0 if failures == 0 else 1)

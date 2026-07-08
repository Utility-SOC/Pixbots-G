class_name DroneBayTile
extends HexTile

const ComponentEquipmentClass = preload("res://scripts/core/ComponentEquipment.gd")

# Equippable in a Backpack's hex grid (alongside Shield/Jammer/Cloak/Heal
# Beacon - see ComponentEquipment.gd's create_*_backpack constructors).
# Presence anywhere in the equipped backpack's grid unlocks a genuine new
# combat unit: a companion Drone with its OWN tiny hex-grid weapon loadout,
# sized by THIS tile's own rarity (not the backpack's) - Natalia: "gives me
# another component slot for a drone... rarity of this tile affects the
# size of the grid the drone has... comes with installed jumpjets matching
# the rarity of the hex."
#
# The loadout itself lives on `drone_loadout` (a full ComponentEquipment,
# same as any body-slot component) rather than in the main mech's
# `components` dict - see HexTile.BodySlot.DRONE's comment for why that
# separation matters, and Drone.gd for how it gets equipped onto the actual
# flying unit.
var drone_loadout: ComponentEquipmentClass = null

func _init():
	tile_type = "Drone Bay"
	category = TileCategory.OUTPUT
	base_color = Color(0.2, 0.55, 0.6)

func get_weight() -> float:
	return 8.0 # a whole extra flying combatant folded up in here

# The Drone Bay doesn't consume backpack energy for anything itself - the
# drone it deploys has its own independent Core Reactor and grid (see
# get_or_build_loadout/create_starter_drone), so it keeps fighting even if
# the main mech's backpack circuit is unpowered or jammed. Pass energy
# straight through rather than swallowing it like a dead-end tile would.
func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	return [packet]

# Guarantees drone_loadout is populated and sized for the CURRENT rarity,
# building it on first use if needed. Every construction path (loot rolls,
# Black Market offers, save/load) should read the loadout through this
# rather than the bare field, since rarity is often assigned right after
# `.new()` (the standard pattern across ComponentEquipment.gd's tile
# constructors) - i.e. AFTER _init() already ran - so eagerly building in
# _init() would silently lock in a Common-sized grid regardless of the
# rarity the caller sets a moment later.
func get_or_build_loadout() -> ComponentEquipmentClass:
	if drone_loadout == null:
		drone_loadout = ComponentEquipmentClass.create_starter_drone(rarity)
	return drone_loadout

# Explicit (re)build, used right after setting .rarity when a caller wants a
# fresh default loadout at that rarity rather than whatever (if anything)
# was already there - e.g. brand-new loot rolls. Deliberately NOT called
# automatically on every rarity change, since there's currently no "upgrade
# an existing Drone Bay in place" path that would need to preserve a
# hand-customized loadout across it (matching how backpacks in general work).
func build_drone_loadout():
	drone_loadout = ComponentEquipmentClass.create_starter_drone(rarity)

# Shared lookup used by GarageMenu (Drone tab), ComponentDiagramView (satellite
# callout), and Main.gd (spawn/respawn) - finds the Drone Bay tile installed
# in a given Backpack ComponentEquipment, or null if there isn't one/no
# backpack is equipped at all.
static func find_in_backpack(backpack) -> DroneBayTile:
	if not backpack or not backpack.hex_grid:
		return null
	for tile in backpack.hex_grid.get_all_tiles():
		if tile.tile_type == "Drone Bay":
			return tile
	return null

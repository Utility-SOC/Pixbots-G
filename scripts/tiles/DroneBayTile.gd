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

# Which procedural chassis silhouette (see DroneRenderer.DRONE_CLASSES) this
# bay's drone renders as. Picked once and persisted (not re-rolled every
# spawn/frame) so a given Drone Bay keeps a stable visual identity across
# deploys and save/load - matching how drone_loadout itself is built once
# and kept, not regenerated. -1 means "not yet assigned" (older saves,
# or a bay that hasn't built its loadout yet).
var visual_class: int = -1

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
func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	return [packet]

# Guarantees drone_loadout is populated and sized for the CURRENT rarity,
# building it on first use if needed. Every construction path (loot rolls,
# Black Market offers, save/load) should read the loadout through this
# rather than the bare field, since rarity is often assigned right after
# `.new()` (the standard pattern across ComponentEquipment.gd's tile
# constructors) - i.e. AFTER _init() already ran - so eagerly building in
# _init() would silently lock in a Common-sized grid regardless of the
# rarity the caller sets a moment later.
# Kept in sync with DroneRenderer.CLASS_COUNT by hand (tiles don't preload
# visuals code) - bump this if a chassis archetype is added/removed.
const VISUAL_CLASS_COUNT = 6

func get_or_build_loadout() -> ComponentEquipmentClass:
	if drone_loadout == null:
		drone_loadout = ComponentEquipmentClass.create_starter_drone(rarity)
	if visual_class < 0:
		visual_class = randi() % VISUAL_CLASS_COUNT
	return drone_loadout

# Manual override (Utility-SOC: "I'd also like to be able to choose drone
# design from the drone bay tile") - the config popup calls this directly;
# the random rolls above only ever apply once, at first creation.
func cycle_visual_class():
	visual_class = (visual_class + 1) % VISUAL_CLASS_COUNT

# Explicit (re)build, used right after setting .rarity when a caller wants a
# fresh default loadout at that rarity rather than whatever (if anything)
# was already there - e.g. brand-new loot rolls. Deliberately NOT called
# automatically on every rarity change, since there's currently no "upgrade
# an existing Drone Bay in place" path that would need to preserve a
# hand-customized loadout across it (matching how backpacks in general work).
func build_drone_loadout():
	drone_loadout = ComponentEquipmentClass.create_starter_drone(rarity)
	visual_class = randi() % VISUAL_CLASS_COUNT

# Shared lookup used by GarageMenu (Drone tabs), ComponentDiagramView
# (satellite callout), and Main.gd (spawn/respawn) - finds every Drone Bay
# tile installed in a given Backpack ComponentEquipment (a build can carry
# more than one - each gets its own independent drone), or an empty array
# if there isn't one/no backpack is equipped at all.
static func find_all_in_backpack(backpack) -> Array[DroneBayTile]:
	var found: Array[DroneBayTile] = []
	if not backpack or not backpack.hex_grid:
		return found
	for tile in backpack.hex_grid.get_all_tiles():
		if tile.tile_type == "Drone Bay":
			found.append(tile)
	return found

# Convenience for callers that only ever want "is there at least one" (the
# ComponentDiagramView satellite summary) - the FIRST bay found, or null.
static func find_in_backpack(backpack) -> DroneBayTile:
	var all = find_all_in_backpack(backpack)
	return all[0] if not all.is_empty() else null

# Spawns one Drone per Drone Bay tile found in `owner_mech`'s equipped
# Backpack, added as children of `parent_node`. Shared by Main.gd (the
# player, wrapped in its own respawn-on-cooldown bookkeeping - see
# _spawn_drones_if_needed) and SquadDirector.gd (enemies, fire-and-forget:
# an enemy mech never gets revived, so there's nothing to respawn once its
# drone dies alongside/after it - see Drone._physics_process's owner-
# validity check, which already handles that cleanup for free). Returns the
# spawned Drone nodes (callers that need per-drone bookkeeping, like Main.gd's
# respawn timers, use the bay tile itself - drone.drone_loadout_source's
# owner - as the stable key, not this return value).
static func spawn_drones_for(owner_mech: Node, parent_node: Node) -> Array:
	var spawned: Array = []
	if not owner_mech or not ("components" in owner_mech) or not owner_mech.components.has(HexTile.BodySlot.BACKPACK):
		return spawned
	var backpack = owner_mech.components[HexTile.BodySlot.BACKPACK]
	var bays = find_all_in_backpack(backpack)
	var DroneScript = load("res://scripts/entities/Drone.gd")
	for i in range(bays.size()):
		var bay = bays[i]
		var loadout = bay.get_or_build_loadout() # also assigns visual_class if unset
		var drone = DroneScript.new()
		drone.setup(owner_mech, loadout, bay.rarity, bay.visual_class)
		var spread_angle = (TAU / max(1, bays.size())) * i
		drone.global_position = owner_mech.global_position + Vector2(cos(spread_angle), sin(spread_angle)) * 70.0
		parent_node.add_child(drone)
		spawned.append(drone)
	return spawned

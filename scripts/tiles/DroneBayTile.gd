class_name DroneBayTile
extends HexTile

const ComponentEquipmentClass = preload("res://scripts/core/ComponentEquipment.gd")

# Equippable in a Backpack's hex grid (alongside Shield/Jammer/Cloak/Heal
# Beacon - see ComponentEquipment.gd's create_*_backpack constructors).
# Presence anywhere in the equipped backpack's grid unlocks a genuine new
# combat unit: a companion Drone with its OWN tiny hex-grid weapon loadout,
# sized by THIS tile's own rarity (not the backpack's) - the user: "gives me
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
	return TileStatsRegistry.get_stat("DroneBayTile", "weight", 8.0) # a whole extra flying combatant folded up in here

# Terminal sink, same routing semantics as a Component Link (per the user:
# "drone bays should not be energy transparent, they should act just like
# links") - energy routed into the bay STOPS here instead of ghosting
# through to whatever sits behind it, so the bay reads as a real
# destination when planning a grid. The captured energy is banked in
# stored_energy (drained by get_bay_energy() - currently unread, a natural
# hook for future drone power-scaling); the drone itself still flies on
# its own independent Core Reactor either way (see get_or_build_loadout/
# create_starter_drone), so an unpowered bay never grounds the drone.
var stored_energy: float = 0.0

# Purely a display cache: which Drone tab this bay corresponds to (1-based,
# matching the "Drone N" label GarageMenu._refresh_component_ui assigns -
# see that function's drone-tab loop, the single source of truth this gets
# stamped from on every refresh). 0 = not yet assigned a tab this session.
# Lets GarageGridRenderer draw the bay's own number directly on its grid
# icon (per the user: "when drones are equipped the tile should have the
# number that corresponds to the drone's tab") without the renderer having
# to re-derive tab ordering itself. Not serialized - it's cosmetic and
# gets recomputed every refresh regardless.
var bay_number: int = 0

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active:
		return []
	packet.is_active = false
	stored_energy += packet.magnitude
	return []

func get_bay_energy() -> float:
	var e = stored_energy
	stored_energy = 0.0
	return e

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

# Like find_all_in_backpack, but across EVERY equipped component - nothing
# actually restricts a Drone Bay to the Backpack (forbidden_tile_types is a
# Black-Market-drawback blacklist, not a slot-type allowlist, and a looted
# Drone Bay is just a tile a player can manually place anywhere a hex is
# valid). find_all_in_backpack alone silently missed any bay placed in the
# Torso/an Arm/a Leg/the Head - "drone bay present does not populate drone
# bay tab" (the Garage's tab list) AND, more seriously, no drone ever
# spawned for it in real combat either, since spawn_drones_for below used
# to have the exact same Backpack-only blind spot.
static func find_all_in_mech(components: Dictionary) -> Array[DroneBayTile]:
	var found: Array[DroneBayTile] = []
	for comp in components.values():
		if not comp or not comp.hex_grid:
			continue
		for tile in comp.hex_grid.get_all_tiles():
			if tile.tile_type == "Drone Bay":
				found.append(tile)
	return found

# Spawns one Drone per Drone Bay tile found ANYWHERE in `owner_mech`'s
# equipped components, added as children of `parent_node`. Shared by
# Main.gd (the player, wrapped in its own respawn-on-cooldown bookkeeping -
# see _spawn_drones_if_needed) and SquadDirector.gd (enemies, fire-and-
# forget: an enemy mech never gets revived, so there's nothing to respawn
# once its drone dies alongside/after it - see Drone._physics_process's
# owner-validity check, which already handles that cleanup for free).
# Returns the spawned Drone nodes (callers that need per-drone bookkeeping,
# like Main.gd's respawn timers, use the bay tile itself - drone.
# drone_loadout_source's owner - as the stable key, not this return value).
# Spawns `count` ADDITIONAL drones cloned from `template_loadout` - the
# megaswarm path (Chloe: RivalProfile.drone_swarm_count). Each drone gets
# its OWN deep copy of the loadout via the SaveManager round trip - a
# ComponentEquipment is a Node and equip_component() reparents it, so
# twenty drones sharing one instance would steal it from each other.
# Clones inherit everything on the template, including any Jammer Module
# ensured onto it (JammerModuleTile.ensure_on_component), which is what
# compounds the swarm's fields into one huge blanket.
static func spawn_drone_swarm(owner_mech: Node, parent_node: Node, template_loadout, count: int, p_rarity: int, p_visual_class: int = 0) -> Array:
	var spawned: Array = []
	if count <= 0 or not template_loadout:
		return spawned
	var DroneScript = load("res://scripts/entities/Drone.gd")
	var sm = load("res://scripts/core/SaveManager.gd").new()
	var serialized = sm._serialize_component(template_loadout)
	for i in range(count):
		var loadout_copy = sm._deserialize_component(serialized)
		var drone = DroneScript.new()
		drone.setup(owner_mech, loadout_copy, p_rarity, p_visual_class)
		# Two staggered rings so the swarm reads as a cloud, not a line.
		var a = TAU * float(i) / max(1, count)
		var ring = 90.0 + 50.0 * (i % 2)
		drone.global_position = owner_mech.global_position + Vector2(cos(a), sin(a)) * ring
		parent_node.add_child(drone)
		spawned.append(drone)
	return spawned

static func spawn_drones_for(owner_mech: Node, parent_node: Node) -> Array:
	var spawned: Array = []
	if not owner_mech or not ("components" in owner_mech):
		return spawned
	var bays = find_all_in_mech(owner_mech.components)
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

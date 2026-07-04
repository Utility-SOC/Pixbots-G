class_name WeaponMountTile
extends HexTile

@export var damage_multiplier: float = 1.0

# MYTHIC ability: alternate firing patterns (see HexTile._fire_combined_projectile).
# 0 = normal, 1 = shotgun spread (5 pellets, 40% each), 2 = 360-degree
# radial burst (8 shots, 50% each), 3 = concentrated beam (faster, piercing).
@export_enum("Normal", "Shotgun", "Radial Burst", "Beam") var mythic_pattern: int = 0

func cycle_mythic_pattern():
	mythic_pattern = (mythic_pattern + 1) % 4

var pending_packets: Array = [] # Stores dictionary: { "packet": packet, "step": step }
var current_charge: float = 0.0 # Used by Mech to track accumulator charging

# Capacitor-bank state (see Mech._recalculate_grid/_shoot/_tick_weapon_charges)
# for a mount with Accumulators adjacent to it. Tracked separately from
# current_charge above so the bank can keep charging in the background
# without competing with/resetting normal fire's own charge cycle.
var bank_current_charge: float = 0.0
var bank_primed: bool = false # true once the bank has reached full charge at least once - unlocks normal auto-fire

func _init():
	tile_type = "Weapon Mount"
	category = TileCategory.OUTPUT

func clear_pending():
	pending_packets.clear()

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	var step = 0
	if "traversal_steps" in packet:
		step = packet.traversal_steps

	# Add copy to pending list
	pending_packets.append({ "packet": packet.copy(), "step": step })

	packet.is_active = false
	packet.magnitude = 0.0
	return [packet]

func fire_pending(mech: Node2D):
	if pending_packets.is_empty():
		return

	var step_groups: Dictionary = {}
	for item in pending_packets:
		var step = item.step
		if not step_groups.has(step):
			step_groups[step] = []
		step_groups[step].append(item.packet)

	var sorted_steps = step_groups.keys()
	sorted_steps.sort()

	for step in sorted_steps:
		var group: Array = step_groups[step]
		if group.is_empty(): continue

		# Merge synced packets
		var merged_packet = group[0].copy()
		for i in range(1, group.size()):
			merged_packet.merge(group[i])

		_fire_combined_projectile(mech, merged_packet, step)

	pending_packets.clear()

# _fire_combined_projectile(), get_muzzle_position(), and _get_power_multiplier()
# now live on the HexTile base class (scripts/core/HexTile.gd) - they were
# duplicated near-verbatim across this file, ComponentLinkTile.gd, and a
# third orphaned copy in ComponentLinkTile_methods.gd (deleted - it was dead
# code, never loaded anywhere). This file's `damage_multiplier` export above
# is still picked up automatically via HexTile._get_damage_multiplier().

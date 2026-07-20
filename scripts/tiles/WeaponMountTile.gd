class_name WeaponMountTile
extends HexTile

@export var damage_multiplier: float = TileStatsRegistry.get_stat("WeaponMountTile", "damage_multiplier", 1.0)

# MYTHIC ability: alternate firing patterns (see HexTile._fire_combined_projectile).
# 0 = normal, 1 = shotgun spread (5 pellets, 40% each), 2 = 360-degree
# radial burst (8 shots, 50% each), 3 = concentrated beam (faster, piercing),
# 4 = mortar (remote payload: lobbed shell delivering elemental AoE at the
# aim point with travel time + ground telegraph - fourth-review ruling; the
# dedicated MissileRackTile is stubbed for the full weapon-variety pass).
@export_enum("Normal", "Shotgun", "Radial Burst", "Beam", "Mortar") var mythic_pattern: int = 0

func cycle_mythic_pattern():
	mythic_pattern = (mythic_pattern + 1) % 5

# MYTHIC ability: aim this mount at a fixed offset from the mouse-aim
# direction, independent of which hex face actually routes power into it
# (see HexTile._fire_combined_projectile's angle_offset computation - a
# non-Mythic mount's firing angle is a byproduct of grid wiring: which
# direction the packet happened to enter from vs. this component's fixed
# "forward" direction). The user: "choose the direction relative to the
# mouse that projectiles come from, making it so mythics can be mounted
# anywhere easily." 0 = dead-on at the mouse (matches default/non-Mythic
# behavior); 1-5 step around it in the same 6-direction convention every
# other directional tile config uses (Splitter faces, Core faces, Conduit
# rotation) - 60 degrees per step, so 3 fires straight back from the mouse.
@export_range(0, 5) var mythic_aim_direction: int = 0

func cycle_mythic_aim_direction():
	mythic_aim_direction = (mythic_aim_direction + 1) % 6

var pending_packets: Array = [] # Stores dictionary: { "packet": packet, "step": step }
var current_charge: float = 0.0 # Used by Mech to track accumulator charging

# Capacitor-bank state (see Mech._recalculate_grid/_shoot/_tick_weapon_charges)
# for a mount with Accumulators adjacent to it. Tracked separately from
# current_charge above so the bank can keep charging in the background
# without competing with/resetting normal fire's own charge cycle.
var bank_current_charge: float = 0.0
# (bank_primed removed: it was written but never read - a vestige of the
# pre-siphon "silent until first fill" gate, superseded by the half-power
# siphon model. It was never serialized, so nothing breaks.)

func _init():
	tile_type = "Weapon Mount"
	category = TileCategory.OUTPUT

func get_weight() -> float:
	return TileStatsRegistry.get_stat("WeaponMountTile", "weight", 6.0) # a gun mount has real heft

func clear_pending():
	pending_packets.clear()

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	var step = 0
	if "traversal_steps" in packet:
		step = packet.traversal_steps

	# Add copy to pending list
	pending_packets.append({ "packet": packet.copy(), "step": step })

	packet.is_active = false
	packet.magnitude = 0.0
	return [packet]

# fire_pending() (grouped/merged pending_packets by step, then fired via
# _fire_combined_projectile) was dead code - the real firing path was
# reimplemented directly in Mech.gd (see its weapon-mount collection loop),
# which reads tile.pending_packets itself with its own grouping logic
# (picks the packet with max acc_damage_mult rather than merging in step
# order). Removed rather than kept as an unmaintained duplicate.
#
# _fire_combined_projectile(), get_muzzle_position(), and _get_power_multiplier()
# now live on the HexTile base class (scripts/core/HexTile.gd) - they were
# duplicated near-verbatim across this file, ComponentLinkTile.gd, and a
# third orphaned copy in ComponentLinkTile_methods.gd (deleted - it was dead
# code, never loaded anywhere). This file's `damage_multiplier` export above
# is still picked up automatically via HexTile._get_damage_multiplier().

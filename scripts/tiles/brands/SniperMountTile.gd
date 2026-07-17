class_name SniperMountTile
extends WeaponMountTile

# Corporate Sponsorships (task #17): Farsight Optics' signature tile - every
# shot fired through it gets 6x range (locked at 6x, deliberately
# stacks multiplicatively with kinetic's own range bonus rather than
# replacing it - see EnergyPacket.range_mult/Projectile._calculate_stats()
# for the actual multiplication point. "I do not care if that is imbalanced
# at this point.")
#
# tile_type stays "Weapon Mount" (inherited, not overridden) - see
# PowerGridSplitterTile.gd's comment for why that matters everywhere else in
# the codebase keys off the exact tile_type string.

const SNIPER_RANGE_MULT = 6.0

func _init():
	super._init()

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	# WeaponMountTile.process_energy() stores packet.copy() into
	# pending_packets (the copy that actually becomes the fired projectile -
	# see Mech._collect_weapon_mounts_and_tile_capabilities) and returns the
	# ORIGINAL packet zeroed out for continued grid traversal. The stamp has
	# to land on `packet` BEFORE delegating, or it'd end up on the zeroed
	# pass-through copy instead of the one that's actually going to fire.
	packet.range_mult *= SNIPER_RANGE_MULT
	return super.process_energy(packet, entry_direction, grid, entry_coord)

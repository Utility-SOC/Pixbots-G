class_name WeaponMountTile
extends HexTile

@export var damage_multiplier: float = TileStatsRegistry.get_stat("WeaponMountTile", "damage_multiplier", 1.0)

# MYTHIC ability: alternate firing patterns (see HexTile._fire_combined_projectile).
# 0 = normal, 1 = shotgun spread (5 pellets, 40% each), 2 = 360-degree
# radial burst (8 shots, 50% each), 3 = concentrated beam (faster, piercing),
# 4 = mortar (remote payload: lobbed shell delivering elemental AoE at the
# aim point with travel time + ground telegraph - fourth-review ruling; the
# dedicated MissileRackTile.gd now covers the full always-indirect/salvo
# weapon-variety pass at every rarity, not just this Mythic-only pattern).
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

# MYTHIC ability: Set a massive energy threshold (300k, 600k, 900k, 1.2M by
# default) that must be met before the weapon fires. It will accumulate
# incoming packets across ticks until the sum meets or exceeds this value,
# at which point it releases a catastrophic single shot. 0 means disabled
# (auto-fire).
const BASE_THRESHOLD_OPTIONS = [0, 300000, 600000, 900000, 1200000]
@export var mythic_firing_threshold: int = 0

# Design request: "I want the capacity options for the weapons mount to
# directly attenuate upward when accumulators are equipped (allowing for
# shots much larger than 12,000,000 energy, and with reverse accumulators
# smaller than 300,000)." The base 5-option list is fixed, but a mount with
# real Accumulator/Reverse Accumulator investment adjacent to it should be
# able to reach thresholds far outside that range in either direction -
# reuses the exact same adjacency scan the accumulator bank-charge system
# already relies on (Mech._get_adjacent_accumulator_bonus/
# _get_adjacent_reverse_accumulator_discount, both static - no live Mech
# instance needed), so "how much accumulator investment is here" means the
# same thing in both systems.
#
# Accumulators extend the CEILING: each step multiplies the previous tier
# by (1 + total adjacent bank_amplify), so a single Mythic-tier Accumulator
# (bank_amplify ~2.5) reaches ~4.2M on the first new tier and clears 12M+
# with two or three stacked - matching the request's own reference number.
# Reverse Accumulators extend the FLOOR the same way in reverse, dividing
# down from 300k, but never below a 1,000-energy hard stop and never
# touching the 0 ("disabled/auto-fire") option itself.
#
# grid/coord are optional - a caller with no grid context (e.g. a debug
# spawn with no real component) just gets the base 5 options, same as
# before this feature existed.
func get_threshold_options(grid: HexGridComponent = null, coord: HexCoord = null) -> Array:
	var options = BASE_THRESHOLD_OPTIONS.duplicate()
	if grid == null or coord == null or not grid.has_tile(coord):
		return options

	var acc_bonus = Mech._get_adjacent_accumulator_bonus(grid, coord)
	if acc_bonus.amplify > 0.0:
		var scale = 1.0 + acc_bonus.amplify
		var tier = float(BASE_THRESHOLD_OPTIONS[-1])
		for i in range(4):
			tier *= scale
			options.append(int(tier))

	var rev_discount = Mech._get_adjacent_reverse_accumulator_discount(grid, coord)
	if rev_discount > 0.0:
		var scale = 1.0 + rev_discount
		var tier = float(BASE_THRESHOLD_OPTIONS[1]) # 300000
		var floor_tiers = []
		for i in range(3):
			tier /= scale
			if tier < 1000.0:
				break
			floor_tiers.append(int(tier))
		floor_tiers.reverse()
		# Insert after the leading 0 (index 0), before the base 300k tier.
		for i in range(floor_tiers.size()):
			options.insert(1 + i, floor_tiers[i])

	return options

func cycle_mythic_firing_threshold(grid: HexGridComponent = null, coord: HexCoord = null):
	var options = get_threshold_options(grid, coord)
	var idx = options.find(mythic_firing_threshold)
	if idx == -1: idx = 0
	idx = (idx + 1) % options.size()
	mythic_firing_threshold = options[idx]


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

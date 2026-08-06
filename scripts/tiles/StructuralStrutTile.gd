class_name StructuralStrutTile
extends HexTile

# The literal floor of commitment (Status.md backlog: "more transparent hex
# tiles" - the roster was short on simple, low-commitment structural options
# below Directional Conduit). Zero energy logic at all - no overrides beyond
# _init()/get_weight() below, relying entirely on HexTile's own base
# process_energy/get_exit_direction/can_enter_from (straight any-direction
# pass-through, see that file) rather than reimplementing what's already the
# default. Purely a hex-bridging filler: something to occupy a cell with
# when you don't want Directional Conduit's rotation/Valve-mode complexity,
# don't want to spend a real tile slot on Amplifier/Infusion/Catalyst, and
# just need the grid to stay connected.
#
# Elemental armor (design request: "struts should function as elemental
# armor"): each Strut can be tuned to one element, same secondary_synergy +
# cycle_synergy()/cycle_synergy_backward() convention as InfuserTile.gd
# (RAW = unconfigured/inert, matches its existing "plain filler until you
# decide otherwise" identity). UNCONDITIONAL from mere presence - no energy
# routing required, same as AnchorTile's vortex immunity - deliberately kept
# simple to match this tile's whole reason for existing (the option BELOW
# Directional Conduit's routing complexity). Mech._collect_weapon_mounts_
# and_tile_capabilities() aggregates every equipped Strut's tagged element
# into elemental_resistances, read by Mech.apply_damage().
var secondary_synergy: EnergyPacket.SynergyType = EnergyPacket.SynergyType.RAW

func _init():
	tile_type = "Structural Strut"
	category = TileCategory.CONDUIT
	base_color = Color(0.45, 0.42, 0.38) # plain, unpowered-looking gunmetal

func get_weight() -> float:
	return TileStatsRegistry.get_stat("StructuralStrutTile", "weight", 0.5) # lighter than even Directional Conduit - no rotation/valve hardware at all

# RAW is part of the cycle now (the inert/default state you can return to),
# so both directions are a plain wrap - same as InfuserTile.gd's version.
func cycle_synergy():
	secondary_synergy = (secondary_synergy + 1) % EnergyPacket.SynergyType.size()

func cycle_synergy_backward():
	secondary_synergy = (secondary_synergy + EnergyPacket.SynergyType.size() - 1) % EnergyPacket.SynergyType.size()

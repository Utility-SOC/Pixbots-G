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

func _init():
	tile_type = "Structural Strut"
	category = TileCategory.CONDUIT
	base_color = Color(0.45, 0.42, 0.38) # plain, unpowered-looking gunmetal

func get_weight() -> float:
	return TileStatsRegistry.get_stat("StructuralStrutTile", "weight", 0.5) # lighter than even Directional Conduit - no rotation/valve hardware at all

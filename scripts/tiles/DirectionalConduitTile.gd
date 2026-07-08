class_name DirectionalConduitTile
extends HexTile

var rotation_steps: int = 0

# MYTHIC "Valve" mode: locks the conduit to one-way flow only, blocking
# backflow entirely - a routing/control tool for complex grids (e.g. forcing
# a shared trunk line to only ever feed outward from a specific Accumulator
# bank, never siphon back into it). Two-Way (index 0) is the tile's normal,
# always-available behavior; One-Way Valve (index 1) is Mythic-locked, same
# UI pattern as Jumpjet's Jump/Blink toggle (see GarageMenu.gd's generic
# Mythic-mode popup and HexTile subclasses like JumpjetTile.gd).
@export_enum("Two-Way", "One-Way Valve") var mythic_mode: int = 0

func cycle_mythic_mode():
	mythic_mode = (mythic_mode + 1) % 2

func _init():
	tile_type = "Directional Conduit"
	category = TileCategory.CONDUIT

func get_weight() -> float:
	return 1.0 # basically just a wire

func get_exit_direction(entry_direction: int) -> int:
	return (entry_direction + 3) % 6

# allowed1 (rotation_steps itself) is the designated "forward" face; allowed2
# is directly opposite it (the "backflow" face). NOTE: this was never
# actually called from the real routing path (Mech._simulate_grid) before -
# rotation_steps only ever fed the Garage's visual flow-preview
# (GarageGridRenderer), so every conduit has effectively been an
# any-direction pass-through in real combat regardless of how it's rotated.
# Deliberately NOT changing that default behavior here (existing loadouts
# shouldn't suddenly start silently dead-ending packets because of a tile
# rotation nobody ever needed to get right) - only Valve mode opts a
# specific conduit into real direction enforcement.
func can_enter_from(direction: int) -> bool:
	if is_blocked: return false
	var allowed1 = rotation_steps % 6
	var allowed2 = (rotation_steps + 3) % 6
	return direction == allowed1 or direction == allowed2

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if is_disabled:
		return [packet] # degraded: straight pass-through, same convention as HexTile's base case
	# Valve mode (Mythic-only) is the ONE case that actually enforces
	# direction: forward-face entry passes through as normal, but entry from
	# the opposite ("backflow") face dead-ends here instead of passing
	# through. Every other configuration (including Two-Way, which is the
	# default for every conduit including Mythic ones left untoggled) keeps
	# the existing any-direction pass-through untouched.
	if rarity == Rarity.MYTHIC and mythic_mode == 1:
		var forward_face = rotation_steps % 6
		if entry_direction != forward_face:
			return []
	return [packet]

# Was missing entirely - GarageGridRenderer's "E to rotate" handler checks
# tile.has_method("rotate") before doing anything, so pressing E over a
# Directional Conduit silently did nothing even though rotation_steps
# above is fully wired up and meaningful for this tile. ReflectorTile has
# the same method; mirroring its implementation here.
func rotate(clockwise: bool = true):
	if clockwise:
		rotation_steps = (rotation_steps + 1) % 6
	else:
		rotation_steps = (rotation_steps - 1) % 6
		if rotation_steps < 0:
			rotation_steps += 6

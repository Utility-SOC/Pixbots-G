class_name HexGridComponent
extends Node

# Maps Vector2i(q, r) -> HexTile
var grid: Dictionary = {}

func _process(delta: float):
	for key in grid:
		var tile = grid[key]
		if tile.has_method("process_durability"):
			tile.process_durability(delta)

func has_tile(coord) -> bool:
	if typeof(coord) == TYPE_OBJECT and coord is HexCoord:
		return grid.has(Vector2i(coord.q, coord.r))
	elif typeof(coord) == TYPE_VECTOR2I:
		return grid.has(coord)
	return false

func get_tile(arg1, arg2 = null) -> HexTile:
	if typeof(arg1) == TYPE_OBJECT and arg1 is HexCoord:
		var key = Vector2i(arg1.q, arg1.r)
		if grid.has(key): return grid[key]
	elif typeof(arg1) == TYPE_VECTOR2I:
		if grid.has(arg1): return grid[arg1]
	elif arg2 != null:
		var key = Vector2i(int(arg1), int(arg2))
		if grid.has(key): return grid[key]
	return null

func add_tile(coord: HexCoord, tile: HexTile):
	tile.grid_position = coord
	grid[Vector2i(coord.q, coord.r)] = tile

func remove_tile(coord: HexCoord) -> HexTile:
	var key = Vector2i(coord.q, coord.r)
	if grid.has(key):
		var tile = grid[key]
		grid.erase(key)
		return tile
	return null

func get_all_tiles() -> Array[HexTile]:
	var tiles: Array[HexTile] = []
	for key in grid:
		tiles.append(grid[key])
	return tiles

func assign_body_slots():
	# Reset slots
	for key in grid:
		grid[key].body_slot = HexTile.BodySlot.NONE
		
	var core = get_tile(0, 0)
	if core:
		core.body_slot = HexTile.BodySlot.TORSO
		
	var weapons = []
	var movement = []
	var sensors = []
	
	for key in grid:
		var tile = grid[key]
		if tile == core: continue
		if tile.category == HexTile.TileCategory.OUTPUT: # Weapons
			weapons.append({ "pos": key, "tile": tile })
		elif tile.category == HexTile.TileCategory.CONVERTER: # Movement/Legs
			movement.append({ "pos": key, "tile": tile })
		elif tile.category == HexTile.TileCategory.PROCESSOR: # Sensors/Head
			sensors.append({ "pos": key, "tile": tile })
			
	# Sort weapons left to right to assign L/R arms
	weapons.sort_custom(func(a, b): return a.pos.x < b.pos.x)
	if weapons.size() > 0: weapons[0].tile.body_slot = HexTile.BodySlot.ARM_L
	if weapons.size() > 1: weapons[weapons.size()-1].tile.body_slot = HexTile.BodySlot.ARM_R
	
	# Same for legs (if we add movement tiles later, right now conduits act as fillers)
	# Just for visual fallback, if no movement tiles, assign bottom conduits to legs
	var lower_tiles = []
	for key in grid:
		var tile = grid[key]
		if tile.body_slot == HexTile.BodySlot.NONE and key.y > 0:
			lower_tiles.append({ "pos": key, "tile": tile })
			
	lower_tiles.sort_custom(func(a, b): return a.pos.x < b.pos.x)
	if lower_tiles.size() > 0: lower_tiles[0].tile.body_slot = HexTile.BodySlot.LEG_L
	if lower_tiles.size() > 1: lower_tiles[lower_tiles.size()-1].tile.body_slot = HexTile.BodySlot.LEG_R
	
	# Assign head to highest tile
	var upper_tiles = []
	for key in grid:
		var tile = grid[key]
		if tile.body_slot == HexTile.BodySlot.NONE and key.y < 0:
			upper_tiles.append({ "pos": key, "tile": tile })
	
	upper_tiles.sort_custom(func(a, b): return a.pos.y < b.pos.y) # lowest y is highest on screen
	if upper_tiles.size() > 0:
		upper_tiles[0].tile.body_slot = HexTile.BodySlot.HEAD

func generate_random_loadout(role: String):
	# Very basic procedural gen to give enemies equipped tiles
	var CoreTileClass = load("res://scripts/tiles/CoreTile.gd")
	var WeaponMountTileClass = load("res://scripts/tiles/WeaponMountTile.gd")
	var AmplifierTileClass = load("res://scripts/tiles/AmplifierTile.gd")
	
	var core_tile = CoreTileClass.new()
	add_tile(HexCoord.new(0, 0), core_tile)
	
	var amp_tile = AmplifierTileClass.new()
	if role == "ranged":
		amp_tile.rarity = HexTile.Rarity.RARE
	add_tile(HexCoord.new(1, 0), amp_tile)
	
	var out_tile = WeaponMountTileClass.new()
	if randf() > 0.9:
		out_tile.rarity = HexTile.Rarity.LEGENDARY
	add_tile(HexCoord.new(2, 0), out_tile)

func route_energy_packet(packet: EnergyPacket, current_coord: HexCoord):
	var tile = get_tile(current_coord.q, current_coord.r)
	if not tile: return
	
	# Legendary Tile effect: If adjacent to an Output/Weapon, it hits multiple facets
	if tile.rarity == HexTile.Rarity.LEGENDARY and tile.category != HexTile.TileCategory.OUTPUT:
		var neighbors = current_coord.get_neighbors()
		var found_output = false
		for i in range(neighbors.size()):
			var n = neighbors[i]
			var n_tile = get_tile(n.q, n.r)
			if n_tile and n_tile.category == HexTile.TileCategory.OUTPUT:
				# It is adjacent to a weapon emitter!
				# We inject energy into 3 different facets of the weapon to trigger extra projectiles.
				print("[LEGENDARY EFFECT] Multiplying energy packet into multiple facets of ", n_tile.tile_type)
				var entry_dirs = [i, (i + 1) % 6, (i + 5) % 6] # Example: front, left, right facets
				for dir in entry_dirs:
					n_tile.process_energy(packet.copy(), dir, self)
				found_output = true
				break
				
		if found_output:
			return # Energy consumed by the output
			
	# Standard routing...
	tile.process_energy(packet, 0, self)

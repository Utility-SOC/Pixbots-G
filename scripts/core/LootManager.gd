extends Node

# Probability map based on rarity
const DROP_RATES = {
	HexTile.Rarity.COMMON: 0.20,
	HexTile.Rarity.UNCOMMON: 0.10,
	HexTile.Rarity.RARE: 0.05,
	HexTile.Rarity.LEGENDARY: 0.01
}

var current_wave: int = 1

func generate_loot_for_mech(mech: Node):
	if not "components" in mech:
		return
		
	var equipped_tiles = []
	for comp in mech.components.values():
		if comp and comp.has_node("HexGridComponent"):
			equipped_tiles.append_array(comp.get_node("HexGridComponent").get_all_tiles())
	
	var is_boss = ("is_boss" in mech and mech.is_boss)
	var is_25th_wave_boss = is_boss and (current_wave % 25 == 0)
	
	if mech.has_meta("boss_drop"):
		var drop_type = mech.get_meta("boss_drop")
		var comp_script = load("res://scripts/core/ComponentEquipment.gd")
		var pack = null
		if drop_type == "shield":
			pack = comp_script.create_shield_backpack()
		elif drop_type == "jetpack":
			pack = comp_script.create_jetpack_backpack()
		elif drop_type == "missile":
			pack = comp_script.create_missile_backpack()
			
		if pack != null:
			# Wrap it in a LootPickup
			var drop = load("res://scripts/entities/LootPickup.gd").new()
			drop.equipment_data = pack
			drop.global_position = mech.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
			if mech.get_parent():
				mech.get_parent().call_deferred("add_child", drop)
				
	for tile in equipped_tiles:
		if is_25th_wave_boss:
			# Guaranteed drop of rare or better
			var roll = randf()
			if roll <= 0.10:
				tile.rarity = HexTile.Rarity.LEGENDARY
			else:
				tile.rarity = HexTile.Rarity.RARE
			_spawn_loot_drop(mech, tile)
			break 
			
		elif is_boss:
			if randf() <= 0.50:
				_spawn_loot_drop(mech, tile)
		else:
			var chance = DROP_RATES[tile.rarity]
			if randf() <= chance:
				_spawn_loot_drop(mech, tile)

func _spawn_loot_drop(mech: Node, tile: HexTile):
	var drop = load("res://scripts/entities/LootPickup.gd").new()
	drop.tile_data = tile
	drop.global_position = mech.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	if mech.get_parent():
		mech.get_parent().call_deferred("add_child", drop)

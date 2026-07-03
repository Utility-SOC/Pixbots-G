extends Node

# Probability map based on rarity
var DROP_RATES = {
	0: 0.20, # COMMON
	1: 0.10, # UNCOMMON
	2: 0.05, # RARE
	3: 0.01  # LEGENDARY
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
	
	if is_boss:
		# Bosses drop full components instead of just tiles
		var comp_script = load("res://scripts/core/ComponentEquipment.gd")
		var pack = null
		if mech.has_meta("boss_drop"):
			var drop_type = mech.get_meta("boss_drop")
			if drop_type == "shield":
				pack = comp_script.create_shield_backpack()
			elif drop_type == "jetpack":
				pack = comp_script.create_jetpack_backpack()
			elif drop_type == "missile":
				pack = comp_script.create_missile_backpack()
				
		if pack == null:
			# Procedural random component
			var rarity = HexTile.Rarity.LEGENDARY if is_25th_wave_boss else HexTile.Rarity.RARE
			var slots = [HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R, HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R, HexTile.BodySlot.HEAD, HexTile.BodySlot.TORSO]
			var slot = slots[randi() % slots.size()]
			pack = comp_script.new(slot, rarity)
			pack.component_name = "Boss " + str(slot) + " Drop"
			pack.role_variant = mech.combat_role if "combat_role" in mech else ""
			pack.generate_procedural_shape()
			
			# Add intake
			var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
			intake.tile_type = "Energy Intake"
			intake.body_slot = slot
			pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
			pack.fixed_sinks.append(HexCoord.new(0, 0))
			
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

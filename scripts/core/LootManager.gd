extends Node

# Probability map based on rarity. Raised across the board per
# FEATURE_ROADMAP.md (feature 5 / group 2): the upgrade + infusion +
# repair economy needs a steady stream of salvage fuel, so drops must be
# generous enough that scrapping chaff is routine, not precious.
# MYTHIC entry added - it was missing entirely, so a mythic tile on an
# enemy (debug-upgraded or future content) crashed the drop roll.
var DROP_RATES = {
	0: 0.30,  # COMMON
	1: 0.18,  # UNCOMMON
	2: 0.09,  # RARE
	3: 0.02,  # LEGENDARY
	4: 0.005, # MYTHIC - baseline; see _get_mythic_drop_rate() for the wave-scaled version actually used
}

# Per Natalia: Mythic drop odds should steadily climb as waves progress
# (paired with SquadDirector's matching wave-scaled Mythic-enemy seeding),
# tuned so a player realistically sees their first Mythic drop by around
# wave/level 30 - not guaranteed, just increasingly likely as more Mythic-
# tier enemies get killed. Every other rarity keeps its flat DROP_RATES
# entry; only Mythic scales, since it's the one rarity meant to feel like
# genuine progression rather than a fixed background rate.
func _get_mythic_drop_rate() -> float:
	return clamp(0.002 * float(current_wave), DROP_RATES[4], 0.08)

# Chance for a NON-boss kill to drop a full procedural component (salvage
# fodder for the component-upgrade loop). Bosses keep their guaranteed drop.
const COMPONENT_DROP_CHANCE = 0.03

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
			elif drop_type == "drone":
				pack = comp_script.create_drone_backpack(HexTile.Rarity.RARE)

		if pack == null:
			var rarity = HexTile.Rarity.LEGENDARY if is_25th_wave_boss else HexTile.Rarity.RARE
			pack = _create_procedural_component(rarity, mech, "Boss")

		if pack != null:
			_spawn_component_drop(mech, pack)

	elif randf() <= COMPONENT_DROP_CHANCE:
		# Regular kills occasionally shed a whole (Common/Uncommon) component
		# - salvage fodder that feeds the upgrade/infusion economy without
		# competing with boss drops for excitement.
		var rarity = HexTile.Rarity.UNCOMMON if randf() < 0.25 else HexTile.Rarity.COMMON
		var salvage = _create_procedural_component(rarity, mech, "Salvaged")
		_spawn_component_drop(mech, salvage)

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
			var chance = _get_mythic_drop_rate() if tile.rarity == HexTile.Rarity.MYTHIC else DROP_RATES.get(tile.rarity, 0.0)
			if randf() <= chance:
				_spawn_loot_drop(mech, tile)

# Shared procedural-component builder - was inlined in the boss branch;
# now regular salvage drops use the exact same path at lower rarity.
func _create_procedural_component(rarity: int, mech: Node, name_prefix: String):
	var comp_script = load("res://scripts/core/ComponentEquipment.gd")
	var slots = [HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R, HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R, HexTile.BodySlot.HEAD, HexTile.BodySlot.TORSO]
	var slot = slots[randi() % slots.size()]
	var pack = comp_script.new(slot, rarity)
	pack.component_name = name_prefix + " " + str(slot) + " Drop"
	pack.role_variant = mech.combat_role if "combat_role" in mech else ""
	pack.generate_procedural_shape()

	# Add intake
	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = slot
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	return pack

func _spawn_component_drop(mech: Node, pack):
	if pack == null:
		return
	var drop = load("res://scripts/entities/LootPickup.gd").new()
	drop.equipment_data = pack
	drop.global_position = mech.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	if mech.get_parent():
		mech.get_parent().call_deferred("add_child", drop)

func _spawn_loot_drop(mech: Node, tile: HexTile):
	var drop = load("res://scripts/entities/LootPickup.gd").new()
	drop.tile_data = tile
	drop.global_position = mech.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	if mech.get_parent():
		mech.get_parent().call_deferred("add_child", drop)

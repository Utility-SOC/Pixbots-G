extends Node

# Confirms enemy tile rarity actually scales with base_rarity now, instead
# of defaulting to Common regardless. Spawns a bare Mythic-rarity Mech (the
# same _ready() path _spawn_bot_for_role triggers via add_child), then walks
# every equipped component's grid and reports what rarity each tile ended
# up at. Safe to delete once validated.

const MechScript = preload("res://scripts/entities/Mech.gd")
const RARITY_NAMES = ["Common", "Uncommon", "Rare", "Legendary", "Mythic"]

func _ready():
	for rarity in [HexTile.Rarity.COMMON, HexTile.Rarity.RARE, HexTile.Rarity.MYTHIC]:
		_check(rarity, "sniper")
	get_tree().quit()

func _check(base_rarity: int, role: String):
	var mech = MechScript.new()
	mech.is_player = false
	mech.combat_role = role
	mech.base_rarity = base_rarity
	# _ready() (triggered by add_child) already calls build_loadout_for_role
	# automatically for non-player mechs - don't call it again manually.
	add_child(mech)

	print("=== base_rarity=", RARITY_NAMES[base_rarity], " role=", role, " ===")
	var counts := {}
	for slot in mech.components.keys():
		var comp = mech.components[slot]
		for coord in comp.hex_grid.grid.keys():
			var tile = comp.hex_grid.grid[coord]
			var key = tile.tile_type + " (" + RARITY_NAMES[tile.rarity] + ")"
			counts[key] = counts.get(key, 0) + 1
	for k in counts.keys():
		print("  ", k, " x", counts[k])
	mech.queue_free()

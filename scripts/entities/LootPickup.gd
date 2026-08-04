class_name LootPickup
extends Area2D

var tile_data: HexTile = null
var equipment_data: Node = null # Can be ComponentEquipment
var chip_data: Dictionary = {} # Chip Splicing - a plain (single-trait) Mod Chip; see LootManager._spawn_chip_drop

func _ready():
	collision_layer = 16 # Layer 5 (Bit 4) for Loot
	collision_mask = 8   # Collide with player (Layer 4)
	add_to_group("loot")
	
	var poly = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0, -6), Vector2(5, -2), Vector2(5, 4), Vector2(0, 8), Vector2(-5, 4), Vector2(-5, -2)
	])
	
	if not chip_data.is_empty():
		poly.color = Color(1.0, 0.85, 0.2) # Amber diamond for chips - distinct from equipment pink / tile rarity colors
		poly.scale = Vector2(1.2, 1.2)
	elif equipment_data:
		poly.color = Color(1.0, 0.4, 0.8) # Pink for equipment
		poly.scale = Vector2(1.5, 1.5)
	elif tile_data:
		match tile_data.rarity:
			HexTile.Rarity.COMMON: poly.color = Color(0.8, 0.8, 0.8)
			HexTile.Rarity.UNCOMMON: poly.color = Color(0.2, 0.8, 0.2)
			HexTile.Rarity.RARE: poly.color = Color(0.2, 0.4, 1.0)
			HexTile.Rarity.LEGENDARY: poly.color = Color(1.0, 0.8, 0.2)
			HexTile.Rarity.MYTHIC: 
				poly.color = Color(0.0, 0.9, 1.0) # Shiny Teal
				
	add_child(poly)
	
	if (tile_data and tile_data.rarity == HexTile.Rarity.MYTHIC) or (equipment_data and equipment_data.get("rarity") == HexTile.Rarity.MYTHIC):
		# Very subtle light reflection animation for Mythic items
		var tw = create_tween().set_loops()
		tw.tween_property(poly, "color", Color(0.8, 1.0, 1.0), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(poly, "color", Color(0.0, 0.9, 1.0), 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	# LootPickup.new()+add_child() can happen synchronously from inside a
	# projectile's own physics collision callback (kill a mech -> die() ->
	# loot drop, all still on the same _on_area_entered stack) - adding a
	# CollisionShape2D here would mutate physics state while the physics
	# server is still flushing the very query that led here ("Can't change
	# this state while flushing queries"). Worse than the same-shaped bug
	# already fixed in ExtractionMarker.gd: that one only broke Garage
	# visuals, this one means the shape genuinely never attaches, so the
	# pickup's Area2D can never detect the player standing on it - loot
	# that LOOKS present (its sprite adds fine) but can never actually be
	# collected, sitting inert forever exactly like the "loot just sitting
	# still nearby" reports.
	call_deferred("add_child", shape)

	body_entered.connect(_on_body_entered)

# `_strength` accepted-and-ignored: loot always pulls at a fixed speed
# regardless of source strength, but every OTHER pull_towards caller in the
# codebase (Mech.pull_towards, Projectile._apply_vortex_pull_to_target, the
# vortex-burst detonation in _resolve_detonation) passes a 3rd strength arg
# unconditionally - a real, pre-existing bug (found 2026-08-03 while
# testing task #33's vortex-pull batching): any Vortex-ratio shot that ever
# got near dropped loot threw "Invalid call... Expected 2 argument(s)" and
# silently skipped pulling that loot, in the shipped game, before this fix.
func pull_towards(target_pos: Vector2, delta_mod: float, _strength: float = 0.0):
	# The vortex effect
	var speed = 200.0 * delta_mod
	global_position = global_position.move_toward(target_pos, speed)

# Used by Mech's Magnet pull logic (Mythic Magnets can filter by rarity).
func get_rarity() -> int:
	if equipment_data:
		return equipment_data.get("rarity")
	elif tile_data:
		return tile_data.rarity
	return -1

func _on_body_entered(body: Node2D):
	if body.has_method("equip_component") and "is_player" in body and body.is_player:
		# NOTE: was body.get_parent() - that broke when the player mech moved
		# from being a direct child of Main to a child of Main.world (the
		# pixel-viewport game world). current_scene still resolves to Main
		# regardless of nesting depth.
		if not chip_data.is_empty():
			print("Player picked up a chip")
			var main = body.get_tree().current_scene
			if main and "player_modifier_chips" in main:
				main.player_modifier_chips.append(chip_data)
		elif equipment_data:
			print("Player picked up equipment: ", equipment_data.component_name)
			var main = body.get_tree().current_scene
			if main and "player_component_inventory" in main:
				main.player_component_inventory.append(equipment_data)
		elif tile_data:
			print("Player picked up tile: ", tile_data.tile_type)
			var main = body.get_tree().current_scene
			if main and "player_inventory" in main:
				main.player_inventory.append(tile_data)
				TileDiscoveryPopup.announce_if_new(tile_data)
			
		queue_free()

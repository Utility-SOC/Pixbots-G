class_name LootPickup
extends Area2D

var tile_data: HexTile = null
var equipment_data: Node = null # Can be ComponentEquipment

func _ready():
	collision_layer = 16 # Layer 5 (Bit 4) for Loot
	collision_mask = 8   # Collide with player (Layer 4)
	add_to_group("loot")
	
	var poly = Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0, -6), Vector2(5, -2), Vector2(5, 4), Vector2(0, 8), Vector2(-5, 4), Vector2(-5, -2)
	])
	
	if equipment_data:
		poly.color = Color(1.0, 0.4, 0.8) # Pink for equipment
		poly.scale = Vector2(1.5, 1.5)
	elif tile_data:
		match tile_data.rarity:
			HexTile.Rarity.COMMON: poly.color = Color(0.8, 0.8, 0.8)
			HexTile.Rarity.UNCOMMON: poly.color = Color(0.2, 0.8, 0.2)
			HexTile.Rarity.RARE: poly.color = Color(0.2, 0.4, 1.0)
			HexTile.Rarity.LEGENDARY: poly.color = Color(1.0, 0.8, 0.2)
			
	add_child(poly)
	
	var shape = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	add_child(shape)
	
	body_entered.connect(_on_body_entered)

func pull_towards(target_pos: Vector2, delta: float):
	# The vortex effect
	var dir = global_position.direction_to(target_pos)
	global_position += dir * 200.0 * delta

func _on_body_entered(body: Node2D):
	if body.has_method("equip_component") and "is_player" in body and body.is_player:
		if equipment_data:
			print("Player picked up equipment: ", equipment_data.component_name)
			var main = body.get_parent()
			if main and "player_component_inventory" in main:
				main.player_component_inventory.append(equipment_data)
		elif tile_data:
			print("Player picked up tile: ", tile_data.tile_type)
			var main = body.get_parent()
			if main and "player_inventory" in main:
				main.player_inventory.append(tile_data)
			
		queue_free()

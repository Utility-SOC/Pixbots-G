class_name LootDrop
extends Area2D

var contained_tile: HexTile

func _ready():
	var shape = CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	shape.shape.radius = 20.0
	add_child(shape)
	
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D):
	if "is_player" in body and body.is_player:
		# Add to player inventory
		print("Player looted: ", contained_tile.tile_type, " (", contained_tile.rarity, ")")
		# Give to player garage (GarageUI logic will catch this later)
		queue_free()

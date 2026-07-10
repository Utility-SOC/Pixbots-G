extends Node

# Confirms LootPickup's collision shape actually attaches after the
# call_deferred fix (deferred calls need a frame to flush - can't check
# immediately after add_child). Safe to delete once validated.

const LootPickup = preload("res://scripts/entities/LootPickup.gd")
const WeaponMountTile = preload("res://scripts/tiles/WeaponMountTile.gd")

var pickup: LootPickup
var _frames := 0

func _ready():
	pickup = LootPickup.new()
	pickup.tile_data = WeaponMountTile.new()
	pickup.tile_data.rarity = HexTile.Rarity.RARE
	add_child(pickup)
	print("Immediately after add_child - child_count: ", pickup.get_child_count(), " (shape not expected yet, deferred)")

func _process(_delta):
	_frames += 1
	if _frames == 2:
		var has_shape = false
		for c in pickup.get_children():
			if c is CollisionShape2D:
				has_shape = true
		print("After 2 frames - child_count: ", pickup.get_child_count(), " has_collision_shape: ", has_shape)
		if has_shape:
			print("PASS")
		else:
			push_error("FAIL: CollisionShape2D never attached")
		get_tree().quit()

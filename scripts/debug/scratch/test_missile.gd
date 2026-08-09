extends SceneTree

func _init():
	var mech = load("res://scripts/entities/Mech.gd").new()
	mech.is_player = true
	var root = Node2D.new()
	root.add_child(mech)

	var tile = load("res://scripts/tiles/MissileRackTile.gd").new()
	print("Tile type: ", tile.tile_type)

	var comp = load("res://scripts/core/ComponentEquipment.gd").create_starter_torso("", 1)
	comp.hex_grid.set_tile(HexCoord.new(0, 0), tile)
	mech.equip_component(comp)

	mech._reset_grid_state()

	var packet = load("res://scripts/core/EnergyPacket.gd").new(100.0, HexCoord.new(0, 0))
	tile.process_energy(packet, 0)

	mech._collect_weapon_mounts_and_tile_capabilities()

	print("Precalculated weapons size: ", mech.precalculated_weapons.size())
	for p in mech.precalculated_weapons:
		print(" - ", p.mount.tile_type, ", charge: ", p.packet.charge_required, ", mag: ", p.packet.magnitude)

	mech.last_aim_position = Vector2(0, 0)
	mech.precalculated_weapons[0].mount.current_charge = 1000.0

	# add a dummy target
	var dummy = load("res://scripts/entities/Mech.gd").new()
	dummy.is_player = false
	dummy.global_position = Vector2(400, 0)
	root.add_child(dummy)

	# wait for physics frame so EntityCache gets it
	await get_tree().process_frame

	print("Enemy group size: ", EntityCache.get_group("enemy").size())

	var fired = mech._shoot_impl(Vector2(0, 0), true, true, 0.16)
	print("Fired: ", fired)

	quit()

extends SceneTree

func _init():
	var file = FileAccess.open("j:/pixel_bots/godot/missile_test_out.txt", FileAccess.WRITE)
	file.store_line("Starting test...")

	var mech = load("res://scripts/entities/Mech.gd").new()
	mech.is_player = true
	var root = Node2D.new()
	root.add_child(mech)

	var tile = load("res://scripts/tiles/MissileRackTile.gd").new()
	file.store_line("Tile type: " + str(tile.tile_type))

	var comp = load("res://scripts/core/ComponentEquipment.gd").create_starter_torso("", 1)
	comp.hex_grid.set_tile(HexCoord.new(0, 0), tile)
	mech.equip_component(comp)

	mech._reset_grid_state()

	var packet = load("res://scripts/core/EnergyPacket.gd").new(100.0, HexCoord.new(0, 0))
	tile.process_energy(packet, 0)

	mech._collect_weapon_mounts_and_tile_capabilities()

	file.store_line("Precalculated weapons size: " + str(mech.precalculated_weapons.size()))
	for p in mech.precalculated_weapons:
		file.store_line(" - " + str(p.mount.tile_type) + ", charge: " + str(p.packet.charge_required) + ", mag: " + str(p.packet.magnitude))

	mech.last_aim_position = Vector2(0, 0)
	mech.precalculated_weapons[0].mount.current_charge = 1000.0

	# add a dummy target
	var dummy = load("res://scripts/entities/Mech.gd").new()
	dummy.is_player = false
	dummy.global_position = Vector2(400, 0)
	root.add_child(dummy)

	var EntityCache = load("res://scripts/core/EntityCache.gd").new()
	root.add_child(EntityCache)

	# wait for physics frame so EntityCache gets it
	# Can't await easily in SceneTree without a running loop? We'll just call the method manually if possible, or wait

	file.close()
	quit()

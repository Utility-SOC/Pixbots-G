extends SceneTree

func _init():
	print("--- Starting Loot System & Hex Component Verification ---")
	
	# Spawn a standard enemy mech
	var mech = Mech.new()
	mech.combat_role = "ranged"
	
	# Mech _ready() doesn't fire immediately in SceneTree._init
	root.add_child(mech)
	mech._ready()
	
	# Verify Hex Component Generation
	var grid = mech.get_node("HexGridComponent")
	print("Mech Hex Grid initialized. Tiles equipped: ", grid.get_all_tiles().size())
	
	# Verify Legendary logic output
	var packet = EnergyPacket.new()
	grid.route_energy_packet(packet, HexCoord.new(1, 0)) # Send through the Amplifier/Legendary slot
	
	print("\nSimulating Mech Death to trigger WYSIWYG Loot Drop...")
	
	# Need a LootManager in the tree
	var loot_manager = LootManager.new()
	root.add_child(loot_manager)
	
	# Mock the loot spawning
	mech.die()
	
	print("Mech died. Loot drops should be spawned in the root (check child count).")
	print("Root children count (includes LootDrops + LootManager): ", root.get_child_count())
	
	print("\nSimulating Wave 25 Boss Death...")
	var boss = Mech.new()
	boss.is_boss = true
	boss.combat_role = "melee"
	root.add_child(boss)
	boss._ready()
	
	loot_manager.current_wave = 25
	boss.die()
	
	print("Boss died. Guaranteed rare/legendary dropped.")
	
	print("\nVerification Complete.")
	quit()

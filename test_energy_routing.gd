extends SceneTree

func _init():
	print("--- Starting Energy Routing & Attack Verification ---")
	
	var mech = Mech.new()
	root.add_child(mech)
	mech._ready()
	
	var grid = mech.get_node("HexGridComponent")
	
	# Create a routing test setup
	# (0, 0) -> Splitter -> (1, 0) and (1, 1)
	# (1, 0) -> Amplifier -> (2, 0) -> WeaponMount (Fire)
	# (1, 1) -> Catalyst -> (2, 1) -> WeaponMount (Vampiric)
	
	var splitter = SplitterTile.new()
	splitter.split_count = 2
	grid.add_tile(HexCoord.new(0, 0), splitter)
	
	var amplifier = AmplifierTile.new()
	amplifier.amplification = 2.0
	grid.add_tile(HexCoord.new(1, 0), amplifier)
	
	var catalyst = CatalystTile.new()
	catalyst.input_synergies.append(EnergyPacket.SynergyType.FIRE)
	catalyst.output_synergy = EnergyPacket.SynergyType.VAMPIRIC
	catalyst.efficiency = 1.5
	grid.add_tile(HexCoord.new(1, 1), catalyst)
	
	var weapon1 = WeaponMountTile.new()
	grid.add_tile(HexCoord.new(2, 0), weapon1)
	
	var weapon2 = WeaponMountTile.new()
	grid.add_tile(HexCoord.new(2, 1), weapon2)
	
	# Send packet!
	var packet = EnergyPacket.new(100.0)
	packet.synergies.clear()
	packet.add_synergy(EnergyPacket.SynergyType.FIRE, 100.0)
	
	print("Initial Packet: Mag 100, FIRE 100")
	var split_packets = splitter.process_energy(packet, 0, grid)
	print("After Splitter: ", split_packets.size(), " packets")
	
	# Route Top path
	var top_packet = split_packets[0]
	print(" Top Packet Mag: ", top_packet.magnitude)
	var amp_packets = amplifier.process_energy(top_packet, 0, grid)
	print(" After Amp Mag: ", amp_packets[0].magnitude)
	weapon1.process_energy(amp_packets[0], 0, grid)
	print(" Weapon 1 Fired! Check Mech children.")
	
	# Route Bottom path
	var bot_packet = split_packets[1]
	print(" Bot Packet Mag: ", bot_packet.magnitude)
	var cat_packets = catalyst.process_energy(bot_packet, 0, grid)
	print(" After Catalyst Vampiric Mag: ", cat_packets[0].synergies.get(EnergyPacket.SynergyType.VAMPIRIC, 0))
	weapon2.process_energy(cat_packets[0], 0, grid)
	print(" Weapon 2 Fired! Check Mech children.")
	
	var children = mech.get_children()
	var attack_names = []
	for c in children:
		if "damage" in c:
			attack_names.append(c.name)
	print("Spawned Attacks: ", attack_names)
	
	print("\nVerification Complete.")
	quit()

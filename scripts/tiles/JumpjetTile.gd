class_name JumpjetTile
extends HexTile

@export var speed_boost_mult: float = 1.5

# MYTHIC ability: locomotion mode. 0 = standard jump/sprint boost,
# 1 = Blink (instant short-range teleport toward the cursor with a
# cooldown - see PlayerController.handle_input). Hover is deferred until outer
# walls and interior obstacles live on separate collision layers; otherwise
# hovering drifts you straight out of the map.
@export_enum("Jump", "Blink") var mythic_mode: int = 0

func cycle_mythic_mode():
	if rarity == Rarity.MYTHIC:
		mythic_mode = (mythic_mode + 1) % 2

func _init():
	tile_type = "Jumpjet"
	category = TileCategory.OUTPUT

func get_weight() -> float:
	return 7.0 # propulsion hardware - heavy, ironic given what it does

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	if packet.magnitude <= 0.0 or not packet.is_active: return []

	packet.is_active = false

	if grid and grid.get_parent():
		var mech = grid.get_parent()
		if mech and "slot_type" in mech:
			mech = mech.get_parent()
			
		if mech and "current_move_speed" in mech and "base_move_speed" in mech:
			if not "jumpjet_energy" in mech:
				mech.set("jumpjet_energy", EnergyPacket.new(0.0, null))
				mech.get("jumpjet_energy").synergies.clear()
				
			var j_energy = mech.get("jumpjet_energy")
			if j_energy:
				j_energy.merge(packet)
			
			if "ignore_terrain" in mech:
				mech.ignore_terrain = true
			if "jumpjet_rarity" in mech:
				mech.jumpjet_rarity = max(mech.jumpjet_rarity, rarity)
				
	return []


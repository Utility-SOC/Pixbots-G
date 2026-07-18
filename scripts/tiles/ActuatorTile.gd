class_name ActuatorTile
extends HexTile

var current_speed_bonus: float = 0.0
@export var base_speed_multiplier: float = TileStatsRegistry.get_stat("ActuatorTile", "base_speed_multiplier", 0.5)

# MYTHIC "Schools" - three distinct feels for the melee/ramming pillar
# (see Mech._process_ramming and update_status_effects), per the user:
#   Velocity - fast, low damage: more move speed, weaker ram hits.
#   Ember    - slow, fire effect: less move speed, but rams hit harder and
#              set the target burning.
#   Balanced - moderate speed/damage, plus a utility perk: extra knockback
#              on a successful ram, and a brief self damage-reduction window
#              right after (the actuator "absorbing" the impact shock).
# Same UI/data pattern as every other Mythic toggle (Jumpjet Jump/Blink,
# Amplifier's 3-way focus, etc.) - see GarageMenu.gd's generic Mythic popup.
@export_enum("Velocity", "Ember", "Balanced") var mythic_mode: int = 0

func cycle_mythic_mode():
	mythic_mode = (mythic_mode + 1) % 3

func _init():
	tile_type = "Actuator"
	category = TileCategory.OUTPUT
	base_color = Color(0.8, 0.4, 0.1) # Orange/Brown for motor

func get_weight() -> float:
	return TileStatsRegistry.get_stat("ActuatorTile", "weight", 7.0) # motor hardware - heavy

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	var p = packet.copy()
	# Calculate speed bonus based on energy
	current_speed_bonus = p.magnitude * base_speed_multiplier
	if p.has_synergy(EnergyPacket.SynergyType.KINETIC):
		current_speed_bonus *= TileStatsRegistry.get_stat("ActuatorTile", "kinetic_bonus_mult", 1.5)
	if p.has_synergy(EnergyPacket.SynergyType.LIGHTNING):
		current_speed_bonus *= TileStatsRegistry.get_stat("ActuatorTile", "lightning_bonus_mult", 2.0)
		
	if grid and grid.get_parent():
		var mech = grid.get_parent()
		if mech and "slot_type" in mech:
			mech = mech.get_parent()
			
		if mech and "actuator_energy" in mech:
			if not mech.get("actuator_energy"):
				mech.set("actuator_energy", EnergyPacket.new(0.0, null))
			mech.get("actuator_energy").merge(p)
		
	p.is_active = false
	p.magnitude = 0.0
	return [p]

func get_speed_bonus() -> float:
	var bonus = current_speed_bonus
	current_speed_bonus = 0.0 # reset for next tick
	return bonus

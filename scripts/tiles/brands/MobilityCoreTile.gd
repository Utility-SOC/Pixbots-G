class_name MobilityCoreTile
extends HexTile

# Corporate Sponsorships (task #17): Velocity Works' signature tile - a
# Jumpjet that's also a Maneuvering Thruster, with its own self-contained
# reactor ("has its own self contained reactor" - locked design). Every other
# ability tile in the game is an energy SINK that only does anything once a
# packet actually routes to it (JumpjetTile/ActuatorTile both early-return
# on packet.magnitude <= 0) - a self-contained reactor means this one grants
# its jumpjet_rarity/thruster_accel_bonus capacity UNCONDITIONALLY, purely
# from being equipped, detected by presence in
# Mech._collect_weapon_mounts_and_tile_capabilities() rather than by
# consuming a routed packet. process_energy() stays a harmless pass-through
# so this tile doesn't disrupt routing if something does happen to feed it.
#
# ignore_terrain (the flag JumpjetTile.process_energy() also sets) is
# deliberately NOT reproduced here - it's dead code on the base tile too
# (nothing ever declares that field on Mech, so JumpjetTile's own
# `if "ignore_terrain" in mech:` guard has always been false; the real
# jumpjet-capability gate everywhere else in the codebase is
# `jumpjet_rarity >= 0`, e.g. Mech._has_jumpjets()).

func _init():
	tile_type = "Mobility Core"
	category = TileCategory.SPECIAL
	base_color = Color(0.3, 0.75, 0.9)

func get_weight() -> float:
	return TileStatsRegistry.get_stat("MobilityCoreTile", "weight", 6.0)

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null, entry_coord: HexCoord = null) -> Array[EnergyPacket]:
	return [packet]

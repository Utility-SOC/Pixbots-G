extends Node

# Perf audit (2026-08-01) item 1: OrbitingArrayTile used to key its per-face
# energy accumulator Dictionary with a freshly-allocated String (a
# concatenated "cell:dir" string) on every single energy packet - real
# per-packet allocation in a hot simulation path. Switched to a Vector2i
# key, natively hashable, no allocation. This check proves the face-gating
# logic (accumulate per face, fire once every distinct face crosses
# threshold) still behaves identically with the new key type - distinct
# faces stay distinct, gating fires at the right face count.
#
# MissileRackTile's own half of this check was removed (2026-08-11) - the
# per-face accumulator (_face_magnitudes/ready_to_fire) it originally
# covered doesn't exist on that tile anymore. MissileRackTile migrated to
# the same pending_packets/current_charge/bank_current_charge model
# WeaponMountTile already uses (commit a28a8c9, "Implement full indirect
# salvo firing for MissileRackTile," 2026-07-26 - well before this check
# was even written) - firing is now driven by a shared scalar charge
# threshold via Mech.gd's weapon-mount collection loop, not per-face
# gating. This check had been silently broken since that migration; there
# is no per-face-key equivalent left on MissileRackTile to test.

const OrbitingArrayTileScript = preload("res://scripts/tiles/OrbitingArrayTile.gd")
const EnergyPacketScript = preload("res://scripts/core/EnergyPacket.gd")

func _make_packet(magnitude: float) -> EnergyPacket:
	var p = EnergyPacketScript.new()
	p.magnitude = magnitude
	p.is_active = true
	p.add_synergy(EnergyPacket.SynergyType.RAW, magnitude)
	return p

func _ready():
	var failures = 0

	# --- OrbitingArrayTile: Vector2i face_key, distinct (cell, dir) pairs stay distinct ---
	var orbit = OrbitingArrayTileScript.new()
	var face_threshold = TileStatsRegistry.get_stat("OrbitingArrayTile", "face_threshold", 10000.0)
	var required_faces = int(TileStatsRegistry.get_stat("OrbitingArrayTile", "required_faces", 6))

	# Same cell_idx (always 0 here - no grid_position/entry_coord set, matching
	# process_energy's own "no grid context" fallback), 3 distinct entry
	# directions - each should occupy its OWN Vector2i(0, dir) key, not collide.
	for dir in range(3):
		orbit.process_energy(_make_packet(face_threshold * 1.1), dir)
	if orbit._face_magnitudes.size() != 3:
		push_error("FAIL LEAK: OrbitingArrayTile Vector2i face_key collided across distinct directions - expected 3 distinct keys, got %d (%s)" % [orbit._face_magnitudes.size(), orbit._face_magnitudes])
		failures += 1
	else:
		print("PASS: OrbitingArrayTile Vector2i face_key keeps distinct (cell, dir) pairs separate")

	var fed_count = 0
	for fk in orbit._face_magnitudes:
		if float(orbit._face_magnitudes[fk]) >= face_threshold:
			fed_count += 1
	if fed_count != 3:
		push_error("FAIL: expected 3 fed faces after 3 over-threshold distinct-direction hits, got %d" % fed_count)
		failures += 1
	else:
		print("PASS: OrbitingArrayTile correctly counts 3 fed faces from 3 distinct-direction over-threshold hits")

	if orbit.ready_to_fire:
		push_error("FAIL: OrbitingArrayTile shouldn't be ready_to_fire yet (3 of %d required faces fed)" % required_faces)
		failures += 1
	else:
		print("PASS: OrbitingArrayTile correctly NOT ready_to_fire with only 3 of %d faces fed" % required_faces)

	if failures == 0:
		print("PASS: CapitalWeaponFaceKeyCheck - OrbitingArrayTile face-gating unchanged after switching off string keys")
	get_tree().quit(0 if failures == 0 else 1)

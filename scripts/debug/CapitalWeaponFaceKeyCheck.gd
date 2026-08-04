extends Node

# Perf audit (2026-08-01) item 1: MissileRackTile/OrbitingArrayTile used to
# key their per-face energy accumulator Dictionary with a freshly-allocated
# String (str(entry_direction), or a concatenated "cell:dir" string) on
# every single energy packet - real per-packet allocation in a hot
# simulation path. Switched to a raw int (MissileRackTile) / Vector2i
# (OrbitingArrayTile) key, both natively hashable, no allocation. This
# check proves the face-gating logic (accumulate per face, fire once every
# distinct face crosses threshold) still behaves identically with the new
# key types - same face stays additive across repeated hits, different
# faces stay distinct, gating fires at the right face count.

const MissileRackTileScript = preload("res://scripts/tiles/MissileRackTile.gd")
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

	# --- MissileRackTile: int face_key, one direction repeated hits accumulate ---
	var rack = MissileRackTileScript.new()
	var threshold = TileStatsRegistry.get_stat("MissileRackTile", "feed_threshold", 2000.0)
	rack.process_energy(_make_packet(threshold * 0.4), 2)
	rack.process_energy(_make_packet(threshold * 0.4), 2) # same direction, should accumulate under _face_magnitudes[2]
	if rack._face_magnitudes.get(2, 0.0) < threshold * 0.79:
		push_error("FAIL: MissileRackTile int face_key isn't accumulating repeated hits on the same direction (got %s)" % [rack._face_magnitudes])
		failures += 1
	else:
		print("PASS: MissileRackTile int face_key accumulates repeated hits on the same direction")

	rack.clear_pending()
	rack.ready_to_fire = false
	rack.process_energy(_make_packet(threshold * 1.5), 3)
	if not rack.ready_to_fire:
		push_error("FAIL: MissileRackTile didn't gate ready_to_fire on a single over-threshold hit")
		failures += 1
	else:
		print("PASS: MissileRackTile int face_key still gates ready_to_fire correctly")

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
		print("PASS: CapitalWeaponFaceKeyCheck - MissileRackTile/OrbitingArrayTile face-gating unchanged after switching off string keys")
	get_tree().quit(0 if failures == 0 else 1)

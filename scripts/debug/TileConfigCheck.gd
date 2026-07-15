extends Node

# Regression harness for the tile-config batch (Status.md queue items 1-2):
#   - Resonator per-path Sync Dropoff (tunable, clamped, drives residue)
#   - Mythic Splitter output-ratio weights (split fractions follow them)
#   - Catalyst gated injection (magnitude gate + every-Nth cadence)
#   - Accumulator auto-dump (packet stamping, adjacency pickup, and the
#     player bank actually firing itself at the threshold)
#   - save round-trip of every new knob through _serialize_tile/JSON

const MechScript = preload("res://scripts/entities/Mech.gd")
const ResonatorTileScript = preload("res://scripts/tiles/ResonatorTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const CatalystTileScript = preload("res://scripts/tiles/CatalystTile.gd")
const AccumulatorTileScript = preload("res://scripts/tiles/AccumulatorTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")

func _count_projectiles(world: Node) -> int:
	var n = 0
	for c in world.get_children():
		if c.is_in_group("projectile"):
			n += 1
	return n

func _ready():
	var failures = 0
	var world = Node2D.new()
	add_child(world)

	# --- 1. Resonator per-path dropoff -------------------------------------
	var reso = ResonatorTileScript.new()
	reso.rarity = HexTile.Rarity.MYTHIC
	reso.adjust_sync_dropoff(0, 4)   # 3 -> 7
	reso.adjust_sync_dropoff(1, -9)  # clamps at 1
	reso.adjust_sync_dropoff(2, 99)  # clamps at 9
	var pkt = EnergyPacket.new(0.0, null)
	pkt.synergies.clear()
	pkt.add_synergy(EnergyPacket.SynergyType.FIRE, 100.0)
	reso.process_energy(pkt, 0) # path 0 deposit
	var res0 = reso._path_residue.get(0, {})
	if reso.get_sync_dropoff(0) != 7 or reso.get_sync_dropoff(1) != 1 or reso.get_sync_dropoff(2) != 9:
		push_error("FAIL: dropoff adjust/clamp wrong: %s" % str(reso.sync_dropoff_per_path))
		failures += 1
	elif int(res0.get("steps_left", -1)) != 7:
		push_error("FAIL: deposited residue used steps_left=%s, expected 7" % str(res0))
		failures += 1
	else:
		print("1) resonator: per-path dropoff 7/1/9 (clamped), residue born with 7 steps")

	# --- 2. Mythic Splitter ratio weights -----------------------------------
	var split = SplitterTileScript.new()
	split.rarity = HexTile.Rarity.MYTHIC
	# active_faces defaults to [1, 5]; weight face 1 to 9x face 5
	split.adjust_ratio_weight(1, 8.0)
	var spkt = EnergyPacket.new(0.0, null)
	spkt.synergies.clear()
	spkt.add_synergy(EnergyPacket.SynergyType.RAW, 100.0)
	var outs = split.process_energy(spkt, 0)
	var total_out = 0.0
	for p in outs:
		total_out += p.magnitude
	var heavy = outs[0].magnitude / max(0.001, total_out) # face 1 is emitted first
	if outs.size() != 2 or abs(heavy - 0.9) > 0.02:
		push_error("FAIL: 9:1 weighted split gave %d packets, heavy share %.3f (expected ~0.90)" % [outs.size(), heavy])
		failures += 1
	else:
		print("2) mythic splitter 9:1 weights: heavy face carries %.0f%% of the volley" % (heavy * 100.0))

	# --- 3. Catalyst gates ----------------------------------------------------
	var cat = CatalystTileScript.new()
	cat.target_synergy = EnergyPacket.SynergyType.ICE
	cat.gate_min_magnitude = 50.0
	var small = EnergyPacket.new(0.0, null)
	small.synergies.clear()
	small.add_synergy(EnergyPacket.SynergyType.FIRE, 30.0)
	cat.process_energy(small, 0)
	var small_untouched = small.synergies.has(EnergyPacket.SynergyType.FIRE) and not small.synergies.has(EnergyPacket.SynergyType.ICE)
	var big = EnergyPacket.new(0.0, null)
	big.synergies.clear()
	big.add_synergy(EnergyPacket.SynergyType.FIRE, 100.0)
	cat.process_energy(big, 0)
	var big_converted = big.synergies.has(EnergyPacket.SynergyType.ICE) and not big.synergies.has(EnergyPacket.SynergyType.FIRE)
	if not small_untouched or not big_converted:
		push_error("FAIL: magnitude gate (small untouched=%s, big converted=%s)" % [small_untouched, big_converted])
		failures += 1
	else:
		print("3a) catalyst magnitude gate: 30 passes through, 100 converts")

	var cat2 = CatalystTileScript.new()
	cat2.target_synergy = EnergyPacket.SynergyType.ICE
	cat2.gate_every_n = 3
	var converted = 0
	for i in range(6):
		var p = EnergyPacket.new(0.0, null)
		p.synergies.clear()
		p.add_synergy(EnergyPacket.SynergyType.FIRE, 100.0)
		cat2.process_energy(p, 0)
		if p.synergies.has(EnergyPacket.SynergyType.ICE):
			converted += 1
	if converted != 2:
		push_error("FAIL: every-3rd cadence converted %d of 6, expected 2" % converted)
		failures += 1
	else:
		print("3b) catalyst cadence: exactly 2 of 6 packets catalyzed at every-3rd")

	# --- 4. Accumulator auto-dump: stamp + adjacency + live fire ------------
	var acc = AccumulatorTileScript.new()
	acc.auto_dump_threshold = 0.5
	var apkt = EnergyPacket.new(100.0, null)
	acc.process_energy(apkt, 0)
	var carried = apkt.copy().auto_dump_threshold
	var merged_pkt = EnergyPacket.new(50.0, null)
	merged_pkt.merge(apkt)
	if abs(carried - 0.5) > 0.001 or abs(merged_pkt.auto_dump_threshold - 0.5) > 0.001:
		push_error("FAIL: auto_dump stamp/copy/merge lost the threshold")
		failures += 1
	else:
		print("4a) auto-dump threshold survives stamp, copy, and merge")

	var mech = MechScript.new()
	mech.is_player = true
	world.add_child(mech)
	mech.set_physics_process(false)
	mech.last_aim_position = Vector2(500, 0)
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	mount.body_slot = HexTile.BodySlot.TORSO
	var bank_packet = EnergyPacket.new(80.0, null)
	bank_packet.charge_required = 10.0
	bank_packet.auto_dump_threshold = 0.5
	mech.precalculated_weapons = [{
		"mount": mount, "packet": bank_packet, "step": 0,
		"slot_type": HexTile.BodySlot.TORSO, "bank_mode": "bank",
	}]
	mount.bank_current_charge = 5.5 # 55% of required - past the 50% threshold
	var before = _count_projectiles(world)
	mech._tick_weapon_charges(0.0)
	var after = _count_projectiles(world)
	if after != before + 1 or mount.bank_current_charge != 0.0:
		push_error("FAIL: auto-dump didn't fire at 55%%/50%% (spawned %d, bank %.2f)" % [after - before, mount.bank_current_charge])
		failures += 1
	else:
		# Below threshold: must NOT fire.
		mount.bank_current_charge = 4.0
		mech._tick_weapon_charges(0.0)
		if _count_projectiles(world) != after:
			push_error("FAIL: auto-dump fired below its threshold")
			failures += 1
		else:
			print("4b) player bank auto-dumps at 55%/50%, holds at 40%")

	# --- 5. Save round-trip of every new knob --------------------------------
	split.grid_position = HexCoord.new(1, 1)
	reso.grid_position = HexCoord.new(0, 1)
	cat.grid_position = HexCoord.new(1, 0)
	acc.grid_position = HexCoord.new(2, 0)
	cat.gate_every_n = 4
	var rt_ok = true
	for tile in [reso, split, cat, acc]:
		var data = JSON.parse_string(JSON.stringify(SaveManager._serialize_tile(tile)))
		var back = SaveManager._deserialize_tile(data)
		for prop in ["sync_dropoff_per_path", "output_ratios", "auto_dump_threshold", "gate_min_magnitude", "gate_every_n"]:
			if prop in tile:
				var a = tile.get(prop)
				var b = back.get(prop)
				if str(a) != str(b) and var_to_str(a) != var_to_str(b):
					# Arrays come back as floats from JSON - compare loosely
					if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY and a.size() == b.size():
						var same = true
						for i in range(a.size()):
							if abs(float(a[i]) - float(b[i])) > 0.001:
								same = false
						if same:
							continue
					if typeof(a) in [TYPE_INT, TYPE_FLOAT] and abs(float(a) - float(b)) < 0.001:
						continue
					push_error("FAIL: %s.%s didn't round-trip (%s -> %s)" % [tile.tile_type, prop, str(a), str(b)])
					rt_ok = false
					failures += 1
	if rt_ok:
		print("5) all four tiles' config knobs survive a JSON save round-trip")

	if failures == 0:
		print("PASS: tile config batch - resonator dropoff, splitter ratios, catalyst gates, accumulator auto-dump")
	get_tree().quit(0 if failures == 0 else 1)

class_name RustGridSim
extends RefCounted

# GDScript half of the Rust hexgrid-sim port (rust_ext/src/hexgrid_sim.rs -
# see its header for the kind table and parity discipline). Walks a grid,
# describes every tile as flat data, and hands the whole packet-routing
# loop to Rust in ONE call; the results (weapon-mount captures, link
# transfers, storage-sink banking, conduit glow synergies) are then written
# back onto the real tile objects so everything downstream of
# Mech._simulate_grid stays byte-identical.
#
# SUPPORTED SUBSET: any grid containing a tile this bridge can't describe
# (stateful tiles - Resonator remnants, Accumulators, Mythic Splitters -
# gated/inverted Catalysts, Magnets, Filters, Lances, shields/cloaks/jets,
# brand tiles...) falls back to the original GDScript sim automatically by
# try_simulate() returning false. RustGridSimParityCheck.gd holds the two
# paths identical on supported builds.

const KIND_PASS = 0
const KIND_AMPLIFIER = 1
const KIND_SPLITTER = 2
const KIND_REFLECTOR = 3
const KIND_CONDUIT = 4
const KIND_INFUSER = 5
const KIND_CATALYST = 6
const KIND_CORE = 7
const KIND_MOUNT_SINK = 8
const KIND_LINK_SINK = 9
const KIND_LINK_ROUTER = 10
const KIND_STORE_SINK = 11
const KIND_FILTER = 12
const KIND_MAGNET = 13
const KIND_JUMPJET = 14
const KIND_ACTUATOR = 15
const KIND_SHIELD_STORE = 16
const KIND_ACCUMULATOR = 17
const KIND_RESONATOR = 18
const KIND_RESONATOR_SYNC = 19
const KIND_PRIME_CIRCUIT = 20
const KIND_LANCE = 21
const KIND_THRUSTER = 22

# MASTER GATE for the Rust path. ENABLED after RustGridSimParityCheck went
# fully green (2026-07-19): captures, transfers, stores, synergies, AND
# traversal steps all packet-identical. (The step divergence the check
# originally caught wasn't the Rust engine at all - SaveManager was
# re-rolling sync_adjustment on every tile clone/load; fixed there.)
# The parity check bypasses this gate so it keeps guarding either way.
const ENABLED = true

static var _sim = null
static var _checked: bool = false

static func _ensure_sim():
	if not _checked:
		_checked = true
		if ClassDB.class_exists("HexGridSim"):
			var candidate = ClassDB.instantiate("HexGridSim")
			# The shipped stub also exposes is_implemented() (false) - only
			# accept the real Phase-1 implementation.
			if candidate and candidate.is_implemented():
				_sim = candidate
	return _sim

static func is_available() -> bool:
	return _ensure_sim() != null

# Describes one tile, or returns {} when the tile is outside the supported
# subset (which vetoes the whole grid - fallback to GDScript).
static func _describe_tile(tile) -> Dictionary:
	var d = {
		"q": tile.grid_position.q if tile.grid_position else 0,
		"r": tile.grid_position.r if tile.grid_position else 0,
		"rarity": int(tile.rarity),
		"disabled": bool(tile.is_disabled),
		"sync_adjustment": int(tile.sync_adjustment),
	}
	var t: String = tile.tile_type
	var script_path = tile.get_script().resource_path if tile.get_script() else ""

	if t == "Amplifier":
		var mult = tile.amplification * tile._get_power_multiplier()
		var aoe_add = 0.0
		if tile.rarity == HexTile.Rarity.MYTHIC:
			match int(tile.mythic_focus):
				1: mult *= TileStatsRegistry.get_stat("AmplifierTile", "mythic_pure_damage_mult", 1.75)
				2:
					mult *= TileStatsRegistry.get_stat("AmplifierTile", "mythic_aoe_power_mult", 0.8)
					aoe_add = TileStatsRegistry.get_stat("AmplifierTile", "mythic_aoe_bonus_add", 1.0)
		d["kind"] = KIND_AMPLIFIER
		d["amp_mult"] = mult
		d["aoe_add"] = aoe_add
	elif t == "Splitter":
		var faces = PackedInt32Array()
		var weights = PackedFloat64Array()
		for f in tile.active_faces:
			faces.append(f)
			# get_ratio_weight already returns the correct per-face weight
			# either way: flat 1.0 for non-Mythic, output_ratios[f] for
			# Mythic - no branching needed here.
			weights.append(tile.get_ratio_weight(f))
		d["kind"] = KIND_SPLITTER
		d["faces"] = faces
		d["weights"] = weights
		# Mythic Splitter: Resonator-style remnant boost + amplify(2.0),
		# same state shape as ResonatorTile below (SplitterTile.gd's own
		# _remnant_magnitudes dict, same 0.8/0.2/0.15 constants).
		d["mythic_remnants"] = tile.rarity == HexTile.Rarity.MYTHIC
		if tile.rarity == HexTile.Rarity.MYTHIC:
			d["remnant"] = _syn_dict_to_packed(tile._remnant_magnitudes)
			d["remnant_present"] = _syn_dict_to_present(tile._remnant_magnitudes)
		# Power Grid Splitter (brand subclass, tile_type stays "Splitter"):
		# a flat 0.5x amplify applied BEFORE the normal split - see
		# PowerGridSplitterTile.gd's header.
		if script_path.ends_with("PowerGridSplitterTile.gd"):
			d["pre_amp"] = 1.0 + tile.POWER_GRID_AMPLIFY_BONUS
	elif t == "Reflector":
		d["kind"] = KIND_REFLECTOR
		d["rotation"] = int(tile.rotation_steps)
	elif t == "Directional Conduit":
		d["kind"] = KIND_CONDUIT
		d["rotation"] = int(tile.rotation_steps)
		d["valve"] = tile.rarity == HexTile.Rarity.MYTHIC and int(tile.mythic_mode) == 1
	elif t == "Elemental Infuser":
		var rate = TileStatsRegistry.get_stat("InfuserTile", "conversion_rate_base", 0.4) \
			+ (tile.rarity * TileStatsRegistry.get_stat("InfuserTile", "conversion_rate_rarity_coeff", 0.15)) \
			+ ((tile.level - 1) * TileStatsRegistry.get_stat("InfuserTile", "conversion_rate_level_coeff", 0.05))
		rate = min(rate, 1.0)
		var amount = tile.power_infusion \
			* (1.0 + tile.rarity * TileStatsRegistry.get_stat("InfuserTile", "infusion_rarity_coeff", 0.5)) \
			* (1.0 + (tile.level - 1) * TileStatsRegistry.get_stat("InfuserTile", "infusion_level_coeff", 0.1))
		d["kind"] = KIND_INFUSER
		d["infuse_syn"] = int(tile.secondary_synergy)
		d["conv_rate"] = rate
		d["infuse_amount"] = amount
	elif t == "Catalyst":
		d["kind"] = KIND_CATALYST
		d["catalyst_target"] = int(tile.target_synergy)
		d["catalyst_mult"] = tile.efficiency * tile._get_power_multiplier()
		d["gate_min_magnitude"] = tile.gate_min_magnitude
		d["gate_every_n"] = tile.gate_every_n
		d["inverted"] = tile.inverted
		d["gate_counter"] = tile._gate_counter
	elif t == "Core Reactor" or t == "Microcore":
		var core_faces = PackedInt32Array()
		for f in tile.active_faces:
			core_faces.append(f)
		d["kind"] = KIND_CORE
		d["faces"] = core_faces
	elif t == "Weapon Mount":
		d["kind"] = KIND_MOUNT_SINK
		# Sniper Mount is a Weapon Mount subclass (tile_type unchanged) that
		# stamps range_mult onto the packet before the capture copy.
		if script_path.ends_with("SniperMountTile.gd"):
			d["range_mult_stamp"] = tile.SNIPER_RANGE_MULT
	elif script_path.ends_with("ComponentLinkTile.gd"):
		if tile.target_slot != HexTile.BodySlot.NONE:
			d["kind"] = KIND_LINK_SINK
		else:
			var link_faces = PackedInt32Array()
			for f in tile.active_faces:
				link_faces.append(f)
			d["kind"] = KIND_LINK_ROUTER
			d["faces"] = link_faces
	elif t == "Heal Beacon":
		d["kind"] = KIND_STORE_SINK
		d["store_coef"] = 1.0 + tile.rarity * 0.5
	elif t == "Jammer Module":
		d["kind"] = KIND_STORE_SINK
		d["store_coef"] = 1.0 + tile.rarity * TileStatsRegistry.get_stat("JammerModuleTile", "energy_storage_rarity_coeff", 0.5)
	elif t == "Drone Bay":
		d["kind"] = KIND_STORE_SINK
		d["store_coef"] = 1.0
	elif t == "Cloak Generator":
		d["kind"] = KIND_STORE_SINK
		# AllyCloakTile (Shadow Systems brand) overrides process_energy to
		# read its OWN "AllyCloakTile" stats key instead of "CloakTile" -
		# see AllyCloakTile.gd's header - so the coefficient can genuinely
		# differ from the base tile even though tile_type is identical.
		if script_path.ends_with("AllyCloakTile.gd"):
			d["store_coef"] = 1.0 + tile.rarity * TileStatsRegistry.get_stat("AllyCloakTile", "energy_storage_rarity_coeff", 0.5)
		else:
			d["store_coef"] = 1.0 + tile.rarity * TileStatsRegistry.get_stat("CloakTile", "energy_storage_rarity_coeff", 0.5)
	elif t == "Filter":
		d["kind"] = KIND_FILTER
		d["filter_allowed"] = int(tile.allowed_synergy)
		d["filter_raw_return"] = tile.raw_return_rate
	elif t == "Magnet":
		# Mythic repel mode is a mech-level flag read post-sim, not a routing
		# change, so it's safe to route the sim itself through Rust.
		d["kind"] = KIND_MAGNET
		d["magnet_lightning_mult"] = TileStatsRegistry.get_stat("MagnetTile", "lightning_bonus_mult", 1.5)
		d["magnetic_power"] = tile.current_magnetic_power # in-place accumulation
	elif t == "Shield Generator":
		# "Shield Generator" is now a single canonical class (ShieldTile);
		# ShieldGeneratorTile is a deprecated thin subclass of it, so both
		# use the same per-rarity curve. Always the curve - no more
		# script-path split.
		d["kind"] = KIND_SHIELD_STORE
		d["shield_mult"] = TileStatsRegistry.get_stat_by_rarity("ShieldTile", "energy_mult_by_rarity", tile.rarity, [1.1, 1.5, 2.5, 5.0, 10.0])
		d["stored_energy"] = tile.stored_energy # in-place accumulation
		d["stored_syn"] = _syn_dict_to_packed(tile.shield_synergies)
		d["stored_syn_present"] = _syn_dict_to_present(tile.shield_synergies)
	elif t == "Accumulator":
		var acc_mult = tile._get_power_multiplier()
		d["kind"] = KIND_ACCUMULATOR
		d["acc_charge_div"] = tile.charge_multiplier / acc_mult
		d["acc_damage"] = tile.damage_boost * acc_mult
		d["acc_auto_dump"] = tile.auto_dump_threshold
		d["acc_trigger"] = _trigger_to_int(tile.trigger_key)
		d["acc_quality"] = tile.get_quality_factor()
	elif t == "Resonator":
		if tile.rarity == HexTile.Rarity.MYTHIC:
			# Mythic Resonator Sync: cross-path proc residue - see
			# ResonatorTile._process_sync/_path_residue. _path_residue is a
			# Dictionary keyed by path_id (0/1/2) -> {"synergy", "steps_left"};
			# packed into fixed-size arrays (-1 = no residue on that path).
			d["kind"] = KIND_RESONATOR_SYNC
			var res_syn = PackedInt32Array([-1, -1, -1])
			var res_steps = PackedInt32Array([0, 0, 0])
			for path_id in tile._path_residue:
				var pid = int(path_id)
				if pid >= 0 and pid < 3:
					res_syn[pid] = int(tile._path_residue[path_id]["synergy"])
					res_steps[pid] = int(tile._path_residue[path_id]["steps_left"])
			d["residue_syn"] = res_syn
			d["residue_steps"] = res_steps
			d["sync_dropoff"] = PackedInt32Array([tile.get_sync_dropoff(0), tile.get_sync_dropoff(1), tile.get_sync_dropoff(2)])
		else:
			d["kind"] = KIND_RESONATOR
			d["res_baseline_mult"] = 1.0 + TileStatsRegistry.get_stat("ResonatorTile", "baseline_amplify", 0.15) * tile._get_power_multiplier()
			d["res_remnant_boost"] = tile.boost_per_remnant * tile._get_power_multiplier()
			d["remnant"] = _syn_dict_to_packed(tile._remnant_magnitudes)
			d["remnant_present"] = _syn_dict_to_present(tile._remnant_magnitudes)
		# Power Grid Resonator (brand subclass, tile_type stays "Resonator",
		# Mythic-only so it always takes the Sync branch above): a flat
		# extra amplify pass on top of the normal baseline/Sync behavior -
		# see PowerGridResonatorTile.gd's header.
		if script_path.ends_with("PowerGridResonatorTile.gd"):
			d["post_amp"] = 1.0 + tile.ENHANCED_AMPLIFY_BONUS
	elif t == "Prime Circuit":
		# Amplifier + Infuser + Resonator-baseline in one tile - see
		# PrimeCircuitTile.gd's own header for why it's three formulas
		# applied sequentially rather than three composed sub-tiles.
		d["kind"] = KIND_PRIME_CIRCUIT
		d["amp_mult"] = TileStatsRegistry.get_stat("PrimeCircuitTile", "amplification", 1.2) * tile._get_power_multiplier()
		d["infuse_syn"] = int(tile.secondary_synergy)
		var pc_rate = TileStatsRegistry.get_stat("PrimeCircuitTile", "conversion_rate_base", 0.4) \
			+ (tile.rarity * TileStatsRegistry.get_stat("PrimeCircuitTile", "conversion_rate_rarity_coeff", 0.15)) \
			+ ((tile.level - 1) * TileStatsRegistry.get_stat("PrimeCircuitTile", "conversion_rate_level_coeff", 0.05))
		d["conv_rate"] = min(pc_rate, 1.0)
		d["infuse_amount"] = TileStatsRegistry.get_stat("PrimeCircuitTile", "power_infusion", 2.0) \
			* (1.0 + tile.rarity * TileStatsRegistry.get_stat("PrimeCircuitTile", "infusion_rarity_coeff", 0.5)) \
			* (1.0 + (tile.level - 1) * TileStatsRegistry.get_stat("PrimeCircuitTile", "infusion_level_coeff", 0.1))
		d["res_baseline_mult"] = 1.0 + TileStatsRegistry.get_stat("PrimeCircuitTile", "baseline_amplify", 0.15) * tile._get_power_multiplier()
		d["res_remnant_boost"] = TileStatsRegistry.get_stat("PrimeCircuitTile", "boost_per_remnant", 1.3) * tile._get_power_multiplier()
		d["remnant"] = _syn_dict_to_packed(tile._remnant_magnitudes)
		d["remnant_present"] = _syn_dict_to_present(tile._remnant_magnitudes)
	elif t == "Maneuvering Thruster":
		# Mech-level merge (mech.thruster_accel_bonus) - same grid.get_parent()
		# chase as Jumpjet/Actuator, replayed by the bridge after simulate_
		# grid returns (see the mech_merges write-back below).
		d["kind"] = KIND_THRUSTER
	elif t == "Jumpjet":
		# Mech-level merge (jumpjet_energy/ignore_terrain/jumpjet_rarity) -
		# the Rust engine captures the packet that WOULD be merged; the
		# bridge replays it onto the real mech after simulate_grid returns
		# (see the mech_merges write-back below), mirroring JumpjetTile.
		# process_energy's grid.get_parent()-chase exactly.
		d["kind"] = KIND_JUMPJET
	elif t == "Actuator":
		d["kind"] = KIND_ACTUATOR
		d["actuator_base_mult"] = tile.base_speed_multiplier
		d["actuator_kin_mult"] = TileStatsRegistry.get_stat("ActuatorTile", "kinetic_bonus_mult", 1.5)
		d["actuator_ltg_mult"] = TileStatsRegistry.get_stat("ActuatorTile", "lightning_bonus_mult", 2.0)
	elif t == "Lance Mount":
		# Multi-cell (footprint_offsets) capture with per-face bookkeeping -
		# see the write-back below for how lance_hits gets replayed onto
		# _face_magnitudes/_fed_packet.
		d["kind"] = KIND_LANCE
		var extra = PackedInt32Array()
		for off in tile.footprint_offsets:
			extra.append(off.x)
			extra.append(off.y)
		d["extra_cells"] = extra
	elif t == "Sensor Array" or t == "Missile Rack" or t == "Mobility Core":
		d["kind"] = KIND_PASS # pure pass-through tiles
	else:
		return {} # anything else: unsupported, whole grid falls back
	return d

# Sniper Mount is a Weapon Mount subclass that stamps range_mult before the
# capture - detected here (after the tile_type branch set KIND_MOUNT_SINK)
# so the range multiplier rides along. Called by _describe_tile's Weapon
# Mount branch via the shared return.
static func _trigger_to_int(trigger_key) -> int:
	match str(trigger_key):
		"1": return 1
		"2": return 2
		"3": return 3
		_: return 0

static func _int_to_trigger(v: int) -> String:
	match v:
		1: return "1"
		2: return "2"
		3: return "3"
		_: return "None"

static func _syn_dict_to_packed(d) -> PackedFloat64Array:
	var out = PackedFloat64Array()
	out.resize(10)
	for k in d:
		out[int(k)] = d[k]
	return out

static func _syn_dict_to_present(d) -> PackedInt32Array:
	var out = PackedInt32Array()
	out.resize(10)
	for k in d:
		out[int(k)] = 1
	return out

static func _packet_to_dict(p) -> Dictionary:
	var syn = PackedFloat64Array()
	var present = PackedInt32Array()
	syn.resize(10)
	present.resize(10)
	for k in p.synergies:
		syn[int(k)] = p.synergies[k]
		present[int(k)] = 1
	var proc = PackedFloat64Array()
	var proc_present = PackedInt32Array()
	proc.resize(10)
	proc_present.resize(10)
	for k in p.proc_synergies:
		proc[int(k)] = p.proc_synergies[k]
		proc_present[int(k)] = 1
	return {
		"magnitude": p.magnitude,
		"syn": syn,
		"syn_present": present,
		"proc": proc,
		"proc_present": proc_present,
		"dir": int(p.direction),
		"q": p.position.q if p.position else 0,
		"r": p.position.r if p.position else 0,
		"steps": 0, # _simulate_grid resets traversal_steps on entry
		"charge_required": p.charge_required,
		"accumulator_quality": p.accumulator_quality,
		"aoe_bonus": p.aoe_bonus,
		"acc_charge_mult": p.acc_charge_mult,
		"acc_damage_mult": p.acc_damage_mult,
		"range_mult": p.range_mult,
		"auto_dump_threshold": p.auto_dump_threshold,
		"trigger": _trigger_to_int(p.trigger_key),
	}

static func _packet_from_dict(d: Dictionary) -> EnergyPacket:
	var p = EnergyPacket.new(0.0, null)
	p.synergies.clear()
	var syn: PackedFloat64Array = d["syn"]
	var present: PackedInt32Array = d["syn_present"]
	for i in range(10):
		if present[i] != 0:
			p.synergies[i] = syn[i]
	if d.has("proc") and d.has("proc_present"):
		var proc: PackedFloat64Array = d["proc"]
		var proc_present: PackedInt32Array = d["proc_present"]
		for i in range(10):
			if proc_present[i] != 0:
				p.proc_synergies[i] = proc[i]
	p.magnitude = float(d["magnitude"])
	p.traversal_steps = int(d["steps"])
	p.charge_required = float(d["charge_required"])
	p.accumulator_quality = float(d["accumulator_quality"])
	p.aoe_bonus = float(d["aoe_bonus"])
	p.acc_charge_mult = float(d["acc_charge_mult"])
	p.acc_damage_mult = float(d["acc_damage_mult"])
	p.range_mult = float(d["range_mult"])
	p.auto_dump_threshold = float(d["auto_dump_threshold"])
	p.trigger_key = _int_to_trigger(int(d.get("trigger", 0)))
	p.is_active = false # captures are terminal, matching the GDScript sinks
	return p

# The whole show. Returns true when the grid was fully simulated in Rust
# (results already applied to the real tiles); false = unsupported tile or
# no Rust available - caller runs the original GDScript sim instead.
static func try_simulate(grid, starting_packets: Array, bypass_gate: bool = false) -> bool:
	if not ENABLED and not bypass_gate:
		return false
	var sim = _ensure_sim()
	if sim == null:
		return false

	var tiles = grid.get_all_tiles()
	var descs: Array = []
	var tile_objs: Array = []
	for tile in tiles:
		var desc = _describe_tile(tile)
		if desc.is_empty():
			return false
		descs.append(desc)
		tile_objs.append(tile)

	var comp = grid.get_parent()
	var valid_cells = PackedInt32Array()
	if comp and "valid_hexes" in comp:
		for h in comp.valid_hexes:
			valid_cells.append(h.q)
			valid_cells.append(h.r)

	var packet_dicts: Array = []
	for p in starting_packets:
		packet_dicts.append(_packet_to_dict(p))

	var result: Dictionary = sim.simulate_grid(descs, valid_cells, packet_dicts)

	# tile_objs is get_all_tiles() order, but Rust indexed tiles by their
	# (q,r) insertion into its grid map - which came from the SAME array
	# order, so indices line up 1:1.
	for cap in result.get("captures", []):
		var tile = tile_objs[int(cap["tile"])]
		var pkt = _packet_from_dict(cap["packet"])
		if "pending_transfer_packets" in tile and tile.get("target_slot") != null and tile.target_slot != HexTile.BodySlot.NONE:
			tile.pending_transfer_packets.append(pkt)
		elif "pending_packets" in tile:
			tile.pending_packets.append({"packet": pkt, "step": int(cap["step"])})
	for st in result.get("stores", []):
		var tile = tile_objs[int(st["tile"])]
		if "stored_energy" in tile:
			tile.stored_energy += float(st["amount"])
	var dominant: Dictionary = result.get("conduit_dominant", {})
	for idx in dominant:
		var tile = tile_objs[int(idx)]
		if "last_dominant_synergy" in tile:
			tile.last_dominant_synergy = int(dominant[idx])

	# Lance Mount: replay each (cell, entry_dir, packet) hit onto the real
	# tile's _face_magnitudes accumulator + track the highest-magnitude
	# _fed_packet seen, exactly mirroring LanceMountTile.process_energy's
	# own bookkeeping (called once per packet arrival there; here, once per
	# captured hit, in the same order Rust discovered them).
	for hit in result.get("lance_hits", []):
		var tile = tile_objs[int(hit["tile"])]
		if not ("_face_magnitudes" in tile):
			continue
		var pkt = _packet_from_dict(hit["packet"])
		var face_key = "%d:%d" % [int(hit["cell"]), int(hit["entry"])]
		tile._face_magnitudes[face_key] = tile._face_magnitudes.get(face_key, 0.0) + pkt.magnitude
		if tile._fed_packet == null or pkt.magnitude > tile._fed_packet.magnitude:
			tile._fed_packet = pkt

	# Jumpjet/Actuator: mech-level merges. The Rust engine has no Godot Node
	# access, so it can't reach into the mech mid-simulation like
	# JumpjetTile/ActuatorTile.process_energy do - it captures the packet
	# that WOULD be merged instead, and this replays it onto the real mech
	# after the fact, chasing the same grid -> component -> mech double-hop.
	var merges: Array = result.get("mech_merges", [])
	if not merges.is_empty():
		var mech = _resolve_mech(grid)
		for m in merges:
			var tile = tile_objs[int(m["tile"])]
			var pkt = _packet_from_dict(m["packet"])
			if tile.tile_type == "Jumpjet":
				if mech and "current_move_speed" in mech and "base_move_speed" in mech:
					if mech.get("jumpjet_energy") == null:
						mech.set("jumpjet_energy", EnergyPacket.new(0.0, null))
						mech.get("jumpjet_energy").synergies.clear()
					mech.get("jumpjet_energy").merge(pkt)
					if "ignore_terrain" in mech:
						mech.ignore_terrain = true
					if "jumpjet_rarity" in mech:
						mech.jumpjet_rarity = max(mech.jumpjet_rarity, tile.rarity)
			elif tile.tile_type == "Actuator":
				if mech and "actuator_energy" in mech:
					if not mech.get("actuator_energy"):
						mech.set("actuator_energy", EnergyPacket.new(0.0, null))
					mech.get("actuator_energy").merge(pkt)
			elif tile.tile_type == "Maneuvering Thruster":
				if mech and "thruster_accel_bonus" in mech:
					mech.thruster_accel_bonus = max(mech.thruster_accel_bonus, tile.rarity)

	# Stateful write-back: the Rust engine started each tile's state from the
	# value we described and returns the final state - mirror it onto the
	# real tile so a subsequent sim (re-simulating a peripheral without a
	# reset) sees exactly what the GDScript path would have left behind.
	for st in result.get("tile_states", []):
		var tile = tile_objs[int(st["tile"])]
		var t: String = tile.tile_type
		if t == "Magnet" and "current_magnetic_power" in tile:
			tile.current_magnetic_power = float(st["magnetic_power"])
		elif t == "Shield Generator":
			if "stored_energy" in tile:
				tile.stored_energy = float(st["stored_energy"])
			if "shield_synergies" in tile:
				tile.shield_synergies = _packed_to_syn_dict(st["stored_syn"])
		elif t == "Resonator" and tile.rarity != HexTile.Rarity.MYTHIC and "_remnant_magnitudes" in tile:
			tile._remnant_magnitudes = _packed_to_syn_dict_from_present(st["remnant"], st["remnant_present"])
		elif t == "Resonator" and tile.rarity == HexTile.Rarity.MYTHIC and "_path_residue" in tile:
			var residue_syn: PackedInt32Array = st["residue_syn"]
			var residue_steps: PackedInt32Array = st["residue_steps"]
			var new_residue = {}
			for path_id in range(3):
				if residue_syn[path_id] >= 0:
					new_residue[path_id] = {"synergy": residue_syn[path_id], "steps_left": residue_steps[path_id]}
			tile._path_residue = new_residue
		elif t == "Splitter" and tile.rarity == HexTile.Rarity.MYTHIC and "_remnant_magnitudes" in tile:
			tile._remnant_magnitudes = _packed_to_syn_dict_from_present(st["remnant"], st["remnant_present"])
		elif t == "Actuator" and "current_speed_bonus" in tile:
			tile.current_speed_bonus = float(st["speed_bonus"])
		elif t == "Prime Circuit" and "_remnant_magnitudes" in tile:
			tile._remnant_magnitudes = _packed_to_syn_dict_from_present(st["remnant"], st["remnant_present"])
		elif t == "Catalyst" and "_gate_counter" in tile:
			tile._gate_counter = int(st.get("gate_counter", 0))
	return true

# Mirrors JumpjetTile/ActuatorTile.process_energy's own mech lookup exactly:
# the hex grid's parent is the owning ComponentEquipment (has slot_type),
# and ITS parent is the actual Mech.
static func _resolve_mech(grid):
	if not grid or not grid.get_parent():
		return null
	var mech = grid.get_parent()
	if mech and "slot_type" in mech:
		mech = mech.get_parent()
	return mech

static func _packed_to_syn_dict(packed) -> Dictionary:
	# Only non-zero entries become keys, matching how GDScript accumulates
	# shield_synergies (a key exists only once something added to it).
	var out = {}
	var arr: PackedFloat64Array = packed
	for i in range(10):
		if arr[i] != 0.0:
			out[i] = arr[i]
	return out

static func _packed_to_syn_dict_from_present(packed, present) -> Dictionary:
	# Resonator remnants keep a key even at ~0 magnitude (consumed *0.2 each
	# pass but never erased), so presence - not non-zero - decides the key.
	var out = {}
	var arr: PackedFloat64Array = packed
	var pres: PackedInt32Array = present
	for i in range(10):
		if pres[i] != 0:
			out[i] = arr[i]
	return out

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
# KIND_JUMPJET (14) / KIND_ACTUATOR (15) are implemented in Rust but NOT
# yet routed here - they merge into MECH-level energy (jumpjet_energy/
# actuator_energy) which needs replay plumbing the bridge doesn't have
# yet, so they still fall back to GDScript. Same for KIND_RESONATOR_SYNC
# (19, cross-path proc residue), KIND_LANCE (21, multi-cell face gating),
# and the Mythic Splitter remnant path. Widening to those is the next
# increment (task tracked); the parity check would catch any early enable.
const KIND_SHIELD_STORE = 16
const KIND_ACCUMULATOR = 17
const KIND_RESONATOR = 18
const KIND_PRIME_CIRCUIT = 20

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
		if tile.rarity == HexTile.Rarity.MYTHIC:
			return {} # Mythic splitter carries remnant state - unsupported
		var faces = PackedInt32Array()
		var weights = PackedFloat64Array()
		for f in tile.active_faces:
			faces.append(f)
			weights.append(tile.get_ratio_weight(f))
		d["kind"] = KIND_SPLITTER
		d["faces"] = faces
		d["weights"] = weights
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
		if (tile.inverted and tile.rarity == HexTile.Rarity.MYTHIC) \
			or tile.gate_min_magnitude > 0.0 or tile.gate_every_n > 1:
			return {} # gated/filter modes are stateful or conditional - unsupported
		d["kind"] = KIND_CATALYST
		d["catalyst_target"] = int(tile.target_synergy)
		d["catalyst_mult"] = tile.efficiency * tile._get_power_multiplier()
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
		# BOTH ShieldTile.gd and ShieldGeneratorTile.gd carry tile_type
		# "Shield Generator" but use different energy multipliers - split by
		# script path (see the task #55 reconciliation note in each file).
		d["kind"] = KIND_SHIELD_STORE
		if script_path.ends_with("ShieldTile.gd"):
			d["shield_mult"] = TileStatsRegistry.get_stat_by_rarity("ShieldTile", "energy_mult_by_rarity", tile.rarity, [1.1, 1.5, 2.5, 5.0, 10.0])
		else:
			d["shield_mult"] = 1.0 + tile.rarity * TileStatsRegistry.get_stat("ShieldGeneratorTile", "energy_storage_rarity_coeff", 0.5)
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
		# Mythic Resonator is the Sync (cross-path proc residue) tile - not
		# yet routed (see the KIND note above); non-Mythic baseline is.
		if tile.rarity == HexTile.Rarity.MYTHIC:
			return {}
		# Power Grid Resonator is a brand (Mythic) tile, so it never reaches
		# here - the Mythic guard above already sends it to GDScript.
		d["kind"] = KIND_RESONATOR
		d["res_baseline_mult"] = 1.0 + TileStatsRegistry.get_stat("ResonatorTile", "baseline_amplify", 0.15) * tile._get_power_multiplier()
		d["res_remnant_boost"] = tile.boost_per_remnant * tile._get_power_multiplier()
		d["remnant"] = _syn_dict_to_packed(tile._remnant_magnitudes)
		d["remnant_present"] = _syn_dict_to_present(tile._remnant_magnitudes)
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
		elif t == "Resonator" and "_remnant_magnitudes" in tile:
			tile._remnant_magnitudes = _packed_to_syn_dict_from_present(st["remnant"], st["remnant_present"])
	return true

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

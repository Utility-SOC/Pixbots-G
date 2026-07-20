extends Node

# Parity harness for the Rust hexgrid-sim port (rust_ext/src/hexgrid_sim.rs
# + scripts/core/RustGridSim.gd): builds grids exercising every routed tile
# kind, runs the ORIGINAL GDScript Mech._simulate_grid on one copy and the
# Rust path on an identical copy, and diffs every capture (magnitude,
# per-synergy composition, procs, accumulator stamps, traversal step),
# every transfer, and every piece of stateful tile write-back (storage
# banks, magnet power, shield synergies, resonator remnants) to tight
# tolerance. This is the drift tripwire the Rust port's header demands -
# any change to a routed tile's process_energy in GDScript that isn't
# mirrored in Rust fails here.
#
# If the loaded rust_ext DLL is still the pre-port stub (the debug DLL is
# locked while the Godot EDITOR is running), this reports SKIP loudly.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const CoreTileScript = preload("res://scripts/tiles/CoreTile.gd")
const AmplifierTileScript = preload("res://scripts/tiles/AmplifierTile.gd")
const SplitterTileScript = preload("res://scripts/tiles/SplitterTile.gd")
const ReflectorTileScript = preload("res://scripts/tiles/ReflectorTile.gd")
const InfuserTileScript = preload("res://scripts/tiles/InfuserTile.gd")
const CatalystTileScript = preload("res://scripts/tiles/CatalystTile.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const HealBeaconTileScript = preload("res://scripts/tiles/HealBeaconTile.gd")
const FilterTileScript = preload("res://scripts/tiles/FilterTile.gd")
const MagnetTileScript = preload("res://scripts/tiles/MagnetTile.gd")
const AccumulatorTileScript = preload("res://scripts/tiles/AccumulatorTile.gd")
const ResonatorTileScript = preload("res://scripts/tiles/ResonatorTile.gd")
const ShieldGeneratorTileScript = preload("res://scripts/tiles/ShieldGeneratorTile.gd")
const JumpjetTileScript = preload("res://scripts/tiles/JumpjetTile.gd")
const ActuatorTileScript = preload("res://scripts/tiles/ActuatorTile.gd")
const LanceMountTileScript = preload("res://scripts/tiles/LanceMountTile.gd")
const PowerGridSplitterTileScript = preload("res://scripts/tiles/brands/PowerGridSplitterTile.gd")
const PowerGridResonatorTileScript = preload("res://scripts/tiles/brands/PowerGridResonatorTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")
const RustGridSimScript = preload("res://scripts/core/RustGridSim.gd")
const SaveManagerScript = preload("res://scripts/core/SaveManager.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

# --- Grid A: the original stateless torture grid ---------------------------
func _build_component_a():
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	var hexes: Array[HexCoord] = [
		HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(2, 0), HexCoord.new(3, 0), HexCoord.new(4, 0),
		HexCoord.new(2, 1), HexCoord.new(1, 2), HexCoord.new(0, 1), HexCoord.new(0, 2),
	]
	comp.valid_hexes = hexes
	comp._rebuild_valid_hex_set()

	var core = CoreTileScript.new()
	core.active_faces.clear()
	core.active_faces.append(0)
	core.active_faces.append(1)
	core.set_face_output(0, EnergyPacket.SynergyType.KINETIC)
	core.set_face_output(1, EnergyPacket.SynergyType.LIGHTNING)
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)

	var amp = AmplifierTileScript.new()
	amp.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(1, 0), amp)

	var splitter = SplitterTileScript.new()
	splitter.rarity = HexTile.Rarity.RARE
	var s_faces: Array[int] = [0, 1]
	splitter.active_faces = s_faces
	comp.hex_grid.add_tile(HexCoord.new(2, 0), splitter)

	var infuser = InfuserTileScript.new()
	infuser.rarity = HexTile.Rarity.UNCOMMON
	infuser.secondary_synergy = EnergyPacket.SynergyType.FIRE
	comp.hex_grid.add_tile(HexCoord.new(3, 0), infuser)

	comp.hex_grid.add_tile(HexCoord.new(4, 0), WeaponMountTileScript.new())

	var refl = ReflectorTileScript.new()
	refl.rotation_steps = 0
	comp.hex_grid.add_tile(HexCoord.new(2, 1), refl)

	var catalyst = CatalystTileScript.new()
	catalyst.target_synergy = EnergyPacket.SynergyType.ICE
	comp.hex_grid.add_tile(HexCoord.new(1, 2), catalyst)

	var beacon = HealBeaconTileScript.new()
	beacon.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(0, 2), beacon)
	return comp

# --- Grid B: the stateful/newly-routed tiles -------------------------------
#   Core(0,0) fires E, SE, SW, NE.
#   E : Filter(1,0 allow FIRE, removes KINETIC) -> Accumulator(2,0) -> Mount(3,0)
#   SE: Resonator(0,1 baseline) -> Magnet(0,2)
#   SW: Shield Generator(-1,1)
#   NE: Sniper Mount(1,-1)
func _build_component_b():
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	var hexes: Array[HexCoord] = [
		HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(2, 0), HexCoord.new(3, 0),
		HexCoord.new(0, 1), HexCoord.new(0, 2), HexCoord.new(-1, 1), HexCoord.new(1, -1),
	]
	comp.valid_hexes = hexes
	comp._rebuild_valid_hex_set()

	var core = CoreTileScript.new()
	core.active_faces.clear()
	for f in [0, 1, 2, 5]:
		core.active_faces.append(f)
	core.set_face_output(0, EnergyPacket.SynergyType.KINETIC) # filtered out downstream
	core.set_face_output(1, EnergyPacket.SynergyType.FIRE)
	core.set_face_output(2, EnergyPacket.SynergyType.ICE)
	core.set_face_output(5, EnergyPacket.SynergyType.LIGHTNING)
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)

	var filt = FilterTileScript.new()
	filt.allowed_synergy = EnergyPacket.SynergyType.FIRE
	comp.hex_grid.add_tile(HexCoord.new(1, 0), filt)

	var accum = AccumulatorTileScript.new()
	accum.rarity = HexTile.Rarity.RARE
	accum.trigger_key = "2"
	accum.auto_dump_threshold = 0.5
	comp.hex_grid.add_tile(HexCoord.new(2, 0), accum)

	comp.hex_grid.add_tile(HexCoord.new(3, 0), WeaponMountTileScript.new())

	var res = ResonatorTileScript.new()
	res.rarity = HexTile.Rarity.RARE # non-Mythic baseline path
	comp.hex_grid.add_tile(HexCoord.new(0, 1), res)

	var mag = MagnetTileScript.new()
	mag.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(0, 2), mag)

	var shield = ShieldGeneratorTileScript.new()
	shield.rarity = HexTile.Rarity.RARE
	comp.hex_grid.add_tile(HexCoord.new(-1, 1), shield)

	# Sniper Mount (brand tile) - stamps range_mult x6 before capture.
	var sniper = load("res://scripts/tiles/brands/SniperMountTile.gd").new()
	comp.hex_grid.add_tile(HexCoord.new(1, -1), sniper)
	return comp

# --- Grid C: Mythic-tier tiles + brand overrides ----------------------------
#   Core(0,0) fires E and SE toward two Reflectors that both redirect into
#   the SAME Resonator Sync tile at (1,1), from DIFFERENT entry directions
#   (path 1 and path 0) - exercises cross-path proc conferral, not just
#   single-path residue deposit. One exit continues into a Mythic Splitter
#   (ratio-weighted fan + remnant boost); the other lands directly on a
#   Weapon Mount so its conferred proc is directly inspectable. Core's West
#   and Northwest faces independently feed a Power Grid Splitter (pre-amp)
#   and a Power Grid Resonator (Mythic Sync + post-amp).
func _build_component_c():
	var comp = ComponentEquipmentScript.new(HexTile.BodySlot.TORSO, HexTile.Rarity.COMMON)
	var hexes: Array[HexCoord] = [
		HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(0, 1), HexCoord.new(1, 1),
		HexCoord.new(2, 1), HexCoord.new(1, 2), HexCoord.new(1, 3), HexCoord.new(0, 3),
		HexCoord.new(-1, 0), HexCoord.new(-2, 0),
		HexCoord.new(0, -1), HexCoord.new(0, -2),
	]
	comp.valid_hexes = hexes
	comp._rebuild_valid_hex_set()

	var core = CoreTileScript.new()
	core.active_faces.clear()
	for f in [0, 1, 3, 4]:
		core.active_faces.append(f)
	core.set_face_output(0, EnergyPacket.SynergyType.FIRE)
	core.set_face_output(1, EnergyPacket.SynergyType.ICE)
	core.set_face_output(3, EnergyPacket.SynergyType.KINETIC)
	core.set_face_output(4, EnergyPacket.SynergyType.LIGHTNING)
	comp.hex_grid.add_tile(HexCoord.new(0, 0), core)

	# East path -> Reflector(1,0) rotation 1 -> exits SE toward Resonator,
	# entering it from NW (path 1).
	var refl_e = ReflectorTileScript.new()
	refl_e.rotation_steps = 1
	comp.hex_grid.add_tile(HexCoord.new(1, 0), refl_e)

	# SE path -> Reflector(0,1) rotation 5 -> exits E toward Resonator,
	# entering it from W (path 0).
	var refl_se = ReflectorTileScript.new()
	refl_se.rotation_steps = 5
	comp.hex_grid.add_tile(HexCoord.new(0, 1), refl_se)

	var res_sync = ResonatorTileScript.new()
	res_sync.rarity = HexTile.Rarity.MYTHIC
	comp.hex_grid.add_tile(HexCoord.new(1, 1), res_sync)

	# Neither Reflector nor Resonator change packet.direction, so each
	# packet continues exiting the Resonator in the same direction it
	# arrived traveling: the path-1 packet (arrived via SE) continues SE
	# to (1,2); the path-0 packet (arrived via E) continues E to (2,1).
	var splitter = SplitterTileScript.new()
	splitter.rarity = HexTile.Rarity.MYTHIC
	var s_faces: Array[int] = [1, 2]
	splitter.active_faces = s_faces
	splitter.output_ratios = [1.0, 3.0, 5.0, 1.0, 1.0, 1.0]
	comp.hex_grid.add_tile(HexCoord.new(1, 2), splitter)
	comp.hex_grid.add_tile(HexCoord.new(1, 3), WeaponMountTileScript.new())
	comp.hex_grid.add_tile(HexCoord.new(0, 3), WeaponMountTileScript.new())

	comp.hex_grid.add_tile(HexCoord.new(2, 1), WeaponMountTileScript.new())

	# West path -> Power Grid Splitter (pre-amp) -> Weapon Mount
	var pg_split = PowerGridSplitterTileScript.new()
	pg_split.rarity = HexTile.Rarity.MYTHIC
	var pg_faces: Array[int] = [3]
	pg_split.active_faces = pg_faces
	comp.hex_grid.add_tile(HexCoord.new(-1, 0), pg_split)
	comp.hex_grid.add_tile(HexCoord.new(-2, 0), WeaponMountTileScript.new())

	# NW path -> Power Grid Resonator (Mythic Sync + post-amp) -> Weapon Mount
	var pg_res = PowerGridResonatorTileScript.new()
	pg_res.rarity = HexTile.Rarity.MYTHIC
	comp.hex_grid.add_tile(HexCoord.new(0, -1), pg_res)
	comp.hex_grid.add_tile(HexCoord.new(0, -2), WeaponMountTileScript.new())

	return comp

func _gen_packets(comp) -> Array:
	var core = comp.hex_grid.get_tile(HexCoord.new(0, 0))
	var pkts = core.generate_energy(comp.hex_grid)
	for p in pkts:
		p.position = HexCoord.new(0, 0)
	return pkts

func _harvest(comp) -> Dictionary:
	var out = {"mounts": {}, "transfers": {}, "stores": {}, "magnet": {}, "shieldsyn": {}, "remnant": {}, "residue": {}}
	for tile in comp.hex_grid.get_all_tiles():
		var key = "%d,%d" % [tile.grid_position.q, tile.grid_position.r]
		if "pending_packets" in tile and tile.pending_packets.size() > 0:
			var entries = []
			for item in tile.pending_packets:
				var pk = item.packet
				entries.append({
					"mag": pk.magnitude, "syn": pk.synergies.duplicate(), "step": item.step,
					"proc": pk.proc_synergies.duplicate(),
					"acc_c": pk.acc_charge_mult, "acc_d": pk.acc_damage_mult,
					"trig": pk.trigger_key, "dump": pk.auto_dump_threshold,
					"qual": pk.accumulator_quality, "range": pk.range_mult,
				})
			out["mounts"][key] = entries
		if "pending_transfer_packets" in tile and tile.pending_transfer_packets.size() > 0:
			var entries2 = []
			for p in tile.pending_transfer_packets:
				entries2.append({"mag": p.magnitude, "syn": p.synergies.duplicate()})
			out["transfers"][key] = entries2
		if "stored_energy" in tile and tile.stored_energy > 0.0:
			out["stores"][key] = tile.stored_energy
		if "current_magnetic_power" in tile and tile.current_magnetic_power != 0.0:
			out["magnet"][key] = tile.current_magnetic_power
		if "shield_synergies" in tile and not tile.shield_synergies.is_empty():
			out["shieldsyn"][key] = tile.shield_synergies.duplicate()
		if "_remnant_magnitudes" in tile and not tile._remnant_magnitudes.is_empty():
			out["remnant"][key] = tile._remnant_magnitudes.duplicate()
		if "_path_residue" in tile and not tile._path_residue.is_empty():
			var r = {}
			for path_id in tile._path_residue:
				r[int(path_id)] = [tile._path_residue[path_id]["synergy"], tile._path_residue[path_id]["steps_left"]]
			out["residue"][key] = r
	return out

func _close(a, b) -> bool:
	return abs(float(a) - float(b)) <= 0.0001 * max(1.0, abs(float(a)))

func _cmp_syn(label: String, ea: Dictionary, eb: Dictionary) -> bool:
	var same = true
	for k in ea:
		if not _close(ea[k], eb.get(k, 0.0)):
			print("    MISMATCH %s[%s]: gd=%f rust=%f" % [label, k, ea[k], eb.get(k, 0.0)])
			same = false
	for k in eb:
		if not ea.has(k) and abs(float(eb[k])) > 0.0001:
			print("    MISMATCH %s extra-rust-key[%s]=%f" % [label, k, eb[k]])
			same = false
	return same

func _compare(a: Dictionary, b: Dictionary) -> bool:
	var same = true
	# Simple scalar-keyed sections.
	for section in ["stores", "magnet"]:
		var ka = a[section].keys(); ka.sort()
		var kb = b[section].keys(); kb.sort()
		if ka != kb:
			print("    MISMATCH %s keys: gd=%s rust=%s" % [section, ka, kb]); same = false; continue
		for key in ka:
			if not _close(a[section][key], b[section][key]):
				print("    MISMATCH %s @%s: gd=%f rust=%f" % [section, key, a[section][key], b[section][key]]); same = false
	# Synergy-dict-keyed sections.
	for section in ["shieldsyn", "remnant"]:
		var ka2 = a[section].keys(); ka2.sort()
		var kb2 = b[section].keys(); kb2.sort()
		if ka2 != kb2:
			print("    MISMATCH %s keys: gd=%s rust=%s" % [section, ka2, kb2]); same = false; continue
		for key in ka2:
			if not _cmp_syn("%s@%s" % [section, key], a[section][key], b[section][key]):
				same = false
	# Resonator Sync residue: {path_id: [synergy, steps_left]}.
	var kr_a = a["residue"].keys(); kr_a.sort()
	var kr_b = b["residue"].keys(); kr_b.sort()
	if kr_a != kr_b:
		print("    MISMATCH residue keys: gd=%s rust=%s" % [kr_a, kr_b]); same = false
	else:
		for key in kr_a:
			var ra = a["residue"][key]; var rb = b["residue"][key]
			var ra_keys = ra.keys(); ra_keys.sort()
			var rb_keys = rb.keys(); rb_keys.sort()
			if ra_keys != rb_keys:
				print("    MISMATCH residue paths @%s: gd=%s rust=%s" % [key, ra_keys, rb_keys]); same = false; continue
			for path_id in ra:
				if ra[path_id] != rb[path_id]:
					print("    MISMATCH residue @%s path %s: gd=%s rust=%s" % [key, path_id, ra[path_id], rb[path_id]]); same = false
	# Transfers.
	var kt_a = a["transfers"].keys(); kt_a.sort()
	var kt_b = b["transfers"].keys(); kt_b.sort()
	if kt_a != kt_b:
		print("    MISMATCH transfers keys: gd=%s rust=%s" % [kt_a, kt_b]); same = false
	else:
		for key in kt_a:
			var ta = a["transfers"][key]; var tb = b["transfers"][key]
			if ta.size() != tb.size():
				print("    MISMATCH transfers count @%s" % key); same = false; continue
			for i in range(ta.size()):
				if not _close(ta[i]["mag"], tb[i]["mag"]):
					print("    MISMATCH transfer mag @%s[%d]" % [key, i]); same = false
				if not _cmp_syn("transfer syn @%s[%d]" % [key, i], ta[i]["syn"], tb[i]["syn"]):
					same = false
	# Mounts (rich per-packet compare).
	var km_a = a["mounts"].keys(); km_a.sort()
	var km_b = b["mounts"].keys(); km_b.sort()
	if km_a != km_b:
		print("    MISMATCH mounts keys: gd=%s rust=%s" % [km_a, km_b]); same = false
	else:
		for key in km_a:
			var ma = a["mounts"][key]; var mb = b["mounts"][key]
			if ma.size() != mb.size():
				print("    MISMATCH mounts count @%s: gd=%d rust=%d" % [key, ma.size(), mb.size()]); same = false; continue
			for i in range(ma.size()):
				for f in ["mag", "acc_c", "acc_d", "dump", "qual", "range"]:
					if not _close(ma[i][f], mb[i][f]):
						print("    MISMATCH mount %s @%s[%d]: gd=%f rust=%f" % [f, key, i, ma[i][f], mb[i][f]]); same = false
				if ma[i]["step"] != mb[i]["step"]:
					print("    MISMATCH mount step @%s[%d]: gd=%d rust=%d" % [key, i, ma[i]["step"], mb[i]["step"]]); same = false
				if str(ma[i]["trig"]) != str(mb[i]["trig"]):
					print("    MISMATCH mount trigger @%s[%d]: gd=%s rust=%s" % [key, i, ma[i]["trig"], mb[i]["trig"]]); same = false
				if not _cmp_syn("mount syn @%s[%d]" % [key, i], ma[i]["syn"], mb[i]["syn"]):
					same = false
				if not _cmp_syn("mount proc @%s[%d]" % [key, i], ma[i]["proc"], mb[i]["proc"]):
					same = false
	return same

func _run_grid(label: String, builder: Callable):
	var sm = SaveManagerScript.new()
	var comp_gd = builder.call()
	var comp_rust = sm._deserialize_component(sm._serialize_component(comp_gd))

	var mech = MechScript.new()
	mech._simulate_grid(comp_gd.hex_grid, _gen_packets(comp_gd), true)
	var handled = RustGridSimScript.try_simulate(comp_rust.hex_grid, _gen_packets(comp_rust), true)
	mech.free()

	_check("[%s] fully inside the routed subset (Rust handled it)" % label, handled)
	if handled:
		var a = _harvest(comp_gd)
		var b = _harvest(comp_rust)
		_check("[%s] captures / transfers / stores / magnet / shield / remnant IDENTICAL" % label, _compare(a, b))
		_check("[%s] baseline produced non-vacuous output" % label,
			not a["mounts"].is_empty() or not a["stores"].is_empty())

func _ready():
	if not RustGridSimScript.is_available():
		print("SKIP: rust_ext DLL is the pre-port stub (debug DLL locked while the Godot editor is open).")
		print("      Close the editor, run `cargo build` in rust_ext/, then re-run.")
		get_tree().quit(0)
		return

	_run_grid("stateless", _build_component_a)
	_run_grid("stateful", _build_component_b)
	_run_grid("mythic", _build_component_c)

	# Fallback correctness: a grid with a still-unrouted tile (a gated
	# Catalyst - conditional/stateful in a way the bridge deliberately
	# doesn't describe) must be refused, not half-simulated.
	var comp_unsup = _build_component_a()
	var gated_catalyst = CatalystTileScript.new()
	gated_catalyst.gate_min_magnitude = 5.0
	comp_unsup.hex_grid.add_tile(HexCoord.new(0, 1), gated_catalyst)
	_check("a grid with an unrouted tile (gated Catalyst) falls back to GDScript",
		not RustGridSimScript.try_simulate(comp_unsup.hex_grid, _gen_packets(comp_unsup), true))

	if failures == 0:
		print("PASS: Rust hexgrid sim is packet-identical to the GDScript original across all routed tiles")
	get_tree().quit(0 if failures == 0 else 1)

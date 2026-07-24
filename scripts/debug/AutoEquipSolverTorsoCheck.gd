extends Node

# Playtest report: "the tutorial does not provide a valid build... literally
# all of the energy goes to the right arm, nothing goes to the backpack or
# head... that first splitter placed is completely worthless." Root cause:
# AutoEquipSolver.solve()'s per-node placement loop checked "is this hex a
# target?" BEFORE checking "is this the Core?" - and the Core's own hex
# position is ALWAYS listed in targets/fixed_sinks (the Torso is one of its
# own BFS-reachability targets), so the is_target check hit first and
# `continue`d past the Core-configuration branch every single time. The
# solver still built a correct multi-branch spanning tree and placed real
# tiles at every branch point - it just never told the Core itself to
# actually use more than one of them, silently leaving active_faces at
# whatever it was before solving (a fresh Core's construction default,
# [0]/East only).
#
# This is GuidedBuildPlanner's own solver AND the real "Auto-Equip" button's
# solver (same class, no separate logic) - this bug affected every player
# who ever clicked Auto-Equip or Skip Tutorial on a Torso, not just the
# guided walkthrough.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const AutoEquipSolverScript = preload("res://scripts/core/AutoEquipSolver.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _real_starter_inventory() -> Array:
	# Mirrors Main.gd._initialize_starter_inventory's taper for exactly the
	# tile types AutoEquipSolver actually consumes (Splitter/Reflector/
	# Amplifier) - a fresh tutorial player's real starting bin, not a
	# synthetic best-case inventory.
	var inventory: Array = []
	var taper = [HexTile.Rarity.COMMON, HexTile.Rarity.UNCOMMON, HexTile.Rarity.RARE]
	var taper_counts = {HexTile.Rarity.COMMON: 5, HexTile.Rarity.UNCOMMON: 3, HexTile.Rarity.RARE: 1}
	var classes = [
		preload("res://scripts/tiles/SplitterTile.gd"),
		preload("res://scripts/tiles/ReflectorTile.gd"),
		preload("res://scripts/tiles/AmplifierTile.gd"),
	]
	for r in taper:
		for c in classes:
			for i in range(taper_counts[r]):
				var tile = c.new()
				tile.rarity = r
				inventory.append(tile)
	return inventory

func _ready():
	var torso = ComponentEquipmentScript.create_starter_torso()
	var solver = AutoEquipSolverScript.new()
	solver.solve(torso, _real_starter_inventory(), null)

	var core = torso.hex_grid.get_tile(HexCoord.new(0, 0))
	_check("Core's active_faces respects its own rarity cap (get_max_faces())",
		core.active_faces.size() <= core.get_max_faces() and core.active_faces.size() >= 1)
	# This starter Torso is COMMON (cap 1) - the user's own hand-built
	# reference build had the Core exit in exactly one direction, with a
	# Splitter doing the real fan-out right at the hub. Confirm the solver
	# now produces that same shape instead of just cramming every direction
	# onto the Core directly (which "worked" but ignored the rarity cap).
	_check("a Common Core is capped to exactly 1 active face", core.active_faces.size() == 1)
	var found_hub_splitter = false
	for coord_v in torso.hex_grid.grid.keys():
		var t = torso.hex_grid.grid[coord_v]
		if t.tile_type == "Splitter" and "active_faces" in t and t.active_faces.size() > 1:
			found_hub_splitter = true
			break
	_check("a Splitter somewhere in the solve actually does the fan-out (not the Core itself)", found_hub_splitter)

	# Playtest report: "there is only one 3 way in the inventory" - the
	# per-hex placement loop used to grab whichever Splitter was FIRST in
	# inventory regardless of whether ITS rarity cap actually supported the
	# number of faces that hex's hub needed, so two different hubs could
	# both end up with 3 active_faces even though _real_starter_inventory()
	# only ever contains one Splitter (the single Rare one) whose
	# max_faces_by_rarity actually allows 3. Every placed Splitter must
	# respect its own cap, and at most as many hubs as the inventory
	# actually supports may reach any given face count.
	var splitter_face_counts: Array = []
	for coord_v in torso.hex_grid.grid.keys():
		var t = torso.hex_grid.grid[coord_v]
		if t.grid_position and t.grid_position.q == coord_v.x and t.grid_position.r == coord_v.y:
			if t.tile_type == "Splitter" and "active_faces" in t:
				_check("Splitter at (%d,%d) respects its own rarity cap (%d faces <= cap %d, rarity %d)" % [coord_v.x, coord_v.y, t.active_faces.size(), t.get_max_faces(), t.rarity],
					t.active_faces.size() <= t.get_max_faces())
				splitter_face_counts.append(t.active_faces.size())
	var three_plus_face_hubs = 0
	for c in splitter_face_counts:
		if c >= 3:
			three_plus_face_hubs += 1
	# _real_starter_inventory() has exactly one Splitter capable of 3 faces
	# (the single RARE one - COMMON/UNCOMMON cap at 2 per
	# max_faces_by_rarity) - never more than one hub should reach 3.
	_check("at most one hub reaches 3 active faces, matching the single Rare Splitter actually in inventory",
		three_plus_face_hubs <= 1)

	# Real simulation, not just static tile inspection - generate energy
	# from the Core and see what actually gets transferred to each limb.
	var initial_packets: Array[EnergyPacket] = []
	for h in torso.hex_grid.grid.keys():
		var tile = torso.hex_grid.get_tile(h)
		if tile.has_method("generate_energy"):
			var pkts = tile.generate_energy(torso.hex_grid)
			for p in pkts:
				p.position = HexCoord.new(h.x, h.y)
			initial_packets.append_array(pkts)

	var dummy_mech = MechScript.new()
	dummy_mech._simulate_grid(torso.hex_grid, initial_packets)
	var transfers = dummy_mech._collect_transfers(torso)
	dummy_mech.free()

	var limb_names = {
		HexTile.BodySlot.ARM_L: "ARM_L", HexTile.BodySlot.ARM_R: "ARM_R",
		HexTile.BodySlot.LEG_L: "LEG_L", HexTile.BodySlot.LEG_R: "LEG_R",
		HexTile.BodySlot.HEAD: "HEAD", HexTile.BodySlot.BACKPACK: "BACKPACK",
	}
	for slot in limb_names:
		_check("%s link actually receives energy from the starter-inventory solve" % limb_names[slot],
			transfers.get(slot, []).size() > 0)

	if failures == 0:
		print("PASS: AutoEquipSolver routes real starter-inventory energy to every limb link on a Torso, not just one")
	get_tree().quit(0 if failures == 0 else 1)

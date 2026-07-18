class_name ComponentEquipment
extends Node

const ComponentLinkTile = preload("res://scripts/tiles/ComponentLinkTile.gd")

var component_name: String = "Generic Component"
var slot_type: HexTile.BodySlot = HexTile.BodySlot.TORSO
var rarity: HexTile.Rarity = HexTile.Rarity.COMMON
var level: int = 1
var role_variant: String = ""

var grid_width: int = 3
var grid_height: int = 3

var hex_grid: HexGridComponent
var fixed_sinks: Array[HexCoord] = []
var valid_hexes: Array[HexCoord] = [] # Defines the irregular shape of the component

# O(1) membership mirror of valid_hexes, keyed by a packed q/r int. Several
# hot-ish paths (add_expansion_hex, _try_add_hex during procedural growth,
# can_place_tile on every drag-drop hover) used to do a linear O(n) scan of
# valid_hexes to answer "is this hex already part of the shape" - fine for a
# 10-hex Common part, wasteful for a 100-hex Mythic one queried repeatedly.
# Kept in sync wherever valid_hexes is mutated; generate_shape() also does a
# full rebuild at the end as a correctness safety net for its non-membership-
# checked branches (head/backpack/arm/leg/fallback just append in bulk).
var _valid_hex_set: Dictionary = {}

static func _hex_key(q: int, r: int) -> int:
	return (q + 4096) * 8192 + (r + 4096)

func _rebuild_valid_hex_set():
	_valid_hex_set.clear()
	for h in valid_hexes:
		_valid_hex_set[_hex_key(h.q, h.r)] = true

# Energy Intake tiles (every create_starter_arm/leg/head + backpack variant
# below) spawn at hex (0,0) riding ComponentLinkTile's class-level default
# active_faces = [0] (hex direction East - see HexCoord.get_directions) -
# nothing here ever pointed it at the shape it actually landed in. Playtest
# report: on any generated shape that doesn't happen to extend East from
# center, the intake's one allowed exit hits empty space, and
# ComponentLinkTile.process_energy's "no tile there" branch silently
# captures the packet as a dead weapon-payload instead of routing it into
# the rest of the grid - the intake renders as connected in the Garage view
# but can never actually deliver power. Point it at every real neighbor the
# shape has instead of a fixed guess (a shape can legitimately touch (0,0)
# from more than one side, so this can set multiple active_faces, which
# ComponentLinkTile's splitter branch already knows how to split across).
static func _orient_intake_to_shape(component: ComponentEquipment, intake: ComponentLinkTile, origin: HexCoord = null) -> void:
	if origin == null:
		origin = HexCoord.new(0, 0)
	var found: Array[int] = []
	for d in range(6):
		var n = origin.neighbor(d)
		if component._valid_hex_set.has(_hex_key(n.q, n.r)):
			found.append(d)
	if found.size() > 0:
		intake.active_faces = found

var infusion_level: int = 0
var infusion_xp: int = 0
var stat_modifiers: Dictionary = {}

# Black Market drawback: tile types that can never be installed on this
# component (enforced in GarageMenu._drop_tile). Empty for normal gear.
var forbidden_tile_types: Array = []

# --- Manual-hex upgrades (feature 5) ---------------------------------------
# Tiering a part up grants a budget of new hexes that the OWNER places by
# hand in the Garage, dictating the component's shape entirely (GarageMenu
# "Upgrade Part" button -> GarageGridRenderer expansion-click mode).

# Returns the number of expansion hexes granted, 0 if already Mythic.
func upgrade_rarity() -> int:
	if rarity >= HexTile.Rarity.MYTHIC:
		return 0
	rarity += 1
	return 3 + rarity # Uncommon grants 4 ... Mythic grants 7

# Add one player-chosen hex to the shape. Must be new and edge-adjacent to
# the existing shape (no floating islands).
func add_expansion_hex(h: HexCoord) -> bool:
	if _valid_hex_set.has(_hex_key(h.q, h.r)):
		return false
	# Adjacency check inverted: instead of scanning every existing hex's
	# neighbors (O(n*6)) to see if any equals h, check h's own 6 neighbors
	# against the O(1) membership set (O(6)) - same result, no scan.
	for d in range(6):
		var n = h.neighbor(d)
		if _valid_hex_set.has(_hex_key(n.q, n.r)):
			valid_hexes.append(HexCoord.new(h.q, h.r))
			_valid_hex_set[_hex_key(h.q, h.r)] = true
			return true
	return false

func _init(p_slot: HexTile.BodySlot = HexTile.BodySlot.TORSO, p_rarity: HexTile.Rarity = HexTile.Rarity.COMMON):
	slot_type = p_slot
	rarity = p_rarity
	
	hex_grid = HexGridComponent.new()
	hex_grid.name = "HexGridComponent"
	add_child(hex_grid)
	
	_setup_grid_bounds()
	_setup_fixed_sinks()

func _setup_grid_bounds():
	match rarity:
		HexTile.Rarity.COMMON:
			grid_width = 3
			grid_height = 3
		HexTile.Rarity.UNCOMMON:
			grid_width = 4
			grid_height = 3
		HexTile.Rarity.RARE:
			grid_width = 4
			grid_height = 4
		HexTile.Rarity.LEGENDARY:
			grid_width = 5
			grid_height = 5

func _setup_fixed_sinks():
	pass

func generate_shape():
	valid_hexes.clear()
	_valid_hex_set.clear()

	# Hex budget by rarity, with a sixth "beyond Mythic" entry because
	# TORSOS read one tier above their printed rarity (design ruling: a
	# Common torso must have room to power every limb, so every torso is
	# one rarity step more generous with hexes). Also fixes a latent bug:
	# MYTHIC wasn't in the old match at all and fell through with
	# base_count = 0 - a one-hex Mythic torso.
	var hex_budget = [10, 18, 28, 48, 72, 100]
	var budget_tier = clamp(rarity, 0, 4)
	if slot_type == HexTile.BodySlot.TORSO:
		budget_tier += 1
	var base_count = hex_budget[budget_tier]

	match slot_type:
		HexTile.BodySlot.HEAD:
			# Head expands upward, vertical zig-zag. Squat and wide.
			var head_len = 3
			if rarity >= HexTile.Rarity.UNCOMMON: head_len = 4
			if rarity >= HexTile.Rarity.RARE: head_len = 5
			if rarity >= HexTile.Rarity.LEGENDARY: head_len = 6
			
			for i in range(head_len):
				var q = i / 2
				valid_hexes.append(HexCoord.new(q, -i))
				
			# Add width for a squat shape
			if rarity >= HexTile.Rarity.UNCOMMON:
				for i in range(1, head_len):
					var q = i / 2
					valid_hexes.append(HexCoord.new(q - 1, -i))
					valid_hexes.append(HexCoord.new(q + 1, -i))
					
			if rarity >= HexTile.Rarity.LEGENDARY:
				for i in range(1, head_len - 1):
					var q = i / 2
					valid_hexes.append(HexCoord.new(q - 2, -i))
					valid_hexes.append(HexCoord.new(q + 2, -i))
					
		HexTile.BodySlot.BACKPACK:
			# Backpack is a wide horizontal cluster
			var pack_width = 3
			var pack_height = 2
			if rarity >= HexTile.Rarity.UNCOMMON: pack_width = 4; pack_height = 3
			if rarity >= HexTile.Rarity.RARE: pack_width = 5; pack_height = 4
			if rarity >= HexTile.Rarity.LEGENDARY: pack_width = 7; pack_height = 5
			
			for q in range(-pack_width/2, pack_width/2 + 1):
				for r in range(-pack_height/2, pack_height/2 + 1):
					valid_hexes.append(HexCoord.new(q, r))
			
		HexTile.BodySlot.TORSO:
			# Torso is symmetrical. Starts at 0,0 and grows outwards
			valid_hexes.append(HexCoord.new(0, 0)) # Core
			var radius = 1
			while valid_hexes.size() < base_count:
				# Add a ring
				for q in range(-radius, radius + 1):
					for r in range(-radius, radius + 1):
						if valid_hexes.size() >= base_count: break
						if abs(q + r) <= radius:
							# Role specific filtering
							if role_variant == "scout" and abs(q) > 1: continue # Thin scout torso
							if role_variant == "brawler" and abs(r) > 1: continue # Wide brawler torso
							
							var h = HexCoord.new(q, r)
							# In axial, symmetry across vertical axis (x=0) is: q -> -q-r, r -> r
							var h_sym = HexCoord.new(-q - r, r)
							
							if not _valid_hex_set.has(_hex_key(h.q, h.r)):
								valid_hexes.append(h)
								_valid_hex_set[_hex_key(h.q, h.r)] = true

							if valid_hexes.size() < base_count:
								if not _valid_hex_set.has(_hex_key(h_sym.q, h_sym.r)):
									valid_hexes.append(h_sym)
									_valid_hex_set[_hex_key(h_sym.q, h_sym.r)] = true
				radius += 1
				
		HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R:
			# Arms are long and narrow. 
			var dir_q = -1 if slot_type == HexTile.BodySlot.ARM_L else 1
			var width = 2 if rarity <= HexTile.Rarity.UNCOMMON else 3
			
			if role_variant == "scout": width = 1
			if role_variant == "brawler": width = 3 if rarity <= HexTile.Rarity.UNCOMMON else 4
			
			var length = base_count / width
			
			if role_variant == "sniper" and slot_type == HexTile.BodySlot.ARM_R:
				width = 1
				length = base_count # Super long rifle arm
			
			for l in range(length):
				for w in range(width):
					if valid_hexes.size() >= base_count: break
					valid_hexes.append(HexCoord.new(dir_q * l, w - width/2))
					
		HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R:
			# Legs are bulky rectangles downwards, tilted outward
			var is_left = slot_type == HexTile.BodySlot.LEG_L
			var width = 3 if rarity <= HexTile.Rarity.UNCOMMON else 4
			
			if role_variant == "scout": width = 2
			if role_variant == "brawler": width = 4 if rarity <= HexTile.Rarity.UNCOMMON else 5
			
			var length = base_count / width
			for l in range(length):
				var tilt = l / 2
				if role_variant == "scout": tilt = l # more tilted/lithe
				var shift = -tilt # Make both legs look like the left leg
				for w in range(width):
					if valid_hexes.size() >= base_count: break
					valid_hexes.append(HexCoord.new(w - width/2 + shift, l))
					
		_:
			# Fallback generic shape
			for q in range(grid_width):
				for r in range(grid_height):
					valid_hexes.append(HexCoord.new(q, r))

	# The non-TORSO branches above just bulk-append without touching
	# _valid_hex_set - one full rebuild here keeps it correct for everyone
	# (cheap: runs once per part generation, not a hot path).
	_rebuild_valid_hex_set()

func generate_procedural_shape():
	valid_hexes.clear()
	_valid_hex_set.clear()
	# Same budget ladder + torso bonus as generate_shape() - procedural
	# (enemy/boss/salvage/Black Market) parts follow the same rules, and
	# Mythic now gets a real 72 instead of Legendary's hand-me-down 48.
	var hex_budget = [10, 18, 28, 48, 72, 100]
	var budget_tier = clamp(rarity, 0, 4)
	if slot_type == HexTile.BodySlot.TORSO:
		budget_tier += 1
	var base_count = hex_budget[budget_tier]

	var start = HexCoord.new(0, 0)
	valid_hexes.append(start)
	_valid_hex_set[_hex_key(start.q, start.r)] = true

	var rng = RandomNumberGenerator.new()
	rng.randomize()

	var role = role_variant
	if role == "":
		var roles = ["ambusher", "brawler", "sniper", "jammer"]
		role = roles[rng.randi() % roles.size()]

	# Composable shapes: a component is built from a handful of "primitives"
	# (attached edge-to-edge so the whole thing stays contiguous), rather
	# than one big undifferentiated random walk. Three primitive kinds:
	#   line  - a straight single-file run of hexes in one direction
	#   hook  - a straight run that bends 60 degrees partway through (hex
	#           neighbor directions are exactly 60 degrees apart, so
	#           switching from direction d to d+-1 IS a 60-degree turn) -
	#           this gives the "thin hook, single diagonal track" look
	#   block - a small blobby cluster (local random-frontier growth)
	# Higher rarity = more primitives combined = more complex silhouettes
	# (e.g. "a big block with a thin hook coming off it").
	var weights = _get_archetype_weights(role)
	var num_primitives = 1
	match rarity:
		HexTile.Rarity.COMMON: num_primitives = 1
		HexTile.Rarity.UNCOMMON: num_primitives = 2
		HexTile.Rarity.RARE: num_primitives = 3
		HexTile.Rarity.LEGENDARY, HexTile.Rarity.MYTHIC: num_primitives = 4

	var remaining = base_count - 1 # start hex already placed
	# num_primitives sets the TARGET silhouette complexity, but must never
	# cap the hex budget: a line/hook primitive that happens to re-trace
	# already-placed cells adds almost nothing (duplicates are skipped, not
	# rerolled), and with a hard N-primitive loop a Mythic boss torso
	# (budget 100) could legitimately come out under 20 hexes (playtest:
	# "ostensibly this empty torso is a mythic boss torso... it is many
	# fewer hexes than it should have"). Keep attaching primitives until
	# the budget is actually SPENT, with a stall guard so a pathological
	# fully-boxed-in shape still terminates.
	var p = 0
	var stall_guard = num_primitives * 8
	while remaining > 0 and stall_guard > 0:
		stall_guard -= 1
		var slots_left = max(1, num_primitives - p)
		var budget = max(2, int(ceil(float(remaining) / slots_left)))
		var attach = valid_hexes[rng.randi() % valid_hexes.size()]
		var archetype = _pick_weighted_archetype(weights, rng)
		var added = _grow_primitive(attach, archetype, budget, rng)
		remaining -= added
		p += 1

# Role-flavored odds of picking each primitive type. Keys must match the
# match statement in _grow_primitive().
func _get_archetype_weights(role: String) -> Dictionary:
	match role:
		"sniper", "scout":
			return {"line": 0.6, "hook": 0.15, "block": 0.25} # long lines
		"brawler":
			return {"line": 0.15, "hook": 0.15, "block": 0.7} # dense blocks
		"ambusher":
			return {"line": 0.15, "hook": 0.6, "block": 0.25} # sharp hooks
		"jammer", "support":
			return {"line": 0.3, "hook": 0.2, "block": 0.5}
		_:
			return {"line": 0.33, "hook": 0.33, "block": 0.34}

func _pick_weighted_archetype(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total = 0.0
	for w in weights.values(): total += w
	var roll = rng.randf() * total
	var acc = 0.0
	for key in weights:
		acc += weights[key]
		if roll <= acc:
			return key
	return "block"

# Grows one primitive starting from an existing placed hex `attach`, adding
# up to `budget` new hexes. Returns how many were actually added (duplicates
# and out-of-bounds cells are skipped, so this can be less than budget).
func _grow_primitive(attach: HexCoord, archetype: String, budget: int, rng: RandomNumberGenerator) -> int:
	var added = 0
	match archetype:
		"line":
			var dir = rng.randi() % 6
			var cur = attach
			for i in range(budget):
				cur = cur.neighbor(dir)
				if _try_add_hex(cur): added += 1
		"hook":
			var dir = rng.randi() % 6
			var bend_at = max(1, int(budget * rng.randf_range(0.3, 0.6)))
			var cur = attach
			for i in range(bend_at):
				cur = cur.neighbor(dir)
				if _try_add_hex(cur): added += 1
			var turn = 1 if rng.randf() < 0.5 else -1
			var new_dir = (dir + turn + 6) % 6
			for i in range(budget - bend_at):
				cur = cur.neighbor(new_dir)
				if _try_add_hex(cur): added += 1
		"block":
			var frontier = [attach]
			var attempts = 0
			while added < budget and frontier.size() > 0 and attempts < budget * 20:
				attempts += 1
				var idx = rng.randi() % frontier.size()
				var cell = frontier[idx]
				var d = rng.randi() % 6
				var n = cell.neighbor(d)
				if _try_add_hex(n):
					frontier.append(n)
					added += 1
				elif rng.randf() < 0.3:
					frontier.remove_at(idx) # cell is likely saturated, stop probing it as often
	return added

# Adds a hex to valid_hexes if it's not already present and stays within a
# sane bounding radius (keeps procedural components from sprawling into
# absurd, unusable shapes at high primitive counts).
func _try_add_hex(h: HexCoord) -> bool:
	if abs(h.q) > 12 or abs(h.r) > 12:
		return false
	if _valid_hex_set.has(_hex_key(h.q, h.r)):
		return false
	valid_hexes.append(h)
	_valid_hex_set[_hex_key(h.q, h.r)] = true
	return true

func can_place_tile(coord: HexCoord) -> bool:
	return _valid_hex_set.has(_hex_key(coord.q, coord.r))

func add_infusion_xp(amount: int):
	infusion_xp += amount
	var needed = 500 + (infusion_level * 500)
	while infusion_xp >= needed:
		infusion_xp -= needed
		infusion_level += 1
		_roll_stat_modifier()
		needed = 500 + (infusion_level * 500)

func _roll_stat_modifier():
	if rarity < HexTile.Rarity.LEGENDARY: return # Only legendary gear can be augmented
	
	var possible_stats = ["kin_mult", "fire_mult", "ice_mult", "vtx_mult", "ltg_mult", "psn_mult", "exp_mult", "prc_mult", "vmp_mult", "dmg_mult", "spd_mult"]
	var roll = possible_stats[randi() % possible_stats.size()]
	
	if stat_modifiers.has(roll):
		stat_modifiers[roll] += 0.05 # Add 5%
	else:
		stat_modifiers[roll] = 1.05 # Start at 105%

static func create_starter_torso(role: String = "", p_rarity: int = HexTile.Rarity.COMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var torso = script.new(HexTile.BodySlot.TORSO, p_rarity)
	torso.component_name = "Torso"
	torso.role_variant = role
	torso.generate_shape() # Generates a shape
	
	# Add a Core at (0,0)
	var core_tile = load("res://scripts/tiles/CoreTile.gd").new()
	core_tile.body_slot = HexTile.BodySlot.TORSO
	core_tile.rarity = p_rarity
	torso.hex_grid.add_tile(HexCoord.new(0, 0), core_tile)
	torso.fixed_sinks.append(HexCoord.new(0, 0))

	# Find outermost Q for arms
	var min_q = 0
	var max_q = 0
	for h in torso.valid_hexes:
		if h.q < min_q: min_q = h.q
		if h.q > max_q: max_q = h.q

	# Add Sink for Left Arm
	var l_arm_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.ARM_L, true)
	l_arm_sink.body_slot = HexTile.BodySlot.TORSO
	l_arm_sink.rarity = p_rarity
	torso.hex_grid.add_tile(HexCoord.new(min_q, 0), l_arm_sink)
	torso.fixed_sinks.append(HexCoord.new(min_q, 0))

	# Add Sink for Right Arm
	var r_arm_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.ARM_R, true)
	r_arm_sink.body_slot = HexTile.BodySlot.TORSO
	r_arm_sink.rarity = p_rarity
	torso.hex_grid.add_tile(HexCoord.new(max_q, 0), r_arm_sink)
	torso.fixed_sinks.append(HexCoord.new(max_q, 0))

	# Find outermost R for head and legs
	var min_r = 0
	var max_r = 0
	for h in torso.valid_hexes:
		if h.r < min_r: min_r = h.r
		if h.r > max_r: max_r = h.r

	# Add Sink for Head (Top)
	var head_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.HEAD, true)
	head_sink.body_slot = HexTile.BodySlot.TORSO
	head_sink.rarity = p_rarity
	torso.hex_grid.add_tile(HexCoord.new(0, min_r), head_sink)
	torso.fixed_sinks.append(HexCoord.new(0, min_r))

	# Add Sink for Left Leg (Bottom Left)
	var l_leg_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.LEG_L, true)
	l_leg_sink.body_slot = HexTile.BodySlot.TORSO
	l_leg_sink.rarity = p_rarity
	torso.hex_grid.add_tile(HexCoord.new(-1, max_r), l_leg_sink)
	torso.fixed_sinks.append(HexCoord.new(-1, max_r))

	# Add Sink for Right Leg (Bottom Right)
	var r_leg_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.LEG_R, true)
	r_leg_sink.body_slot = HexTile.BodySlot.TORSO
	r_leg_sink.rarity = p_rarity
	torso.hex_grid.add_tile(HexCoord.new(1, max_r), r_leg_sink)
	torso.fixed_sinks.append(HexCoord.new(1, max_r))

	# Add Sink for Accessory Return (receives energy from Head/Backpack, acts as Input)
	var head_return_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new()
	head_return_sink.body_slot = HexTile.BodySlot.TORSO
	head_return_sink.tile_type = "Accessory Return"
	head_return_sink.rarity = p_rarity
	var acc_pos = HexCoord.new(0, min_r + 1)
	for h in torso.valid_hexes:
		if not torso.hex_grid.has_tile(h):
			acc_pos = h
			break
	torso.hex_grid.add_tile(acc_pos, head_return_sink)
	torso.fixed_sinks.append(acc_pos)

	# Add Sink for Backpack
	var backpack_sink = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.BACKPACK, true)
	backpack_sink.body_slot = HexTile.BodySlot.TORSO
	backpack_sink.rarity = p_rarity
	torso.hex_grid.add_tile(HexCoord.new(0, 1), backpack_sink)
	torso.fixed_sinks.append(HexCoord.new(0, 1))

	if role != "":
		var ai_mount = load("res://scripts/tiles/WeaponMountTile.gd").new()
		ai_mount.body_slot = HexTile.BodySlot.TORSO
		ai_mount.rarity = p_rarity
		var ai_mount_pos = HexCoord.new(1, -1)
		for h in torso.valid_hexes:
			if not torso.hex_grid.has_tile(h):
				ai_mount_pos = h
				break
		torso.hex_grid.add_tile(ai_mount_pos, ai_mount)
		torso.fixed_sinks.append(ai_mount_pos)

		var ai_core = load("res://scripts/tiles/MicrocoreTile.gd").new()
		ai_core.rarity = p_rarity
		var ai_core_pos = null
		for d in range(6):
			var n = ai_mount_pos.neighbor(d)
			for h in torso.valid_hexes:
				if h.equals(n) and not torso.hex_grid.has_tile(h):
					ai_core_pos = h
					ai_core.active_faces.clear()
					ai_core.active_faces.append((d + 3) % 6)
					break
			if ai_core_pos:
				break
		if ai_core_pos:
			torso.hex_grid.add_tile(ai_core_pos, ai_core)

	return torso
	
static func create_starter_arm(is_left: bool, role: String = "", p_rarity: int = HexTile.Rarity.COMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var slot = HexTile.BodySlot.ARM_L if is_left else HexTile.BodySlot.ARM_R
	var arm = script.new(slot, p_rarity)
	arm.component_name = "L. Arm" if is_left else "R. Arm"
	arm.role_variant = role
	arm.generate_shape()
	
	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = slot
	intake.rarity = p_rarity
	arm.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	arm.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(arm, intake)

	# Add a Weapon Mount at the furthest extent
	var max_q = 0
	var mount_h = HexCoord.new(0, 0)
	var dir = -1 if is_left else 1
	for h in arm.valid_hexes:
		if h.q * dir > max_q * dir:
			max_q = h.q
			mount_h = HexCoord.new(h.q, h.r)

	var mount = load("res://scripts/tiles/WeaponMountTile.gd").new()
	mount.body_slot = slot
	mount.rarity = p_rarity
	arm.hex_grid.add_tile(mount_h, mount)
	arm.fixed_sinks.append(mount_h)

	if role != "":
		var ai_core = load("res://scripts/tiles/MicrocoreTile.gd").new()
		ai_core.rarity = p_rarity
		var ai_core_pos = null
		for d in range(6):
			var n = mount_h.neighbor(d)
			for h in arm.valid_hexes:
				if h.equals(n) and not arm.hex_grid.has_tile(h):
					ai_core_pos = h
					ai_core.active_faces.clear()
					ai_core.active_faces.append((d + 3) % 6)
					break
			if ai_core_pos:
				break
		if ai_core_pos:
			arm.hex_grid.add_tile(ai_core_pos, ai_core)
	
	return arm

static func create_starter_leg(is_left: bool, role: String = "", p_rarity: int = HexTile.Rarity.COMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var slot = HexTile.BodySlot.LEG_L if is_left else HexTile.BodySlot.LEG_R
	var leg = script.new(slot, p_rarity)
	leg.component_name = "L. Leg" if is_left else "R. Leg"
	leg.role_variant = role
	leg.generate_shape()
	
	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = slot
	intake.rarity = p_rarity
	leg.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	leg.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(leg, intake)

	# Add Actuator at bottom
	var max_r = 0
	var mount_h = HexCoord.new(0, 0)
	for h in leg.valid_hexes:
		if h.r > max_r:
			max_r = h.r
			mount_h = HexCoord.new(h.q, h.r)

	var actuator = load("res://scripts/tiles/ActuatorTile.gd").new()
	actuator.body_slot = slot
	actuator.rarity = p_rarity
	leg.hex_grid.add_tile(mount_h, actuator)
	leg.fixed_sinks.append(mount_h)

	return leg

static func create_starter_head(role: String = "", p_rarity: int = HexTile.Rarity.COMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var head = script.new(HexTile.BodySlot.HEAD, p_rarity)
	head.component_name = "Head"
	head.role_variant = role
	head.generate_shape()
	
	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = HexTile.BodySlot.HEAD
	intake.rarity = p_rarity
	head.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	head.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(head, intake)

	var min_r = 0
	for h in head.valid_hexes:
		if h.r < min_r: min_r = h.r

	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.HEAD
	tor_return.rarity = p_rarity
	head.hex_grid.add_tile(HexCoord.new(0, min_r), tor_return)
	head.fixed_sinks.append(HexCoord.new(0, min_r))

	return head

static func create_starter_backpack(role: String = "", p_rarity: int = HexTile.Rarity.COMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, p_rarity)
	pack.component_name = "Backpack"
	pack.role_variant = role
	pack.generate_shape()
	
	var core = load("res://scripts/tiles/MicrocoreTile.gd").new()
	core.body_slot = HexTile.BodySlot.BACKPACK
	core.rarity = p_rarity
	pack.hex_grid.add_tile(HexCoord.new(0, 0), core)

	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r

	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	tor_return.rarity = p_rarity
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))

	return pack

# Standalone body for the Drone companion (see DroneBayTile.gd) - a small,
# self-powered TORSO-slot component. Registering it as TORSO (rather than
# inventing a whole parallel "generate energy" path) means equip_component()
# automatically drops a Core Reactor at (0,0) the moment it's equipped onto
# the Drone's own Mech-like node (see Drone.gd), so the drone generates its
# own power completely independent of the main mech's circuit - it keeps
# fighting even if the main mech's build is unpowered or jammed.
#
# generate_shape()'s TORSO branch grows symmetrically outward from (0,0)
# using the same rarity-indexed hex_budget ladder as the player's own torso,
# including the same "+1 tier" bump every TORSO-slot component gets there
# (originally meant to make room for 4 limbs + head + backpack sinks) -
# harmless here (just a modest bonus: a Common Drone Bay's drone gets an
# 18-hex grid, an Uncommon's gets 28, etc.) and not worth special-casing
# away just to shave a few hexes. Rarity still directly drives the grid
# size either way - exactly the user's "rarity of this tile affects the size
# of the grid the drone has."
static func create_starter_drone(p_rarity: int = HexTile.Rarity.COMMON) -> ComponentEquipment:
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var drone = script.new(HexTile.BodySlot.TORSO, p_rarity)
	drone.component_name = "Drone"
	drone.generate_shape()

	drone.fixed_sinks.append(HexCoord.new(0, 0)) # Core Reactor goes here on equip

	# Pre-installed Jumpjet, matching THIS tile's rarity (the user: "comes
	# with installed jumpjets matching the rarity of the hex in the
	# backpack") - scales the drone's own Mech.jumpjet_rarity/
	# current_move_speed up with rarity so it can actually keep pace with a
	# fast player instead of trailing behind.
	var jet_pos = _first_free_hex(drone, [HexCoord.new(0, 0)])
	var jumpjet = load("res://scripts/tiles/JumpjetTile.gd").new()
	jumpjet.rarity = p_rarity
	jumpjet.body_slot = HexTile.BodySlot.TORSO
	drone.hex_grid.add_tile(jet_pos, jumpjet)
	drone.fixed_sinks.append(jet_pos)

	# Starter Weapon Mount so a freshly-looted Drone Bay isn't a dead gun the
	# moment it's equipped - the player can rearrange/replace it like any
	# other tile (it's not in fixed_sinks).
	var mount_pos = _first_free_hex(drone, [HexCoord.new(0, 0), jet_pos])
	var mount = load("res://scripts/tiles/WeaponMountTile.gd").new()
	mount.rarity = p_rarity
	mount.body_slot = HexTile.BodySlot.TORSO
	drone.hex_grid.add_tile(mount_pos, mount)

	return drone

# Finds the first hex in `comp.valid_hexes` that isn't already occupied and
# isn't in `avoid` - small helper for create_starter_drone's pre-installed
# tiles. Falls back to (0, 1) if the shape is somehow too small (shouldn't
# happen at any real rarity - even Common gets a 10-hex budget).
static func _first_free_hex(comp: ComponentEquipment, avoid: Array) -> HexCoord:
	for h in comp.valid_hexes:
		var taken = comp.hex_grid.has_tile(h)
		var avoided = false
		for a in avoid:
			if a.q == h.q and a.r == h.r:
				avoided = true
				break
		if not taken and not avoided:
			return h
	return HexCoord.new(0, 1)

static func create_shield_backpack():
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.MYTHIC)
	pack.component_name = "Mythic Shield"
	pack.generate_shape()
	
	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(pack, intake)
	
	var shield_class = load("res://scripts/tiles/ShieldTile.gd")
	if shield_class:
		var shield = shield_class.new()
		shield.rarity = HexTile.Rarity.MYTHIC
		shield.body_slot = HexTile.BodySlot.BACKPACK
		pack.hex_grid.add_tile(HexCoord.new(0, 1), shield)
		
	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r
		
	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))
		
	return pack

static func create_jetpack_backpack():
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.UNCOMMON)
	pack.component_name = "Jetpack"
	pack.generate_shape()
	
	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(pack, intake)
	
	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r
		
	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))
	
	return pack

static func create_drone_backpack(p_rarity: int = HexTile.Rarity.UNCOMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, p_rarity)
	pack.component_name = "Drone Bay"
	pack.generate_shape()

	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(pack, intake)

	var drone_bay = load("res://scripts/tiles/DroneBayTile.gd").new()
	drone_bay.rarity = p_rarity
	drone_bay.body_slot = HexTile.BodySlot.BACKPACK
	drone_bay.build_drone_loadout()
	pack.hex_grid.add_tile(HexCoord.new(1, 0), drone_bay)
	pack.fixed_sinks.append(HexCoord.new(1, 0))

	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r

	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))

	return pack

static func create_missile_backpack():
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, HexTile.Rarity.LEGENDARY)
	pack.component_name = "Missile Pod"
	pack.generate_shape()
	
	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(pack, intake)
	
	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r
		
	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))
	
	# Pre-wire with microcores and mounts
	var microcore_class = load("res://scripts/tiles/MicrocoreTile.gd")
	var mount_class = load("res://scripts/tiles/WeaponMountTile.gd")
	
	# Add 3 Microcores (Legendary)
	for i in range(3):
		var core = microcore_class.new()
		core.rarity = HexTile.Rarity.LEGENDARY
		core.active_faces.clear()
		core.active_faces.append_array([1, 5]) # Output left and right
		core.set_face_output(1, (i % 6) + 1) # Set specific synergy
		core.set_face_output(5, (i % 6) + 1)
		# Just drop them in arbitrary valid positions for now
		if pack.valid_hexes.size() > i + 2:
			pack.hex_grid.add_tile(pack.valid_hexes[i + 2], core)
			
	# Add 6 Mounts (Legendary)
	var offset = 5
	for i in range(6):
		var mount = mount_class.new()
		mount.rarity = HexTile.Rarity.LEGENDARY
		if pack.valid_hexes.size() > offset + i:
			pack.hex_grid.add_tile(pack.valid_hexes[offset + i], mount)
			
	return pack

static func create_cloak_backpack(p_rarity: int = HexTile.Rarity.UNCOMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, p_rarity)
	pack.component_name = "Cloak Field"
	pack.role_variant = "ambusher"
	pack.generate_shape()

	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(pack, intake)

	var cloak = load("res://scripts/tiles/CloakTile.gd").new()
	cloak.rarity = p_rarity
	cloak.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(1, 0), cloak)

	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r

	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))

	return pack

# Single-jammer variant - superseded by create_dual_utility_backpack for
# scout's roll (see Mech._create_role_backpack), kept as a standalone
# constructor in case debug/modding code wants a plain single-item jammer
# backpack without the two-slot roll.
static func create_jammer_backpack(p_rarity: int = HexTile.Rarity.UNCOMMON):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, p_rarity)
	pack.component_name = "Jammer Module"
	pack.role_variant = "scout"
	pack.generate_shape()

	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(pack, intake)

	var jammer = load("res://scripts/tiles/JammerModuleTile.gd").new()
	jammer.rarity = p_rarity
	jammer.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(1, 0), jammer)

	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r

	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))

	return pack

# "Utility Duo" backpack - two utility tiles instead of one, rolled as one
# of three combos per the user's design: two Jammers, a Jammer + Cloak, or
# two Heal Beacons ("med packs"). Reactive: when the director has detected
# the player over-relying on one synergy for kills (forced_synergy >= 0,
# see SquadDirector.counter_jam_synergy via Mech._get_reactive_jam_synergy),
# the roll leans hard toward jammer-containing combos and any jammer(s)
# rolled target that exact synergy - jammers actually show up on the field
# in response to tactics, not just theoretically possible.
static func create_dual_utility_backpack(p_rarity: int = HexTile.Rarity.UNCOMMON, forced_synergy: int = -1) -> ComponentEquipment:
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, p_rarity)
	pack.role_variant = "support"
	pack.generate_shape()

	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(pack, intake)

	var roll = randf()
	var combo: String
	if forced_synergy >= 0:
		combo = "jammer_jammer" if roll < 0.55 else ("jammer_cloak" if roll < 0.9 else "heal_heal")
	else:
		combo = "jammer_jammer" if roll < 0.35 else ("jammer_cloak" if roll < 0.7 else "heal_heal")

	var slot_a: HexTile
	var slot_b: HexTile
	match combo:
		"jammer_jammer":
			slot_a = load("res://scripts/tiles/JammerModuleTile.gd").new(forced_synergy)
			slot_b = load("res://scripts/tiles/JammerModuleTile.gd").new(forced_synergy)
			pack.component_name = "Twin Jammer Rig"
		"jammer_cloak":
			slot_a = load("res://scripts/tiles/JammerModuleTile.gd").new(forced_synergy)
			slot_b = load("res://scripts/tiles/CloakTile.gd").new()
			pack.component_name = "Jammer/Cloak Rig"
		_:
			slot_a = load("res://scripts/tiles/HealBeaconTile.gd").new()
			slot_b = load("res://scripts/tiles/HealBeaconTile.gd").new()
			pack.component_name = "Twin Med Pack"

	slot_a.rarity = p_rarity
	slot_a.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(1, 0), slot_a)

	slot_b.rarity = p_rarity
	slot_b.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(-1, 0), slot_b)

	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r

	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))

	return pack

static func create_support_backpack(p_rarity: int = HexTile.Rarity.UNCOMMON, forced_synergy: int = -1):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	var pack = script.new(HexTile.BodySlot.BACKPACK, p_rarity)
	pack.component_name = "Support Kit"
	pack.role_variant = "support"
	pack.generate_shape()

	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(pack, intake)

	var healer = load("res://scripts/tiles/HealBeaconTile.gd").new()
	healer.rarity = p_rarity
	healer.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(1, 0), healer)

	# Higher-rarity support kits have room for a second ability. Used to be
	# always a Jammer Module; now it's a genuine roll (Jammer / Cloak /
	# second Heal Beacon) so support bots show up with real loadout variety
	# instead of one fixed pairing - and when the director has flagged an
	# over-relied-on synergy, the roll leans toward Jammer and aims it at
	# that synergy (see create_dual_utility_backpack's forced_synergy).
	if p_rarity >= HexTile.Rarity.RARE:
		var roll = randf()
		var jammer_chance = 0.7 if forced_synergy >= 0 else 0.45
		var second: HexTile
		if roll < jammer_chance:
			second = load("res://scripts/tiles/JammerModuleTile.gd").new(forced_synergy)
		elif roll < jammer_chance + 0.3:
			second = load("res://scripts/tiles/CloakTile.gd").new()
		else:
			second = load("res://scripts/tiles/HealBeaconTile.gd").new()
		second.rarity = p_rarity
		second.body_slot = HexTile.BodySlot.BACKPACK
		pack.hex_grid.add_tile(HexCoord.new(-1, 0), second)

	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r

	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))

	return pack

# Commander kit (FEATURE_ROADMAP.md group 4): standard support bots are
# capped at 2 special support modules (see create_support_backpack above);
# a Commander stacks up to FIVE - heal, jammer, shield generator, cloak,
# and a second heal beacon at Legendary+. One of these on the field is what
# makes a squad feel like it has a spine.
static func create_command_backpack(p_rarity: int = HexTile.Rarity.RARE):
	var script = load("res://scripts/core/ComponentEquipment.gd")
	p_rarity = max(p_rarity, HexTile.Rarity.RARE) # command kits don't come cheap
	var pack = script.new(HexTile.BodySlot.BACKPACK, p_rarity)
	pack.component_name = "Command Suite"
	pack.role_variant = "commander"
	pack.generate_shape()

	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	_orient_intake_to_shape(pack, intake)

	# Module loadout: [script_path, coord]. Order matters - the first four
	# always install; the fifth (second heal beacon) is Legendary+ only.
	var modules = [
		["res://scripts/tiles/HealBeaconTile.gd", HexCoord.new(1, 0)],
		["res://scripts/tiles/JammerModuleTile.gd", HexCoord.new(-1, 0)],
		["res://scripts/tiles/ShieldGeneratorTile.gd", HexCoord.new(1, -1)],
		["res://scripts/tiles/CloakTile.gd", HexCoord.new(-1, 1)],
	]
	if p_rarity >= HexTile.Rarity.LEGENDARY:
		modules.append(["res://scripts/tiles/HealBeaconTile.gd", HexCoord.new(2, -1)])

	for m in modules:
		var tile = load(m[0]).new()
		tile.rarity = p_rarity
		tile.body_slot = HexTile.BodySlot.BACKPACK
		pack.hex_grid.add_tile(m[1], tile)

	# Commanders come with a companion Drone by default (the user: "commanders
	# should come with one by default at the appropriate rarity") - always
	# installed, not rarity-gated like the second Heal Beacon above, since
	# this is the one guaranteed case (see Mech._create_role_backpack's
	# generic per-role chance for everyone else). build_drone_loadout() is
	# called explicitly (unlike the generic module loop above) since
	# DroneBayTile needs its nested loadout/visual_class built, not just
	# rarity/body_slot set.
	var drone_bay = load("res://scripts/tiles/DroneBayTile.gd").new()
	drone_bay.rarity = p_rarity
	drone_bay.body_slot = HexTile.BodySlot.BACKPACK
	drone_bay.build_drone_loadout()
	pack.hex_grid.add_tile(HexCoord.new(-2, 1), drone_bay)

	var max_r = 0
	for h in pack.valid_hexes:
		if h.r > max_r: max_r = h.r

	var tor_return = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.TORSO, true)
	tor_return.tile_type = "Torso Return"
	tor_return.body_slot = HexTile.BodySlot.BACKPACK
	pack.hex_grid.add_tile(HexCoord.new(0, max_r), tor_return)
	pack.fixed_sinks.append(HexCoord.new(0, max_r))

	return pack

func update_link_positions():
	if slot_type != HexTile.BodySlot.TORSO:
		return
		
	var min_q = 0
	var max_q = 0
	var min_r = 0
	var max_r = 0
	for h in valid_hexes:
		if h.q < min_q: min_q = h.q
		if h.q > max_q: max_q = h.q
		if h.r < min_r: min_r = h.r
		if h.r > max_r: max_r = h.r
		
	var new_sinks: Array[HexCoord] = []
	new_sinks.append(HexCoord.new(0, 0)) # Core
	
	var all_hexes = hex_grid.grid.keys()
	var tiles_to_move = [] # Array of Dicts: {tile, old_coord, new_coord}
	
	for key in all_hexes:
		var h = HexCoord.new(key.x, key.y)
		var tile = hex_grid.get_tile(h)
		# ComponentLinkTile._init() always overwrites tile_type away from its
		# initial "Component Link" value (to "Left Arm Link"/"Energy Intake"/
		# etc. - see that file's own _init) before returning, so no instance
		# EVER retains that literal string - this gate never matched anything,
		# making the whole function a silent no-op. Check the script instead.
		if tile.get_script() and tile.get_script().resource_path.ends_with("ComponentLinkTile.gd"):
			var new_coord = h
			if tile.target_slot == HexTile.BodySlot.ARM_L:
				new_coord = HexCoord.new(min_q, 0)
			elif tile.target_slot == HexTile.BodySlot.ARM_R:
				new_coord = HexCoord.new(max_q, 0)
			elif tile.target_slot == HexTile.BodySlot.HEAD:
				new_coord = HexCoord.new(0, min_r)
			elif tile.target_slot == HexTile.BodySlot.LEG_L:
				new_coord = HexCoord.new(-1, max_r)
			elif tile.target_slot == HexTile.BodySlot.LEG_R:
				new_coord = HexCoord.new(1, max_r)
			
			if new_coord.q != h.q or new_coord.r != h.r:
				tiles_to_move.append({"tile": tile, "old": h, "new": new_coord})
			else:
				new_sinks.append(new_coord)
				
	for move in tiles_to_move:
		hex_grid.remove_tile(move.old)
		hex_grid.add_tile(move.new, move.tile)
		new_sinks.append(move.new)
		
	fixed_sinks = new_sinks

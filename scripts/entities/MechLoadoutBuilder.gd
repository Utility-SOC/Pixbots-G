class_name MechLoadoutBuilder
extends RefCounted

# Extracted from Mech.gd (docs: Status.md, engine-coupling cut). Holds no scene-tree state of its own;
# every instance method operates on the owning `mech`. Mech.gd keeps one-line wrappers so callers are unchanged.

var mech

func _init(p_mech = null):
	mech = p_mech

# Special-ability backpacks for specific roles (cloak for ambushers, an
# occasional jammer module for scouts, heal beacon for support). Falls back
# to the plain default backpack otherwise. Kept as a thin dispatcher so
# adding a new role ability later is a one-line match arm.
func _create_role_backpack(role: String, p_rarity: int) -> ComponentEquipment:
	var forced_synergy = mech._get_reactive_jam_synergy()
	match role:
		"ambusher":
			if SimRng.stream("loot").randf() < 0.85: # not guaranteed, keeps some loot variety
				return Mech.ComponentEquipment.create_cloak_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON))
		"scout":
			# Base chance is low (infrequent, per the original design request),
			# but jumps way up once the director's flagged the player leaning
			# on one synergy for kills - "jammers spawn in response to player
			# tactics," not just at a fixed background rate.
			var chance = 0.25 if forced_synergy < 0 else 0.65
			if SimRng.stream("loot").randf() < chance:
				return Mech.ComponentEquipment.create_dual_utility_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON), forced_synergy)
		"support":
			return Mech.ComponentEquipment.create_support_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON), forced_synergy)
		"commander":
			return Mech.ComponentEquipment.create_command_backpack(max(p_rarity, HexTile.Rarity.RARE))

	# Commanders always come with a companion Drone (see create_command_
	# backpack); every other enemy role gets a modest independent chance at
	# one too (the user: "mobs/enemies should get to have them too") - never
	# for the player (role == "" only ever happens for the player's own
	# backpack, which stays entirely Garage-controlled, never procedurally
	# overridden). Rolled AFTER the role match above so it only ever applies
	# to whichever roles fell through without a guaranteed special backpack
	# of their own (including a "scout"/"ambusher" that rolled OUT of their
	# usual jammer/cloak chance above).
	if role != "":
		var roll = SimRng.stream("loot").randf()
		if roll < 0.08:
			return Mech.ComponentEquipment.create_drone_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON))
		elif roll < 0.12:
			return Mech.ComponentEquipment.create_missile_backpack()

	# Smoke Grenade cover (per the user: "some types of enemies... have
	# smoke grenades", later widened to "bosses should absolutely get
	# grenades too") - rolled independently of role, same "mobs get toys
	# too" spirit as the drone roll above. Open to everyone this function
	# builds for, bosses/rivals/champions included - no tier restriction.
	if role != "" and SimRng.stream("loot").randf() < 0.2:
		return Mech.ComponentEquipment.create_smoke_grenade_backpack(max(p_rarity, HexTile.Rarity.UNCOMMON))

	return Mech.ComponentEquipment.create_starter_backpack(role, p_rarity)

# Stock-replay counterpart of _recalculate_grid() - identical except the
# expensive _simulate_energy_flow() pass (confirmed via live diagnostic to
# cost 200ms+ per spawn on dense builds, see the 2026-08-10 step-cap/cull
# fix in this file and rust_ext/src/hexgrid_sim.rs) is replaced with a
# memoized replay of that pass's own output, cached on the StockBuild
# itself. Safe because the packet-routing simulation is a pure function of
# tile layout - no RNG anywhere in the routing path (generate_energy/
# process_energy); the only RNG on any tile type lives at construction
# time (JammerModuleTile._init's mode roll) or actual-fire time
# (MissileRackTile's shell-spread jitter), neither of which this touches -
# and the cache self-invalidates for free: StockBuildMutator.establish()/
# promote() always hand back a brand-new StockBuild object with an empty
# cache, never mutate serialized_components on an existing one in place.
func _recalculate_grid_for_stock(stock: StockBuild):
	mech._reset_grid_state()
	mech._compute_mass_and_stat_modifiers()

	if not mech.components.has(HexTile.BodySlot.TORSO):
		return

	if stock._simulation_cache.is_empty():
		var torso = mech.components[HexTile.BodySlot.TORSO]
		mech._simulate_energy_flow(torso)
		mech._capture_stock_simulation_cache(stock)
	else:
		mech._restore_stock_simulation_cache(stock)

	mech._collect_weapon_mounts_and_tile_capabilities()
	mech._finalize_grid_state()

# Replays a StockBuild's serialized tile placements onto this mech's
# already-built starter components, then recalculates via the memoized
# stock-cache path. Extracted out of build_loadout_for_role's use_stock
# branch so prewarm_stock_build (below) can drive the exact same replay
# on a throwaway, never-in-tree bot instead of duplicating this logic.
func _replay_stock_tiles(stock: StockBuild):
	# Deliberately NOT SaveManager._deserialize_component() here - that
	# rebuilds a whole fresh ComponentEquipment (generate_shape() +
	# per-tile deserialize + several legacy-save-compat sweeps: stray-
	# tile absorption, fixed_sinks re-inference, Energy Intake re-
	# orientation), real overhead built for an occasional save-file
	# load, not a per-spawn hot path. The component this mech already
	# has (built moments ago by create_starter_torso/arm, same code path
	# a fresh solve() would also build onto) already has the correct
	# shape/fixed_sinks/rarity - only the individual PLACED tiles need
	# restoring, via the lightweight per-tile SaveManager._deserialize_
	# tile(), same as AutoEquipSolver's own cache-replay (_replay_plan)
	# uses for the same reason.
	for slot_key in stock.serialized_components:
		var slot = int(slot_key)
		if not mech.components.has(slot):
			continue
		var comp = mech.components[slot]
		var grid = comp.hex_grid
		for tdata in stock.serialized_components[slot_key].get("tiles", []):
			var tile = SaveManager._deserialize_tile(tdata)
			if not tile or not tile.grid_position:
				continue
			var h = tile.grid_position
			var is_fixed_or_core = (h.q == 0 and h.r == 0)
			if not is_fixed_or_core:
				for s in comp.fixed_sinks:
					if s.q == h.q and s.r == h.r:
						is_fixed_or_core = true
						break
			if is_fixed_or_core:
				# Core/fixed-sink tiles already exist (constructed by
				# create_starter_* moments ago) - reconfigure the REAL
				# one's active_faces rather than replacing it outright.
				var real_tile = grid.get_tile(h)
				if real_tile and "active_faces" in tile and "active_faces" in real_tile:
					real_tile.active_faces = tile.active_faces.duplicate()
			else:
				grid.add_tile(h, tile)
	_recalculate_grid_for_stock(stock)

# Loading-screen prewarm factory (user's own idea, 2026-08-10: "would it
# help if we did a loading screen when we return from the garage for it
# to build out the enemy mechs in advance" - said after the step-cap/cull
# fix alone still wasn't enough). Builds a throwaway Mech purely to
# populate `stock`'s simulation cache (_recalculate_grid_for_stock) at
# Deploy time instead of paying that one-time simulate cost live during
# the wave that actually needs it - see StockBuildEvolution.
# prewarm_all_simulation_caches, called from Main._close_garage().
#
# Deliberately NEVER add_child()'d into any real scene tree: no
# MechRenderer, no CollisionShape2D, no "enemy" group membership, no AI
# state - _replay_stock_tiles/_recalculate_grid_for_stock don't need any
# of that (verified: no get_tree() call anywhere in that call chain
# except _create_role_backpack's _get_reactive_jam_synergy(), which is
# now null-safe specifically for this), and adding a real throwaway bot
# into the live world even briefly would risk it getting drawn, targeted,
# or counted toward the wave's enemy total. No-op if this build's cache
# is already warm (the common case after a build's first-ever prewarm or
# replay this session - _simulation_cache lives in memory for the rest of
# the session once populated, see StockBuild._simulation_cache's own
# comment).
static func prewarm_stock_build(stock: StockBuild) -> void:
	if not stock._simulation_cache.is_empty():
		return
	var bot = load("res://scripts/entities/Mech.gd").new()
	bot.is_player = false
	bot.combat_role = stock.role
	bot.base_rarity = stock.rarity
	bot.equip_component(Mech.ComponentEquipment.create_starter_torso(stock.role, stock.rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_arm(true, stock.role, stock.rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_arm(false, stock.role, stock.rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_leg(true, stock.role, stock.rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_leg(false, stock.role, stock.rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_head(stock.role, stock.rarity))
	bot.equip_component(bot._create_role_backpack(stock.role, stock.rarity))
	bot._replay_stock_tiles(stock)
	bot.free()

# Solves and registers a (template, role, rarity, slot) StockBuild that
# doesn't exist yet, off-tree, so the first live spawn of it is a cache
# replay instead of a fresh AutoEquipSolver run mid-wave. Mirrors what a
# real spawn's fresh-solve branch does (same inventory, same spawn_profile
# plumbing) via build_loadout_for_role itself, then warms the new build's
# simulation cache. No-op if the build already exists.
static func presolve_stock_build(evo, template_name: String, role: String, rarity: int, slot: int, profile) -> void:
	if evo.get_stock_build(template_name, role, rarity, slot) != null:
		return
	var bot = load("res://scripts/entities/Mech.gd").new()
	bot.is_player = false
	bot.combat_role = role
	bot.base_rarity = rarity
	bot.spawn_template_name = template_name
	bot.sub_archetype_slot = slot
	bot.spawn_profile = profile
	bot._stock_evo_override = evo
	bot.equip_component(Mech.ComponentEquipment.create_starter_torso(role, rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_arm(true, role, rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_arm(false, role, rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_leg(true, role, rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_leg(false, role, rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_head(role, rarity))
	bot.equip_component(bot._create_role_backpack(role, rarity))
	bot.build_loadout_for_role(role)
	bot.free()
	var stock = evo.get_stock_build(template_name, role, rarity, slot)
	if stock != null:
		prewarm_stock_build(stock)

# Off-tree solve of one extra (unregistered) candidate build for a key that
# already has a champion; its simulation cache is warmed so a live spawn that
# rolls a deviation test replays it instantly and reports its fitness back
# through the normal record_deviation_result path.
static func generate_deviation_candidate(evo, template_name: String, role: String, rarity: int, slot: int, profile) -> StockBuild:
	var bot = load("res://scripts/entities/Mech.gd").new()
	bot.is_player = false
	bot.combat_role = role
	bot.base_rarity = rarity
	bot.spawn_template_name = template_name
	bot.sub_archetype_slot = slot
	bot.spawn_profile = profile
	bot._stock_evo_override = evo
	bot._force_deviation = true
	bot.equip_component(Mech.ComponentEquipment.create_starter_torso(role, rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_arm(true, role, rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_arm(false, role, rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_leg(true, role, rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_leg(false, role, rarity))
	bot.equip_component(Mech.ComponentEquipment.create_starter_head(role, rarity))
	bot.equip_component(bot._create_role_backpack(role, rarity))
	bot.build_loadout_for_role(role)
	var ok: bool = bot._is_deviation_test
	var serialized: Dictionary = bot._deviation_components
	bot.free()
	if not ok:
		return null
	var candidate = StockBuildMutator.establish(template_name, role, rarity, serialized, slot, profile.profile_name if profile else "")
	prewarm_stock_build(candidate)
	return candidate

func build_loadout_for_role(role_name: String):
	# StockBuild cache/evolution (see StockBuildEvolution.gd) - every mech of
	# the same squad template's same role slot reuses one evolving build
	# instead of independently re-running AutoEquipSolver every spawn. A
	# small fraction of spawns still test a fresh deviation (see
	# should_test_deviation()) so the pool keeps improving; SquadDirector.
	# credit_bot_death() reports that deviation's fitness back when this bot
	# dies. Skipped entirely if there's no template context (debug spawns,
	# the safety-fallback trio in Main._spawn_wave_async) - those fall
	# straight through to the solver exactly as before this system existed.
	var stock_evo = mech._get_stock_build_evolution()
	var stock = null
	var use_stock = false
	if stock_evo and mech.spawn_template_name != "":
		var _t_stock_lookup = Time.get_ticks_usec()
		stock = stock_evo.get_stock_build(mech.spawn_template_name, role_name, mech.base_rarity, mech.sub_archetype_slot)
		use_stock = stock != null
		if use_stock and not mech._force_deviation and stock_evo.should_test_deviation():
			# Deviation rolled: consume a candidate generated off-wave
			# (StockBuildEvolution.pregenerate) so no fresh solve lands
			# mid-wave. Pool empty -> just replay the champion this once.
			var candidate = stock_evo.take_deviation_candidate(mech.spawn_template_name, role_name, mech.base_rarity, mech.sub_archetype_slot) if stock_evo.has_method("take_deviation_candidate") else null
			if candidate != null:
				Mech._perf_stock_lookup_usec += Time.get_ticks_usec() - _t_stock_lookup
				_replay_stock_tiles(candidate)
				mech._is_deviation_test = true
				mech._deviation_components = candidate.serialized_components
				mech._build_profile_name = candidate.solver_profile_name
				return
		elif use_stock and mech._force_deviation:
			use_stock = false
		Mech._perf_stock_lookup_usec += Time.get_ticks_usec() - _t_stock_lookup

	if use_stock:
		var _t_stock_replay = Time.get_ticks_usec()
		_replay_stock_tiles(stock)
		Mech._perf_stock_replay_usec += Time.get_ticks_usec() - _t_stock_replay
		mech._champion_build = stock
		mech._build_profile_name = stock.solver_profile_name
		return

	var _t_fresh_inventory = Time.get_ticks_usec()
	var inventory = []

	var add_tile = func(path, rarity, synergy=0):
		var tile = load(path).new()
		tile.rarity = rarity
		if synergy > 0 and "secondary_synergy" in tile:
			tile.secondary_synergy = synergy
		inventory.append(tile)

	# Tile rarity matches base_rarity uniformly (the player doesn't need to
	# see Mythic tiles until facing Mythic foes - a bot's own base_rarity
	# already gates that, per Main.MYTHIC_MILESTONE_START_WAVE). Used to
	# offset support tiles a step or two below the signature tile's rarity
	# ("signature tile strongest, support tiles trail behind") - real, but
	# rarity is part of both AutoEquipSolver's topology-cache key and
	# StockBuildEvolution's cache key, so that variance multiplied the
	# effective cache-key space per role for no gameplay benefit at low/mid
	# rarity. Microcore's own +1-above-component exception lives separately
	# in ComponentEquipment.gd's fixed-sink placement, not here.
	var tier = func(offset: int) -> int:
		return mech.base_rarity

	match role_name:
		"sniper":
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", tier.call(0))
			add_tile.call("res://scripts/tiles/CatalystTile.gd", tier.call(0))
			add_tile.call("res://scripts/tiles/DirectionalConduitTile.gd", tier.call(2))
		"brawler":
			add_tile.call("res://scripts/tiles/SplitterTile.gd", tier.call(1))
			add_tile.call("res://scripts/tiles/SplitterTile.gd", tier.call(1))
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", tier.call(1))
		"flamethrower":
			add_tile.call("res://scripts/tiles/InfuserTile.gd", tier.call(0), 1) # FIRE
			add_tile.call("res://scripts/tiles/SplitterTile.gd", tier.call(1))
			add_tile.call("res://scripts/tiles/SplitterTile.gd", tier.call(2))
		"ambusher":
			add_tile.call("res://scripts/tiles/InfuserTile.gd", tier.call(0), 4) # KINETIC
			add_tile.call("res://scripts/tiles/AmplifierTile.gd", tier.call(1))
		"scout":
			pass # Uses basic conduits if they were available, fallback empty solver handles it
		"commander":
			# Weapons are secondary for a Commander - the Command Suite
			# backpack is the payload. Feed the solver defensive parts.
			add_tile.call("res://scripts/tiles/ShieldTile.gd", tier.call(0))
			add_tile.call("res://scripts/tiles/AccumulatorTile.gd", tier.call(0))

	if mech.is_nemesis:
		# Nemesis Bounty: a bare retargeted Microcore face (SquadDirector.
		# _spawn_bot_for_role's counter-build) is only as strong as that
		# Microcore's own power_output - real, felt danger needs the packet
		# to pick up more magnitude on the way to the mount. Two Amplifiers
		# (not one) so the solver has enough headroom to actually chain one
		# onto the counter-built weapon path instead of both fighting over
		# the same single junction every other role tile already wants; a
		# Reflector gives it real material to route a longer/looping path
		# through them rather than a flat straight line. This is guaranteed
		# gear, not a probabilistic roll - the whole point of a Nemesis is
		# that it doesn't wobble.
		add_tile.call("res://scripts/tiles/AmplifierTile.gd", tier.call(0))
		add_tile.call("res://scripts/tiles/AmplifierTile.gd", tier.call(0))
		add_tile.call("res://scripts/tiles/ReflectorTile.gd", tier.call(0))

	# Give the solver something to actually work with: an Infuser it can
	# configure toward the spawn profile's counter-element/Pierce priority.
	# Without this, a profile could only ever reorder whatever flavor tiles
	# the role already hardcodes above - it couldn't introduce a genuinely
	# new counter-element into a role that doesn't normally use one.
	if mech.spawn_profile != null:
		add_tile.call("res://scripts/tiles/InfuserTile.gd", tier.call(1))
		
	# Inject a real Amplifier/Splitter/Elemental Infuser pool into the
	# solver's inventory for AI bots (user request 2026-08-10: "enemy bots
	# need to be able to use splitter/amplifier loops and have lots of
	# elemental infusers... try to use less than 20% directional conduit").
	# AutoEquipSolver only ever synthesizes a fresh Directional Conduit as
	# a LAST RESORT once inventory genuinely runs dry (see AutoEquipSolver.
	# gd's FILLER_TILE_PRIORITY/_straight_tile_priority - Amplifier/
	# Catalyst/Elemental Infuser/Splitter are ALL already prioritized ahead
	# of Directional Conduit for every cell type) - the fix belongs here,
	# in how much real inventory gets supplied, not in the solver's
	# placement logic. The previous fixed `min(4, base_rarity + 1)`
	# Amplifier-only pool was nowhere near enough to cover a real grid (a
	# Mythic Torso alone has 70+ open cells) - this scales with the bot's
	# actual open-hex budget instead, and rotates through all three
	# pass-through types so hubs get real Splitters to fan out into loops
	# and straight runs get Amplifier/Infuser variety instead of defaulting
	# to wire.
	if mech.spawn_template_name != "":
		var open_hex_budget = 0
		for slot in mech.components:
			var comp = mech.components[slot]
			if comp and comp.valid_hexes:
				open_hex_budget += comp.valid_hexes.size()
		var filler_count = clampi(open_hex_budget, 4, 250)
		var filler_types = [
			"res://scripts/tiles/AmplifierTile.gd",
			"res://scripts/tiles/SplitterTile.gd",
			"res://scripts/tiles/InfuserTile.gd",
			"res://scripts/tiles/CatalystTile.gd",
		]
		for i in range(filler_count):
			add_tile.call(filler_types[i % filler_types.size()], mech.base_rarity)

	var solver = Mech.AutoEquipSolverScript.new()
	Mech._perf_fresh_inventory_usec += Time.get_ticks_usec() - _t_fresh_inventory

	if mech.components.has(HexTile.BodySlot.TORSO):
		inventory = solver.solve(mech.components[HexTile.BodySlot.TORSO], inventory, mech.spawn_profile)
	if mech.components.has(HexTile.BodySlot.ARM_R):
		inventory = solver.solve(mech.components[HexTile.BodySlot.ARM_R], inventory, mech.spawn_profile)
	if mech.components.has(HexTile.BodySlot.ARM_L):
		inventory = solver.solve(mech.components[HexTile.BodySlot.ARM_L], inventory, mech.spawn_profile)
	# Head/Backpack condition the energy returning to the torso (Catalyst/
	# Amplifier/Infuser between their feed and Torso Return).
	for acc_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
		if mech.components.has(acc_slot) and not mech.components[acc_slot].fixed_sinks.is_empty():
			inventory = solver.solve(mech.components[acc_slot], inventory, mech.spawn_profile)

	mech._recalculate_grid()

	var _t_post_solve_serialize = Time.get_ticks_usec()
	mech._build_profile_name = mech.spawn_profile.profile_name if mech.spawn_profile != null else ""
	if stock_evo and mech.spawn_template_name != "":
		var serialized := {}
		for slot in [HexTile.BodySlot.TORSO, HexTile.BodySlot.ARM_R, HexTile.BodySlot.ARM_L, HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
			if mech.components.has(slot):
				serialized[slot] = SaveManager._serialize_component(mech.components[slot])
		if stock == null:
			stock_evo.establish_stock_build(mech.spawn_template_name, role_name, mech.base_rarity, serialized, mech.sub_archetype_slot, mech._build_profile_name)
		else:
			# This spawn rolled a deviation test against an existing build -
			# don't apply the result yet, just remember it. credit_bot_death()
			# reports it to StockBuildEvolution once this bot's own fitness is
			# known (see SquadDirector.credit_bot_death).
			mech._is_deviation_test = true
			mech._deviation_components = serialized
	Mech._perf_post_solve_serialize_usec += Time.get_ticks_usec() - _t_post_solve_serialize

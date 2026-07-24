extends Node

# Explicit preload rather than the bare global class name: LootManager is the
# first-registered autoload (see project.godot), and the engine's global
# script-class cache for a brand new file isn't always populated yet by the
# time the very first autoload is parsed - preload() sidesteps that entirely,
# same pattern already used elsewhere in this codebase for cross-script refs.
const BrandTileFactoryScript = preload("res://scripts/core/BrandTileFactory.gd")

# Probability map based on rarity. Raised across the board per
# FEATURE_ROADMAP.md (feature 5 / group 2): the upgrade + infusion +
# repair economy needs a steady stream of salvage fuel, so drops must be
# generous enough that scrapping chaff is routine, not precious.
# MYTHIC entry added - it was missing entirely, so a mythic tile on an
# enemy (debug-upgraded or future content) crashed the drop roll.
var DROP_RATES = {
	0: 0.30,  # COMMON
	1: 0.18,  # UNCOMMON
	2: 0.09,  # RARE
	3: 0.02,  # LEGENDARY
	4: 0.005, # MYTHIC - baseline; see _get_mythic_drop_rate() for the wave-scaled version actually used
}

# Per the user: Mythic drop odds should steadily climb as waves progress
# (paired with SquadDirector's matching wave-scaled Mythic-enemy seeding),
# tuned so a player realistically sees their first Mythic drop by around
# wave/level 30 - not guaranteed, just increasingly likely as more Mythic-
# tier enemies get killed. Every other rarity keeps its flat DROP_RATES
# entry; only Mythic scales, since it's the one rarity meant to feel like
# genuine progression rather than a fixed background rate.
func _get_mythic_drop_rate() -> float:
	return clamp(0.002 * float(current_wave), DROP_RATES[4], 0.08)

# Per the user: "the hex tiles that are core (accessory return, torso
# return, core reactor, links) should all drop at a much lower rate.
# Microcores should ALSO drop at a lower rate than they are now, but I'm
# happy for them to spawn more often than the returns, core and links."
# Every equipped tile independently rolls a drop by RARITY alone - but a
# Torso structurally REQUIRES one Core Reactor, one Accessory Return, and
# one Link per limb/head/backpack (7 mandatory "plumbing" tiles) regardless
# of build, while only a handful of tiles are ever genuinely interesting
# processors (Amplifier/Splitter/Resonator/Catalyst/...). With no per-type
# adjustment, that plumbing majority dominates what actually drops. This
# multiplier applies on top of the normal rarity-based chance.
#
# Follow-up (per the user): "links, intakes, returns, actuators, and
# microcores need to drop less frequently at all tiers except mythic."
# Two changes from the original pass: Energy Intake was already covered
# but Actuator wasn't (a plain 1.0x tile until now) - added alongside the
# other plumbing types. And Mythic tier is now EXEMPT from this multiplier
# entirely (returns 1.0) - a Mythic-tier Link/Return/Intake/Actuator/
# Microcore is a genuinely exciting drop worth keeping at full odds, unlike
# the low-tier plumbing this reduction is really aimed at. Both
# multipliers also cut further (0.2->0.12, 0.5->0.3) since the ask was
# "less frequently," not just "mythic-exempt" - the microcore-more-common-
# than-structural relationship the user asked to preserve the first time
# stays intact (0.3 > 0.12, same ~2.5x ratio as before).
const STRUCTURAL_TILE_TYPES = ["Core Reactor", "Accessory Return", "Torso Return", "Energy Intake", "Actuator",
	"Left Arm Link", "Right Arm Link", "Left Leg Link", "Right Leg Link", "Head Link", "Backpack Link"]
const STRUCTURAL_DROP_MULTIPLIER = 0.12
const MICROCORE_DROP_MULTIPLIER = 0.3

func _tile_type_drop_multiplier(tile_type: String, rarity: int = HexTile.Rarity.COMMON) -> float:
	if rarity == HexTile.Rarity.MYTHIC:
		return 1.0
	if tile_type in STRUCTURAL_TILE_TYPES:
		return STRUCTURAL_DROP_MULTIPLIER
	if tile_type == "Microcore":
		return MICROCORE_DROP_MULTIPLIER
	return 1.0

# Chance for a NON-boss kill to drop a full procedural component (salvage
# fodder for the component-upgrade loop). Bosses keep their guaranteed drop.
const COMPONENT_DROP_CHANCE = 0.03

var current_wave: int = 1

func generate_loot_for_mech(mech: Node):
	if not "components" in mech:
		return
		
	var equipped_tiles = []
	for comp in mech.components.values():
		if comp and comp.has_node("HexGridComponent"):
			equipped_tiles.append_array(comp.get_node("HexGridComponent").get_all_tiles())
	
	var is_boss = ("is_boss" in mech and mech.is_boss)
	var is_25th_wave_boss = is_boss and (current_wave % 25 == 0)
	
	if is_boss:
		# Bosses drop full components instead of just tiles
		var comp_script = load("res://scripts/core/ComponentEquipment.gd")
		var pack = null
		if mech.has_meta("boss_drop"):
			var drop_type = mech.get_meta("boss_drop")
			if drop_type == "shield":
				pack = comp_script.create_shield_backpack()
			elif drop_type == "jetpack":
				pack = comp_script.create_jetpack_backpack()
			elif drop_type == "missile":
				pack = comp_script.create_missile_backpack()
			elif drop_type == "drone":
				pack = comp_script.create_drone_backpack(HexTile.Rarity.RARE)

		if pack == null:
			var rarity = HexTile.Rarity.LEGENDARY if is_25th_wave_boss else HexTile.Rarity.RARE
			pack = _create_procedural_component(rarity, mech, "Boss")

		if pack != null:
			_spawn_component_drop(mech, pack)

		# Corporate Sponsorships (task #17): this boss's own brand drops one
		# of its tiles regardless of the player's sponsorship - see
		# BrandRegistry.gd's header for why (it's how an unaligned/differently
		# -sponsored player can still eventually get any brand's gear).
		if "brand_affiliation" in mech and mech.brand_affiliation != "":
			var boss_brand_tile = BrandTileFactoryScript.random_tile_for_brand(mech.brand_affiliation)
			if boss_brand_tile:
				_spawn_loot_drop(mech, boss_brand_tile)

			# Sponsor drip-feed bonus: a sponsored player ALSO gets one of
			# their OWN brand's tiles from every boss kill that ISN'T already
			# their own sponsor's boss (no double-dip beating your own
			# champion - you already got the line above for that case).
			var main = mech.get_tree().current_scene if mech.is_inside_tree() else null
			if main and "player_sponsorship" in main and main.player_sponsorship != "" and main.player_sponsorship != mech.brand_affiliation:
				var sponsor_tile = BrandTileFactoryScript.random_tile_for_brand(main.player_sponsorship)
				if sponsor_tile:
					_spawn_loot_drop(mech, sponsor_tile)

	elif randf() <= COMPONENT_DROP_CHANCE:
		# Regular kills occasionally shed a whole (Common/Uncommon) component
		# - salvage fodder that feeds the upgrade/infusion economy without
		# competing with boss drops for excitement.
		var rarity = HexTile.Rarity.UNCOMMON if randf() < 0.25 else HexTile.Rarity.COMMON
		var salvage = _create_procedural_component(rarity, mech, "Salvaged")
		_spawn_component_drop(mech, salvage)

	for tile in equipped_tiles:
		if is_25th_wave_boss:
			# Guaranteed drop of rare or better
			var roll = randf()
			if roll <= 0.10:
				tile.rarity = HexTile.Rarity.LEGENDARY
			else:
				tile.rarity = HexTile.Rarity.RARE
			_spawn_loot_drop(mech, tile)
			break 
			
		elif is_boss:
			if randf() <= 0.50:
				_spawn_loot_drop(mech, tile)
		else:
			var chance = _get_mythic_drop_rate() if tile.rarity == HexTile.Rarity.MYTHIC else DROP_RATES.get(tile.rarity, 0.0)
			chance *= _tile_type_drop_multiplier(tile.tile_type, tile.rarity)
			if randf() <= chance:
				_spawn_loot_drop(mech, tile)

# PvP ghost (Traveling Champion) loot - design ruling: a defeated ghost
# ALWAYS drops one component and some tiles, with the ghost's own
# equipped-tile rarities acting as a weighted loot table (rarer tiles it
# actually carried show up more often), still subject to normal rarity
# drop odds for the extra rolls.
func generate_ghost_loot(mech: Node):
	if not "components" in mech:
		return
	var equipped_tiles = []
	for comp in mech.components.values():
		if comp and comp.has_node("HexGridComponent"):
			equipped_tiles.append_array(comp.get_node("HexGridComponent").get_all_tiles())
	if equipped_tiles.is_empty():
		return

	# Rarity-weighted sampling of the ghost's own kit.
	var weights = []
	var total_weight = 0.0
	for tile in equipped_tiles:
		var wgt = pow(2.0, float(tile.rarity)) # each tier twice as attractive
		weights.append(wgt)
		total_weight += wgt

	var pick_weighted = func():
		var roll = randf() * total_weight
		for i in range(equipped_tiles.size()):
			roll -= weights[i]
			if roll <= 0.0:
				return equipped_tiles[i]
		return equipped_tiles[equipped_tiles.size() - 1]

	# 1. Guaranteed component at a rarity sampled from the ghost's kit.
	var comp_rarity = pick_weighted.call().rarity
	var pack = _create_procedural_component(comp_rarity, mech, "Champion")
	_spawn_component_drop(mech, pack)

	# 2. One guaranteed tile + a few extra rolls gated by the normal
	# per-rarity drop odds (the "still subject to normal drop rules" part).
	# A tile instance can only be handed to ONE pickup - re-picks are skipped.
	var dropped = {}
	var first_tile = pick_weighted.call()
	dropped[first_tile] = true
	_spawn_loot_drop(mech, first_tile)
	for _i in range(3):
		var tile = pick_weighted.call()
		if dropped.has(tile):
			continue
		var chance = _get_mythic_drop_rate() if tile.rarity == HexTile.Rarity.MYTHIC else DROP_RATES.get(tile.rarity, 0.0)
		chance *= _tile_type_drop_multiplier(tile.tile_type, tile.rarity)
		if randf() <= chance:
			dropped[tile] = true
			_spawn_loot_drop(mech, tile)

# Shared procedural-component builder - was inlined in the boss branch;
# now regular salvage drops use the exact same path at lower rarity.
func _create_procedural_component(rarity: int, mech: Node, name_prefix: String):
	var comp_script = load("res://scripts/core/ComponentEquipment.gd")
	var slots = [HexTile.BodySlot.ARM_L, HexTile.BodySlot.ARM_R, HexTile.BodySlot.LEG_L, HexTile.BodySlot.LEG_R, HexTile.BodySlot.HEAD, HexTile.BodySlot.TORSO]
	var slot = slots[randi() % slots.size()]
	var pack = comp_script.new(slot, rarity)
	pack.component_name = name_prefix + " " + str(slot) + " Drop"
	pack.role_variant = mech.combat_role if "combat_role" in mech else ""
	pack.generate_procedural_shape()

	# Add intake
	var intake = load("res://scripts/tiles/ComponentLinkTile.gd").new(HexTile.BodySlot.NONE, true)
	intake.tile_type = "Energy Intake"
	intake.body_slot = slot
	pack.hex_grid.add_tile(HexCoord.new(0, 0), intake)
	pack.fixed_sinks.append(HexCoord.new(0, 0))
	comp_script._orient_intake_to_shape(pack, intake)
	return pack

func _spawn_component_drop(mech: Node, pack):
	if pack == null:
		return
	var drop = load("res://scripts/entities/LootPickup.gd").new()
	drop.equipment_data = pack
	drop.global_position = mech.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	if mech.get_parent():
		mech.get_parent().call_deferred("add_child", drop)

func _spawn_loot_drop(mech: Node, tile: HexTile):
	var drop = load("res://scripts/entities/LootPickup.gd").new()
	drop.tile_data = tile
	drop.global_position = mech.global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))
	if mech.get_parent():
		mech.get_parent().call_deferred("add_child", drop)

class_name MechDamage
extends RefCounted

# Extracted from Mech.gd (docs: Status.md, engine-coupling cut). Holds no scene-tree state of its own;
# every instance method operates on the owning `mech`. Mech.gd keeps one-line wrappers so callers are unchanged.

var mech

func _init(p_mech = null):
	mech = p_mech

# Shared shield-mitigation step used by both apply_damage() and
# apply_part_damage() (previously duplicated verbatim in both - a fix to
# one would silently desync from the other). Mutates shield_hp directly and
# returns the amount of damage that should still be applied to HP/parts
# (0.0 if the shield fully absorbed the hit).
func _apply_shield_mitigation(amount: float, element: String) -> float:
	if mech.shield_hp <= 0 or amount <= 0:
		return amount

	# RPG Shield Logic
	if element == "LIGHTNING":
		amount *= 1.5 # Base 1.5x against any shield

	var shield_str = ""
	var syn_id = 0
	if typeof(mech.dominant_shield_synergy) == TYPE_INT:
		syn_id = mech.dominant_shield_synergy
	elif typeof(mech.dominant_shield_synergy) == TYPE_STRING and mech.dominant_shield_synergy != "":
		syn_id = int(mech.dominant_shield_synergy)

	# dominant_shield_synergy is a stringified SynergyType id (see
	# _recalculate_grid's shield block - keys come straight from packet
	# synergies dicts). A previous hand-written table here used a stale
	# numbering (3=POISON where SynergyType 3 is LIGHTNING, etc.), which
	# silently broke the elemental rock-paper-scissors for LIGHTNING/VORTEX/
	# POISON shields and gave VAMPIRIC/KINETIC shields no counters at all.
	if syn_id > 0:
		shield_str = EnergyPacket.element_name(syn_id)

	if shield_str != "":
		if element == "FIRE" and shield_str == "ICE": amount *= 2.0
		elif element == "ICE" and shield_str == "FIRE": amount *= 2.0
		elif element == "POISON" and shield_str == "VAMPIRIC": amount *= 2.0
		elif element == "VAMPIRIC" and shield_str == "POISON": amount *= 2.0
		elif element == "KINETIC" and shield_str == "LIGHTNING": amount *= 2.0
		elif element == "LIGHTNING" and shield_str == "KINETIC": amount *= 2.0
		elif element == "VORTEX" and shield_str == "KINETIC": amount *= 2.0

	# MYTHIC Shield - Aegis: a hard per-hit damage cap while shields hold,
	# turning big alpha-strikes into a multi-hit whittling fight instead.
	# Pure tank/absorb - no offensive payoff, unlike Deflector below.
	if mech.shield_mythic_mode == 0 and mech.max_shield_hp > 0:
		amount = min(amount, mech.max_shield_hp * Mech.AEGIS_HIT_CAP_RATIO)

	# Corporate Sponsorships: Aegis Dynamics' elemental Aegis - the SAME hard
	# per-hit cap as the Mythic Shield Generator's own Aegis mode above, but
	# gated on brand equip rather than a Mythic mode toggle, and scoped to
	# every "elemental" synergy specifically (locked design: "anything not
	# kinetic, pierce, raw, or explosion" - i.e. FIRE/ICE/LIGHTNING/VORTEX/
	# POISON/VAMPIRIC). Independent of shield_mythic_mode - a mech with BOTH
	# a Mythic Aegis Shield Generator AND this brand tile just gets whichever
	# cap is more restrictive, since both apply as separate min() clamps.
	if mech.has_elemental_aegis and mech.max_shield_hp > 0 and element in Mech.ELEMENTAL_SYNERGY_NAMES:
		amount = min(amount, mech.max_shield_hp * Mech.AEGIS_HIT_CAP_RATIO)

	mech.shield_hp -= amount
	if mech.shield_hp < 0:
		var overflow = -mech.shield_hp
		mech.shield_hp = 0
		# MYTHIC Shield - Deflector: "very effective defense tool if used
		# properly" per the user - overflow that would otherwise bleed
		# through to HP instead gets ejected as an offensive burst in a
		# random direction, fully absorbing the hit (no HP damage taken)
		# at the cost of not being an AIMED counterattack.
		if mech.shield_mythic_mode == 1:
			_deflect_overflow(overflow)
			return 0.0
		return overflow
	return 0.0 # Shields absorbed all damage

# Ejects `amount` of absorbed overflow energy as a random-direction AoE
# burst - reuses the same PhysicsShapeQueryParameters2D/intersect_shape
# pattern Projectile._trigger_biome_explosion already uses for its own AoE
# hits, rather than inventing a second implementation of "damage everyone
# in a radius."
func _deflect_overflow(amount: float):
	var burst_dir = Vector2.RIGHT.rotated(SimRng.stream("combat").randf() * TAU)
	# enemy + player layers, same convention as OilSlickHazard._tick_damage
	var colliders = SimPhysics.circle_colliders(mech, Transform2D(0.0, mech.global_position + burst_dir * (Mech.DEFLECTOR_BURST_RADIUS * 0.5)), Mech.DEFLECTOR_BURST_RADIUS, SimPhysics.LAYER_ENEMY | SimPhysics.LAYER_PLAYER)
	for col in colliders:
		if col != mech and col.has_method("apply_damage"):
			col.apply_damage(amount, "RAW")
	if mech.get_parent():
		var ring = load("res://scripts/visuals/BossTelegraphRing.gd").new()
		mech.get_parent().add_child(ring)
		ring.global_position = mech.global_position + burst_dir * (Mech.DEFLECTOR_BURST_RADIUS * 0.5)
		ring.burst(15.0, Mech.DEFLECTOR_BURST_RADIUS, 0.2, Color(0.3, 0.6, 1.0, 1.0))

# Locked exemption list (FEATURE_ROADMAP.md Decision Log): bosses,
# Commanders, Support units, and anyone standing in a Support unit's aura
# are immune to the instant-execution roll above. This was originally the
# single-purpose PiercingJammerMech's whole reason for existing; it's now
# one of three functions on the general-purpose SupportMech (scripts/
# entities/SupportMech.gd - see its header), which adds itself to the
# "pierce_immunity_aura" group on _ready(). The aura check below is a
# plain distance test against every live one, done only at execution-roll
# time (a PIERCE hit that got past shields) rather than every frame - this
# is a rare event, so an O(k) scan over however many support units are
# alive is cheap and avoids any per-frame cached-flag sync complexity.
func _is_pierce_execution_exempt() -> bool:
	if mech.is_boss:
		return true
	if mech.combat_role == "commander" or mech.combat_role == "support":
		return true
	for pj in mech.get_tree().get_nodes_in_group("pierce_immunity_aura"):
		# Only SupportMech instances ever join this group, so
		# PIERCE_AURA_RADIUS (one of its own script constants) is always
		# present - no membership guard needed beyond instance validity.
		if is_instance_valid(pj) and mech.global_position.distance_to(pj.global_position) <= pj.PIERCE_AURA_RADIUS:
			return true
	return false

func _apply_smoke_mitigation(amount: float, element: String) -> float:
	if amount <= 0.0 or element == "PIERCE" or element == "EXPLOSION":
		return amount
	if mech.is_in_smoke():
		amount *= Mech.SMOKE_DAMAGE_MULT
	return amount

func _apply_damage_body(amount: float, element: String = "RAW", source: Node = null, was_reflected: bool = false, source_label_override: String = ""):
	if amount > 0 and element == "VORTEX" and mech.vortex_damage_reduction > 0.0:
		amount *= (1.0 - mech.vortex_damage_reduction)

	if mech.elemental_resistances.has(element):
		amount *= mech.elemental_resistances[element]

	amount = _apply_smoke_mitigation(amount, element)

	# PIERCE "rent" status: torn armor takes +20% from everything while
	# the rend lasts (applied to damage only, never to heals).
	if amount > 0 and mech.status_effects.has("rent"):
		amount *= 1.2

	# DRENCHED (geysers, water): soaked armour conducts Lightning (+50%) and shrugs off Fire (-50%).
	if amount > 0 and mech.status_effects.has("drenched"):
		if element == "LIGHTNING":
			amount *= 1.5
		elif element == "FIRE":
			amount *= 0.5

	# Balanced-school Mythic Actuator: a brief post-ram "brace" window
	# (see _process_ramming) shaves incoming damage - the utility half of
	# that school's flavor, on top of the extra ram knockback it also gets.
	if amount > 0 and mech._brace_timer > 0.0:
		amount *= 0.75

	if amount > 0 and mech.wager_damage_taken_mult != 1.0:
		amount *= mech.wager_damage_taken_mult # a "glass" wager

	# Capture-point armour buff (CaptureBuffs): a timed cut to damage taken.
	if amount > 0 and not mech.capture_buffs.is_empty():
		amount *= CaptureBuffs.damage_taken_mult(mech)

	# Corporate Sponsorships: Keeneye Sensing's Counter-Cloak tile. Cloak
	# itself never gates targeting/visibility anywhere in this codebase (it's
	# purely a modulate.a fade plus the attacker's own ambush damage
	# multiplier - see SensorTile.gd's header) so "bypasses cloak" resolves
	# to negating that multiplier when you're the one getting hit. Checked at
	# HIT time via the attacker's LIVE _get_ambush_multiplier() (true while
	# still cloaked OR within the brief post-decloak ambush window) rather
	# than tracking which specific packet was ambush-boosted at fire time -
	# an honest approximation: it correctly discounts the shot that actually
	# reveals/represents the ambush, but could rarely also discount an
	# unrelated normal shot from the same attacker if it happens to land
	# during a coincidentally-timed later ambush window.
	if amount > 0 and mech.has_cloak_detection and is_instance_valid(source) and source.has_method("_get_ambush_multiplier"):
		var ambush_mult = source._get_ambush_multiplier()
		if ambush_mult > 1.0:
			amount /= ambush_mult

	if not mech.is_player:
		var main = mech.get_tree().current_scene
		# SquadDirector lives under Main.world (the pixel-viewport game
		# world), not directly under Main itself - see Main.gd's
		# _setup_pixel_viewport() for why.
		if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
			main.world.get_node("SquadDirector").log_player_damage(amount, element)

	if amount > 0:
		mech.time_since_last_hit = 0.0
		mech._break_cloak()
		# Remember what element is currently hurting us - if this hit kills
		# us, die() reports it to the director as the kill method
		# (feeds pierce-overuse counter-pressure, see SquadDirector).
		mech.last_damage_element = element

	amount = _apply_shield_mitigation(amount, element)
	# NOTE: this used to be `if amount <= 0: return`, which was correct for
	# "shields fully absorbed a positive hit" (mitigation returns exactly
	# 0.0 for that case) but ALSO silently swallowed every heal - a heal
	# comes in as a negative amount, passes through mitigation unchanged
	# (shields don't interact with negative amounts), and a negative number
	# is always <= 0, so every single heal (Vampiric lifesteal, Heal
	# Beacon's self-heal path if it's ever routed through here, etc.) was
	# quietly doing nothing. Only an EXACT zero means "shields absorbed it
	# all, nothing left to apply" - that's the only case that should bail.
	if amount == 0.0:
		return

	# Reactive Plating counter-hit (design request - see has_reactive_plating's
	# field comment for the full trigger design). `amount` here is the FINAL
	# post-elemental-resistance, post-shield damage that's about to land, so
	# the counter-hit scales off what actually got through, not the raw
	# incoming number. was_reflected guards against infinite ping-pong
	# between two mutually-plated mechs standing adjacent - this counter-hit
	# is tagged was_reflected=true, so it can't trigger the attacker's OWN
	# plating back at us in turn.
	if amount > 0.0 and mech.has_reactive_plating and mech.embrittle_timer <= 0.0 and not was_reflected \
			and is_instance_valid(source) and source.has_method("apply_damage") and "global_position" in source:
		var trigger_radius = TileStatsRegistry.get_stat("ReactivePlatingTile", "trigger_radius", 140.0)
		if mech.global_position.distance_to(source.global_position) <= trigger_radius:
			var src_id = source.get_instance_id()
			if not mech._reactive_plating_cooldowns.has(src_id):
				var counter_dmg = amount * mech.reactive_plating_reflect_pct
				if counter_dmg > 0.0:
					mech._reactive_plating_cooldowns[src_id] = TileStatsRegistry.get_stat("ReactivePlatingTile", "trigger_cooldown", 0.75)
					source.apply_damage(counter_dmg, "RAW", mech, true, "REACTIVE ARMOR")

	# Squad._calculate_fitness's damage-traded and reflection-punishment
	# axes (see took_damage's own field comment) - post-mitigation amount,
	# same point dealt_damage's counterpart fires from the attacker's side.
	if not mech.is_player and amount > 0:
		mech.took_damage.emit(amount, was_reflected)

	# Near-peer evolution premium: this victim is on the player's side
	# (is_player covers the player AND player-owned drones; the "player"
	# group membership distinguishes which) and the attacker is an enemy
	# bot - credit it (see note_priority_target_damage / fitness).
	if mech.is_player and amount > 0 and is_instance_valid(source) \
			and source.get("is_player") == false and source.has_method("note_priority_target_damage"):
		source.note_priority_target_damage(amount, mech.is_in_group("player"))

	if mech.is_player and amount > 0:
		_log_incoming_damage(amount, element, source, source_label_override)
		var main = mech.get_tree().current_scene
		if main and "world" in main and main.world and main.world.has_node("SquadDirector"):
			main.world.get_node("SquadDirector").log_bot_damage(amount, element)

	# Piercing "cut in half" execution: a low flat chance for any PIERCE hit
	# that actually gets past shields to instantly finish the target,
	# regardless of remaining HP. Locked exemption list per
	# FEATURE_ROADMAP.md's Decision Log - see _is_pierce_execution_exempt().
	if element == "PIERCE" and not _is_pierce_execution_exempt():
		if SimRng.stream("combat").randf() < Mech.PIERCE_EXECUTION_CHANCE:
			_show_floating_text("EXECUTED", Color(1.0, 0.15, 0.15))
			HitstopManager.trigger()
			mech.hp = 0
			if mech.is_player and is_instance_valid(source) and source.has_method("note_priority_kill"):
				source.note_priority_kill(mech.is_in_group("player"))
			mech.die()
			return

	if amount < 0:
		_show_floating_text("+%d" % int(round(-amount)), Color(0.3, 1.0, 0.4))
	elif amount >= 1.0:
		# Skip tiny continuous-tick damage (burning ticks ~0.08/frame) so
		# the display doesn't turn into a wall of flickering micro-numbers.
		_show_floating_text(str(int(round(amount))), Color(1.0, 0.9, 0.3) if mech.is_player else Color(1.0, 1.0, 1.0))

	var shatter_source = source if is_instance_valid(source) else (mech.hit_source if is_instance_valid(mech.hit_source) else null)
	IceEffects.try_shatter(mech, element, amount, shatter_source)
	if amount < 0.0:
		# A heal never lifts HP above max_hp (it used to be uncapped: lifesteal on huge shots banked millions of HP over a 100 HP
		# bar). Health already above max (a set value) is left alone, it just stops growing.
		mech.hp = maxf(mech.hp, minf(mech.hp - amount, mech.max_hp))
	else:
		mech.hp -= amount
	if not mech.pending_shatter.is_empty():
		IceEffects.resolve_shatter(mech)
	if mech.hp <= 0:
		# Killing-blow premium for near-peer evolution (see note_priority_kill).
		if mech.is_player and is_instance_valid(source) and source.has_method("note_priority_kill"):
			source.note_priority_kill(mech.is_in_group("player"))
		mech.die()

# "Rival <name>" takes priority over "Boss" over plain role, matching how
# those are already surfaced elsewhere (see Main.gd's RIVAL floating text /
# rival_name meta). Static so projectiles/mortars can call it at FIRE time,
# while the shooter is still guaranteed alive - see _log_incoming_damage's
# own comment for why that matters.
static func resolve_attacker_label(source: Node) -> String:
	if source and is_instance_valid(source):
		if source.has_meta("rival_name"):
			return "Rival " + str(source.get_meta("rival_name"))
		elif "is_boss" in source and source.is_boss:
			return "Boss"
		elif "combat_role" in source and source.combat_role != "":
			return source.combat_role.capitalize()
	return "Environment"

# Appends one entry to recent_damage_log and prunes anything older than
# DEATH_LOG_LOOKBACK_SEC (plus a hard size cap as a defensive backstop) -
# see the field's own comment for what reads this. amount here is already
# post-mitigation (the real damage that got through shields), which is the
# number that actually matters for "what killed me."
#
# label_override: playtest report - a kill from a bot whose projectile/
# mortar was still in flight when the bot itself died showed up as "Hit by:
# Environment" even though it was a real KINETIC weapon hit. Label captured
# now (from the still-valid `source`) covers the common case, but `source`
# is already null by the time Projectile._handle_hit calls apply_damage if
# the shooter died mid-flight - Godot's argument-type check rejects a freed
# reference before it even reaches here. Projectile/MortarShell snapshot the
# shooter's label at FIRE time (while it's still alive) via
# resolve_attacker_label() and pass it through as this override so a kill
# from an already-dead attacker still gets credited correctly instead of
# falling back to "Environment".
func _log_incoming_damage(amount: float, element: String, source: Node, label_override: String = ""):
	var label = resolve_attacker_label(source)
	if label == "Environment" and label_override != "":
		label = label_override

	var now = Time.get_ticks_msec() / 1000.0
	var entry = {
		"label": label,
		"element": element,
		"amount": amount,
		"time": now,
	}
	mech.recent_damage_log.append(entry)

	var cutoff = now - Mech.DEATH_LOG_LOOKBACK_SEC
	while mech.recent_damage_log.size() > 0 and mech.recent_damage_log[0]["time"] < cutoff:
		mech.recent_damage_log.pop_front()
	while mech.recent_damage_log.size() > 200:
		mech.recent_damage_log.pop_front()

# Shared floating-text popup for damage/heal numbers - used from here and
# from _emit_heal_pulse() (which sets hp directly and bypasses this
# function entirely, so it calls this separately).
func _show_floating_text(text: String, color: Color):
	# Hidden enemies (player currently Blind, see Main._update_player_blind_state)
	# shouldn't leak combat info through floating damage/status text - it's a
	# sibling node under `parent`, not a child of this mech, so it isn't
	# covered by the .visible toggle there automatically.
	if not mech.is_player and not mech.visible:
		return
	# Global popup budget (see ProjectileManager.request_floater): a bullet
	# storm shouldn't also spawn hundreds of tweened Labels per second. The
	# player's own popups always count as high-priority.
	if not ProjectileManager.request_floater(mech.is_player):
		return
	var parent = mech.get_parent()
	if not parent:
		return
	var lbl = Label.new()
	lbl.text = text
	lbl.modulate = color
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.z_index = 90
	lbl.global_position = mech.global_position + Vector2(randf_range(-12, 12), -30)
	parent.add_child(lbl)
	var tw = lbl.create_tween()
	tw.tween_property(lbl, "global_position", lbl.global_position + Vector2(randf_range(-6, 6), -40), 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7).set_ease(Tween.EASE_IN)
	tw.tween_callback(lbl.queue_free)

func apply_part_damage(slot: int, amount: float, element: String = "RAW"):
	amount = _apply_shield_mitigation(amount, element)
	if amount <= 0:
		return # Shields absorbed all part damage - nothing got through to roll a disable either

	# Smoke mitigation for the LOCAL tile-hit/disable-roll amount only - the
	# global-HP trickle below (apply_damage(amount*0.2, ...)) applies its
	# own smoke mitigation inside apply_damage itself; mitigating both here
	# AND there would double-apply it to that one portion.
	var mitigated_amount = _apply_smoke_mitigation(amount, element)

	if not mech.components.has(slot): return
	var comp = mech.components[slot]

	# Shooting the stump of a destroyed limb hurts the torso instead - a broken
	# part is not a free invulnerable decoy.
	if comp.is_broken and mech.components.has(HexTile.BodySlot.TORSO):
		slot = HexTile.BodySlot.TORSO
		comp = mech.components[slot]

	# Limb breakage: non-torso parts soak hits into a structural integrity pool.
	if slot != HexTile.BodySlot.TORSO and not comp.is_broken:
		if comp.integrity < 0.0:
			var share = Mech.LIMB_INTEGRITY_SHARE.get(slot, 0.3)
			comp.max_integrity = mech.max_hp * share
			comp.integrity = comp.max_integrity
		comp.integrity -= mitigated_amount
		if comp.integrity <= 0.0:
			mech._break_component(comp)

	# Apply damage to a random tile in that component's grid - still not
	# picky about exactly where the structural HP damage lands.
	var tiles = comp.hex_grid.get_all_tiles()
	if tiles.size() > 0:
		var hit_tile = tiles[SimRng.stream("combat").randi() % tiles.size()]
		var was_offline = hit_tile.is_disabled
		hit_tile.take_damage(mitigated_amount)
		if hit_tile.is_disabled and not was_offline:
			mech._on_tile_went_offline(hit_tile)
		# Any hit that actually reached the component (shields didn't fully
		# absorb it) also gets a separate shot at knocking a tile offline,
		# independent of that specific tile's own HP pool - see
		# _roll_component_disable for the priority/severity math.
		_roll_component_disable(comp, mitigated_amount, element)

	# Apply a small fraction of locational damage to global structure HP
	mech.apply_damage(amount * 0.2, element)

func _roll_component_disable(comp, amount: float, element: String):
	var target = _find_disable_priority_tile(comp)
	if not target:
		return

	var severity = amount / max(1.0, target.max_hp)
	var pierce_bonus = Mech.DISABLE_PIERCE_BONUS if element == "PIERCE" else 1.0
	var chance = Mech.DISABLE_BASE_CHANCE * severity * pierce_bonus * target.get_disable_risk()
	if chance < Mech.DISABLE_MIN_CHANCE:
		return # too weak a hit on too low-priority a tile - never disables from this one

	if SimRng.stream("combat").randf() >= chance:
		return

	target.hp = 0
	target.is_disabled = true
	target.notify_activity() # wake the grid's durability countdown
	mech._on_tile_went_offline(target)
	if severity * pierce_bonus >= Mech.GRAVE_HIT_RATIO:
		# Catastrophic overkill - the tile is fried, not just knocked
		# offline. No self-recovery timer; only a Garage repair fixes it.
		target.power_lost = true
		_show_floating_text(target.tile_type + " DESTROYED", Color(1.0, 0.2, 0.2))
	else:
		var base_cooldown = 3.0
		target.disable_timer = base_cooldown + (target.times_disabled * 2.0)
		target.times_disabled += 1
		_show_floating_text(target.tile_type + " OFFLINE", Color(1.0, 0.7, 0.2))

# Priority search for the disable roll's target - independent of which tile
# happened to take the direct structural damage in apply_part_damage above.
# "Heal Beacon" joins the secondary tier (Status.md counterplay-tells backlog
# item, "make Heal Beacons targetable"): it used to fall into the unpriorized
# `other` bucket alongside filler like Magnet/Jumpjet, so focused fire on an
# enemy healer's backpack almost never actually knocked the beacon itself
# offline. Matches HexTile.get_disable_risk()'s tiering for the same tile.
func _find_disable_priority_tile(comp):
	var tiles = comp.hex_grid.get_all_tiles()
	if tiles.is_empty():
		return null

	var splitters: Array = []
	var secondary: Array = []
	var other: Array = []
	for t in tiles:
		if t.is_disabled or t.power_lost:
			continue
		if t.tile_type == "Splitter":
			splitters.append(t)
		elif t.tile_type in ["Reflector", "Resonator", "Amplifier", "Heal Beacon"]:
			secondary.append(t)
		else:
			other.append(t)

	if not splitters.is_empty():
		return SimRng.pick("combat", splitters)
	if not secondary.is_empty():
		return SimRng.pick("combat", secondary)
	if not other.is_empty():
		return SimRng.pick("combat", other)
	return null

func apply_status(effect_name: String, duration: float):
	duration = BiomeIdentity.scaled_duration(mech, effect_name, duration) # cold ground keeps Freeze, hot ground melts it...
	if not mech.status_duration_mult.is_empty() and mech.status_duration_mult.has(effect_name):
		duration *= mech.status_duration_mult[effect_name] # Stun/Shock/Freeze Guard
		if duration < 0.03:
			return # shrugged off entirely
	mech.status_effects[effect_name] = duration
	if effect_name == "drenched":
		mech.status_effects.erase("burning") # soaked: any fire is put out
	if effect_name == "burning" or effect_name == "poisoned" or effect_name == "frozen" or effect_name == "paralyzed":
		load("res://scripts/visuals/StatusAura.gd").ensure_on(mech)

func update_status_effects(delta: float):
	mech._poll_offline_tiles(delta)
	mech.current_move_speed = (mech.base_move_speed - mech.actuator_speed_bonus * (1.0 - mech.phase_flow)) * mech._get_mass_speed_mult() * pow(Mech.LEG_BROKEN_SPEED_MULT, mech.broken_leg_count())
	if mech.is_amphibious and mech._in_water:
		mech.current_move_speed *= Mech.AMPHIBIOUS_WATER_SPEED_MULT

	# Mythic Actuator "school" flavor - see ActuatorTile.gd/_process_ramming.
	# Velocity trades ram damage for extra speed; Ember trades speed for
	# harder/fire-tagged rams; Balanced sits in the middle and gets its
	# utility perk (knockback + brace window) purely on the ramming side.
	if mech.actuator_school == 0: # Velocity
		mech.current_move_speed *= 1.15
	elif mech.actuator_school == 1: # Ember
		mech.current_move_speed *= 0.9

	if mech._brace_timer > 0.0:
		mech._brace_timer -= delta

	if not mech.status_runner:
		mech.status_runner = Mech.StatusEffectRunner.new(mech)
	mech.status_runner.tick(delta)

	if mech.is_cloaked:
		mech.current_move_speed *= 1.25 # Sneaking in fast while unseen

	# (Ambush-window countdown now lives in CloakSystem.tick(), ticked from
	# _physics_process alongside the rest of cloak's per-frame state.)

	# Overlord boss ability ("Rally") - temporary speed buff on top of the
	# self-heal/shield-refresh it grants (see _do_rally). Ticked here so it
	# decays like every other timed status effect above instead of needing
	# its own timer loop.
	if mech._rally_speed_timer > 0.0:
		mech._rally_speed_timer -= delta
		mech.current_move_speed *= Mech.RALLY_SPEED_MULT

	if mech.phase_shifter_active or mech.phase_flow < 1.0:
		PhaseDrain.tick(mech, delta)

	if not mech.capture_buffs.is_empty():
		CaptureBuffs.tick(mech, delta)
		mech.current_move_speed *= CaptureBuffs.speed_mult(mech)

	if not mech.jammed_synergies.is_empty():
		var synergies_to_clear = []
		for syn_id in mech.jammed_synergies:
			mech.jammed_synergies[syn_id] -= delta
			if mech.jammed_synergies[syn_id] <= 0:
				synergies_to_clear.append(syn_id)
		for syn_id in synergies_to_clear:
			mech.jammed_synergies.erase(syn_id)

# --- Cloak ---------------------------------------------------------------
# Thin wrappers only - see CloakSystem.gd for the actual charge/timer/
# visual tick and the ambush-window bonus. Both stay as real Mech methods
# (not e.g. mech.cloak_system.break_cloak()) because they're called from
# many places both inside this file and externally (BossBrain,
# PlayerController) - lazily constructing here matches the same pattern
# update_status_effects() uses for status_runner, so callers never have to
# know or care whether a CloakSystem exists yet.

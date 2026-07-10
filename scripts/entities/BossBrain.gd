extends RefCounted
class_name BossBrain

# Boss-only positioning, enrage, and signature-ability logic, split out of
# Mech.gd (see that file's _execute_ai_tactics for the lazy-construction
# call site, gated on is_boss). Composed, not a Node - see Mech.gd's
# boss_brain/status_runner/player_controller fields for why (load-bearing
# _physics_process ordering rules out sibling Nodes).
#
# _rally_speed_timer/RALLY_SPEED_MULT deliberately stay on Mech (not moved
# here) - _do_rally() below only writes into mech._rally_speed_timer; the
# countdown-and-apply lives in Mech.update_status_effects, which reads state
# from several other systems in the same frame. The boss fitness-tracking
# block (_boss_time_alive/get_boss_fitness/etc.) also stays on Mech, since
# get_boss_fitness() is called externally as boss.get_boss_fitness() by
# Main.gd/SquadDirector.gd.

const JumpjetResidue = preload("res://scripts/attacks/JumpjetResidue.gd")

var mech: Mech

func _init(p_mech: Mech):
	mech = p_mech

var enrage_stage: int = 0
const ENRAGE_THRESHOLDS: Array = [0.5, 0.2] # HP fraction that triggers each stage

const BOSS_ABILITY_COOLDOWN = 6.0
var boss_ability_cooldown: float = 3.0 # first use isn't instant - gives the player a beat to size the boss up first
var boss_ability_state: String = "" # "" = idle/ready; otherwise the ability currently winding up ("shockwave"/"railgun")
var boss_ability_windup: float = 0.0
var _boss_railgun_aim: Vector2 = Vector2.ZERO

# Role that would have used this ability before boss_profile.ability_pool
# existed - the fallback for a profile-less boss (e.g. debug-menu spawned)
# and the seed data _register_default_boss_profiles builds each archetype's
# starting pool from.
const ROLE_DEFAULT_ABILITY = {
	"brawler": "shockwave", "sniper": "railgun", "ambusher": "blink_strike",
	"flamethrower": "fire_pool", "jammer": "jam_burst", "commander": "rally",
}

# True while resolving a chained follow-up ability, so _maybe_chain_ability
# can never trigger a second chain off of a chain (caps it at exactly one
# extra use per original trigger, however deep enrage_stage gets).
var _boss_chaining: bool = false

var _hitrun_phase: String = "advance"
var _hitrun_timer: float = 0.0
const HITRUN_STRIKE_DURATION = 0.4

func is_channeling() -> bool:
	return boss_ability_state != ""

func tick_ability_cooldown_and_maybe_start(delta: float) -> void:
	boss_ability_cooldown -= delta
	if boss_ability_cooldown <= 0.0:
		_start_ability()

# Falls back to the pre-profile hardcoded rule (sniper/jammer kite,
# everything else aggressive) for a profile-less boss, e.g. one spawned
# directly from the debug menu without going through Main._spawn_boss.
func get_position_style() -> String:
	if mech.boss_profile and mech.boss_profile.position_style != "":
		return mech.boss_profile.position_style
	if mech.combat_role == "sniper" or mech.combat_role == "jammer":
		return "kiter"
	return "aggressive"

# Returns true if it fully handled movement+shooting this frame (caller
# skips the shared approach/orbit logic below in that case). "aggressive"
# (and every non-boss mech) always returns false and falls through to that
# shared logic, unchanged from before position styles existed.
func try_reposition(delta: float, dist: float, dir: Vector2) -> bool:
	var style = get_position_style()

	if style == "kiter" and dist < mech.engagement_distance * 0.6:
		# Backs off when the player closes to melee range instead of
		# orbiting in place at whatever (now too close) distance -
		# otherwise a kiter just stands there tanking hits like a Brawler
		# once you're in its face.
		var retreat_dir = _pick_retreat_dir(dir)
		mech.velocity = retreat_dir * mech.current_move_speed * mech.speed_modifier
		if dist < mech.engagement_distance + 150.0:
			mech._shoot(mech.target.global_position, true, true, delta)
		return true

	if style == "circler":
		# Continuously strafes around the target while smoothly correcting
		# back toward its preferred engagement_distance band, instead of
		# the binary "approach until in range, then orbit" default - reads
		# as constantly repositioning rather than beelining in and parking.
		var radius_error = dist - mech.engagement_distance
		var tangent = Vector2(-dir.y, dir.x) * mech.rotational_direction
		var radial = dir * clamp(radius_error / 100.0, -1.0, 1.0)
		var move_dir = tangent + radial
		move_dir = move_dir.normalized() if move_dir.length() > 0.01 else tangent
		mech.velocity = move_dir * mech.current_move_speed * mech.speed_modifier * 0.8
		if dist < mech.engagement_distance + 150.0:
			mech._shoot(mech.target.global_position, true, true, delta)
		return true

	return false

# Smarter-than-straight-back retreat: samples several candidate angles off
# directly-away-from-target and raycasts each, picking whichever has the
# most open space before hitting something - so a kiting boss backs into
# open ground instead of blindly reversing into whatever's directly behind
# it (a wall, a corner, another obstacle).
func _pick_retreat_dir(dir: Vector2) -> Vector2:
	var space_state = mech.get_world_2d().direct_space_state
	var candidate_offsets_deg = [0.0, 25.0, -25.0, 50.0, -50.0]
	var probe_dist = 150.0
	var best_dir = -dir
	var best_clearance = -1.0
	for deg in candidate_offsets_deg:
		var candidate = (-dir).rotated(deg_to_rad(deg))
		var query = PhysicsRayQueryParameters2D.create(mech.global_position, mech.global_position + candidate * probe_dist, 1)
		var result = space_state.intersect_ray(query)
		var clearance = probe_dist if result.is_empty() else mech.global_position.distance_to(result.position)
		if clearance > best_clearance:
			best_clearance = clearance
			best_dir = candidate
	return best_dir

# --- Boss Cloak Hit-and-Run ------------------------------------------------
# Any boss with a Cloak Generator equipped (has_cloak_generator - whichever
# role rolled it, not just an ambusher-based Specter) cycles advance ->
# strike -> retreat -> advance instead of the plain per-mech cloak AI's
# one-shot "stay hidden while closing, reveal once close, then stay
# revealed" behavior. This is what makes cloak usage read as deliberate
# hit-and-run rather than a single ambush per fight.
#
# It doesn't fight _update_cloak's own is_cloaked bookkeeping - it just
# controls MOVEMENT so the boss's distance from the player naturally walks
# through _update_cloak's existing thresholds (wants_cloak = dist >
# engagement_distance*0.9) at the right times: cloaked while advancing,
# revealed by firing during the strike (which is what _shoot's
# _get_ambush_multiplier() check turns into the 2.5x ambush bonus, both for
# that shot and for anything else landed within the following 0.25s window),
# then forced back out past the recloak threshold during retreat.
func try_hit_and_run(delta: float, dist: float, dir: Vector2) -> bool:
	if not mech.has_cloak_generator:
		return false
	match _hitrun_phase:
		"advance":
			mech.velocity = dir * mech.current_move_speed * mech.speed_modifier
			if dist <= mech.engagement_distance * 0.7:
				_hitrun_phase = "strike"
				_hitrun_timer = HITRUN_STRIKE_DURATION
		"strike":
			mech.velocity = Vector2.ZERO
			if dist < mech.engagement_distance + 150.0:
				mech._shoot(mech.target.global_position, true, true, delta)
			_hitrun_timer -= delta
			if _hitrun_timer <= 0.0:
				_hitrun_phase = "retreat"
		"retreat":
			var retreat_dir = _pick_retreat_dir(dir)
			mech.velocity = retreat_dir * mech.current_move_speed * mech.speed_modifier
			if dist > mech.engagement_distance * 1.3:
				_hitrun_phase = "advance"
		_:
			_hitrun_phase = "advance"
	return true

# --- Boss Enrage & Signature Abilities -----------------------------------
# Every boss gets two things layered on top of its ordinary role AI
# (movement/shooting are otherwise untouched - see Mech._execute_ai_tactics):
# enrage phases as HP drops, and cooldown-gated signature ability use.
# Neither system runs for non-boss mechs. Which ENRAGE STYLE and which
# ABILITIES are available now varies per-boss via boss_profile (see
# BossProfile.gd / SquadDirector's boss profile evolution) instead of being
# the same fixed escalation for every boss.

# Each style hits a different combination of fire_rate/speed_modifier/
# engagement_distance/self-heal per stage - see _apply_enrage_style. Falls
# back to "berserker" if boss_profile is null (debug-spawned boss, etc.).
func get_enrage_style() -> String:
	if mech.boss_profile and mech.boss_profile.enrage_style != "":
		return mech.boss_profile.enrage_style
	return "berserker"

func update_enrage():
	while enrage_stage < ENRAGE_THRESHOLDS.size() and mech.max_hp > 0.0 and mech.hp <= mech.max_hp * ENRAGE_THRESHOLDS[enrage_stage]:
		enrage_stage += 1
		_apply_enrage_style(get_enrage_style())
		mech._show_floating_text("ENRAGED", Color(1.0, 0.25, 0.1))
		var cam = mech.get_tree().get_first_node_in_group("camera")
		if cam and cam.has_method("shake"):
			cam.shake(2.0, 0.5)
		var orig_modulate = mech.modulate
		var flash_tween = mech.create_tween()
		flash_tween.tween_property(mech, "modulate", Color(1.6, 0.4, 0.3) * orig_modulate, 0.1)
		flash_tween.tween_property(mech, "modulate", orig_modulate, 0.4)

# Four flavors, each leaning on a different stat so "enraged" reads
# differently depending on the boss instead of every boss getting the
# identical fire_rate/speed/engage bump:
#   berserker  - mostly fire rate (shoots much faster, the classic "rage")
#   juggernaut - mostly speed + engagement range (charges you down harder)
#   vampiric   - modest all-around bump PLUS an actual heal-back, a real
#                "second wind" rather than just a stat spike
#   unstable   - the biggest, most chaotic all-around swing (highest risk
#                for the player to be near when it procs, but also the
#                easiest to punish since nothing here is subtle)
func _apply_enrage_style(style: String):
	match style:
		"berserker":
			mech.fire_rate *= 0.65
			mech.speed_modifier *= 1.08
			mech.engagement_distance *= 0.95
		"juggernaut":
			mech.fire_rate *= 0.9
			mech.speed_modifier *= 1.35
			mech.engagement_distance *= 0.75
		"vampiric":
			mech.fire_rate *= 0.85
			mech.speed_modifier *= 1.1
			mech.engagement_distance *= 0.9
			var heal_amt = mech.max_hp * 0.1
			mech.hp = min(mech.max_hp, mech.hp + heal_amt)
			if heal_amt >= 1.0:
				mech._show_floating_text("+%d" % int(round(heal_amt)), Color(0.3, 1.0, 0.5))
		"unstable":
			mech.fire_rate *= randf_range(0.5, 0.85)
			mech.speed_modifier *= randf_range(1.1, 1.5)
			mech.engagement_distance *= randf_range(0.7, 1.0)
		_:
			mech.fire_rate *= 0.8
			mech.speed_modifier *= 1.15
			mech.engagement_distance *= 0.9

func _get_ability_pool() -> Array:
	if mech.boss_profile and not mech.boss_profile.ability_pool.is_empty():
		return mech.boss_profile.ability_pool
	if ROLE_DEFAULT_ABILITY.has(mech.combat_role):
		return [ROLE_DEFAULT_ABILITY[mech.combat_role]]
	return []

# Dispatches by ability key (drawn from boss_profile.ability_pool, which
# mutation can grow to 2 abilities that alternate - the actual "more
# evolution options" this replaces the old fixed combat_role match with).
# Telegraphed abilities (shockwave/railgun) set boss_ability_state and let
# continue_ability resolve them next; instant ones (blink/fire pool/jam
# burst/rally) fire immediately and reset the cooldown themselves.
func _start_ability():
	if not mech.target or not is_instance_valid(mech.target):
		return
	var pool = _get_ability_pool()
	if pool.is_empty():
		boss_ability_cooldown = BOSS_ABILITY_COOLDOWN # no ability available - don't retry every frame
		return
	var ability = pool[randi() % pool.size()]
	match ability:
		"shockwave":
			boss_ability_state = "shockwave"
			boss_ability_windup = 0.6
			var telegraph = load("res://scripts/visuals/BossTelegraphRing.gd").new()
			if mech.get_parent():
				mech.get_parent().add_child(telegraph)
				telegraph.global_position = mech.global_position
				telegraph.telegraph(220.0, boss_ability_windup, Color(1.0, 0.4, 0.1, 0.8))
		"railgun":
			boss_ability_state = "railgun"
			boss_ability_windup = 1.2
			_boss_railgun_aim = mech.target.global_position
			_spawn_railgun_telegraph(_boss_railgun_aim, boss_ability_windup)
		"blink_strike":
			_do_blink_strike()
			boss_ability_cooldown = BOSS_ABILITY_COOLDOWN
		"fire_pool":
			_do_fire_pool()
			boss_ability_cooldown = BOSS_ABILITY_COOLDOWN
		"jam_burst":
			_do_jam_burst()
			boss_ability_cooldown = BOSS_ABILITY_COOLDOWN
		"rally":
			_do_rally()
			boss_ability_cooldown = BOSS_ABILITY_COOLDOWN
		_:
			boss_ability_cooldown = BOSS_ABILITY_COOLDOWN # unrecognized key - don't retry every frame

	# Instant abilities resolved above (boss_ability_state is still "" for
	# them) can chain right here; telegraphed ones chain later, from
	# continue_ability, once they've actually resolved.
	if boss_ability_state == "" and not _boss_chaining:
		_maybe_chain_ability()

# From enrage_stage 2 ("desperate", 20% HP) onward, every ability use is
# immediately followed by a second one - the fight's climax reads as an
# actual combo instead of the same single move on repeat. Deliberately a
# flat property of the stage (not a depletable charge) so it stays a
# consistent threat for the rest of the fight once a boss gets there.
func _maybe_chain_ability():
	if enrage_stage >= 2 and mech.target and is_instance_valid(mech.target):
		_boss_chaining = true
		_start_ability()
		_boss_chaining = false

# Ticks down an in-progress windup and resolves it once it hits zero. The
# boss is rooted (see Mech._execute_ai_tactics) for the entire duration this
# is non-empty, which is what sells "channeling" rather than "moving
# normally while also somehow attacking."
func continue_ability(delta):
	boss_ability_windup -= delta
	if boss_ability_windup > 0.0:
		return
	if boss_ability_state == "shockwave":
		_resolve_shockwave()
	elif boss_ability_state == "railgun":
		_resolve_railgun()
	boss_ability_state = ""
	boss_ability_cooldown = BOSS_ABILITY_COOLDOWN
	if not _boss_chaining:
		_maybe_chain_ability()

# Warhulk: AoE damage + knockback centered on the boss. Damage/HP scale off
# the boss's OWN max_hp (which already carries wave/difficulty/hp_mult
# scaling) so this stays relevant at any wave without separate tuning.
func _resolve_shockwave():
	var radius = 220.0
	var p = mech._get_player_ref()
	if p:
		if mech.global_position.distance_to(p.global_position) <= radius and p.has_method("apply_damage"):
			var dmg = mech.max_hp * 0.06 * mech._get_ambush_multiplier()
			p.apply_damage(dmg, "RAW")
			mech._boss_emit_dealt_damage(dmg) # ability damage doesn't route through Projectile - credit fitness tracking manually
			if "external_force" in p:
				var away = p.global_position - mech.global_position
				away = away.normalized() if away.length() > 0.01 else Vector2.RIGHT
				p.external_force += away * 700.0
	var ring = load("res://scripts/visuals/BossTelegraphRing.gd").new()
	if mech.get_parent():
		mech.get_parent().add_child(ring)
		ring.global_position = mech.global_position
		ring.burst(20.0, radius, 0.25, Color(1.0, 0.6, 0.2, 1.0))
	var cam = mech.get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(2.5, 0.3)

# Longshot: a locked firing line shown during the windup (so the player can
# see it and step off the line) - not a ring, so it gets its own tiny
# Line2D helper rather than reusing BossTelegraphRing.
func _spawn_railgun_telegraph(aim_point: Vector2, duration: float):
	var line = Line2D.new()
	line.width = 4.0
	line.default_color = Color(1.0, 0.2, 0.2, 0.0)
	line.z_index = 50
	# Points are in the line's own local space (matches the convention in
	# Projectile._spawn_instant_bolt_flash) - global_position below is what
	# actually places it in the world, not a baked-in world coordinate.
	var to_aim = aim_point - mech.global_position
	var far_local = to_aim.normalized() * 2000.0 if to_aim.length() > 0.01 else Vector2.RIGHT * 2000.0
	line.points = PackedVector2Array([Vector2.ZERO, far_local])
	line.global_position = mech.global_position
	if mech.get_parent():
		mech.get_parent().add_child(line)
		var tw = line.create_tween()
		tw.tween_property(line, "modulate:a", 1.0, duration * 0.6)
		tw.tween_property(line, "modulate:a", 0.3, duration * 0.4)
		tw.tween_callback(line.queue_free)

func _resolve_railgun():
	var dir_locked = mech.global_position.direction_to(_boss_railgun_aim)
	if dir_locked == Vector2.ZERO:
		dir_locked = Vector2.RIGHT
	var p = mech._get_player_ref()
	if p:
		var to_player = p.global_position - mech.global_position
		var along = to_player.dot(dir_locked)
		if along > 0.0:
			var perp = (to_player - dir_locked * along).length()
			if perp < 40.0 and p.has_method("apply_damage"): # beam width tolerance
				var dmg = mech.max_hp * 0.1 * mech._get_ambush_multiplier()
				p.apply_damage(dmg, "PIERCE")
				mech._boss_emit_dealt_damage(dmg) # ability damage doesn't route through Projectile - credit fitness tracking manually
	var beam = Line2D.new()
	beam.width = 10.0
	beam.default_color = Color(1.0, 0.9, 0.7, 1.0)
	beam.z_index = 51
	beam.points = PackedVector2Array([Vector2.ZERO, dir_locked * 2000.0])
	beam.global_position = mech.global_position
	if mech.get_parent():
		mech.get_parent().add_child(beam)
		var tw = beam.create_tween()
		tw.tween_property(beam, "modulate:a", 0.0, 0.25)
		tw.tween_callback(beam.queue_free)
	var cam = mech.get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(2.0, 0.25)

# Specter: teleports to a random flank of the target and fires immediately
# while is_cloaked - _shoot() already applies the ambush bonus (via
# _get_ambush_multiplier()) to any shot fired while cloaked, so this gets a
# guaranteed heavy hit for free without needing new damage code. The strike
# also opens the usual 0.25s post-decloak window, so a fast follow-up shot
# right after still lands the bonus too.
func _do_blink_strike():
	var flank_dir = Vector2.RIGHT.rotated(randf() * TAU)
	var dest = mech.target.global_position + flank_dir * 130.0
	# Snap to the nearest clear tile, same helper used for squad spawns -
	# a raw random offset could otherwise occasionally land the teleport
	# inside a wall/obstacle with no collision-resolution to bail it out.
	var map = mech._get_map_ref()
	if map:
		dest = map.get_valid_spawn_position(dest)
	mech.global_position = dest
	mech.is_cloaked = true
	mech._shoot(mech.target.global_position, true, true, 0.0)
	mech._show_floating_text("STRIKE", Color(0.7, 0.6, 1.0))
	var cam = mech.get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(1.5, 0.2)

# Incinerator: drops a JumpjetResidue hazard zone (the same DoT-zone class
# the player's own Jumpjet uses) at the player's current position. Reused
# wholesale rather than writing a new hazard class - it already does
# exactly this (expanding damage-over-time zone with a fade-out). Its
# default collision_mask targets Enemies (for the player's own residue), so
# that's overridden to Player here.
func _do_fire_pool():
	if not mech.target or not is_instance_valid(mech.target):
		return
	# Same construction order as the player's own jumpjet residue (see
	# above): global_position + setup() BEFORE add_child, so _ready() bakes
	# the visual/particle colors correctly from the start instead of
	# building a default-white zone and recoloring it after.
	var residue = JumpjetResidue.new()
	residue.global_position = mech.target.global_position
	residue.lifetime = 4.0
	residue.source_mech = mech # credits fitness tracking for this DoT zone's ticks (see JumpjetResidue._physics_process)
	residue.setup(mech.max_hp * 0.015, {EnergyPacket.SynergyType.FIRE: 1.0})
	if mech.get_parent():
		mech.get_parent().add_child(residue)
	residue.collision_mask = 8 # Player - JumpjetResidue defaults to Enemies (4) for the player's own residue
	mech._show_floating_text("BURN", Color(1.0, 0.5, 0.1))

# Warden: a big one-shot spatial jam burst layered on top of the
# JammerMech's own continuous power-drain aura (see JammerMech.gd) - the
# passive drain is the constant pressure, this is the periodic spike. Spawns
# a short-lived JammerField (same class the equippable Jammer Module uses)
# instead of the old full-screen blackout - owner_mech=null keeps it
# stationary (no anchor to lag toward), lifetime=1.5 self-frees it.
func _do_jam_burst():
	var burst_radius = 900.0
	var field = load("res://scripts/visuals/JammerField.gd").new()
	field.global_position = mech.global_position
	field.setup(null, burst_radius, 1.5)
	if mech.get_parent():
		mech.get_parent().add_child(field)
	mech._show_floating_text("JAM BURST", Color(0.3, 0.6, 1.0))

# Overlord: no summoning (per design constraint) - instead a big self-heal,
# a full shield refresh, and a temporary speed buff (see the
# _rally_speed_timer tick in Mech.update_status_effects).
func _do_rally():
	var heal_amt = mech.max_hp * 0.15
	mech.hp = min(mech.max_hp, mech.hp + heal_amt)
	if mech.max_shield_hp > 0.0:
		mech.shield_hp = mech.max_shield_hp
	mech._rally_speed_timer = 4.0
	if heal_amt >= 1.0:
		mech._show_floating_text("+%d RALLY" % int(round(heal_amt)), Color(0.3, 1.0, 0.5))
	var cam = mech.get_tree().get_first_node_in_group("camera")
	if cam and cam.has_method("shake"):
		cam.shake(1.0, 0.3)

extends RefCounted
class_name StatusEffectRunner

# The true elemental-status tick loop, split out of Mech.gd's
# update_status_effects() (see that function's own body for the lazy-
# construction call site). Composed, not a Node - see Mech.gd's
# boss_brain/status_runner/player_controller fields for why (load-bearing
# _physics_process ordering rules out sibling Nodes).
#
# Owns no persistent fields of its own. status_effects (the dict) and
# apply_status() deliberately STAY on Mech - hazard/projectile scripts call
# apply_status() externally on any Mech at any time, including before a
# status_runner would otherwise exist, so the dict can't live here without
# reintroducing that construction-ordering hazard.
#
# Everything else update_status_effects() used to do inline (mass-speed
# baseline, Actuator school flavor, brace timer, cloak speed bonus, ambush
# window, boss Rally timer, jammed_synergies countdown) stays inline on
# Mech, in the same order it always ran in - only the true per-effect loop
# below moved.

# Burning used to be a flat 5 damage per second whatever lit it, which is +2% on a late-game shot. It now scales with the
# igniting shot: dps = shot damage x fire ratio x BURN_DPS_PER_SHOT_DAMAGE, never below the old flat 5.
const BURN_BASE_DPS = 5.0
const BURN_DPS_PER_SHOT_DAMAGE = 5.0 / 120.0 # (tune) a full-Fire 120 shot burns for 5/s, a 600 shot for 25/s

var mech: Mech

static func burn_dps_for(shot_damage: float, fire_ratio: float) -> float:
	return maxf(BURN_BASE_DPS, shot_damage * fire_ratio * BURN_DPS_PER_SHOT_DAMAGE)

# Ignites `target` from a shot. A burn already running keeps the stronger of the two intensities.
static func apply_burn(target: Node, shot_damage: float, fire_ratio: float) -> void:
	var was_burning = target.status_effects.has("burning") if "status_effects" in target else false
	target.apply_status("burning", 3.0 * fire_ratio)
	if "burn_dps" in target and target.status_effects.has("burning"):
		var dps = burn_dps_for(shot_damage, fire_ratio)
		target.burn_dps = maxf(dps, target.burn_dps) if was_burning else dps

func _init(p_mech: Mech):
	mech = p_mech

func tick(delta: float) -> void:
	var effects_to_remove = []
	for effect in mech.status_effects:
		mech.status_effects[effect] -= delta

		# Handle active effects - full elemental status suite (group 3).
		# Movement effects multiply onto current_move_speed (which was just
		# reset to base above), damage effects tick per second.
		if effect == "frozen":
			mech.current_move_speed = mech.base_move_speed * 0.4 # 60% slow
		elif effect == "burning":
			mech.apply_damage(mech.burn_dps * delta)
		elif effect == "poisoned":
			mech.apply_damage(4.0 * delta)
			mech.current_move_speed *= 0.8
		elif effect == "bleeding":
			mech.apply_damage(6.0 * delta)
		elif effect == "paralyzed":
			mech.current_move_speed = 0.0 # LIGHTNING lockup
		elif effect == "immobilized":
			mech.current_move_speed = 0.0 # heavy VAMPIRIC pin
		elif effect == "staggered":
			mech.current_move_speed *= 0.5
		elif effect == "concussed":
			mech.current_move_speed *= 0.1
		elif effect == "vortexed":
			# Dragged toward the impact point stored by the projectile
			mech.pull_towards(mech.vortex_drag_point, delta, 500.0)
		# ("rent" has no per-frame effect - it's consumed as a +20% damage
		# amplifier inside apply_damage.)

		# Check if expired
		if mech.status_effects[effect] <= 0:
			effects_to_remove.append(effect)

	# Embrittlement outlasts nothing: it ends with its timer, and a thawed mech forgets the ice that froze it.
	if mech.embrittle_timer > 0.0:
		mech.embrittle_timer -= delta
		# Only the unblocked share of actuator flow reaches the legs: slow in proportion.
		mech.current_move_speed *= 1.0 - 0.6 * mech.embrittle_block
		if mech.embrittle_timer <= 0.0:
			mech.embrittle_block = 0.0
	if mech.frozen_ice_energy > 0.0 and not mech.status_effects.has("frozen"):
		mech.frozen_ice_energy = 0.0
	for effect in effects_to_remove:
		mech.status_effects.erase(effect)
		if effect == "burning":
			mech.burn_dps = BURN_BASE_DPS

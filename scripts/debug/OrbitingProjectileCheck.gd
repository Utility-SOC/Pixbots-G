extends Node

# Regression harness for OrbitingProjectile.gd's Area2D -> Node2D perf fix
# (2026-08-04 user report: 5fps/133ms at wave 6 with only 6 live enemies -
# see the file's own header comment for the root cause) plus two real bugs
# found while fixing it:
#   1. setup() called EnergyPacket.get_dominant_synergy(synergies) as if it
#      were a static function taking a Dictionary - it's an instance method
#      taking none, so dominant_synergy silently stayed stuck at RAW and
#      orbiting shots never got their real elemental orbit pattern/lash.
#   2. The old body_entered handler called the nonexistent
#      EnergyPacket.synergy_name() (real name: element_name()) - contact
#      damage from an orb touching an enemy has likely never actually
#      landed in production.
#
# (2026-08-13: contact damage assertion updated - a later redesign turned
# the old one-shot 14px contact mine into a sustained DPS tick over
# CONTACT_DPS_WINDOW seconds at the widened 45px CONTACT_RADIUS, so a single
# _check_contact() call now lands damage * (CONTACT_CHECK_INTERVAL /
# CONTACT_DPS_WINDOW), not the full `damage` value - see
# OrbitingProjectile.gd's own CONTACT_DPS_WINDOW comment. Not a regression,
# the check just predated that redesign.)
# Covers: dominant_synergy resolves correctly from a raw dict, no Area2D/
# physics-server dependency remains, throttled contact damage lands with a
# valid element string, throttled lightning lash lands, and the orb is
# deliberately NOT in the "projectile" group (MagnetSystem.gd's repel loop
# would otherwise mutate fields this class doesn't have).
#
# Shooter/target are plain fake Node2Ds, not real Mech instances - a real
# Mech's own _ready() does a lot of startup work, and if any of it queries
# EntityCache.get_group("enemy") before this test's own fake target joins
# that group, EntityCache's per-frame cache (see EntityCache.gd) would
# return a STALE snapshot for the rest of this synchronous _ready() call
# (the cache only invalidates when the engine's frame stamp actually
# advances, which never happens mid-function). Plain fakes sidestep that
# risk entirely.

const OrbitingProjScript = preload("res://scripts/entities/OrbitingProjectile.gd")
const EnergyPacketScript = preload("res://scripts/core/EnergyPacket.gd")
const CONTACT_CHECK_INTERVAL = 0.1 # mirrors OrbitingProjectile.gd's own const
const CONTACT_DPS_WINDOW = 2.0 # mirrors OrbitingProjectile.gd's own const

var failures = 0

func _check(label: String, actual, expected):
	if actual != expected:
		push_error("FAIL: %s - got %s, expected %s" % [label, actual, expected])
		failures += 1
	else:
		print("ok: %s = %s" % [label, actual])

func _check_true(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	var world = Node2D.new()
	add_child(world)

	var shooter = Node2D.new()
	shooter.global_position = Vector2.ZERO
	world.add_child(shooter)

	# --- 1. dominant_synergy resolves correctly from a raw dict ---------------
	var orb = OrbitingProjScript.new()
	orb.setup(shooter, 50.0, {EnergyPacket.SynergyType.LIGHTNING: 100.0}, true, 0.0)
	world.add_child(orb) # setup() before add_child() - matches OrbitingArrayTile.fire()'s real call order
	_check("setup() resolves dominant_synergy from a raw synergies dict (not stuck at RAW)",
		orb.dominant_synergy, EnergyPacket.SynergyType.LIGHTNING)

	# --- 2. No Area2D / physics-server dependency ------------------------------
	_check_true("OrbitingProjectile is a plain Node2D, not an Area2D", not (orb is Area2D))
	_check_true("OrbitingProjectile is deliberately NOT in the \"projectile\" group (MagnetSystem.gd coupling risk)",
		not orb.is_in_group("projectile"))

	# --- 3. Throttled contact damage lands with a valid element string --------
	var damage_log: Array = []
	var fake_target_script = GDScript.new()
	fake_target_script.source_code = "extends Node2D\nsignal got_hit(amount, element)\nfunc apply_damage(amount, element = \"RAW\", source = null, was_reflected = false, source_label_override = \"\"):\n\tgot_hit.emit(amount, element)\n"
	fake_target_script.reload()
	var fake_target = Node2D.new()
	fake_target.set_script(fake_target_script)
	world.add_child(fake_target)
	fake_target.add_to_group("enemy") # after entering the tree - see the file-header note on EntityCache staleness
	fake_target.global_position = Vector2(5, 0) # within CONTACT_RADIUS (45) of the shooter's origin
	fake_target.got_hit.connect(func(amount, element): damage_log.append([amount, element]))

	var contact_orb = OrbitingProjScript.new()
	contact_orb.setup(shooter, 42.0, {EnergyPacket.SynergyType.FIRE: 100.0}, true, 0.0)
	world.add_child(contact_orb)
	# Force the throttle to fire on the very next check instead of waiting out
	# its randomized initial offset (CONTACT_CHECK_INTERVAL).
	contact_orb._contact_timer = 0.0
	contact_orb._check_contact(0.016)
	_check("throttled contact check damages an in-range enemy exactly once", damage_log.size(), 1)
	if damage_log.size() > 0:
		_check_true("contact damage amount matches the orb's per-tick DPS-windowed share (damage * CHECK_INTERVAL/DPS_WINDOW)",
			is_equal_approx(float(damage_log[0][0]), 42.0 * (CONTACT_CHECK_INTERVAL / CONTACT_DPS_WINDOW)))
		_check("contact damage uses a real EnergyPacket.element_name() string, not the nonexistent synergy_name()",
			str(damage_log[0][1]), "FIRE")

	# --- 4. Throttled lightning lash lands without crashing -------------------
	damage_log.clear()
	fake_target.global_position = Vector2(150, 0) # outside CONTACT_RADIUS, inside the 220px lash radius
	var lash_orb = OrbitingProjScript.new()
	lash_orb.setup(shooter, 60.0, {EnergyPacket.SynergyType.LIGHTNING: 100.0}, true, 0.0)
	world.add_child(lash_orb)
	lash_orb._check_lightning_lash()
	_check("lightning lash damages an enemy within its 220px radius", damage_log.size(), 1)
	if damage_log.size() > 0:
		_check_true("lash damage is 40% of the orb's base damage", is_equal_approx(float(damage_log[0][0]), 60.0 * 0.4))

	# fake_target joined the real global "enemy" group so _check_contact()/
	# _check_lightning_lash() could find it via EntityCache - but other
	# always-on autoloads (SeparationBatcher, SightAndSearchBatcher) also
	# scan that same group every physics tick and expect every member to be
	# a real Mech (is_boss, etc). quit() is deferred to end-of-frame, so at
	# least one more physics tick can still land before the process actually
	# exits - drop the group membership now so those autoloads don't trip
	# over this test's fake node on the way out.
	fake_target.remove_from_group("enemy")

	if failures == 0:
		print("PASS: OrbitingProjectileCheck - Node2D perf fix + dominant_synergy/element_name bugs verified")
	get_tree().quit(0 if failures == 0 else 1)

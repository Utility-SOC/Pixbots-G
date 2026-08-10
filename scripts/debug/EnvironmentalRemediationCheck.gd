extends Node

# Regression check for EnvironmentalRemediationMech.gd (user request
# 2026-08-10: "an environmental remediation unit - it cleans up the damage
# puddles from missiles ... Travelling around with a circular aura cleaning
# up standing residue from missile explosions").
#
# Verifies:
#   1. A puddle within remediation_radius gets remediate()'d (its remaining
#      lifetime shortened) on a scan.
#   2. A puddle well outside remediation_radius is left completely alone.
#   3. ElementalPuddle.remediate() itself only ever shortens _duration, never
#      lengthens it (calling it on an already-short-lived puddle is a no-op).
#
# SAFETY: same `components = {}` pre-set pattern as SupportMechCheck.gd -
# Mech._ready() never runs build_loadout_for_role(), no SquadDirector (real
# or fake) needed or constructed.

const RemediationMechScript = preload("res://scripts/entities/EnvironmentalRemediationMech.gd")
const ElementalPuddleScript = preload("res://scripts/attacks/ElementalPuddle.gd")

var failures = 0
var world: Node = null

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_puddle(pos: Vector2, duration: float = 30.0) -> Area2D:
	var puddle = ElementalPuddleScript.new()
	puddle.setup(60.0, duration, 100.0, {EnergyPacket.SynergyType.FIRE: 100.0}, true)
	world.add_child(puddle) # _ready() runs here - tags "missile_puddle", starts _duration/_life_timer
	puddle.global_position = pos
	return puddle

func _ready():
	world = Node.new()
	add_child(world)

	var medic = RemediationMechScript.new()
	medic.is_player = false
	medic.combat_role = "remediation"
	medic.components = {}
	world.add_child(medic)
	medic.global_position = Vector2(1000, 1000)

	var near_puddle = _make_puddle(Vector2(1000, 1100), 30.0) # 100px away, well within remediation_radius
	var far_puddle = _make_puddle(Vector2(9000, 9000), 30.0) # far outside remediation_radius

	_check("puddle starts with its full seeded duration before any scan",
		near_puddle._duration == 30.0)

	medic._clean_nearby_puddles()

	_check("a puddle within the remediation aura gets its lifetime shortened",
		near_puddle._duration < 30.0)
	_check("a puddle far outside the remediation aura is left untouched",
		far_puddle._duration == 30.0)

	# remediate() is idempotent/only-ever-shortens: calling it again on an
	# already-short puddle shouldn't resurrect a longer lifetime.
	var shortened = near_puddle._duration
	near_puddle.remediate()
	_check("calling remediate() again never lengthens the duration back out",
		near_puddle._duration <= shortened)

	if failures == 0:
		print("PASS: EnvironmentalRemediationMech cleans up missile puddles within its aura and leaves distant ones alone")
	get_tree().quit(0 if failures == 0 else 1)

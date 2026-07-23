extends Node

# Task #41: Explosion and Vampiric have no flight-path role of their own
# (see Projectile._prepare_flight_request's ratio list - EXPLOSION is
# absent) - they only ever reach more than one target by riding along
# whichever chain mechanic (Lightning hops or Pierce pass-through) is
# actually delivering the hits. Without decay, a chain-lightning/pierce
# shot re-triggered full-strength AoE/lifesteal on every single hop for
# free. _compute_hit_decay() should taper 1.0 (first hit) -> 0.0 (final
# hop/pierce), Lightning taking priority over Pierce when both are
# present (mirrors the existing decrement-priority in _handle_hit's tail),
# and a plain non-chain shot should always get 1.0.

const ProjectileScript = preload("res://scripts/entities/Projectile.gd")

var world: Node2D
var failures: int = 0

func _make_projectile(synergies: Dictionary) -> Node:
	var proj = ProjectileScript.new()
	proj.synergies = synergies
	proj.damage = 10.0
	world.add_child(proj) # _ready() computes ratios + _calculate_stats()
	proj.set_physics_process(false)
	proj.monitoring = false
	proj.monitorable = false
	return proj

func _check(label: String, got: float, expect: float):
	if abs(got - expect) > 0.001:
		push_error("FAIL: %s (got %.4f, expected %.4f)" % [label, got, expect])
		failures += 1
	else:
		print("ok: %s (%.4f)" % [label, got])

func _ready():
	world = Node2D.new()
	add_child(world)

	# --- Full lightning: 4 hops, decay should step 1.0 -> 0.75 -> 0.5 -> 0.25 -> 0.0 ---
	var ltg = _make_projectile({EnergyPacket.SynergyType.LIGHTNING: 10.0})
	if ltg._lightning_hops_max != 4:
		push_error("FAIL: expected 4 lightning hops at full ratio, got %d" % ltg._lightning_hops_max)
		failures += 1
	var expected_ltg = [1.0, 0.75, 0.5, 0.25, 0.0]
	for i in range(expected_ltg.size()):
		_check("lightning hit %d decay" % (i + 1), ltg._compute_hit_decay(), expected_ltg[i])
		if ltg._lightning_hops_left > 0:
			ltg._lightning_hops_left -= 1 # mirrors _handle_hit's tail decrement
	ltg.queue_free()

	# --- Full pierce: pierce_count 5, decay should step 1.0 -> 0.75 -> 0.5 -> 0.25 -> 0.0 ---
	var prc = _make_projectile({EnergyPacket.SynergyType.PIERCE: 10.0})
	if prc._pierce_count_max != 5:
		push_error("FAIL: expected pierce_count_max=5 at full ratio, got %d" % prc._pierce_count_max)
		failures += 1
	var expected_prc = [1.0, 0.75, 0.5, 0.25, 0.0]
	for i in range(expected_prc.size()):
		_check("pierce hit %d decay" % (i + 1), prc._compute_hit_decay(), expected_prc[i])
		prc.pierce_count -= 1 # mirrors _handle_hit's tail decrement
	prc.queue_free()

	# --- Plain RAW shot: no chain mechanic active, decay always 1.0 ---
	var raw = _make_projectile({EnergyPacket.SynergyType.RAW: 10.0})
	_check("plain single-hit shot decay", raw._compute_hit_decay(), 1.0)
	raw.queue_free()

	# --- Both lightning and pierce present: lightning takes priority ---
	var both = _make_projectile({EnergyPacket.SynergyType.LIGHTNING: 10.0, EnergyPacket.SynergyType.PIERCE: 10.0})
	if both._lightning_hops_max <= 0 or both._pierce_count_max <= 1:
		push_error("FAIL: combined shot should have both a lightning and pierce budget to test priority against")
		failures += 1
	both._lightning_hops_left = 2 # partway through its hop budget, hops_max stays whatever _calculate_stats set
	var expect_priority = float(both._lightning_hops_left) / float(both._lightning_hops_max)
	_check("lightning takes priority over pierce when both active", both._compute_hit_decay(), expect_priority)
	both.queue_free()

	if failures == 0:
		print("PASS: hit decay tapers correctly for lightning + pierce chains, plain shots stay at full strength, lightning takes priority")
	get_tree().quit(0 if failures == 0 else 1)

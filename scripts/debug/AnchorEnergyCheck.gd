extends Node

# Anchor is an energy-fed terminal tile: it absorbs what reaches it, and protection against ENEMY Vortex pull grows with the
# fed energy (saturating); an unfed Anchor behaves as before. Also checks the wiring into pull_target.

const MechScript = preload("res://scripts/entities/Mech.gd")
const AnchorScript = preload("res://scripts/tiles/AnchorTile.gd")

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _ready():
	_check("no energy, no extra protection", AnchorTile.protection_for(0.0) == 0.0 and AnchorTile.damage_reduction_for(0.0) == 0.0)
	_check("half the reference energy gives a bit under half the cap", AnchorTile.protection_for(AnchorTile.ANCHOR_REF_ENERGY) == AnchorTile.MAX_PULL_PROTECTION * 0.5)
	_check("more energy protects more", AnchorTile.protection_for(1000.0) > AnchorTile.protection_for(100.0))
	_check("protection saturates below the cap", AnchorTile.protection_for(1e9) < AnchorTile.MAX_PULL_PROTECTION + 1e-6 and AnchorTile.protection_for(1e9) > 0.89)
	_check("damage reduction follows protection", AnchorTile.damage_reduction_for(1000.0) == AnchorTile.DAMAGE_REDUCTION_SHARE * AnchorTile.protection_for(1000.0))

	var a = AnchorScript.new()
	var p = EnergyPacket.new()
	p.magnitude = 120.0
	var out = a.process_energy(p, 0)
	_check("an Anchor absorbs: nothing continues", out.size() == 1 and out[0].magnitude == 0.0 and not out[0].is_active)
	a.process_energy(p, 0)
	_check("it stores what was fed in (240)", is_equal_approx(a.stored_energy, 240.0))
	_check("get_anchor_energy returns it once and clears", is_equal_approx(a.get_anchor_energy(), 240.0) and a.stored_energy == 0.0)

	# Wiring: an enemy-side body with more protection is pulled less by the same shot.
	var weak = MechScript.new()
	weak.is_player = false
	add_child(weak)
	weak.set_physics_process(false)
	weak.global_position = Vector2(300, 0)
	var strong = MechScript.new()
	strong.is_player = false
	add_child(strong)
	strong.set_physics_process(false)
	strong.global_position = Vector2(300, 0)
	strong.vortex_pull_protection_ratio = AnchorTile.protection_for(1000.0)
	VortexEffects.reset_crashes()
	VortexEffects.pull_target(weak, Vector2.ZERO, true, 1.0, 400.0, 0.05, Vector2.ZERO, 36.0)
	VortexEffects.pull_target(strong, Vector2.ZERO, true, 1.0, 400.0, 0.05, Vector2.ZERO, 36.0)
	_check("an energy-fed Anchor wearer is pulled less (%.1f vs %.1f)" % [strong.external_force.length(), weak.external_force.length()],
		weak.external_force.length() > 0.0 and strong.external_force.length() < weak.external_force.length() * 0.5)
	VortexEffects.reset_crashes()
	print("AnchorEnergyCheck: failures=%d" % failures)
	get_tree().quit(1 if failures > 0 else 0)

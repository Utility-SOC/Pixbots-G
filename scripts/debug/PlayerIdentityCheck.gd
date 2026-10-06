extends Node

const MechScript = preload("res://scripts/entities/Mech.gd")
var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _packet(syn: Dictionary):
	var p = EnergyPacket.new()
	p.synergies = syn
	return {"packet": p}

func _ready():
	var m = MechScript.new()
	m.is_player = true
	add_child(m)
	m.set_physics_process(false)
	await get_tree().process_frame
	m.precalculated_weapons.clear()
	_check("no weapons -> no identity", m.compute_identity_synergy() == -1)
	m.precalculated_weapons = [_packet({EnergyPacket.SynergyType.RAW: 500.0})]
	_check("RAW-only is not an identity", m.compute_identity_synergy() == -1)
	m.precalculated_weapons = [_packet({EnergyPacket.SynergyType.FIRE: 60.0, EnergyPacket.SynergyType.RAW: 900.0}), _packet({EnergyPacket.SynergyType.ICE: 20.0})]
	_check("the dominant non-RAW element wins (fire)", m.compute_identity_synergy() == EnergyPacket.SynergyType.FIRE)
	m.precalculated_weapons = [_packet({EnergyPacket.SynergyType.FIRE: 30.0}), _packet({EnergyPacket.SynergyType.ICE: 20.0}), _packet({EnergyPacket.SynergyType.ICE: 20.0})]
	_check("totals are summed across weapons (ice 40 > fire 30)", m.compute_identity_synergy() == EnergyPacket.SynergyType.ICE)
	# trim colour follows the identity
	var r = m._renderer
	m.identity_synergy = EnergyPacket.SynergyType.POISON
	var c = r._hero_trim_color(Color(0.9, 0.85, 0.2))
	_check("hero trim takes the element colour (green dominant)", c.g > c.r and c.g > c.b)
	m.identity_synergy = -1
	_check("and falls back to the default gold with no identity", r._hero_trim_color(Color(0.9, 0.85, 0.2)) == Color(0.9, 0.85, 0.2))
	print("player identity check done, failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)

extends Node

# _tick_weapon_charges early-out + idle flag must be behaviour-identical to the original loop. Two bare Mechs get
# identical synthetic weapon lists (fake mounts/packets, mixed rarities, "normal" and plain entries, one initially
# offline); both are driven with ONE shared random schedule of ticks, "shots" (charge consumed exactly as
# _shoot_impl does, including resetting the idle flag) and offline/online toggles. One ticks with
# diag_slow_charges on (the original loop), the other with it off. Every charge is compared after every tick.

const MechScript = preload("res://scripts/entities/Mech.gd")

class FakeMount extends RefCounted:
	var current_charge := 0.0
	var bank_current_charge := 0.0
	var is_disabled := false
	var power_lost := false
	var rarity := 0

class FakePacket extends RefCounted:
	var charge_required := 1.0

var failures = 0
func _check(l: String, c: bool):
	if c: print("ok: " + l)
	else:
		push_error("FAIL: " + l)
		failures += 1

func _build(m) -> void:
	var req := [1.0, 1.4, 0.8, 2.0, 1.1, 0.6]
	var rar := [0, 1, 2, 3, 4, 0]
	for k in range(req.size()):
		var mount = FakeMount.new()
		mount.rarity = rar[k]
		mount.current_charge = req[k] * (0.2 * k)
		var pkt = FakePacket.new()
		pkt.charge_required = req[k]
		m.precalculated_weapons.append({"mount": mount, "packet": pkt, "slot_type": HexTile.BodySlot.ARM_L, "bank_mode": "normal" if k % 2 == 0 else ""})
	m.precalculated_weapons[2].mount.is_disabled = true # starts offline
	m.fire_rate = 0.5
	m._charges_idle = false

func _ready():
	var slow_m = MechScript.new()
	var fast_m = MechScript.new()
	_build(slow_m)
	_build(fast_m)
	var n_w: int = slow_m.precalculated_weapons.size()

	seed(1234)
	var mismatches := 0
	var idle_ticks := 0
	for tick in range(2400):
		var shoot_idx := -1
		if randf() < 0.04:
			shoot_idx = randi() % n_w
		var toggle := -1
		if tick % 301 == 100: toggle = 0 # weapon 2 online
		if tick % 301 == 200: toggle = 1 # offline again
		for pair in [[slow_m, true], [fast_m, false]]:
			var m = pair[0]
			MechScript.diag_slow_charges = pair[1]
			if shoot_idx >= 0:
				var data = m.precalculated_weapons[shoot_idx]
				if not m._weapon_offline(data) and data.mount.current_charge >= data.packet.charge_required:
					data.mount.current_charge -= data.packet.charge_required
					m._charges_idle = false # what _shoot_impl does
			if toggle >= 0:
				m.precalculated_weapons[2].mount.is_disabled = (toggle == 1)
			m._tick_weapon_charges(1.0 / 60.0)
		MechScript.diag_slow_charges = false
		if fast_m._charges_idle:
			idle_ticks += 1
		for k in range(n_w):
			if not is_equal_approx(slow_m.precalculated_weapons[k].mount.current_charge, fast_m.precalculated_weapons[k].mount.current_charge):
				mismatches += 1
	_check("every weapon's charge matches the original loop on all 2400 ticks (%d mismatches)" % mismatches, mismatches == 0)
	_check("the idle flag engaged on some ticks (%d of 2400)" % idle_ticks, idle_ticks > 50)
	# A weapon coming back online while the rest are full must resume charging (idle must not stick).
	var m2 = MechScript.new()
	_build(m2)
	for k in range(600):
		m2._tick_weapon_charges(1.0 / 60.0)
	var w2 = m2.precalculated_weapons[2]
	_check("an offline, uncharged weapon keeps the loop awake (not idle)", not m2._charges_idle)
	w2.mount.is_disabled = false
	for k in range(600):
		m2._tick_weapon_charges(1.0 / 60.0)
	_check("it charges fully once back online (%.2f of %.2f)" % [w2.mount.current_charge, w2.packet.charge_required], w2.mount.current_charge >= w2.packet.charge_required - 0.0001)
	_check("and then the mech goes idle", m2._charges_idle)
	print("MechChargeTickParityCheck: %d failure(s)" % failures)
	get_tree().quit(1 if failures > 0 else 0)

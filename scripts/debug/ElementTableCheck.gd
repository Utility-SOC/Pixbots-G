extends Node

# Regression harness for the canonical element name/id table
# (EnergyPacket.SYNERGY_NAMES / element_name / element_id) and the shield
# rock-paper-scissors it feeds. Before consolidation, three call sites kept
# hand-written copies on DIFFERENT numberings: Mech's shield mitigation
# treated SynergyType 3 (LIGHTNING) as POISON etc., VAMPIRIC/KINETIC shields
# had no counters at all, and SquadDirector's counter-doctrine picked wrong
# counter elements. This locks the fixed behavior in.

const MechScript = preload("res://scripts/entities/Mech.gd")

func _ready():
	var failures = 0

	# --- 1. Name table stays in lockstep with the SynergyType enum ---
	var enum_keys = EnergyPacket.SynergyType.keys()
	if enum_keys.size() != EnergyPacket.SYNERGY_NAMES.size():
		push_error("FAIL: SYNERGY_NAMES size != SynergyType size")
		failures += 1
	for i in range(enum_keys.size()):
		if enum_keys[i] != EnergyPacket.SYNERGY_NAMES[i]:
			push_error("FAIL: SYNERGY_NAMES[%d]=%s but SynergyType key is %s" % [i, EnergyPacket.SYNERGY_NAMES[i], enum_keys[i]])
			failures += 1

	# --- 2. Round trip + unknown handling ---
	for i in range(EnergyPacket.SYNERGY_NAMES.size()):
		if EnergyPacket.element_id(EnergyPacket.element_name(i)) != i:
			push_error("FAIL: round trip broke for id %d" % i)
			failures += 1
	if EnergyPacket.element_id("NOT_AN_ELEMENT") != -1:
		push_error("FAIL: unknown name should give -1")
		failures += 1
	if EnergyPacket.element_name(-5) != "RAW" or EnergyPacket.element_name(99) != "RAW":
		push_error("FAIL: out-of-range id should fall back to RAW")
		failures += 1
	print("1-2) name table synced with enum, round trip OK")

	# --- 3. Shield RPS through _apply_shield_mitigation ---
	var world = Node2D.new()
	add_child(world)
	var mech = MechScript.new()
	mech.is_player = true
	world.add_child(mech)
	mech.set_physics_process(false)

	# element hitting the shield -> [shield SynergyType id, expected multiplier]
	var cases = [
		["FIRE", EnergyPacket.SynergyType.ICE, 2.0],       # fire melts ice shields
		["ICE", EnergyPacket.SynergyType.FIRE, 2.0],       # ice extinguishes fire shields
		["KINETIC", EnergyPacket.SynergyType.LIGHTNING, 2.0], # kinetic shatters lightning shields (broken pre-fix: 3 was mapped to POISON)
		["LIGHTNING", EnergyPacket.SynergyType.KINETIC, 3.0], # 2.0x counter * 1.5x lightning-vs-any-shield (broken pre-fix: KINETIC had no mapping)
		["VORTEX", EnergyPacket.SynergyType.KINETIC, 2.0],  # vortex crushes kinetic shields
		["POISON", EnergyPacket.SynergyType.VAMPIRIC, 2.0], # poison corrupts vampiric shields (broken pre-fix: VAMPIRIC=9 had no mapping)
		["VAMPIRIC", EnergyPacket.SynergyType.POISON, 2.0], # vampiric drains poison shields (broken pre-fix: 5 was mapped to VORTEX)
		["FIRE", EnergyPacket.SynergyType.FIRE, 1.0],       # same element: no counter bonus
		["LIGHTNING", EnergyPacket.SynergyType.VORTEX, 1.5], # lightning's flat bonus vs ALL shields
	]
	for c in cases:
		var element: String = c[0]
		var shield_id: int = c[1]
		var expected: float = c[2]
		mech.shield_hp = 10000.0
		mech.max_shield_hp = 10000.0
		mech.dominant_shield_synergy = str(shield_id)
		mech.shield_mythic_mode = -1 # no Aegis cap / Deflector in the way
		var before = mech.shield_hp
		var leftover = mech._apply_shield_mitigation(100.0, element)
		var absorbed = before - mech.shield_hp
		if abs(absorbed - 100.0 * expected) > 0.01 or leftover != 0.0:
			push_error("FAIL: %s vs %s shield absorbed %.1f (expected %.1f)" % [element, EnergyPacket.element_name(shield_id), absorbed, 100.0 * expected])
			failures += 1
	if failures == 0:
		print("3) shield rock-paper-scissors correct for all %d cases" % cases.size())
		print("PASS: element table + shield RPS verified")
	get_tree().quit(0 if failures == 0 else 1)

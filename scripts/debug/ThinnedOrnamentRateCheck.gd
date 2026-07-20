extends Node

# Regression harness for: "could you thin the types of particles rather
# than fully trimming some? Like, if I had half as many kinetic showing up
# on screen, and a quarter of the vortex (showing up consistently)?"
#
# Root cause of the ORIGINAL report (vortex spirals inconsistent): a single
# global lite/full toggle (ProjectileManager.lite_visuals(), tripped at 90+
# live shots) gated ALL ornaments for ALL synergies identically and
# instantaneously - once the live count crossed 90, EVERY new shot lost its
# ornament outright, and the exact live count at the moment any given shot
# fires is unpredictable, so it read as random flicker rather than a
# deliberate style.
#
# Fixed with ProjectileManager.should_show_full_ornament(synergy_type): once
# saturated, each synergy gets its OWN "1 in N" rate via a STABLE rotating
# counter (not a per-shot coin flip), so the ratio is exact and
# reproducible, and Projectile._build_visuals() consults it per-ornament
# instead of one blanket flag.

const ComponentEquipmentScript = preload("res://scripts/core/ComponentEquipment.gd")
const WeaponMountTileScript = preload("res://scripts/tiles/WeaponMountTile.gd")
const MechScript = preload("res://scripts/entities/Mech.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1. Below saturation: always full, regardless of synergy ---
	_check("below saturation, VORTEX always gets the full ornament",
		ProjectileManager.should_show_full_ornament(EnergyPacket.SynergyType.VORTEX))
	_check("below saturation, KINETIC always gets the full ornament",
		ProjectileManager.should_show_full_ornament(EnergyPacket.SynergyType.KINETIC))

	# --- 2. Saturate the screen with dummy registrations (mirrors
	# PerfSaturationCheck.gd's own technique) ---
	var world = Node2D.new()
	add_child(world)
	var dummies: Array = []
	for i in range(120):
		var d = Node2D.new()
		world.add_child(d)
		ProjectileManager.register(d)
		dummies.append(d)
	_check("saturation threshold is actually active now", ProjectileManager.lite_visuals())

	# --- 3. VORTEX: exactly 1 in 4 comes back true, in a stable, exact
	# rotating pattern (not roughly-a-quarter via randomness) ---
	var vortex_hits = 0
	var vortex_pattern: Array = []
	for i in range(12):
		var full = ProjectileManager.should_show_full_ornament(EnergyPacket.SynergyType.VORTEX)
		vortex_pattern.append(full)
		if full:
			vortex_hits += 1
	_check("VORTEX shows its full ornament exactly 3 times in 12 calls (1-in-4 rate)", vortex_hits == 3)
	_check("VORTEX's true hits land on calls 4, 8, 12 - a stable repeating pattern, not random",
		vortex_pattern[3] and vortex_pattern[7] and vortex_pattern[11] and
		not vortex_pattern[0] and not vortex_pattern[1] and not vortex_pattern[2])

	# --- 4. KINETIC: exactly 1 in 2 (half), per the user's own example ---
	var kinetic_hits = 0
	for i in range(10):
		if ProjectileManager.should_show_full_ornament(EnergyPacket.SynergyType.KINETIC):
			kinetic_hits += 1
	_check("KINETIC shows its full ornament exactly 5 times in 10 calls (1-in-2 rate, 'half as many')", kinetic_hits == 5)

	# --- 5. Independent counters: a synergy with no configured rate uses
	# the default, and doesn't share state with VORTEX/KINETIC's counters ---
	var raw_hits = 0
	for i in range(ProjectileManager.ORNAMENT_DEFAULT_FULL_RATE * 3):
		if ProjectileManager.should_show_full_ornament(EnergyPacket.SynergyType.RAW):
			raw_hits += 1
	_check("an unlisted synergy (RAW) uses ORNAMENT_DEFAULT_FULL_RATE independently",
		raw_hits == 3)

	# --- 6. End-to-end: a real fired projectile still builds successfully
	# under saturation with no script errors (exercises the full
	# _build_visuals() reorder, including the ratio-gated Kinetic/Vortex/
	# Poison-secondary/multi-synergy-helix sites). ---
	var mech = MechScript.new()
	mech.is_player = true
	world.add_child(mech)
	mech.set_physics_process(false)
	mech.last_aim_position = Vector2(500, 0)
	var mount = WeaponMountTileScript.new()
	mount.rarity = HexTile.Rarity.RARE
	mount.body_slot = HexTile.BodySlot.TORSO
	# At 120 live dummies, consolidation may or may not be banking (K > 1) -
	# depends on ProjectileManager's current tuning, which this test
	# shouldn't hardcode an assumption about. Fire up to K times (the
	# guaranteed point a banked volley releases) rather than assuming one
	# call always spawns immediately.
	var k = ProjectileManager.consolidation_factor()
	var fired_ok = false
	for i in range(k):
		var packet = EnergyPacket.new(50.0, null)
		packet.synergies.clear()
		packet.add_synergy(EnergyPacket.SynergyType.VORTEX, 30.0)
		packet.add_synergy(EnergyPacket.SynergyType.KINETIC, 20.0)
		mount._fire_combined_projectile(mech, packet, 0)
		for c in world.get_children():
			if c.is_in_group("projectile"):
				fired_ok = true
		if fired_ok:
			break
	_check("a mixed Vortex/Kinetic shot still builds its visuals cleanly under saturation (within %d consolidated volleys)" % k, fired_ok)

	for d in dummies:
		ProjectileManager.unregister(d)
		d.queue_free()

	if failures == 0:
		print("PASS: per-synergy ornament thinning gives exact, stable rates instead of a blanket on/off")
	get_tree().quit(0 if failures == 0 else 1)

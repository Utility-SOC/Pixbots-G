extends Node

# Regression check for AntiMissileJammerMech.gd + MortarShell.gd's matching
# "anti_missile_aura" landing check (user request 2026-08-10: "an anti-
# missile jammer class ... they can shoot down missiles, as well as prevent
# missiles from detonating in their range (they will crash to the ground
# harmlessly)").
#
# Verifies:
#   1. Active scan shoots down an in-flight hostile shell within radius
#      (MortarShell.release() - removed from the tree, returned to the pool).
#   2. A friendly-fired shell (same side as the aura) is left alone.
#   3. Passive backstop: a shell landing inside a hostile aura's radius
#      crashes harmlessly (_crashed_harmlessly = true) instead of detonating
#      - no damage/puddle path taken, confirmed by no ElementalPuddle child
#      appearing under world.
#   4. A shell landing well outside any aura's radius detonates normally.
#
# SAFETY: mirrors SupportMechCheck.gd's established safe pattern - sets
# `components = {}` on every Mech before add_child() so Mech._ready() never
# runs build_loadout_for_role() (which would call _get_stock_build_
# evolution(), itself already null-safe with no "SquadDirector"-named node
# present - but this check doesn't even reach that path). No SquadDirector,
# real or fake, is ever constructed here.

const AntiMissileJammerMechScript = preload("res://scripts/entities/AntiMissileJammerMech.gd")
const MortarShellScript = preload("res://scripts/attacks/MortarShell.gd")

var failures = 0
var world: Node = null

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _make_aura(pos: Vector2, p_is_player: bool):
	var aura = AntiMissileJammerMechScript.new()
	aura.is_player = p_is_player
	aura.combat_role = "anti_missile"
	aura.components = {}
	world.add_child(aura)
	aura.global_position = pos
	return aura

func _make_shell(pos: Vector2, p_fired_by_player: bool, p_flight_time: float = 5.0) -> Node2D:
	var shell = MortarShellScript.acquire()
	shell.setup(pos, pos, p_flight_time, 50.0, {EnergyPacket.SynergyType.FIRE: 100.0}, p_fired_by_player, null)
	world.add_child(shell)
	return shell

func _ready():
	world = Node.new()
	add_child(world)

	# --- 1 & 2: active scan ---------------------------------------------
	var aura_player_side = _make_aura(Vector2(1000, 1000), true) # defends the player
	var enemy_shell_near = _make_shell(Vector2(1000, 1050), false) # enemy-fired, in range, in flight
	var player_shell_near = _make_shell(Vector2(1000, 1080), true) # friendly-fired, in range, in flight

	aura_player_side._intercept_nearby_shells()

	_check("an enemy-fired shell in flight within radius is shot down (removed from the tree)",
		not enemy_shell_near.is_inside_tree())
	_check("a shell fired by the SAME side as the aura is left alone",
		player_shell_near.is_inside_tree())
	player_shell_near.release()

	# --- 3: passive backstop, hostile shell lands inside a hostile aura --
	var aura_enemy_side = _make_aura(Vector2(2000, 2000), false) # enemy-side unit, defends against player shells
	# setup() clamps flight_time to a floor of 0.15 (MortarShell.gd's own
	# `max(0.15, p_flight_time)`) regardless of what's requested here - the
	# _process delta below must exceed THAT floor, not the requested value.
	var hostile_shell = _make_shell(Vector2(2000, 2040), true, 0.01) # player-fired, landing inside the enemy aura
	var children_before = world.get_child_count()
	hostile_shell._process(0.2) # advances past the real (floor-clamped) flight_time, lands this tick
	_check("a hostile shell landing inside an opposing aura crashes harmlessly",
		hostile_shell._crashed_harmlessly)
	_check("no ElementalPuddle was spawned for a harmlessly-crashed shell",
		world.get_child_count() == children_before) # puddle would be a 3rd child of world; only the shell itself is
	hostile_shell.release()

	# --- 4: a shell landing outside every aura's radius detonates normally
	var far_shell = _make_shell(Vector2(9000, 9000), true, 0.01)
	far_shell._process(0.2) # see hostile_shell's comment above on the 0.15 floor
	_check("the control shell actually landed this tick (sanity check on the test itself)",
		far_shell._landed)
	_check("a shell landing outside any aura's radius detonates normally (not crashed harmlessly)",
		not far_shell._crashed_harmlessly)
	far_shell.release()

	if failures == 0:
		print("PASS: AntiMissileJammerMech shoots down in-flight hostile shells and neutralizes landings within its aura, leaving friendly shells and out-of-range shells untouched")
	get_tree().quit(0 if failures == 0 else 1)

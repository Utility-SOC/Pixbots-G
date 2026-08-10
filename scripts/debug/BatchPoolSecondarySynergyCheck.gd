extends Node

# Regression check for layered secondary-synergy visuals (per the user:
# "in the old version I think it was more than the top two being
# represented in projectiles"). Real Projectile.gd never makes synergies
# compete for a single winner - Fire/Vortex/Poison each get their own
# independent trail/particle effect on top of the dominant-color main body.
# ProjectileBatchPool now tracks up to 2 secondary synergies per shot and
# renders small orbiting "echo" instances for them, reusing otherwise-idle
# per-synergy MultiMesh channels at that shot's own pool slot.
#
# Tests the pure functions directly (_compute_secondary_synergies,
# _compute_echo_render) rather than round-tripping through MultiMesh - see
# BatchPoolFlightParityCheck.gd's own header for why immediate get/set on a
# MultiMesh doesn't reliably work under --headless.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1: a packet with 3 significant elements picks the two non-dominant
	# ones as secondaries, sorted by strength.
	var ratios_three = {
		EnergyPacket.SynergyType.EXPLOSION: 0.6,
		EnergyPacket.SynergyType.KINETIC: 0.25,
		EnergyPacket.SynergyType.VORTEX: 0.2,
	}
	var secondaries = ProjectileBatchPoolScript._compute_secondary_synergies(ratios_three, EnergyPacket.SynergyType.EXPLOSION)
	_check("the biggest non-dominant ratio (KINETIC, 0.25) becomes the first secondary",
		secondaries[0] == EnergyPacket.SynergyType.KINETIC)
	_check("the second-biggest non-dominant ratio (VORTEX, 0.2) becomes the second secondary",
		secondaries[1] == EnergyPacket.SynergyType.VORTEX)

	# --- 2: the dominant itself is never picked as its own secondary, even
	# if it's technically the biggest value in the dict.
	var ratios_dom_biggest = {
		EnergyPacket.SynergyType.FIRE: 0.9,
		EnergyPacket.SynergyType.ICE: 0.3,
	}
	var secondaries2 = ProjectileBatchPoolScript._compute_secondary_synergies(ratios_dom_biggest, EnergyPacket.SynergyType.FIRE)
	_check("the dominant synergy is excluded from its own secondary list",
		secondaries2[0] != EnergyPacket.SynergyType.FIRE and secondaries2[1] != EnergyPacket.SynergyType.FIRE)
	_check("with only one other real element, the second secondary slot stays empty",
		secondaries2[0] == EnergyPacket.SynergyType.ICE and secondaries2[1] == ProjectileBatchPoolScript.NO_SYNERGY)

	# --- 3: ratios below SECONDARY_SYNERGY_THRESHOLD don't qualify as
	# secondaries at all - trace amounts shouldn't visually clutter the shot.
	var ratios_trace = {
		EnergyPacket.SynergyType.POISON: 0.7,
		EnergyPacket.SynergyType.PIERCE: 0.05, # below threshold (0.15)
	}
	var secondaries3 = ProjectileBatchPoolScript._compute_secondary_synergies(ratios_trace, EnergyPacket.SynergyType.POISON)
	_check("a trace-level ratio below SECONDARY_SYNERGY_THRESHOLD doesn't qualify as a secondary",
		secondaries3[0] == ProjectileBatchPoolScript.NO_SYNERGY and secondaries3[1] == ProjectileBatchPoolScript.NO_SYNERGY)

	# --- 4: a pure single-element packet has no secondaries at all.
	var ratios_pure = {EnergyPacket.SynergyType.LIGHTNING: 1.0}
	var secondaries4 = ProjectileBatchPoolScript._compute_secondary_synergies(ratios_pure, EnergyPacket.SynergyType.LIGHTNING)
	_check("a pure single-element packet has no secondaries",
		secondaries4[0] == ProjectileBatchPoolScript.NO_SYNERGY and secondaries4[1] == ProjectileBatchPoolScript.NO_SYNERGY)

	# --- 5: echo render orbits around the main body, and two echoes with
	# opposite phase (0 and PI) land on roughly opposite sides at the same
	# instant, matching Projectile.gd's own helix-particle phase spacing.
	var render_pos = Vector2(500, 300)
	var echo_a = ProjectileBatchPoolScript._compute_echo_render(render_pos, 1.0, 0.0, 1.0, EnergyPacket.SynergyType.KINETIC)
	var echo_b = ProjectileBatchPoolScript._compute_echo_render(render_pos, 1.0, PI, 1.0, EnergyPacket.SynergyType.VORTEX)
	_check("both echoes stay within ECHO_ORBIT_RADIUS of the main body",
		echo_a["position"].distance_to(render_pos) <= ProjectileBatchPoolScript.ECHO_ORBIT_RADIUS + 0.01 and
		echo_b["position"].distance_to(render_pos) <= ProjectileBatchPoolScript.ECHO_ORBIT_RADIUS + 0.01)
	_check("opposite-phase echoes (0 vs PI) land on opposite sides of the main body at the same instant",
		echo_a["position"].distance_to(echo_b["position"]) > ProjectileBatchPoolScript.ECHO_ORBIT_RADIUS)
	_check("each echo takes its OWN synergy's color, not the main body's",
		echo_a["color"] != echo_b["color"])

	if failures == 0:
		print("PASS: secondary-synergy selection excludes the dominant and sub-threshold trace amounts, and echo rendering orbits distinctly per synergy")
	get_tree().quit(0 if failures == 0 else 1)

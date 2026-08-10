extends Node

# Phase 10 of the batch-pool full-parity plan (2026-08-10): bespoke per-
# synergy visual ornaments. The pool's secondary-synergy "echo" mechanism
# used to be ONE generic orbiting-instance formula reused identically for
# every synergy - real Projectile.gd gives specific synergies genuinely
# bespoke treatment instead (Pierce's static glowing core, Kinetic's own
# trail shape, Vortex's 3-own-radius/own-speed orbiters, Fire's particle
# trail). Tests the new pure render-math functions directly (same "test
# the math, not a MultiMesh round-trip" reasoning as every other render
# check this session), plus static mesh-resource-identity checks that
# don't touch per-instance MultiMesh state at all (so they're not subject
# to the known --headless get/set-doesn't-round-trip limitation either).

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

func _ready():
	# --- 1: Pierce as a secondary is a STATIC core, not an orbiting dot ---
	var render_pos = Vector2(500, 300)
	var pierce_echo = ProjectileBatchPoolScript._compute_echo_render(render_pos, 3.7, 0.0, 0.9, EnergyPacket.SynergyType.PIERCE)
	_check("Pierce's echo sits exactly AT the render position (no orbit offset), unlike every other synergy's echo",
		pierce_echo["position"] == render_pos)
	_check("Pierce's echo is white (matching Projectile.gd's own glowing-core color), not Pierce's element color",
		pierce_echo["color"].r == 1.0 and pierce_echo["color"].g == 1.0 and pierce_echo["color"].b == 1.0)
	var kinetic_echo = ProjectileBatchPoolScript._compute_echo_render(render_pos, 3.7, 0.0, 0.9, EnergyPacket.SynergyType.KINETIC)
	_check("a non-Pierce echo (Kinetic) still orbits normally (unchanged from before this phase)",
		kinetic_echo["position"] != render_pos)

	# --- 2: Vortex's 3-orb helix - own fixed radius, 3 evenly-phase-spaced
	# positions, all colored as Vortex regardless of which fixed channel
	# they're rendered through ---
	var orb0 = ProjectileBatchPoolScript._compute_vortex_helix_render(render_pos, 1.0, 0, 1.0)
	var orb1 = ProjectileBatchPoolScript._compute_vortex_helix_render(render_pos, 1.0, 1, 1.0)
	var orb2 = ProjectileBatchPoolScript._compute_vortex_helix_render(render_pos, 1.0, 2, 1.0)
	for orb in [orb0, orb1, orb2]:
		_check("each Vortex helix orb stays within its own fixed VORTEX_HELIX_RADIUS of the main body",
			orb["position"].distance_to(render_pos) <= ProjectileBatchPoolScript.VORTEX_HELIX_RADIUS + 0.01)
	_check("the 3 orbs land at 3 genuinely distinct positions at the same instant (evenly phase-spaced, not stacked)",
		orb0["position"].distance_to(orb1["position"]) > 1.0 and orb1["position"].distance_to(orb2["position"]) > 1.0 and orb0["position"].distance_to(orb2["position"]) > 1.0)
	_check("all 3 orbs are colored as Vortex regardless of which borrowed channel renders them",
		orb0["color"] == orb1["color"] and orb1["color"] == orb2["color"])
	_check("VORTEX_HELIX_CHANNELS names exactly 3 fixed, distinct channel indices",
		ProjectileBatchPoolScript.VORTEX_HELIX_CHANNELS.size() == 3 and
		ProjectileBatchPoolScript.VORTEX_HELIX_CHANNELS[0] != ProjectileBatchPoolScript.VORTEX_HELIX_CHANNELS[1] and
		ProjectileBatchPoolScript.VORTEX_HELIX_CHANNELS[1] != ProjectileBatchPoolScript.VORTEX_HELIX_CHANNELS[2])
	_check("Vortex's own channel (4) is never one of the 3 borrowed ones (it's spending that on its own dominant rendering)",
		not ProjectileBatchPoolScript.VORTEX_HELIX_CHANNELS.has(EnergyPacket.SynergyType.VORTEX))

	# --- 3: tapered trail mesh - a real triangle with the expected front-
	# opaque/back-transparent vertex-color gradient baked in ---
	var taper = ProjectileBatchPoolScript._build_tapered_trail_mesh(20.0, 6.0)
	_check("the tapered trail mesh is a real, non-null ArrayMesh with one surface",
		taper != null and taper.get_surface_count() == 1)
	var arrays = taper.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	_check("the tapered mesh has exactly 3 vertices (front-left, front-right, back point)",
		verts.size() == 3)
	_check("the two front vertices are fully opaque",
		colors[0].a == 1.0 and colors[1].a == 1.0)
	_check("the back (tail) vertex fades to fully transparent",
		colors[2].a == 0.0)
	_check("the back vertex is genuinely BEHIND the front ones (negative X, matching the trail-offset direction convention)",
		verts[2].x < verts[0].x and verts[2].x < verts[1].x)

	# --- 4: Fire and Kinetic's trail channels use their OWN dedicated mesh,
	# not the same resource as their main body (structural check on static
	# multimesh configuration - no per-instance state involved, so this
	# doesn't hit the known --headless get/set staleness issue) ---
	var pool = ProjectileBatchPoolScript.new(4)
	add_child(pool) # _ready() runs synchronously here, calling _setup_multimesh() once
	_check("Fire's trail channel uses a DIFFERENT mesh resource than its main body (bespoke tapered trail, not a reused-shape copy)",
		pool._trail_multimeshes[EnergyPacket.SynergyType.FIRE].mesh != pool._synergy_multimeshes[EnergyPacket.SynergyType.FIRE].mesh)
	_check("Kinetic's trail channel uses a DIFFERENT mesh resource than its main body",
		pool._trail_multimeshes[EnergyPacket.SynergyType.KINETIC].mesh != pool._synergy_multimeshes[EnergyPacket.SynergyType.KINETIC].mesh)
	_check("a synergy NOT special-cased (e.g. Ice) still reuses its main body's mesh for its trail (unchanged from before this phase - regression guard)",
		pool._trail_multimeshes[EnergyPacket.SynergyType.ICE].mesh == pool._synergy_multimeshes[EnergyPacket.SynergyType.ICE].mesh)

	if failures == 0:
		print("PASS: Pierce gets a static glowing core, Vortex gets its own 3-orb helix on 3 guaranteed-idle fixed channels, Fire/Kinetic get bespoke tapered trail meshes, and every other synergy's rendering is unchanged")
	get_tree().quit(0 if failures == 0 else 1)

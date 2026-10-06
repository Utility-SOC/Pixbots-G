extends GPUParticles2D

# Ambient weather that follows the player and changes with the ground underfoot: snow on tundra, rising
# embers over volcano, drifting dust on desert, loose leaves in forest. One GPU particle system for the
# whole game (particles are world-space, so they stay put as you move), re-pointed at a new preset when
# the biome under the player has changed for two checks in a row.

const CHECK_INTERVAL = 0.5
const AREA = Vector3(1200.0, 760.0, 0.0)

# biome int (MapGenerator.BiomeType) -> preset. Colour, gravity, velocity range, size range, count.
const PRESETS = {
	4: {"name": "snow", "color": Color(1.0, 1.0, 1.0, 0.95), "gravity": Vector3(-14, 28, 0), "vmin": 8.0, "vmax": 24.0, "smin": 2.7, "smax": 5.4, "amount": 120, "life": 9.0, "dir": Vector3(-0.3, 1, 0), "spread": 25.0},
	5: {"name": "embers", "color": Color(1.0, 0.55, 0.15, 0.9), "gravity": Vector3(6, -30, 0), "vmin": 6.0, "vmax": 22.0, "smin": 2.4, "smax": 4.8, "amount": 80, "life": 6.0, "dir": Vector3(0, -1, 0), "spread": 35.0},
	2: {"name": "dust", "color": Color(0.85, 0.72, 0.45, 0.45), "gravity": Vector3(26, 2, 0), "vmin": 30.0, "vmax": 70.0, "smin": 2.0, "smax": 4.1, "amount": 70, "life": 8.0, "dir": Vector3(1, 0.05, 0), "spread": 10.0},
	3: {"name": "leaves", "color": Color(0.85, 0.6, 0.2, 0.9), "gravity": Vector3(8, 14, 0), "vmin": 6.0, "vmax": 16.0, "smin": 3.4, "smax": 5.8, "amount": 40, "life": 12.0, "dir": Vector3(0.3, 1, 0), "spread": 40.0},
}

var current: String = "" # preset name currently showing ("" = clear weather)
var _candidate: String = ""
var _timer := 0.0

func _ready():
	z_index = 40 # above the terrain and mechs, below UI (which is on its own canvas layer)
	local_coords = false
	emitting = false
	visibility_rect = Rect2(-AREA.x, -AREA.y, AREA.x * 2.0, AREA.y * 2.0)

static func preset_for_biome(biome: int) -> String:
	return PRESETS[biome]["name"] if PRESETS.has(biome) else ""

func _process(delta: float):
	_timer += delta
	if _timer < CHECK_INTERVAL:
		return
	_timer = 0.0
	var maps = get_tree().get_nodes_in_group("map_generator")
	if maps.is_empty():
		return
	var biome: int = maps[0].get_biome_at_world_pos(global_position)
	var want = preset_for_biome(biome)
	if want == current:
		_candidate = want
		return
	if want == _candidate:
		apply(biome) # second consecutive check agrees
	else:
		_candidate = want

func apply(biome: int) -> void:
	var name = preset_for_biome(biome)
	current = name
	_candidate = name
	if name == "":
		emitting = false
		return
	var p: Dictionary = PRESETS[biome]
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = AREA * 0.5
	mat.direction = p["dir"]
	mat.spread = p["spread"]
	mat.initial_velocity_min = p["vmin"]
	mat.initial_velocity_max = p["vmax"]
	mat.gravity = p["gravity"]
	mat.scale_min = p["smin"]
	mat.scale_max = p["smax"]
	mat.color = p["color"]
	process_material = mat
	amount = p["amount"]
	lifetime = p["life"]
	preprocess = p["life"] * 0.8 # the sky is already full the moment it starts
	explosiveness = 0.0
	restart()
	emitting = true

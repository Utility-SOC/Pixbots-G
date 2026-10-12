class_name WeatherSystem
extends Node

# Intermittent map weather: Desert maps get sandstorms, Tundra maps rare blizzards. A storm warns, ramps up, holds, then
# fades. While it blows, every mech's detection range shrinks (`sight_mult`, read by SightAndSearch) and a tinted veil
# covers the screen, so the map itself is occluded. Timings come from the seeded "combat" stream (a seed reproduces the
# same weather). All numbers (tune). One WeatherSystem lives under the MapGenerator and joins group "weather".
#
# Not yet: the blizzard slowing movement, sight loss for the player's own sensors/minimap, weather on other map types.

enum State { CLEAR, RAMP_UP, HOLD, FADE }

const KINDS = {
	"sandstorm": {"first": Vector2(25.0, 60.0), "gap": Vector2(70.0, 140.0), "ramp": 6.0, "hold": Vector2(18.0, 30.0), "fade": 8.0,
		"min_sight": 0.2, "ebb_depth": 0.55, "ebb_period": 7.0, "tint": Color(0.85, 0.65, 0.35), "max_alpha": 0.55, "warn": "SANDSTORM", "once_in": 1},
	"blizzard": {"first": Vector2(90.0, 180.0), "gap": Vector2(120.0, 240.0), "ramp": 7.0, "hold": Vector2(15.0, 25.0), "fade": 9.0,
		"min_sight": 0.15, "ebb_depth": 0.5, "ebb_period": 9.0, "tint": Color(0.9, 0.95, 1.0), "max_alpha": 0.6, "warn": "BLIZZARD", "once_in": 3},
}
const KIND_BY_MAP = {"Desert": "sandstorm", "Tundra": "blizzard"}

var kind: String = "sandstorm"
var state: int = State.CLEAR
var intensity: float = 0.0 # 0 clear .. 1 full storm
var _timer: float = 0.0
var _hold_t: float = 0.0 # seconds into the HOLD phase (drives the ebb and flow)
var _rng: RandomNumberGenerator = null
var storms_started: int = 0
var _veil: ColorRect = null
var _label: Label = null
var _layer: CanvasLayer = null

func _ready():
	add_to_group("weather")
	_rng = SimRng.stream("combat")
	_timer = _roll(KINDS[kind]["first"])
	if DisplayServer.get_name() != "headless":
		_build_veil()

func _roll(range_v: Vector2) -> float:
	return _rng.randf_range(range_v.x, range_v.y)

func _process(delta: float):
	advance(delta)
	_update_veil()

# Steps the weather by `delta` seconds (separate from _process so tests can drive it).
func advance(delta: float) -> void:
	var k: Dictionary = KINDS[kind]
	_timer -= delta
	match state:
		State.CLEAR:
			if _timer <= 0.0:
				# Blizzards are rare: only every Nth due storm actually blows, the rest are skipped (a longer lull).
				if int(k["once_in"]) > 1 and _rng.randi_range(1, int(k["once_in"])) != 1:
					_timer = _roll(k["gap"])
					return
				storms_started += 1
				state = State.RAMP_UP
				_timer = float(k["ramp"])
		State.RAMP_UP:
			intensity = 1.0 - clampf(_timer / float(k["ramp"]), 0.0, 1.0)
			if _timer <= 0.0:
				intensity = 1.0
				state = State.HOLD
				_hold_t = 0.0
				_timer = _roll(k["hold"])
		State.HOLD:
			# The storm ebbs and flows: it peaks at full strength, thins by ebb_depth, and swells again.
			_hold_t += delta
			intensity = 1.0 - float(k["ebb_depth"]) * (0.5 - 0.5 * cos(TAU * _hold_t / float(k["ebb_period"])))
			if _timer <= 0.0:
				state = State.FADE
				_timer = float(k["fade"])
		State.FADE:
			intensity = minf(intensity, clampf(_timer / float(k["fade"]), 0.0, 1.0)) # never swells while fading
			if _timer <= 0.0:
				intensity = 0.0
				state = State.CLEAR
				_timer = _roll(k["gap"])

func current_sight_mult() -> float:
	return 1.0 - (1.0 - float(KINDS[kind]["min_sight"])) * intensity

# Detection range multiplier from the weather in play (1.0 when there is none). Cheap: one group lookup.
static func sight_mult(tree: SceneTree) -> float:
	if tree == null:
		return 1.0
	var nodes = tree.get_nodes_in_group("weather")
	if nodes.is_empty() or not is_instance_valid(nodes[0]):
		return 1.0
	return nodes[0].current_sight_mult()

func _build_veil() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 3 # above the world (0), below the HUD (5)
	add_child(_layer)
	_veil = ColorRect.new()
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.color = Color(0, 0, 0, 0)
	_layer.add_child(_veil)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.position = Vector2(-120, 70)
	_label.modulate = Color(1, 1, 1, 0)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_label)

func _update_veil() -> void:
	if _veil == null:
		return
	var k: Dictionary = KINDS[kind]
	var c: Color = k["tint"]
	c.a = float(k["max_alpha"]) * intensity
	_veil.color = c
	_label.text = str(k["warn"]) + (" INCOMING" if state == State.RAMP_UP else (" - VISION REDUCED" if state == State.HOLD else ""))
	_label.modulate.a = 1.0 if (state == State.RAMP_UP or state == State.HOLD) else 0.0

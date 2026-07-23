extends "res://scripts/entities/JammerMech.gd"

# General Support unit - replaces the old single-purpose PiercingJammerMech.
# Per the user: "Replace [the piercing jammer unit] with a general support
# unit with healing and sensor jammers. Make sure the commanders have
# enough support to be able to make a difference in a pitched battle."
#
# Still a JammerMech subclass (inherits the continuous weapon-power-jam
# aura wholesale via _process/_draw - a Support unit still saps the
# player's damage output like a Warden), and keeps the ORIGINAL Piercing
# Jammer feature that actually justified the role's existence
# (FEATURE_ROADMAP.md Decision Log): nearby allies (and itself) are immune
# to the player's PIERCE instant-execution roll - see Mech.
# _is_pierce_execution_exempt(), gated on the "pierce_immunity_aura" group
# this class joins in _ready().
#
# Two more support functions layer on top of that:
#   - Healing: seeds the Heal Beacon capacity fields (has_healer/
#     heal_pulse_*) directly rather than requiring an equipped Heal Beacon
#     tile - same trick this class already used for jammer_power/
#     jammer_radius below. HealBeaconSystem.gd (driven by Mech._physics_
#     process's unconditional _update_healer(delta) call) does the actual
#     periodic squad-heal pulse from there with zero extra plumbing.
#   - Sensor jamming: a persistent JammerField (see that class's header) -
#     the same "Blind"/exact-position-denial effect the tile-driven Jammer
#     Module's VISION mode grants an equipped mech, just spawned directly
#     here instead of requiring a routed Jammer Module tile. Combined with
#     the inherited power-jam aura, this covers BOTH halves of "sensor
#     jammers" per the design call: denies the player's effective sight/
#     targeting (JammerField) AND reduces their weapon power (inherited aura).

const JammerFieldScript = preload("res://scripts/visuals/JammerField.gd")

const PIERCE_AURA_RADIUS = 500.0
const SENSOR_JAM_RADIUS = 550.0

var sensor_jam_field = null
var _sensor_field_exit_hooked: bool = false

func _ready():
	super._ready()
	add_to_group("pierce_immunity_aura")

	# Slightly tighter/weaker power-jam than a stock Warden (this unit's
	# value is spread across three support functions, not out-jamming the
	# player on power alone) - recompute from the same wave-scaling formula
	# JammerMech._ready used, just with a gentler floor.
	var main = get_tree().current_scene
	if main and "current_wave" in main:
		jammer_power = max(0.35, 0.6 - (main.current_wave * 0.01))
	jammer_radius = 650.0

	# Teal ring - matches MechRenderer's existing "support" role color
	# (Color(0.2, 0.7, 0.75)) so the aura reads as the same unit as its body.
	ring_glow_color = Color(0.2, 0.7, 0.75)

	# Healing capacity, seeded directly (see class comment above) rather
	# than derived from an equipped tile. Gentle wave scaling on the pulse
	# power so a Support unit stays relevant as enemy HP pools grow with it.
	has_healer = true
	heal_pulse_radius = 220.0
	heal_pulse_interval = 3.0
	heal_pulse_power = 30.0
	if main and "current_wave" in main:
		heal_pulse_power += main.current_wave * 1.2

func _process(delta: float):
	super._process(delta)
	_ensure_sensor_jam_field()

func _ensure_sensor_jam_field():
	if sensor_jam_field and is_instance_valid(sensor_jam_field):
		sensor_jam_field.global_position = global_position
		return
	if not get_parent():
		return
	sensor_jam_field = JammerFieldScript.new()
	sensor_jam_field.global_position = global_position
	sensor_jam_field.setup(self, SENSOR_JAM_RADIUS, -1.0)
	get_parent().add_child(sensor_jam_field)
	if not _sensor_field_exit_hooked:
		_sensor_field_exit_hooked = true
		tree_exiting.connect(_release_sensor_jam_field)

func _release_sensor_jam_field():
	if sensor_jam_field and is_instance_valid(sensor_jam_field):
		sensor_jam_field.queue_free()
	sensor_jam_field = null

# The pierce-immunity aura radius is meaningfully larger than the power-jam
# radius (protects a whole squad clustered around it, not just whoever it's
# actively jamming) - draw a second, larger glow ring so the protective
# radius itself is readable on screen instead of being an invisible
# game-state check.
func _draw():
	super._draw()
	var pulse = 0.5 + sin(Time.get_ticks_msec() / 150.0) * 0.2
	var c = Color(0.95, 0.3, 0.2)
	draw_arc(Vector2.ZERO, PIERCE_AURA_RADIUS, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.08 * pulse), 10.0, true)
	draw_arc(Vector2.ZERO, PIERCE_AURA_RADIUS, 0.0, TAU, 64, Color(c.r, c.g, c.b, 0.35), 1.5, true)

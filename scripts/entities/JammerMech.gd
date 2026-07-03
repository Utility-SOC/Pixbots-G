extends "res://scripts/entities/Mech.gd"

var jammer_radius: float = 800.0
var jammer_power: float = 0.5 # 50% reduction early game
var is_jamming: bool = false

var jammer_visual: Polygon2D

func _ready():
	super._ready()
	
	# Calculate scaling power reduction based on current wave
	var main = get_tree().current_scene
	if main and "current_wave" in main:
		# Starts at 0.5 (50%), reaches 0.1 (90% reduction) around wave 30+
		jammer_power = max(0.1, 0.5 - (main.current_wave * 0.015))
		
	# Add an area indicator for the jammer
	jammer_visual = Polygon2D.new()
	var pts = PackedVector2Array()
	for i in range(32):
		var a = i * PI / 16.0
		pts.append(Vector2(cos(a), sin(a)))
	jammer_visual.polygon = pts
	jammer_visual.scale = Vector2(jammer_radius, jammer_radius)
	jammer_visual.color = Color(0.2, 0.5, 1.0, 0.1)
	jammer_visual.z_index = -5
	add_child(jammer_visual)

func _process(delta: float):
	if is_instance_valid(target) and target.has_method("apply_jammer_debuff"):
		var dist = global_position.distance_to(target.global_position)
		if dist <= jammer_radius:
			is_jamming = true
			target.apply_jammer_debuff(jammer_power)
			jammer_visual.color = Color(0.2, 0.5, 1.0, 0.3 + sin(Time.get_ticks_msec() / 150.0) * 0.1) # Pulsing visual
		else:
			is_jamming = false
			jammer_visual.color = Color(0.2, 0.5, 1.0, 0.1)

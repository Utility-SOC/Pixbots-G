import os
import re

file_path = "j:/pixel_bots/godot/scripts/entities/Projectile.gd"

with open(file_path, "r") as f:
    content = f.read()

# Replace _calculate_stats
new_stats = """func _calculate_stats():
\t# Organic Stat Scaling
\tvar r_raw = ratios.get(EnergyPacket.SynergyType.RAW, 0.0)
\tvar r_kin = ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)
\tvar r_ice = ratios.get(EnergyPacket.SynergyType.ICE, 0.0)
\tvar r_exp = ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0)
\tvar r_prc = ratios.get(EnergyPacket.SynergyType.PIERCE, 0.0)
\tvar r_psn = ratios.get(EnergyPacket.SynergyType.POISON, 0.0)
\t
\t# Base Speed
\tvar spd_mod = 0.0
\tspd_mod += 800.0 * r_kin
\tspd_mod += 400.0 * r_prc
\tspd_mod -= 250.0 * r_psn
\tspd_mod -= 200.0 * r_ice
\tfinal_speed = base_speed + spd_mod
\tif final_speed < 50.0: final_speed = 50.0
\t
\t# Size/Mass
\tvar s_mod = 1.0 + r_raw # RAW directly increases volume
\ts_mod += 1.5 * r_ice # ICE adds crystalline mass
\ts_mod += 2.0 * r_exp # EXPLOSION adds volatility/size
\ts_mod -= 0.5 * r_prc # PIERCE makes it sleek
\tscale = Vector2(s_mod, s_mod)
\t
\t# Base Damage Multiplier from RAW
\tdamage *= (1.0 + r_raw * 1.5)
\t
\t# Pierce Count (PIERCE sets base to high, otherwise 1)
\tif r_prc > 0.0:
\t\tpierce_count = 1 + int(4.0 * r_prc)
\telse:
\t\tpierce_count = 1
\t\t
\t# Homing check
\tif ratios.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0) > 0.05:
\t\tis_homing = true
\t\t
\t# Color Blending
\tfinal_color = Color(0,0,0,0)
\tfor k in ratios:
\t\tvar c = Color.WHITE
\t\tmatch k:
\t\t\tEnergyPacket.SynergyType.FIRE: c = Color(1.0, 0.3, 0.0)
\t\t\tEnergyPacket.SynergyType.ICE: c = Color(0.2, 0.8, 1.0)
\t\t\tEnergyPacket.SynergyType.KINETIC: c = Color(1.0, 1.0, 1.0)
\t\t\tEnergyPacket.SynergyType.VORTEX: c = Color(0.5, 0.0, 1.0)
\t\t\tEnergyPacket.SynergyType.LIGHTNING: c = Color(1.0, 0.9, 0.2)
\t\t\tEnergyPacket.SynergyType.POISON: c = Color(0.2, 0.8, 0.2)
\t\t\tEnergyPacket.SynergyType.EXPLOSION: c = Color(1.0, 0.5, 0.0)
\t\t\tEnergyPacket.SynergyType.PIERCE: c = Color(0.0, 1.0, 0.5)
\t\t\tEnergyPacket.SynergyType.VAMPIRIC: c = Color(0.8, 0.0, 0.3)
\t\tfinal_color += c * ratios[k]
\tif final_color.a == 0:
\t\tfinal_color = Color.WHITE
"""

content = re.sub(
    r"func _calculate_stats\(\):.*?(?=func _build_visuals\(\):)",
    new_stats,
    content,
    flags=re.DOTALL
)

# Replace _physics_process
new_physics = """func _physics_process(delta: float):
\ttime_alive += delta
\tvar space_state = get_world_2d().direct_space_state
\t
\tvar r_kin = ratios.get(EnergyPacket.SynergyType.KINETIC, 0.0)
\tvar r_vamp = ratios.get(EnergyPacket.SynergyType.VAMPIRIC, 0.0)
\tvar r_ice = ratios.get(EnergyPacket.SynergyType.ICE, 0.0)
\tvar r_fire = ratios.get(EnergyPacket.SynergyType.FIRE, 0.0)
\tvar r_prc = ratios.get(EnergyPacket.SynergyType.PIERCE, 0.0)
\tvar r_psn = ratios.get(EnergyPacket.SynergyType.POISON, 0.0)
\tvar r_vtx = ratios.get(EnergyPacket.SynergyType.VORTEX, 0.0)
\tvar r_ltg = ratios.get(EnergyPacket.SynergyType.LIGHTNING, 0.0)
\t
\t# 1. MASS / INERTIA (ICE & RAW)
\t# Heavy objects resist steering. Pierce ignores friction but doesn't affect mass steering resistance.
\tvar steering_resistance = 1.0 + (3.0 * r_ice) # Ice makes it very hard to turn
\t
\t# 2. VAMPIRIC TERMINAL HOMING ("The Hunter")
\tvar active_homing_target = null
\tif is_homing:
\t\tvar closest = null
\t\tvar min_dist = 400.0 + (300.0 * r_vamp)
\t\tvar query = PhysicsShapeQueryParameters2D.new()
\t\tvar shape = CircleShape2D.new()
\t\tshape.radius = min_dist
\t\tquery.shape = shape
\t\tquery.transform = global_transform
\t\tquery.collision_mask = 4 if collision_mask & 4 else 8
\t\tvar results = space_state.intersect_shape(query)
\t\tfor res in results:
\t\t\tvar col = res["collider"]
\t\t\tif col.has_method("apply_damage"):
\t\t\t\tvar d = global_position.distance_to(col.global_position)
\t\t\t\tif d < min_dist:
\t\t\t\t\tmin_dist = d
\t\t\t\t\tclosest = col
\t\tif closest:
\t\t\tactive_homing_target = closest
\t\t\ttarget_direction = (closest.global_position - global_position).normalized()
\t
\t# 3. KINETIC STEERING ("The Straightener") & VAMPIRIC OVERRIDE
\tvar current_speed = final_speed
\t
\tif active_homing_target != null:
\t\t# Vampiric smoothly forces a curve to guarantee hit
\t\tvar turn_speed = (8.0 * r_vamp) / steering_resistance
\t\tdirection = direction.lerp(target_direction, turn_speed * delta).normalized()
\telif target_direction != Vector2.ZERO:
\t\tvar turn_speed = 0.5 # Passive drift
\t\tif r_kin > 0.0:
\t\t\tturn_speed += (6.0 * r_kin)
\t\tturn_speed /= steering_resistance
\t\tdirection = direction.lerp(target_direction, turn_speed * delta).normalized()
\t
\t# 4. FIRE DECELERATION ("The Plume") vs PIERCE / KINETIC
\t# Pierce grants infinite mass/0 drag. Kinetic actively pushes through drag.
\tif r_fire > 0.0:
\t\tvar drag_coefficient = 800.0 * r_fire
\t\tdrag_coefficient *= (1.0 - r_prc) # Pierce cancels drag organically
\t\tdrag_coefficient = max(0.0, drag_coefficient - (500.0 * r_kin)) # Kinetic fights it
\t\t
\t\tcurrent_speed = max(50.0, final_speed - drag_coefficient * time_alive)
\t
\t# 5. POISON GRAVITY LOB ("The Mortar")
\tvar gravity_velocity = Vector2.ZERO
\tif r_psn > 0.0:
\t\tgravity_velocity = Vector2(0, 400.0 * r_psn * time_alive) # Accelerates downwards over time
\t
\t# ORGANIC VELOCITY ACCUMULATION
\tvar ortho = Vector2(-direction.y, direction.x)
\tvar velocity = (direction * current_speed) + gravity_velocity
\tvar visual_offset = Vector2.ZERO
\t
\t# 6. VORTEX SWIRL ("The Swirler")
\t# Applies a strong tangential force that oscillates, moving the projectile itself.
\tif r_vtx > 0.0:
\t\tvar swirl_amplitude = 250.0 * r_vtx
\t\tvar swirl_freq = 6.0
\t\tvar swirl_vel = ortho * cos(time_alive * swirl_freq) * swirl_amplitude
\t\tvelocity += swirl_vel
\t\t
\t\tif r_vtx > 0.1:
\t\t\t_pull_nearby_items(delta)
\t
\t# 7. LIGHTNING ZIG-ZAG ("The Arc")
\t# Lightning snaps instantly along the path, modeled as a square wave offset.
\tif r_ltg > 0.0:
\t\tvar wave_sign = sign(fmod(time_alive * 20.0, 2.0) - 1.0)
\t\tvisual_offset += ortho * wave_sign * (30.0 * r_ltg)
\t
\t# APPLY PHYSICS
\tposition += velocity * delta
\t
\t# APPLY VISUALS
\tvisual_node.position = visual_offset
\t# If poison gravity is dominating, point downwards
\tif gravity_velocity.length() > (direction * current_speed).length():
\t\tvisual_node.rotation = velocity.angle()
\telse:
\t\tvisual_node.rotation = direction.angle()
\t
\t# Update Helix Particles
\tif helix_particles.size() > 0:
\t\tfor p in helix_particles:
\t\t\tvar angle = time_alive * p["speed"] + p["phase"]
\t\t\tp["node"].position = Vector2(cos(angle)*p["radius"]*0.5, sin(angle)*p["radius"])
\t\t\t
\t# Update trails
\tfor child in visual_node.get_children():
\t\tif child.has_meta("is_trail"):
\t\t\tchild.add_point(Vector2(-velocity.length() * 0.02, 0))
\t\t\tif child.get_point_count() > 10:
\t\t\t\tchild.remove_point(0)
"""

content = re.sub(
    r"func _physics_process\(delta: float\):.*?(?=func _pull_nearby_items)",
    new_physics,
    content,
    flags=re.DOTALL
)

# Update timer timeout for Explosion
detonation_logic = """\t# EXPLOSION DETONATION
\tvar timer = Timer.new()
\ttimer.wait_time = _get_lifetime()
\ttimer.one_shot = true
\ttimer.timeout.connect(func():
\t\tif ratios.get(EnergyPacket.SynergyType.EXPLOSION, 0.0) > 0.1:
\t\t\t_trigger_explosion()
\t\tqueue_free()
\t)
\tadd_child(timer)
\ttimer.start()"""

content = re.sub(
    r"\tvar timer = Timer\.new\(\).*?timer\.start\(\)",
    detonation_logic,
    content,
    flags=re.DOTALL
)

with open(file_path, "w") as f:
    f.write(content)
print("Projectile.gd patched for Phase 3.")

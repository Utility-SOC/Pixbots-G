import os
import re

file_path = "j:/pixel_bots/godot/scripts/entities/Projectile.gd"

with open(file_path, "r") as f:
    content = f.read()

# 1. Add target_direction
if "var target_direction: Vector2 = Vector2.ZERO" not in content:
    content = content.replace("var direction: Vector2 = Vector2.ZERO", 
                              "var direction: Vector2 = Vector2.ZERO\nvar target_direction: Vector2 = Vector2.ZERO")

# 2. Modify timer wait time in _ready
content = content.replace("timer.wait_time = 4.0", "timer.wait_time = _get_lifetime()")

# 3. Add _get_lifetime helper
lifetime_func = """func _get_lifetime() -> float:
\tvar base_life = 4.0
\tif ratios.has(EnergyPacket.SynergyType.FIRE):
\t\tbase_life = lerp(base_life, 0.4, ratios[EnergyPacket.SynergyType.FIRE]) # Very short lifetime for fire
\t\tif ratios.has(EnergyPacket.SynergyType.KINETIC):
\t\t\t# Kinetic stretches the fire plume length
\t\t\tbase_life += 1.0 * ratios[EnergyPacket.SynergyType.KINETIC]
\treturn max(0.1, base_life)
"""
if "func _get_lifetime" not in content:
    content = content.replace("func _calculate_stats():", lifetime_func + "\nfunc _calculate_stats():")

# 4. Rewrite _physics_process
new_physics = """func _physics_process(delta: float):
\ttime_alive += delta
\t
\tvar space_state = get_world_2d().direct_space_state
\t
\t# Homing Steering (VAMPIRIC - Target Closest Enemy)
\tif is_homing:
\t\tvar closest = null
\t\tvar min_dist = 400.0
\t\tvar query = PhysicsShapeQueryParameters2D.new()
\t\tvar shape = CircleShape2D.new()
\t\tshape.radius = 300.0
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
\t\t\ttarget_direction = (closest.global_position - global_position).normalized()
\t
\t# 1. KINETIC STEERING ("The Straightener")
\tvar current_speed = final_speed
\tif ratios.has(EnergyPacket.SynergyType.KINETIC) and target_direction != Vector2.ZERO:
\t\tvar k_ratio = ratios[EnergyPacket.SynergyType.KINETIC]
\t\tvar turn_speed = 5.0 * k_ratio # Faster turn based on Kinetic strength
\t\tdirection = direction.lerp(target_direction, turn_speed * delta).normalized()
\telif target_direction != Vector2.ZERO and ratios.has(EnergyPacket.SynergyType.RAW):
\t\t# Raw has a very slow passive alignment just to eventually point forward, or maybe none?
\t\t# User said "Kinetic... go forward no matter what... stronger kinetic means shorter time before turning forward".
\t\t# We'll give raw a tiny bit of steering so it isn't completely useless when fired backwards, but Kinetic is the true straightener.
\t\tdirection = direction.lerp(target_direction, 0.5 * delta).normalized()
\t
\t# 2. FIRE DECELERATION ("The Plume")
\tif ratios.has(EnergyPacket.SynergyType.FIRE):
\t\t# High drag, but Kinetic fights it
\t\tvar f_ratio = ratios[EnergyPacket.SynergyType.FIRE]
\t\tvar drag = 800.0 * f_ratio
\t\tif ratios.has(EnergyPacket.SynergyType.KINETIC):
\t\t\tdrag -= 600.0 * ratios[EnergyPacket.SynergyType.KINETIC] # Kinetic pushes through the drag
\t\t
\t\tcurrent_speed = max(50.0, final_speed - drag * time_alive)
\t
\t# Trajectory Offsets (Visual/Physical Displacement)
\tvar ortho = Vector2(-direction.y, direction.x)
\tvar pos_offset = Vector2.ZERO
\t
\t# VORTEX SWIRL ("The Swirler")
\tvar vortex_offset = Vector2.ZERO
\tif ratios.has(EnergyPacket.SynergyType.VORTEX):
\t\tvar v_ratio = ratios[EnergyPacket.SynergyType.VORTEX]
\t\t# Swirl is a perpendicular force that oscillates, creating looping bezier-like curves
\t\t# When combined with Fire it creates "tentacles"
\t\t# When combined with Kinetic it "wobbles" on its way forward
\t\tvar swirl_amplitude = 150.0 * v_ratio
\t\tvar swirl_freq = 8.0
\t\tvortex_offset = ortho * sin(time_alive * swirl_freq) * swirl_amplitude
\t\t
\t\t# VORTEX also pulls enemies
\t\tif v_ratio > 0.1:
\t\t\t_pull_nearby_items(delta)
\t
\t# FIRE WEAVE
\tif ratios.has(EnergyPacket.SynergyType.FIRE):
\t\tpos_offset += ortho * sin(time_alive * 25.0) * (10.0 * ratios[EnergyPacket.SynergyType.FIRE])
\t\t
\t# LIGHTNING ZIG-ZAG
\tif ratios.has(EnergyPacket.SynergyType.LIGHTNING):
\t\tvar wave = fmod(time_alive * 30.0, 2.0) - 1.0
\t\tpos_offset += ortho * wave * (15.0 * ratios[EnergyPacket.SynergyType.LIGHTNING])
\t\t
\t# POISON LOB
\tif ratios.has(EnergyPacket.SynergyType.POISON):
\t\tpos_offset.y += (time_alive * time_alive * 300.0) * ratios[EnergyPacket.SynergyType.POISON]
\t
\t# Apply Base Movement + Vortex physical displacement
\tvar velocity = direction * current_speed
\tif vortex_offset != Vector2.ZERO:
\t\t# Derivative of the vortex offset to add to velocity to physically move it
\t\tvar v_ratio = ratios[EnergyPacket.SynergyType.VORTEX]
\t\tvar swirl_vel = ortho * cos(time_alive * 8.0) * (150.0 * v_ratio * 8.0)
\t\tvelocity += swirl_vel
\t\t
\tposition += velocity * delta
\t
\t# Apply Visual Offsets
\tvisual_node.position = pos_offset
\tvisual_node.rotation = direction.angle()
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
\t\t\tchild.add_point(Vector2(-current_speed * 0.1, 0)) # Extend backwards relative to projectile
\t\t\tif child.get_point_count() > 10:
\t\t\t\tchild.remove_point(0)
"""

content = re.sub(
    r"func _physics_process\(delta: float\):.*?(?=func _pull_nearby_items)",
    new_physics,
    content,
    flags=re.DOTALL
)

with open(file_path, "w") as f:
    f.write(content)

print("Projectile.gd patched successfully.")

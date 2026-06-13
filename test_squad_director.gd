extends SceneTree

func _init():
	print("--- Starting Dynamic Squad Director Simulation ---")
	
	var director = SquadDirector.new()
	root.add_child(director)
	
	# Register 3 competing templates
	var t1 = SquadTemplate.new("Standard Assault")
	t1.add_role("melee", 3)
	t1.add_role("ranged", 2)
	
	var t2 = SquadTemplate.new("Heavy Melee")
	t2.add_role("melee", 5)
	
	var t3 = SquadTemplate.new("Sniper Squad")
	t3.add_role("ranged", 4)
	
	director.register_template(t1)
	director.register_template(t2)
	director.register_template(t3)
	
	# Simulate 50 squad encounters
	print("\nRunning 50 Encounters...")
	for i in range(50):
		var squad = director.spawn_squad()
		if not squad:
			continue
			
		# Add dummy mechs to the squad
		var total_mechs = 0
		for count in squad.template.required_roles.values():
			total_mechs += count
			
		for m in range(total_mechs):
			var mech = Mech.new()
			squad.add_child(mech)
			squad.add_member(mech)
			
		# Advance time based on arbitrary "encounter length"
		# Let's say "Heavy Melee" survives longer on average, 
		# but "Sniper Squad" does massive damage quickly.
		
		var sim_time = randf_range(10.0, 30.0)
		var damage = randf_range(100.0, 500.0)
		
		# Bias the simulation
		if squad.template.template_name == "Heavy Melee":
			sim_time += 20.0 # Lives longer
		elif squad.template.template_name == "Sniper Squad":
			damage += 800.0 # Does more damage
		
		# Simulate the encounter
		squad.time_alive = sim_time
		
		# Simulate damage dealing
		for mech in squad.members:
			mech.emit_signal("dealt_damage", damage / total_mechs)
			
		# Kill the mechs to trigger resolution
		for mech in squad.members:
			mech.queue_free()
			
	# Print Final Results
	print("\n--- Final Learned Weights ---")
	for t in director.templates:
		print(t.template_name, " -> Weight: ", "%.1f" % t.spawn_weight, " (Average Fitness: ", "%.1f" % t.get_average_fitness(), ")")
		
	print("\nTest complete.")
	quit()

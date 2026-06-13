extends SceneTree

func _init():
	var main = load("res://Main.tscn").instantiate()
	root.add_child(main)
	
	await create_timer(0.5).timeout
	
	# Spawn enemy
	var enemy = main.player.get_script().new()
	enemy.is_player = false
	enemy.global_position = Vector2(100, 100)
	enemy.collision_layer = 4
	enemy.collision_mask = 1 | 2 | 8
	enemy.add_to_group("enemies")
	main.add_child(enemy)
	
	await create_timer(0.5).timeout
	
	# Fire projectile from player
	var proj = load("res://scripts/entities/Projectile.gd").new()
	proj.global_position = main.player.global_position
	proj.direction = proj.global_position.direction_to(enemy.global_position)
	proj.collision_mask = 1 | 4
	proj.damage = 1000.0
	main.add_child(proj)
	
	print("Fired projectile towards enemy! Pos: ", proj.global_position, " Enemy Pos: ", enemy.global_position)
	
	# Wait for hit
	for i in range(30):
		await create_timer(0.1).timeout
		if not is_instance_valid(enemy):
			print("Enemy was destroyed!")
			break
		if not is_instance_valid(proj):
			print("Projectile was destroyed! Enemy HP: ", enemy.hp)
			break
			
	if is_instance_valid(enemy):
		print("Enemy survived! HP: ", enemy.hp)
	if is_instance_valid(proj):
		print("Projectile survived! Pos: ", proj.global_position)
		
	quit()

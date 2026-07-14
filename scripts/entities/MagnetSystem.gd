class_name MagnetSystem
extends RefCounted

# Player Magnet field logic (pull radius, loot attraction, Mythic repel-mode
# projectile reflection, and the pull-radius ring visual) - split out of
# Mech.gd's _physics_process, see SightAndSearch.gd's header comment for the
# established composed-RefCounted-helper pattern this follows. All state
# (total_magnetic_power, magnet_repel_mode, min_loot_attract_rarity,
# magnet_visual, the _magnet_* timers, and the MAGNET_* tuning constants)
# stays on Mech itself - only the behavior that reads/writes it moved here.
# Lazily constructed the first time the player mech needs it (see
# Mech._physics_process's call site), same lazy pattern as the other
# composed helpers.
#
# total_magnetic_power/magnet_repel_mode stay directly on Mech (not moved) -
# they're written from _recalculate_grid's tile-scan, and read directly by
# scripts/debug/MagnetRepelRepro.gd, so they have to stay reachable as plain
# Mech-level fields regardless.

var mech: Mech

func _init(p_mech: Mech):
	mech = p_mech

func update(delta: float):
	if mech.total_magnetic_power > 0.0:
		# Saturating curve (see Mech.MAGNET_POWER_SCALE's field comment) -
		# approaches linear-in-power for normal magnitudes, asymptotes
		# to a fixed ceiling no matter how large total_magnetic_power
		# gets (loop-abuse case).
		var magnet_power_factor = 1.0 - exp(-mech.total_magnetic_power / mech.MAGNET_POWER_SCALE)
		var pull_radius = 150.0 + mech.MAGNET_PULL_RADIUS_MAX_BONUS * magnet_power_factor
		_update_visual(pull_radius)

		mech._magnet_accum_delta += delta
		mech._magnet_update_timer -= delta
		# Mythic Repel mode (design ruling): the field REFLECTS enemy
		# projectiles instead of shoving mechs - ownership flips so the
		# reflected shot hunts enemies and credits us for the damage.
		# Runs per-frame, NOT on the 10Hz throttle: a fast bolt covers
		# 40-400px between 10Hz ticks and would tunnel straight through
		# the field. The "projectile" group is small; this stays cheap.
		if mech.magnet_repel_mode:
			for proj in EntityCache.get_group("projectile"):
				if not is_instance_valid(proj):
					continue
				if proj.get("fired_by_player") != false:
					continue # only enemy shots get turned
				if proj.global_position.distance_to(mech.global_position) > pull_radius:
					continue
				proj.fired_by_player = true
				proj.collision_mask = 4 | 1 | 32 # now hunts enemies + world + obstacles
				proj.source_mech = mech # damage credit / lifesteal to us
				if "was_reflected" in proj:
					proj.was_reflected = true
				var away = (proj.global_position - mech.global_position).normalized()
				if away == Vector2.ZERO:
					away = -proj.direction
				proj.direction = away
				if "target_direction" in proj:
					proj.target_direction = away
				proj.modulate = Color(1.6, 1.6, 2.2) # flash so the turn reads

		if mech._magnet_update_timer <= 0.0:
			mech._magnet_update_timer = 1.0 / mech.MAGNET_UPDATE_HZ
			var eff_delta = mech._magnet_accum_delta
			mech._magnet_accum_delta = 0.0

			var loot_nodes = EntityCache.get_group("loot")
			for loot in loot_nodes:
				if not is_instance_valid(loot):
					continue # cached snapshot - see EntityCache's caller contract
				if mech.min_loot_attract_rarity >= 0 and loot.has_method("get_rarity") and loot.get_rarity() < mech.min_loot_attract_rarity:
					continue # Mythic Magnet filter - not shiny enough to bother with
				if loot.global_position.distance_to(mech.global_position) < pull_radius:
					# Pull strength scales with power - same saturating
					# curve as pull_radius above.
					loot.pull_towards(mech.global_position, eff_delta * (0.5 + mech.MAGNET_PULL_SPEED_MAX_BONUS * magnet_power_factor))
	elif mech.magnet_visual:
		mech.magnet_visual.visible = false

# Visual feedback for how far the Magnet is currently reaching - previously
# the pull radius had zero on-screen representation, so there was no way to
# tell how strong/far a magnet build actually was without guessing from feel.
# Gold tint when a Mythic Magnet's rarity filter is active, cyan otherwise.
func _update_visual(pull_radius: float):
	if not mech.magnet_visual:
		mech.magnet_visual = Line2D.new()
		mech.magnet_visual.z_index = -1
		var pts = PackedVector2Array()
		for i in range(33):
			var a = i * TAU / 32.0
			pts.append(Vector2(cos(a), sin(a)))
		mech.magnet_visual.points = pts
		mech.add_child(mech.magnet_visual)

	mech.magnet_visual.visible = true
	mech.magnet_visual.scale = Vector2.ONE * pull_radius
	var is_filtered = mech.min_loot_attract_rarity >= 0
	var base_color = Color(1.0, 0.85, 0.2) if is_filtered else Color(0.3, 0.9, 1.0)
	var pulse = 0.35 + sin(Time.get_ticks_msec() / 200.0) * 0.15
	mech.magnet_visual.default_color = Color(base_color.r, base_color.g, base_color.b, pulse)
	# The node itself is scaled up to pull_radius to draw the ring at the
	# right size, which would also scale up the line width - counteract
	# that so the ring reads as a consistent ~2px outline regardless of how
	# large the pull radius is.
	mech.magnet_visual.width = 2.0 / max(1.0, pull_radius)

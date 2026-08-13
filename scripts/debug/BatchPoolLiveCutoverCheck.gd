extends Node

# Regression check for the live-combat batch-pool cutover ("okay, now how
# do I enable batch in gameplay?", 2026-08-11). Covers the pieces that
# didn't exist while the batch pool was Test-Range-only: friend/foe
# filtering (previously absent - safe only with the Test Range's single
# known-side dummy), stat_modifiers/range_mult threading through spawn()
# (previously silently dropped - would have been a hidden equipment-bonus
# nerf in real combat), sync_targets_from_groups(), and
# ProjectileManager.should_use_batch_pool()'s gating. Does NOT call
# SaveManager.set_batch_render_mode/set_batch_renderer_in_combat (those
# persist to the real user://settings.cfg) - flips the in-memory fields
# directly instead and restores them afterward.

const ProjectileBatchPoolScript = preload("res://scripts/entities/ProjectileBatchPool.gd")

var failures = 0

func _check(label: String, cond: bool):
	if cond:
		print("ok: " + label)
	else:
		push_error("FAIL: " + label)
		failures += 1

class _FakeTarget:
	extends Node
	var is_player: bool = false
	var is_dead: bool = false
	var broadphase_radius: float = 20.0

func _ready():
	# --- _is_valid_target_side: mirrors Projectile.gd's collision_mask split ---
	var enemy_target = _FakeTarget.new()
	enemy_target.is_player = false
	var player_target = _FakeTarget.new()
	player_target.is_player = true

	_check("a player-fired shot (fired_by_player=true) is valid against an enemy target (is_player=false)",
		ProjectileBatchPoolScript._is_valid_target_side(enemy_target, true))
	_check("a player-fired shot is INVALID against a player-side target (is_player=true) - no friendly fire",
		not ProjectileBatchPoolScript._is_valid_target_side(player_target, true))
	_check("an enemy-fired shot (fired_by_player=false) is valid against a player-side target",
		ProjectileBatchPoolScript._is_valid_target_side(player_target, false))
	_check("an enemy-fired shot is INVALID against another enemy target - no enemy-on-enemy fire",
		not ProjectileBatchPoolScript._is_valid_target_side(enemy_target, false))

	# --- _apply_stat_modifiers: direct port of Projectile.gd:609-621 -------
	var unmodified = ProjectileBatchPoolScript._apply_stat_modifiers(100.0, 500.0, {}, {})
	_check("empty stat_modifiers leaves damage/speed completely unchanged (the default, zero-behavior-change case)",
		unmodified["damage"] == 100.0 and unmodified["speed"] == 500.0)

	var dmg_scaled = ProjectileBatchPoolScript._apply_stat_modifiers(100.0, 500.0, {}, {"dmg_mult": 1.5})
	_check("dmg_mult applies as a flat multiplier regardless of ratios",
		abs(dmg_scaled["damage"] - 150.0) < 0.01)

	var spd_scaled = ProjectileBatchPoolScript._apply_stat_modifiers(100.0, 500.0, {}, {"spd_mult": 2.0})
	_check("spd_mult applies as a flat multiplier to speed, not damage",
		abs(spd_scaled["speed"] - 1000.0) < 0.01 and abs(spd_scaled["damage"] - 100.0) < 0.01)

	var kin_full = ProjectileBatchPoolScript._apply_stat_modifiers(100.0, 500.0,
		{EnergyPacket.SynergyType.KINETIC: 1.0}, {"kin_mult": 2.0})
	_check("kin_mult fully applies (2x) to a pure-Kinetic (ratio 1.0) shot",
		abs(kin_full["damage"] - 200.0) < 0.01)
	var kin_half = ProjectileBatchPoolScript._apply_stat_modifiers(100.0, 500.0,
		{EnergyPacket.SynergyType.KINETIC: 0.5}, {"kin_mult": 2.0})
	_check("kin_mult applies at half strength (1.5x) to a half-Kinetic-ratio blend - lerp, not a flat multiplier",
		abs(kin_half["damage"] - 150.0) < 0.01)
	var kin_absent = ProjectileBatchPoolScript._apply_stat_modifiers(100.0, 500.0, {}, {"kin_mult": 2.0})
	_check("kin_mult has zero effect on a shot with no Kinetic ratio at all",
		abs(kin_absent["damage"] - 100.0) < 0.01)

	# --- spawn(): new stat_modifiers/range_mult params default safely -----
	var pool = ProjectileBatchPoolScript.new(8)
	add_child(pool)

	# --- z_index (2026-08-13 fix: "invisible on the water map, visible in
	# the black void outside it") - the pool is a single long-lived node
	# created once at game start, but Main._rotate_campaign_map() creates a
	# brand-new MapGenerator and adds it to `world` on every map rotation,
	# landing it as a LATER sibling than this already-existing pool. Without
	# an explicit z_index, same-z_index sibling order took over and the
	# freshly rotated-in terrain drew on top of every batch shot from that
	# point on. z_index sidesteps sibling order entirely - must clear
	# terrain (MapGenerator chunk sprites, MechRenderer parts: 0-2).
	_check("ProjectileBatchPool sets an explicit z_index high enough to draw above terrain/mechs regardless of map-rotation sibling order",
		pool.z_index > 2)

	var i_default = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 100.0, 10.0, 2.0, Color.WHITE, 1.0, true, self)
	_check("spawn() omitting stat_modifiers/range_mult behaves exactly as before (existing call sites unaffected)",
		pool._damage[i_default] == 100.0 and pool._speed[i_default] == 500.0)
	var default_max_range = pool._max_range[i_default]

	var i_modified = pool.spawn(Vector2.ZERO, Vector2.RIGHT, 500.0, 100.0, 10.0, 2.0, Color.WHITE, 1.0, true, self,
		0, {}, {}, 0.0, {"dmg_mult": 2.0}, 2.0)
	_check("spawn() with stat_modifiers threads dmg_mult through to the stored damage",
		abs(pool._damage[i_modified] - 200.0) < 0.01)
	_check("spawn() with range_mult scales the stored max_range proportionally",
		abs(pool._max_range[i_modified] - default_max_range * 2.0) < 0.01)

	# --- sync_targets_from_groups(): pulls player+enemy+drone groups -------
	var fake_player = _FakeTarget.new()
	fake_player.name = "FakePlayerForSync"
	fake_player.is_player = true
	var fake_enemy = _FakeTarget.new()
	fake_enemy.name = "FakeEnemyForSync"
	fake_enemy.is_player = false
	add_child(fake_player)
	add_child(fake_enemy)
	fake_player.add_to_group("player")
	fake_enemy.add_to_group("enemy")
	pool.sync_targets_from_groups()
	_check("sync_targets_from_groups() populates _targets from the real 'player' and 'enemy' groups",
		pool._targets.has(fake_player) and pool._targets.has(fake_enemy))
	fake_player.remove_from_group("player")
	fake_enemy.remove_from_group("enemy")

	# --- ProjectileManager.should_use_batch_pool(): gated on BOTH the
	# setting AND a valid pool reference ------------------------------------
	var orig_setting = SaveManager.batch_renderer_in_combat
	var orig_pool_ref = ProjectileManager.live_batch_pool

	SaveManager.batch_renderer_in_combat = false
	ProjectileManager.live_batch_pool = pool
	_check("should_use_batch_pool() is false when the setting is off, even with a valid pool reference",
		not ProjectileManager.should_use_batch_pool())

	SaveManager.batch_renderer_in_combat = true
	ProjectileManager.live_batch_pool = null
	_check("should_use_batch_pool() is false when the setting is on but no pool reference exists yet",
		not ProjectileManager.should_use_batch_pool())

	SaveManager.batch_renderer_in_combat = true
	ProjectileManager.live_batch_pool = pool
	_check("should_use_batch_pool() is true only when both the setting is on AND a valid pool exists",
		ProjectileManager.should_use_batch_pool())

	# Restore real state - this check must not leave global autoload state
	# changed for whatever runs after it.
	SaveManager.batch_renderer_in_combat = orig_setting
	ProjectileManager.live_batch_pool = orig_pool_ref

	fake_player.queue_free()
	fake_enemy.queue_free()

	if failures == 0:
		print("PASS: friend/foe filtering blocks same-side hits both directions, stat_modifiers/range_mult thread through spawn() correctly (and default to zero-behavior-change when omitted), sync_targets_from_groups() pulls real groups, should_use_batch_pool() requires both the setting and a live pool reference, and the pool draws above terrain via z_index regardless of map-rotation sibling order")
	get_tree().quit(0 if failures == 0 else 1)

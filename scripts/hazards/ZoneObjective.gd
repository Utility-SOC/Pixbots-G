class_name ZoneObjective
extends Node2D

# Map-zone gameplay (Phase 2). Two kinds, both created by MapGenerator from the structure pass's zones:
#   "hold"  (forts)    stand inside the ring to fill it; it fills at full speed with only you inside,
#                      stalls while any living enemy is inside too (contested), and drains slowly when
#                      you leave. Full ring = a guaranteed salvage component whose rarity grows with the
#                      wave. One-shot per map.
#   "cache" (villages) walk up to the crate and it opens for a smaller salvage drop. One-shot.
# Rewards reuse LootManager's component builder, so every cache part is wired and routable.

const HOLD_SECONDS = 10.0
const DRAIN_RATE = 0.5 # fraction of the fill speed
const CACHE_OPEN_RADIUS = 44.0
const DONE_LINGER = 2.5

var kind: String = "hold"
var radius: float = 150.0
var progress: float = 0.0
var contested: bool = false
var done: bool = false
var reward_rarity_override: int = -1 # tests
var rewards_given: int = 0

var _linger := 0.0
var _redraw_t := 0.0

func _ready():
	add_to_group("zone_objective")
	z_index = -2

static func rarity_for_wave(wave: int, base: int) -> int:
	# Every 40 waves lifts the reward a tier, capped below Mythic (those stay boss-only).
	return clampi(base + wave / 40, HexTile.Rarity.COMMON, HexTile.Rarity.LEGENDARY)

func _process(delta: float):
	if done:
		_linger -= delta
		modulate.a = clampf(_linger / DONE_LINGER, 0.0, 1.0)
		if _linger <= 0.0:
			queue_free()
		return
	if kind == "cache":
		if _player_distance() <= CACHE_OPEN_RADIUS:
			_complete()
		return
	step(delta)
	_redraw_t += delta
	if _redraw_t >= 0.1:
		_redraw_t = 0.0
		queue_redraw()

# Advance the hold meter by `delta`; split from _process so tests can drive it.
func step(delta: float) -> void:
	if done:
		return
	var player_in = _player_distance() <= radius
	contested = player_in and _enemy_inside()
	if player_in and not contested:
		progress = minf(progress + delta / HOLD_SECONDS, 1.0)
	elif not player_in:
		progress = maxf(progress - delta / HOLD_SECONDS * DRAIN_RATE, 0.0)
	if progress >= 1.0:
		_complete()

func _player_distance() -> float:
	var players = EntityCache.get_group("player")
	if players.size() > 0 and is_instance_valid(players[0]) and players[0].get("is_dead") != true:
		return players[0].global_position.distance_to(global_position)
	return 1.0e9

func _enemy_inside() -> bool:
	for e in EntityCache.get_group("enemy"):
		if is_instance_valid(e) and e.get("is_dead") != true and e.global_position.distance_to(global_position) <= radius:
			return true
	return false

func _complete() -> void:
	if done:
		return
	done = true
	_linger = DONE_LINGER
	var loot = get_node_or_null("/root/LootManager")
	if loot != null:
		var base = HexTile.Rarity.RARE if kind == "hold" else HexTile.Rarity.UNCOMMON
		var rarity = reward_rarity_override if reward_rarity_override >= 0 else rarity_for_wave(loot.current_wave, base)
		var pack = loot._create_procedural_component(rarity, self, "Cache")
		loot._spawn_component_drop(self, pack)
		rewards_given += 1
	Sfx.play("pickup", global_position, 3.0)
	queue_redraw()

func _draw():
	if kind == "cache":
		var c = Color(0.85, 0.7, 0.3, 0.9) if not done else Color(0.5, 0.5, 0.5, 0.6)
		draw_rect(Rect2(-9, -7, 18, 14), c.darkened(0.4))
		draw_rect(Rect2(-9, -7, 18, 14), c, false, 2.0)
		draw_line(Vector2(-9, -1), Vector2(9, -1), c, 2.0)
		return
	var col = Color(0.4, 0.9, 0.5) if not contested else Color(1.0, 0.45, 0.35)
	if done:
		col = Color(0.6, 0.9, 1.0)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(col.r, col.g, col.b, 0.25), 3.0)
	if progress > 0.0:
		draw_arc(Vector2.ZERO, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, Color(col.r, col.g, col.b, 0.9), 5.0)
	draw_circle(Vector2.ZERO, 7.0, Color(col.r, col.g, col.b, 0.8))

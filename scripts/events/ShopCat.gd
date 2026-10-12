class_name ShopCat
extends Node2D

# The Shop Cat: a very rare visitor, like a sandstorm but friendlier. At a tiny chance per wave on any map the Shopkeeper's
# cat wanders onto the battlefield, trots up to the player, and sits. Stand next to it for a few seconds to pet it and it
# brings luck: three capture-point buffs for 90 s, a bit of scrap and a line from the Shopkeeper. Enemies ignore it and
# nothing can hurt it. It wanders off after a minute whether or not it was petted. All numbers (tune).

const CHANCE_PER_WAVE = 0.02
const SPAWN_DISTANCE = 520.0
const WALK_SPEED = 95.0
const SIT_DISTANCE = 64.0
const PET_RADIUS = 56.0
const PET_SECONDS = 2.5
const STAY_SECONDS = 60.0
const LUCK_SECONDS = 90.0
const BASE_SCRAP = 25
const SCRAP_PER_WAVE = 2

enum State { ARRIVING, SITTING, LEAVING }

var main: Node = null
var state: int = State.ARRIVING
var petted: bool = false
var pet_progress: float = 0.0
var _age: float = 0.0
var _leave_dir: Vector2 = Vector2.RIGHT
var _anim: float = 0.0

# The per-wave roll (pure, so tests can drive it).
static func should_spawn(r01: float, wave: int) -> bool:
	return wave >= 2 and r01 < CHANCE_PER_WAVE

# Called at the start of each wave. Returns the cat, or null when it does not show up.
static func maybe_spawn(main_node: Node, force: bool = false) -> ShopCat:
	if main_node == null or main_node.get("player") == null or not is_instance_valid(main_node.player):
		return null
	if not main_node.get_tree().get_nodes_in_group("shop_cat").is_empty():
		return null
	if not force and not should_spawn(SimRng.stream("event").randf(), int(main_node.get("current_wave"))):
		return null
	var cat = ShopCat.new()
	cat.main = main_node
	var angle = SimRng.stream("event").randf() * TAU
	var pos: Vector2 = main_node.player.global_position + Vector2.from_angle(angle) * SPAWN_DISTANCE
	var map = main_node.get("map")
	if map != null and map.has_method("get_valid_spawn_position"):
		pos = map.get_valid_spawn_position(pos)
	cat.global_position = pos
	cat._leave_dir = Vector2.from_angle(angle)
	var world = main_node.get("world")
	(world if world != null else main_node).add_child(cat)
	return cat

func _ready():
	add_to_group("shop_cat")
	z_index = 4
	queue_redraw()

func _player() -> Node2D:
	var players = EntityCache.get_group("player")
	if players.size() > 0 and is_instance_valid(players[0]) and players[0].get("is_dead") != true:
		return players[0]
	return null

func _process(delta: float):
	step(delta)
	_anim += delta
	if int(_anim * 6.0) != int((_anim - delta) * 6.0):
		queue_redraw()

# Advances the cat by `delta` seconds (split from _process so tests can drive it).
func step(delta: float) -> void:
	_age += delta
	var p = _player()
	match state:
		State.ARRIVING:
			if p == null:
				state = State.LEAVING
				return
			var to_p = p.global_position - global_position
			if to_p.length() <= SIT_DISTANCE:
				state = State.SITTING
			else:
				global_position += to_p.normalized() * WALK_SPEED * delta
			if _age > STAY_SECONDS:
				state = State.LEAVING
		State.SITTING:
			if p != null and p.global_position.distance_to(global_position) <= PET_RADIUS:
				pet_progress += delta
				if pet_progress >= PET_SECONDS and not petted:
					_reward(p)
			else:
				pet_progress = maxf(pet_progress - delta, 0.0)
			if _age > STAY_SECONDS or petted and pet_progress >= PET_SECONDS + 3.0:
				state = State.LEAVING
			elif petted:
				pet_progress += delta
		State.LEAVING:
			global_position += _leave_dir * WALK_SPEED * 1.4 * delta
			if _age > STAY_SECONDS + 8.0 or (petted and _age > 0.0 and global_position.distance_to(p.global_position if p != null else global_position) > SPAWN_DISTANCE * 1.5):
				queue_free()

func _reward(p: Node2D) -> void:
	petted = true
	var types: Array = CaptureBuffs.TYPES.duplicate()
	SimRng.shuffle("event", types)
	for i in range(mini(CaptureBuffs.MAX_ACTIVE, types.size())):
		if CaptureBuffs.grant(p, types[i]):
			p.capture_buffs[types[i]] = LUCK_SECONDS
	if p.has_method("_show_floating_text"):
		p._show_floating_text("CAT LUCK", Color(1.0, 0.8, 0.4))
	if main != null and is_instance_valid(main):
		var wave = int(main.get("current_wave")) if main.get("current_wave") != null else 1
		if main.get("player_scrap") != null:
			main.player_scrap += BASE_SCRAP + SCRAP_PER_WAVE * wave
		if main.has_method("show_dialogue"):
			main.show_dialogue("Shopkeeper", DialogueManager.get_shop_cat_line(), Color(1.0, 0.8, 0.5), 7.0)
	Sfx.play("pickup", global_position, 3.0)

func _draw():
	var orange = Color(0.92, 0.55, 0.2)
	var dark = Color(0.62, 0.34, 0.1)
	var cream = Color(0.98, 0.9, 0.75)
	var px = 3.0
	var sit = state == State.SITTING
	var bob = 0.0 if sit else (px if int(_anim * 6.0) % 2 == 0 else 0.0)
	# body
	draw_rect(Rect2(-4 * px, -3 * px - bob, 8 * px, 5 * px) if not sit else Rect2(-3 * px, -4 * px, 6 * px, 7 * px), orange)
	draw_rect(Rect2(-4 * px, -1 * px - bob, 8 * px, px) if not sit else Rect2(-3 * px, -1 * px, 6 * px, px), dark) # stripes
	draw_rect(Rect2(-4 * px, 1 * px - bob, 8 * px, px) if not sit else Rect2(-3 * px, 1 * px, 6 * px, px), dark)
	# head
	var hx = 3 * px if not sit else 0.0
	var hy = -5 * px - bob if not sit else -7 * px
	draw_rect(Rect2(hx - 2 * px, hy, 5 * px, 4 * px), orange)
	draw_rect(Rect2(hx - 2 * px, hy - px, px, px), dark) # ears
	draw_rect(Rect2(hx + 2 * px, hy - px, px, px), dark)
	draw_rect(Rect2(hx - px, hy + px, px, px), Color(0.1, 0.1, 0.1)) # eyes
	draw_rect(Rect2(hx + px, hy + px, px, px), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(hx, hy + 2 * px, px, px), cream) # nose and chin
	# tail, swishing
	var sw = px if int(_anim * 4.0) % 2 == 0 else -px
	draw_rect(Rect2(-5 * px if not sit else -4 * px, -3 * px + sw, px, 4 * px), dark)
	if sit and not petted and pet_progress <= 0.0 and _player() != null and _player().global_position.distance_to(global_position) < 140.0:
		draw_rect(Rect2(-px, -12 * px, 2 * px, 3 * px), Color(1, 1, 1)) # "!" bubble
		draw_rect(Rect2(-px, -8 * px, 2 * px, px), Color(1, 1, 1))
	if sit and pet_progress > 0.0 and not petted:
		draw_rect(Rect2(-12, 20, 24, 4), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-12, 20, 24.0 * clampf(pet_progress / PET_SECONDS, 0.0, 1.0), 4), Color(1.0, 0.7, 0.8))

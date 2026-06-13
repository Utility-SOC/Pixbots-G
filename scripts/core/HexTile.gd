class_name HexTile
extends Resource

enum TileCategory {
	CONDUIT, PROCESSOR, STORAGE, ROUTER, CONVERTER, OUTPUT, SPECIAL
}

enum Rarity {
	COMMON, UNCOMMON, RARE, LEGENDARY
}

enum BodySlot {
	NONE, TORSO, ARM_L, ARM_R, LEG_L, LEG_R, HEAD, BACKPACK
}

@export var tile_type: String = "Base"
@export var category: TileCategory = TileCategory.CONDUIT
@export var rarity: Rarity = Rarity.COMMON:
	set(val):
		rarity = val
		_roll_sync_adjustment()
		
@export var body_slot: BodySlot = BodySlot.NONE
@export var level: int = 1
@export var is_blocked: bool = false

var grid_position: HexCoord = null
var base_color: Color = Color.GRAY
var sync_adjustment: int = 0

func _roll_sync_adjustment():
	sync_adjustment = 0
	if rarity == Rarity.RARE:
		if randf() < 0.4:
			sync_adjustment = 1 if randf() < 0.5 else -1
	elif rarity == Rarity.LEGENDARY:
		if randf() < 0.8:
			var rolls = [1, -1, 2, -2]
			sync_adjustment = rolls[randi() % rolls.size()]

var max_hp: float = 30.0
var hp: float = 30.0
var is_disabled: bool = false
var disable_timer: float = 0.0
var times_disabled: int = 0
var time_since_last_hit: float = 0.0

func take_damage(amount: float):
	hp -= amount
	time_since_last_hit = 0.0
	if hp <= 0 and not is_disabled:
		is_disabled = true
		var base_cooldown = 3.0
		disable_timer = base_cooldown + (times_disabled * 2.0)
		times_disabled += 1
		hp = 0

func process_durability(delta: float):
	time_since_last_hit += delta
	if time_since_last_hit >= 5.0 and times_disabled > 0 and not is_disabled:
		times_disabled = 0
	
	if is_disabled:
		disable_timer -= delta
		if disable_timer <= 0:
			is_disabled = false
			hp = max_hp # Fully restored on reboot

func _init(_type: String = "Base", _category: TileCategory = TileCategory.CONDUIT):
	tile_type = _type
	category = _category

func process_energy(packet: EnergyPacket, entry_direction: int, grid: Node = null) -> Array[EnergyPacket]:
	if is_disabled:
		# Degraded capacity: acts as a straight pass-through, ignoring the tile's special logic
		return [packet]
	# Base implementation just passes it through
	return [packet]

func get_exit_direction(entry_direction: int) -> int:
	return (entry_direction + 3) % 6

func can_enter_from(direction: int) -> bool:
	return not is_blocked

# Specific variants can be created as subclasses extending HexTile

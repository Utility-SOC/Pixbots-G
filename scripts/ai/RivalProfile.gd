class_name RivalProfile
extends BossProfile

# A RivalProfile extends BossProfile to add specific constraints for the 
# 15 Yu-Gi-Oh! style named rivals (and PvP Ghost Clones).
# It enforces exact components or bans, and tracks their dialogue lines.

@export var rival_name: String = ""
@export var is_ghost: bool = false
@export var forced_components: Array[String] = []
@export var banned_components: Array[String] = []

# If true, the AutoEquipSolver is forced to use only Mythic rarity parts (e.g. Arthur).
@export var force_mythic_only: bool = false
# If true, the AutoEquipSolver is forced to use only Scavenged/Junk parts (e.g. Sammy).
@export var force_junk_only: bool = false

@export var dialogue_intro: String = ""
@export var dialogue_win: String = ""
@export var dialogue_loss: String = ""

# For Leo & Luna: 2v1 match. If > 1, SquadDirector spawns multiple Mechs.
@export var mech_count: int = 1

func _init(_name: String = "Rival", _base_role: String = "brawler"):
	super(_name, _base_role)
	rival_name = _name

func to_dict() -> Dictionary:
	var d = super.to_dict()
	d["rival_name"] = rival_name
	d["is_ghost"] = is_ghost
	d["forced_components"] = forced_components
	d["banned_components"] = banned_components
	d["force_mythic_only"] = force_mythic_only
	d["force_junk_only"] = force_junk_only
	d["dialogue_intro"] = dialogue_intro
	d["dialogue_win"] = dialogue_win
	d["dialogue_loss"] = dialogue_loss
	d["mech_count"] = mech_count
	return d

func from_dict(data: Dictionary):
	super.from_dict(data)
	if data.has("rival_name"): rival_name = data["rival_name"]
	if data.has("is_ghost"): is_ghost = bool(data["is_ghost"])
	
	if data.has("forced_components"):
		forced_components.clear()
		for c in data["forced_components"]:
			forced_components.append(str(c))
			
	if data.has("banned_components"):
		banned_components.clear()
		for c in data["banned_components"]:
			banned_components.append(str(c))
			
	if data.has("force_mythic_only"): force_mythic_only = bool(data["force_mythic_only"])
	if data.has("force_junk_only"): force_junk_only = bool(data["force_junk_only"])
	if data.has("dialogue_intro"): dialogue_intro = str(data["dialogue_intro"])
	if data.has("dialogue_win"): dialogue_win = str(data["dialogue_win"])
	if data.has("dialogue_loss"): dialogue_loss = str(data["dialogue_loss"])
	if data.has("mech_count"): mech_count = int(data["mech_count"])

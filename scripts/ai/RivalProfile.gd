class_name RivalProfile
extends BossProfile

# A RivalProfile extends BossProfile to add specific constraints for the
# 15 Yu-Gi-Oh! style named rivals (and PvP Ghost Clones).
# It enforces mythic-only/junk-only loadout constraints, and tracks their
# dialogue lines.

@export var rival_name: String = ""
@export var is_ghost: bool = false

# If true, the AutoEquipSolver is forced to use only Mythic rarity parts (e.g. Arthur).
@export var force_mythic_only: bool = false
# If true, the AutoEquipSolver is forced to use only Scavenged/Junk parts (e.g. Sammy).
@export var force_junk_only: bool = false

@export var dialogue_intro: String = ""
@export var dialogue_win: String = ""
@export var dialogue_loss: String = ""
# One-line flavor description of the rival's deck gimmick (from dialogue.json).
@export var gimmick: String = ""
# Round-scaling villain monologues from dialogue.json, keyed by round
# ("round_1".."round_3", "mythic").
@export var monologues: Dictionary = {}

# For Leo & Luna: 2v1 match. If > 1, SquadDirector spawns multiple Mechs.
@export var mech_count: int = 1

# For Chloe (the drone swarm rival): she carries a Jammer Module herself
# AND every one of her drones gets one too - each drone projects its own
# VISION-mode JammerField, and JammerField's existing proximity stacking
# (stack_multiplier compounds multiplicatively for same-side fields within
# JAMMER_LINK_RANGE) turns a clustered swarm into one huge combined
# jamming field, per the user: "she comes with a jammer, each of her
# drones should have one too so she has a huge jamming field built from
# their combined power." See Main._apply_rival_drone_jammers.
@export var drones_have_jammers: bool = false

# Total live drones this rival fields at spawn (0 = just whatever the
# build's Drone Bays naturally produce). Chloe's megaswarm: her intro
# promises "about twenty micro-bots" - extra drones beyond the bays are
# spawned from clones of her bay loadout (see Main._apply_rival_drone_
# profile / DroneBayTile.spawn_drone_swarm), each carrying its own jammer
# when drones_have_jammers is set, so the whole swarm's fields compound.
@export var drone_swarm_count: int = 0

func _init(_name: String = "Rival", _base_role: String = "brawler"):
	super(_name, _base_role)
	rival_name = _name

func to_dict() -> Dictionary:
	var d = super.to_dict()
	d["rival_name"] = rival_name
	d["is_ghost"] = is_ghost
	d["force_mythic_only"] = force_mythic_only
	d["force_junk_only"] = force_junk_only
	d["dialogue_intro"] = dialogue_intro
	d["dialogue_win"] = dialogue_win
	d["dialogue_loss"] = dialogue_loss
	d["gimmick"] = gimmick
	d["monologues"] = monologues
	d["mech_count"] = mech_count
	d["drones_have_jammers"] = drones_have_jammers
	d["drone_swarm_count"] = drone_swarm_count
	return d

func from_dict(data: Dictionary):
	super.from_dict(data)
	if data.has("rival_name"): rival_name = data["rival_name"]
	if data.has("is_ghost"): is_ghost = bool(data["is_ghost"])
	if data.has("force_mythic_only"): force_mythic_only = bool(data["force_mythic_only"])
	if data.has("force_junk_only"): force_junk_only = bool(data["force_junk_only"])
	if data.has("dialogue_intro"): dialogue_intro = str(data["dialogue_intro"])
	if data.has("dialogue_win"): dialogue_win = str(data["dialogue_win"])
	if data.has("dialogue_loss"): dialogue_loss = str(data["dialogue_loss"])
	if data.has("gimmick"): gimmick = str(data["gimmick"])
	if data.has("monologues"): monologues = data["monologues"].duplicate()
	if data.has("mech_count"): mech_count = int(data["mech_count"])
	if data.has("drones_have_jammers"): drones_have_jammers = bool(data["drones_have_jammers"])
	if data.has("drone_swarm_count"): drone_swarm_count = int(data["drone_swarm_count"])

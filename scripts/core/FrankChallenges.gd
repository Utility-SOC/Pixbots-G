class_name FrankChallenges
extends RefCounted

# Frank's Challenges: tactical puzzle scenarios. A fixed enemy set in a fixed arena under a rule that breaks the usual way of
# winning, so the build has to change rather than just grow. Pick one from the main menu (ChallengesMenu); Main runs it with
# a ChallengeRunner instead of waves. The rules (all relative to YOUR average shot, so they bite at any power level):
#   flat      every hit the enemies take is cut by a flat amount: many small hits vanish, a few big ones get through
#   eye       "The Eye": hits above a threshold are shrugged off (10%), hits at or below it do 150%: restrained builds win
#   shield    enemy shields are multiplied (burn through them or bypass them)
# Records (best time) are kept per challenge in settings.cfg [Challenges].

const CHALLENGES = [
	{"id": "thick_skin", "title": "Thick Skin", "brief": "Frank: Four hard-shelled brawlers. Every hit loses 60% of your average shot, flat. Spam will bounce.",
	 "map": "Sports Arena", "wave": 20, "enemies": [{"role": "brawler", "n": 4}], "rule": {"flat": 0.6}, "seconds": 150.0, "reward": 120},
	{"id": "the_eye", "title": "The Eye", "brief": "Frank: Neighborhood Watch sensor sweep. Anything stronger than a normal shot of yours makes it flinch away. Go gentle.",
	 "map": "Urban", "wave": 20, "enemies": [{"role": "scout", "n": 4}, {"role": "sniper", "n": 2}], "rule": {"eye": 1.0}, "seconds": 150.0, "reward": 140},
	{"id": "glass_parade", "title": "Glass Parade", "brief": "Frank: Twenty-four fragile little things, all at once. Don't run out of ammunition. You don't have ammunition. Run out of patience.",
	 "map": "Poppy Fields", "wave": 20, "enemies": [{"role": "scout", "n": 24}], "rule": {}, "seconds": 120.0, "reward": 100},
	{"id": "iron_wall", "title": "Iron Wall", "brief": "Frank: Three brawlers with triple shields. Break the bubble first or go around it.",
	 "map": "Military Base", "wave": 25, "enemies": [{"role": "brawler", "n": 3}], "rule": {"shield": 3.0}, "seconds": 150.0, "reward": 140},
	{"id": "sniper_alley", "title": "Sniper Alley", "brief": "Frank: Six snipers. They like distance. You will have to take it away.",
	 "map": "Munitions Range", "wave": 25, "enemies": [{"role": "sniper", "n": 6}], "rule": {}, "seconds": 180.0, "reward": 150},
	{"id": "coliseum_trial", "title": "Colosseum Trial", "brief": "Frank: A taste of the Elite Four stage. Sand, a crowd you can't see, and a commander with friends.",
	 "map": "Colosseum", "wave": 30, "enemies": [{"role": "commander", "n": 1}, {"role": "brawler", "n": 3}, {"role": "sniper", "n": 2}], "rule": {"shield": 1.5}, "seconds": 240.0, "reward": 220},
]

static func find(id: String) -> Dictionary:
	for c in CHALLENGES:
		if c["id"] == id:
			return c
	return {}

# The player's average shot damage (packet magnitude over the equipped weapons), the yardstick the rules scale from.
static func reference_shot(player: Node) -> float:
	var total = 0.0
	var n = 0
	if player != null and "precalculated_weapons" in player:
		for data in player.precalculated_weapons:
			total += float(data.packet.magnitude)
			n += 1
	return maxf(total / float(n), 1.0) if n > 0 else 1.0

# Applies a challenge's rule to one enemy mech.
static func apply_rule(bot: Node, rule: Dictionary, reference: float) -> void:
	if rule.has("flat"):
		bot.flat_damage_reduction = float(rule["flat"]) * reference
	if rule.has("eye"):
		bot.eye_threshold = float(rule["eye"]) * reference
	if rule.has("shield"):
		bot.max_shield_hp = maxf(bot.max_shield_hp, bot.max_hp * 0.5) * float(rule["shield"])
		bot.shield_hp = bot.max_shield_hp

# What the rule does to a hit of `amount` on a mech carrying these numbers (the same arithmetic MechDamage runs).
static func filter_hit(amount: float, flat_reduction: float, eye_threshold: float) -> float:
	if amount <= 0.0:
		return amount
	if flat_reduction > 0.0:
		amount = maxf(amount - flat_reduction, amount * 0.02)
	if eye_threshold > 0.0:
		amount = amount * 0.1 if amount > eye_threshold else amount * 1.5
	return amount

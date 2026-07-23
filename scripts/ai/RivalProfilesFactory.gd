class_name RivalProfilesFactory
extends RefCounted

static func create_profiles(dialogue_data: Dictionary) -> Dictionary:
	var profiles = {}
	var d_rivals = dialogue_data.get("rivals", {})
	
	# 1. Arthur
	var arthur = RivalProfile.new("Arthur", "brawler")
	arthur.force_mythic_only = true
	profiles["Arthur"] = arthur

	# 2. Beatrice
	var beatrice = RivalProfile.new("Beatrice", "jammer")
	# Perfect synergy - relies on AutoEquipSolver with maxed amplify
	profiles["Beatrice"] = beatrice

	# 3. Grog
	var grog = RivalProfile.new("Grog", "brawler")
	grog.hp_mult = 3.0
	grog.enrage_style = "juggernaut"
	profiles["Grog"] = grog

	# 4. Leo & Luna
	var leo_luna = RivalProfile.new("Leo & Luna", "ambusher")
	leo_luna.mech_count = 2
	leo_luna.position_style = "kiter"
	profiles["Leo & Luna"] = leo_luna

	# 5. Rudy
	var rudy = RivalProfile.new("Rudy", "flamethrower")
	rudy.enrage_style = "unstable"
	profiles["Rudy"] = rudy

	# 6. Professor P.
	var prof = RivalProfile.new("Professor P.", "jammer")
	# Poison and Fire logic will be set by giving him a Reactive Profile with Poison
	profiles["Professor P."] = prof

	# 7. Zane
	var zane = RivalProfile.new("Zane", "ambusher")
	zane.hp_mult = 0.5
	zane.position_style = "circler"
	profiles["Zane"] = zane

	# 8. Chloe - the drone-swarm rival ("she never fights alone"). Her
	# schtick: she carries a jammer and EVERY drone carries one too, so the
	# clustered swarm compounds into one huge jamming field via
	# JammerField's proximity stacking - see RivalProfile.drones_have_jammers.
	var chloe = RivalProfile.new("Chloe", "commander")
	chloe.drones_have_jammers = true
	chloe.drone_swarm_count = 20 # "expect about twenty micro-bots" - her intro line, honored literally
	profiles["Chloe"] = chloe

	# 9. Vance
	var vance = RivalProfile.new("Vance", "brawler")
	vance.position_style = "kiter"
	vance.hp_mult = 2.0
	profiles["Vance"] = vance

	# 10. Maya
	var maya = RivalProfile.new("Maya", "sniper")
	maya.position_style = "kiter"
	profiles["Maya"] = maya

	# 11. Declan
	var declan = RivalProfile.new("Declan", "commander")
	profiles["Declan"] = declan

	# 12. Jin
	var jin = RivalProfile.new("Jin", "brawler")
	jin.enrage_style = "unstable"
	profiles["Jin"] = jin

	# 13. Sammy
	var sammy = RivalProfile.new("Sammy", "brawler")
	sammy.force_junk_only = true
	profiles["Sammy"] = sammy

	# 14. Rex
	var rex = RivalProfile.new("Rex", "brawler")
	profiles["Rex"] = rex

	# Fill in dialogue from JSON
	for key in profiles.keys():
		var r: RivalProfile = profiles[key]
		if d_rivals.has(key):
			var d = d_rivals[key]
			r.dialogue_intro = d.get("intro", "")
			r.dialogue_win = d.get("win", "")
			r.dialogue_loss = d.get("loss", "")
			r.gimmick = d.get("gimmick", "")
			if d.has("monologues"):
				r.monologues = d["monologues"].duplicate()

	return profiles

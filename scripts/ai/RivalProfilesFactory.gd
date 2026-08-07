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

	# --- Elite Four (STORY_SCRIPT.md "## Elite Four" - unlocked after all 15
	# Regulars are beaten at least once, see SaveManager.all_regulars_defeated
	# / SquadDirector.get_next_rival's gating). One tier above the Regulars -
	# all get a meaningful hp_mult bump on top of their gimmick lever.

	# 15. Hrothgar (The Battle-Wizard) - huge telegraphed AoE mortars that
	# escalate the longer the fight runs. Kept at range (kiter), the chaotic
	# escalation reads as "unstable" (same enrage_style Rudy already uses for
	# his own building-chaos gimmick).
	var hrothgar = RivalProfile.new("Hrothgar", "sniper")
	hrothgar.position_style = "kiter"
	hrothgar.enrage_style = "unstable"
	hrothgar.hp_mult = 2.0
	profiles["Hrothgar"] = hrothgar

	# 16. Dan (The Barbarian) - starter-tier gear, zero Mythic parts, wins
	# purely on positioning/timing/aggression. force_junk_only is the same
	# lever Sammy already uses; the hp_mult compensates so a Common-rarity
	# loadout is still a real Elite-tier threat, matching "nobody can
	# explain how he's undefeated."
	var dan = RivalProfile.new("Dan", "brawler")
	dan.force_junk_only = true
	dan.enrage_style = "berserker"
	dan.position_style = "aggressive"
	dan.hp_mult = 2.5
	profiles["Dan"] = dan

	# 17. Evan (The Rogue) - deliberately under-powered chip damage, evasive,
	# hard to pin down, wears you down instead of racing for burst. Circler
	# keeps him mobile; vampiric enrage fits the "grinds you down over time"
	# read better than an escalating-damage style would.
	var evan = RivalProfile.new("Evan", "ambusher")
	evan.position_style = "circler"
	evan.enrage_style = "vampiric"
	evan.hp_mult = 1.75
	profiles["Evan"] = evan

	# 18. Joe (uses parts in unexpected ways) - explicitly under-designed per
	# STORY_SCRIPT.md's own admission ("Not fully worked out yet... Needs a
	# real design pass before this is playable"). Reasonable Elite-tier
	# placeholder only: commander fits "gets value out of configurations
	# nobody else would" better than a straight damage role until the real
	# hex-routing gimmick gets built.
	var joe = RivalProfile.new("Joe", "commander")
	joe.hp_mult = 2.0
	profiles["Joe"] = joe

	# 19. Frank (the shop owner himself - the twist finale). NOT part of the
	# Elite Four unlock gate and NOT added to SquadDirector's normal rival
	# pool - he's the Tournament bracket's own capstone fight, spawned
	# directly by Main.gd only after all 4 Elite Four are beaten within a
	# single Tournament run. Toughest fight in the game: two-ability kit and
	# the highest hp_mult of any profile, "no more nice guy behind the
	# counter."
	var frank = RivalProfile.new("Frank", "commander")
	frank.ability_pool = ["shockwave", "rally"]
	frank.enrage_style = "berserker"
	frank.position_style = "aggressive"
	frank.hp_mult = 3.5
	profiles["Frank"] = frank

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

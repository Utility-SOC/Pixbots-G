class_name MechGridSim
extends RefCounted

# Extracted from Mech.gd (docs: Status.md, engine-coupling cut). Holds no scene-tree state of its own;
# every instance method operates on the owning `mech`. Mech.gd keeps one-line wrappers so callers are unchanged.

var mech

func _init(p_mech = null):
	mech = p_mech

# Pure-GDScript reference implementation kept ONLY so PacketTaxParityCheck.gd
# can keep validating rust_ext/src/packet_tax.rs's correctness for whenever
# a real (full-frame-batched) call site gets built - NOT called from
# _shoot_impl above (see the block comment there for why).
static func _batch_scale_packets_fallback(requests: Array) -> Array:
	var out: Array = []
	for req in requests:
		var magnitude = req.magnitude * req.tax
		var synergies: Dictionary = {}
		for k in req.synergies:
			synergies[k] = req.synergies[k] * req.tax
		for jammed_id in req.jammed_synergies:
			if synergies.has(jammed_id):
				var suppressed = synergies[jammed_id] * 0.9
				magnitude = max(0.0, magnitude - suppressed)
				synergies[jammed_id] *= 0.1
		magnitude *= req.ambush_mult
		out.append({"magnitude": magnitude, "synergies": synergies})
	return out

func _recalculate_grid():
	var _t_recalc = Time.get_ticks_usec()
	_reset_grid_state()
	var _tp1 = Time.get_ticks_usec()
	_compute_mass_and_stat_modifiers()
	var _tp2 = Time.get_ticks_usec()

	if not mech.components.has(HexTile.BodySlot.TORSO):
		return

	var torso = mech.components[HexTile.BodySlot.TORSO]
	_simulate_energy_flow(torso)
	var _tp3 = Time.get_ticks_usec()
	_collect_weapon_mounts_and_tile_capabilities()
	var _tp4 = Time.get_ticks_usec()
	_finalize_grid_state()
	var _tp5 = Time.get_ticks_usec()
	if mech.is_player:
		mech._update_identity_synergy()
	Mech._perf_phase_usec[0] += _tp1 - _t_recalc
	Mech._perf_phase_usec[1] += _tp2 - _tp1
	Mech._perf_phase_usec[2] += _tp3 - _tp2
	Mech._perf_phase_usec[3] += _tp4 - _tp3
	Mech._perf_phase_usec[4] += _tp5 - _tp4
	Mech._perf_recalc_usec += Time.get_ticks_usec() - _t_recalc
	Mech._perf_recalc_calls += 1

func _reset_grid_state():
	mech._ai_shot_speed_cache = -1.0
	mech._ai_explosion_cache = -1.0
	mech.precalculated_weapons.clear()
	mech._charges_idle = false
	mech.lance_mounts.clear()
	mech.max_shield_hp = 0.0 # Reset shield HP
	mech.has_shield_generator = false
	mech.is_vortex_immune = false
	mech.vortex_pull_protection_ratio = 0.0
	mech.vortex_damage_reduction = 0.0
	mech.anchor_energy = 0.0
	mech.shield_recharge_delay = 3.0
	mech.shield_recharge_rate = 0.0
	mech.base_move_speed = 150.0 # Reset base speed for Jumpjets to calculate
	mech.jumpjet_rarity = -1
	mech.thruster_accel_bonus = -1
	mech.magnet_repel_mode = false
	mech.jumpjet_blink_mode = false
	mech.actuator_school = -1
	mech.shield_mythic_mode = -1

	if mech.jumpjet_energy == null:
		mech.jumpjet_energy = EnergyPacket.new(0.0, null)
	mech.jumpjet_energy.magnitude = 0.0
	mech.jumpjet_energy.synergies.clear()

	# Reset cloak/jammer-module/healer capability flags; they get rebuilt
	# below from whatever tiles are actually equipped this recalculation.
	mech.has_cloak_generator = false
	mech.max_cloak_charge = 0.0
	mech.cloak_recharge_rate = 0.0
	mech.cloak_recharge_delay = 1.0
	mech.shadow_share_radius = 0.0
	mech.shadow_stealth_fire = false
	mech.shadow_toggle_mode = false
	# smoke_charge (the current runtime charge, like cloak_charge) is
	# deliberately NOT reset here - only the build-derived capacity fields
	# get rebuilt below, same as cloak's own reset just above.
	mech.has_smoke_grenade = false
	mech.max_smoke_charge = 0.0
	mech.smoke_recharge_rate = 0.0
	mech.has_jammer_immunity = false
	mech.has_cloak_detection = false
	mech.sensor_sight_bonus = 0.0
	mech.has_elemental_aegis = false
	mech.has_shield_pulse = false
	mech.shield_pulse_power = 0.0
	mech.shield_pulse_radius = 0.0
	mech.has_jammer_module = false
	mech._jammer_tiles.clear()
	mech.has_healer = false
	mech.heal_pulse_power = 0.0
	mech.has_field_repair = false
	mech.repair_energy_flow = 0.0

	mech.total_magnetic_power = 0.0
	mech.min_loot_attract_rarity = -1
	mech.stat_modifiers.clear()
	mech.elemental_resistances.clear() # rebuilt below from equipped Structural Struts (elemental armor)
	mech.status_duration_mult.clear() # rebuilt below from equipped Stun/Shock/Freeze Guards
	mech._status_resist_sum.clear()
	mech.has_reactive_plating = false
	mech.reactive_plating_reflect_pct = 0.0

func _compute_mass_and_stat_modifiers():
	# Melee/mass physics pillar: total mass drives the movement-speed
	# penalty/bonus below (see update_status_effects) and the ramming
	# damage formula (see _process_ramming). Recomputed here rather than
	# every frame since it only changes on loadout edits, same as every
	# other grid-derived stat in this function.
	mech.total_mass = 0.0
	var mass_reduction_sum = 0.0
	for comp in mech.components.values():
		if comp.get("hex_grid") and not comp.is_broken:
			for t in comp.hex_grid.get_all_tiles():
				mech.total_mass += t.get_weight()
		if comp.get("mass_reduction"):
			mass_reduction_sum += float(comp.mass_reduction)
	# Overclocking's permanent mass-reduction reward - see MIN_TOTAL_MASS's
	# own comment for why this is floored rather than left unclamped.
	mech.total_mass = max(Mech.MIN_TOTAL_MASS, mech.total_mass - mass_reduction_sum)

	# Aggregate all component stat modifiers
	for comp in mech.components.values():
		if comp.get("stat_modifiers"):
			for k in comp.stat_modifiers:
				if mech.stat_modifiers.has(k):
					mech.stat_modifiers[k] += comp.stat_modifiers[k] - 1.0 # Additive percentage bonuses
				else:
					mech.stat_modifiers[k] = comp.stat_modifiers[k]

# Multi-phase torso->peripheral->return->re-simulate energy routing pass.
# `torso` is the already-resolved TORSO component (caller already guarded
# on it existing).
func _simulate_energy_flow(torso):
	for c in mech.components.values():
		if c and c.get("hex_grid"):
			c.hex_grid.reset_flow()
	# Collect energy from ALL generators in the Torso
	var initial_packets: Array[EnergyPacket] = []
	for coord in torso.hex_grid.grid.keys():
		var t = torso.hex_grid.get_tile(coord)
		if t.has_method("generate_energy"):
			var pkts = t.generate_energy(torso.hex_grid)
			for p in pkts:
				p.position = HexCoord.new(coord.x, coord.y)
			initial_packets.append_array(pkts)

	# PHASE 1: Route through Torso grid
	_simulate_grid(torso.hex_grid, initial_packets)

	# PHASE 2: Collect transferred packets from Sinks and route into peripheral grids
	var peripheral_transfer = _collect_transfers(torso)
	# Simulate HEAD and BACKPACK first so they can return energy
	var return_pkts: Array[EnergyPacket] = []
	for accessory_slot in [HexTile.BodySlot.HEAD, HexTile.BodySlot.BACKPACK]:
		if peripheral_transfer.has(accessory_slot) and mech.components.has(accessory_slot) and not mech.components[accessory_slot].is_broken:
			var accessory_comp = mech.components[accessory_slot]
			var a_pkts = peripheral_transfer[accessory_slot]
			_route_to_peripheral(a_pkts, accessory_comp)

			for coord in accessory_comp.hex_grid.grid.keys():
				var t = accessory_comp.hex_grid.get_tile(coord)
				if t.has_method("generate_energy"):
					var pkts = t.generate_energy(accessory_comp.hex_grid)
					for p in pkts:
						p.position = HexCoord.new(coord.x, coord.y)
					a_pkts.append_array(pkts)

			_simulate_grid(accessory_comp.hex_grid, a_pkts)

			# Collect return packets
			var accessory_return = _collect_transfers(accessory_comp)
			if accessory_return.has(HexTile.BodySlot.TORSO):
				return_pkts.append_array(accessory_return[HexTile.BodySlot.TORSO])

	if return_pkts.size() > 0:
		var return_pos = HexCoord.new(0, 0)
		var return_tile = null
		# Find the Accessory Return node
		for coord_v in torso.hex_grid.grid.keys():
			var t = torso.hex_grid.grid[coord_v]
			if t.tile_type == "Accessory Return":
				return_pos = HexCoord.new(coord_v.x, coord_v.y)
				return_tile = t
				break

		var final_return_pkts: Array[EnergyPacket] = []
		for pkt in return_pkts:
			if return_tile:
				# Process it through the Return Link
				var out = return_tile.process_energy(pkt, 0, torso.hex_grid)
				for p in out:
					p.position = return_pos
					p.is_active = true
					final_return_pkts.append(p)
			else:
				pkt.position = return_pos
				pkt.is_active = true
				final_return_pkts.append(pkt)

		# Re-simulate Torso with returned energy!
		_simulate_grid(torso.hex_grid, final_return_pkts)

		# Add any new transfers from Torso back into the peripheral pools
		var second_transfers = _collect_transfers(torso)
		for slot in second_transfers:
			if not peripheral_transfer.has(slot):
				peripheral_transfer[slot] = []
			peripheral_transfer[slot].append_array(second_transfers[slot])

	# Simulate remaining peripherals (Arms, Legs)
	for slot in mech.components.keys():
		if slot == HexTile.BodySlot.HEAD or slot == HexTile.BodySlot.BACKPACK or slot == HexTile.BodySlot.TORSO:
			continue # Already simulated

		var comp = mech.components[slot]
		if comp.is_broken:
			continue # a destroyed limb carries no energy
		var pkts: Array[EnergyPacket] = []
		if peripheral_transfer.has(slot):
			pkts.append_array(peripheral_transfer[slot])
			_route_to_peripheral(pkts, comp)

		# get_all_tiles() (not raw .grid.keys()) - footprint-safe, see
		# HexGridComponent.get_all_tiles's own comment.
		for t in comp.hex_grid.get_all_tiles():
			if t.has_method("generate_energy"):
				var generated = t.generate_energy(comp.hex_grid)
				for p in generated:
					p.position = t.grid_position
				pkts.append_array(generated)

		_simulate_grid(comp.hex_grid, pkts)

	for c in mech.components.values():
		if c and c.get("hex_grid"):
			c.hex_grid.flow_ready = true

func _collect_weapon_mounts_and_tile_capabilities():
	for comp in mech.components.values():
		if comp.is_broken:
			continue # destroyed limb: no weapons, no tile abilities
		for tile in comp.hex_grid.get_all_tiles():
			if tile.is_disabled or tile.power_lost:
				continue # knocked-out/destroyed tiles contribute nothing until rebooted/repaired
			if (tile.tile_type == "Weapon Mount" or tile.tile_type == "Missile Rack" or tile.tile_type == "Accessory Return" or tile.tile_type == "Torso Return") and "pending_packets" in tile and tile.pending_packets.size() > 0:
				# Accumulator split-fire model (the user's locked design):
				# whenever accumulators feed this mount - routed THROUGH the
				# circuit (packet.acc_*_mult) or sitting adjacent (bank) -
				# the mount gets TWO fully independent weapons:
				#   - NORMAL entry: the un-boosted packet. Mouse-fired,
				#     behaves almost as if no accumulator existed (small
				#     quality tax) - EXCEPT that while the big shot is still
				#     charging, the accumulator siphons HALF the payload.
				#     Once the big shot sits full, the siphon stops and
				#     normal shots return to full strength.
				#   - BANK entry: the big charged shot. Charges passively,
				#     fired ONLY by pressing its 1/2/3 key - one press, one
				#     big hit. Clicking never touches it.
				var bank_charge = 0.0
				var bank_amplify = 0.0
				var bank_quality = 1.0
				var bank_auto_dump = 0.0
				var reverse_discount = 0.0
				var chopper_split = 1
				if (tile.tile_type == "Weapon Mount" or tile.tile_type == "Missile Rack") and tile.grid_position:
					var bank = _get_adjacent_accumulator_bonus(comp.hex_grid, tile.grid_position)
					bank_charge = bank.charge
					bank_amplify = bank.amplify
					bank_quality = bank.quality
					bank_auto_dump = bank.auto_dump
					# Reverse Accumulator: floored at 0.75 total so a mount can
					# never be discounted below 25% of its real charge time,
					# no matter how many adjacent tiles contribute.
					reverse_discount = min(0.75, _get_adjacent_reverse_accumulator_discount(comp.hex_grid, tile.grid_position))
					# Chopper (renamed-in-place ReverseAccumulatorTile.gd):
					# separate ability from the discount above - how many
					# smaller shots this mount's one combined release gets
					# split into, see _get_adjacent_chopper_split_factor.
					chopper_split = _get_adjacent_chopper_split_factor(comp.hex_grid, tile.grid_position)

				# Detect routed-through accumulators via the recorded mults
				var probe = tile.pending_packets[0].packet
				for i in range(1, tile.pending_packets.size()):
					if tile.pending_packets[i].packet.acc_damage_mult > probe.acc_damage_mult:
						probe = tile.pending_packets[i].packet
				var has_routed_acc = probe.acc_damage_mult > 1.001

				# Firing quanta (shared Mythic dial - see HexTile.
				# get_frame_multiplier_options()/cycle_mythic_frame_
				# multiplier(), and WeaponMountTile.gd's field comment for
				# why this replaced the old standalone energy-threshold
				# system). 1 = "Auto," fire whenever charged.
				var frame_multiplier = tile.get("mythic_frame_multiplier")
				if frame_multiplier == null:
					frame_multiplier = 1

				if frame_multiplier > 1 or tile.tile_type == "Missile Rack":
					var combined = tile.pending_packets[0].packet.copy()
					for i in range(1, tile.pending_packets.size()):
						combined.merge(tile.pending_packets[i].packet)

					combined.charge_required *= float(frame_multiplier)
					combined.magnitude *= float(frame_multiplier)
					for k in combined.synergies:
						combined.synergies[k] *= float(frame_multiplier)
					combined.chopper_split = chopper_split

					mech.precalculated_weapons.append({
						"mount": tile,
						"packet": combined,
						"step": 0,
						"slot_type": comp.slot_type
					})
				elif bank_charge > 0.0 or has_routed_acc:
					var combined = tile.pending_packets[0].packet.copy()
					for i in range(1, tile.pending_packets.size()):
						combined.merge(tile.pending_packets[i].packet)
					# Adjacent (bank) accumulators tax normal fire the same
					# way routed-through ones do - worst neighbor wins.
					combined.accumulator_quality = min(combined.accumulator_quality, bank_quality)

					# Bank entry: the big charged shot. Boosts from routed
					# accumulators (acc_damage_mult) and adjacent bank
					# accumulators (bank_amplify) combine; charge time is the
					# base cost scaled by acc_charge_mult plus the adjacency
					# bank's own charge. Fired ONLY by pressing its 1/2/3 key
					# (PlayerController.fire_charged); AI auto-releases on full
					# (_tick_weapon_charges). The mouse never fires this.
					var enhanced = combined.copy()
					enhanced.amplify(combined.acc_damage_mult * (1.0 + bank_amplify))
					enhanced.charge_required = (combined.charge_required * combined.acc_charge_mult + bank_charge) * (1.0 - reverse_discount)
					enhanced.trigger_key = combined.trigger_key if combined.trigger_key != "None" else "1"
					# Auto-dump: routed-through accumulators stamped the packet
					# already (copy/merge carry it); adjacent bank accumulators
					# contribute theirs here - highest threshold wins.
					enhanced.auto_dump_threshold = max(enhanced.auto_dump_threshold, bank_auto_dump)
					# Chopper split applies to the alpha-strike bank shot only -
					# deliberately NOT stamped onto normal_entry below (the
					# small continuous mouse-fire side has no "alpha strike"
					# to redistribute, and splitting it would just add
					# pointless recursion/projectile overhead to already-
					# frequent shots).
					enhanced.chopper_split = chopper_split

					# Normal-fire entry: the base (unamplified) packet, at
					# whatever charge_required routing naturally gave it.
					# While the bank below is still charging, _shoot() halves
					# this entry's payload (the accumulator is siphoning);
					# bank_required is stashed here so _shoot can tell.
					var normal_entry = combined.copy()
					normal_entry.charge_required *= Mech.RAPID_FIRE_CHARGE_MULT * (1.0 - reverse_discount)
					mech.precalculated_weapons.append({
						"mount": tile,
						"packet": normal_entry,
						"step": 0,
						"slot_type": comp.slot_type,
						"bank_mode": "normal",
						"bank_required": enhanced.charge_required
					})

					mech.precalculated_weapons.append({
						"mount": tile,
						"packet": enhanced,
						"step": 0,
						"slot_type": comp.slot_type,
						"bank_mode": "bank"
					})
				else:
					var step_groups = {}
					for item in tile.pending_packets:

						var step = item.step
						if not step_groups.has(step):
							step_groups[step] = item.packet.copy()
						else:
							step_groups[step].merge(item.packet)

					for step in step_groups:
						step_groups[step].charge_required *= Mech.RAPID_FIRE_CHARGE_MULT * (1.0 - reverse_discount)
						step_groups[step].chopper_split = chopper_split
						mech.precalculated_weapons.append({
							"mount": tile,
							"packet": step_groups[step],
							"step": step,
							"slot_type": comp.slot_type
						})
				tile.clear_pending()

			# Missile Rack deliberately NOT included here despite also being a
			# capital-weapon-style mount - unlike Lance Mount/Orbiting Array,
			# it has no cooldown_timer/ready_to_fire/fire() interface at all
			# (see MissileRackTile.gd's header: it fires through the exact
			# same pending_packets/precalculated_weapons pipeline as a plain
			# Weapon Mount, gated above at "tile_type == Weapon Mount or
			# Missile Rack"). It used to be included in this OR chain, which
			# pushed MissileRackTile instances into lance_mounts - crashed
			# _tick_weapon_charges's "lance.cooldown_timer" read below with
			# "Invalid access to property or key 'cooldown_timer' on a base
			# object of type 'Resource (MissileRackTile)'" the moment one was
			# equipped (user-reported, 2026-08-05).
			if (tile.tile_type == "Lance Mount" or tile.tile_type == "Orbiting Array") and tile.has_method("clear_pending"):
				mech.lance_mounts.append(tile)
				# Lance Mount's ready_to_fire is only ever computed by
				# check_face_gate() (unlike Orbiting Array, which sets
				# ready_to_fire inline inside process_energy) - without this
				# call clear_pending() below wipes _face_magnitudes first and
				# the gate never gets checked, so a Lance Mount can never fire
				# in real gameplay (only the debug parity check called
				# check_face_gate directly).
				if tile.has_method("check_face_gate"):
					tile.check_face_gate()
				tile.clear_pending()

			if tile.has_method("get_speed_bonus"):
				mech.base_move_speed += tile.get_speed_bonus()

			if tile.has_method("get_magnetic_power"):
				mech.total_magnetic_power += tile.get_magnetic_power()

			if tile.has_method("get_min_attract_rarity"):
				var filter_rarity = tile.get_min_attract_rarity()
				if filter_rarity >= 0:
					# Most permissive combination if multiple magnets disagree
					mech.min_loot_attract_rarity = filter_rarity if mech.min_loot_attract_rarity < 0 else min(mech.min_loot_attract_rarity, filter_rarity)

			# Mythic Magnet in Repel mode / Mythic Jumpjet in Blink mode
			if tile.tile_type == "Magnet" and tile.rarity == HexTile.Rarity.MYTHIC and tile.get("repel_mode") == true:
				mech.magnet_repel_mode = true
			if tile.tile_type == "Jumpjet" and tile.rarity == HexTile.Rarity.MYTHIC and int(tile.get("mythic_mode")) == 1:
				mech.jumpjet_blink_mode = true

			if tile.tile_type == "Actuator" and tile.rarity == HexTile.Rarity.MYTHIC:
				mech.actuator_school = int(tile.get("mythic_mode"))

			if tile.tile_type == "Shield Generator" and tile.rarity == HexTile.Rarity.MYTHIC:
				mech.shield_mythic_mode = int(tile.get("mythic_mode"))

			if tile.tile_type == "Anchor":
				mech.is_vortex_immune = true
				if tile.has_method("get_anchor_energy"):
					mech.anchor_energy += tile.get_anchor_energy()
					mech.vortex_pull_protection_ratio = max(mech.vortex_pull_protection_ratio, AnchorTile.protection_for(mech.anchor_energy))
					mech.vortex_damage_reduction = max(mech.vortex_damage_reduction, AnchorTile.damage_reduction_for(mech.anchor_energy))
				if tile.rarity == HexTile.Rarity.MYTHIC:
					mech.vortex_pull_protection_ratio = max(mech.vortex_pull_protection_ratio, 0.5)
					mech.vortex_damage_reduction = max(mech.vortex_damage_reduction, 0.25)

			if tile.tile_type == "Shield Generator" and tile.has_method("get_shield_energy"):
				mech.has_shield_generator = true
				var shield_energy = tile.get_shield_energy()
				# Scale directly 1:1 with energy to allow tanking own hits
				mech.max_shield_hp += shield_energy
				# Mythic takes .25s, Legendary takes 0.5s, Rare takes 1.0s, Uncommon 2.0s, Common 3.0s
				if tile.rarity == HexTile.Rarity.MYTHIC:
					mech.shield_recharge_delay = min(mech.shield_recharge_delay, 0.25)
				elif tile.rarity == HexTile.Rarity.LEGENDARY:
					mech.shield_recharge_delay = min(mech.shield_recharge_delay, 0.5)
				elif tile.rarity == HexTile.Rarity.RARE:
					mech.shield_recharge_delay = min(mech.shield_recharge_delay, 1.0)
				elif tile.rarity == HexTile.Rarity.UNCOMMON:
					mech.shield_recharge_delay = min(mech.shield_recharge_delay, 2.0)
				else:
					mech.shield_recharge_delay = min(mech.shield_recharge_delay, 3.0)

				# Rapidly recharge (e.g. fully recharge in 2 seconds)
				mech.shield_recharge_rate += mech.max_shield_hp * 0.5

				if tile.has_method("get_shield_synergies"):
					var syns = tile.get_shield_synergies()
					for k in syns:
						if mech.shield_synergies.has(k):
							mech.shield_synergies[k] += syns[k]
						else:
							mech.shield_synergies[k] = syns[k]

			if tile.tile_type == "Cloak Generator" and tile.has_method("get_cloak_energy"):
				mech.has_cloak_generator = true
				var cloak_energy_amount = tile.get_cloak_energy()
				mech.max_cloak_charge += cloak_energy_amount
				var duration = tile.get_cloak_duration() if tile.has_method("get_cloak_duration") else 3.0
				var recharge_time = tile.get_recharge_time() if tile.has_method("get_recharge_time") else 6.0
				mech.cloak_drain_rate = mech.max_cloak_charge / max(0.1, duration)
				mech.cloak_recharge_rate += mech.max_cloak_charge / max(0.1, recharge_time)
				# Corporate Sponsorships: Shadow Systems' AllyCloakTile - see
				# Mech.gd's shadow_* field block for what these unlock.
				if tile.brand_id == "cloak" and tile.has_method("get_ally_share_radius"):
					mech.shadow_share_radius = max(mech.shadow_share_radius, tile.get_ally_share_radius())
					mech.shadow_stealth_fire = true
					mech.shadow_toggle_mode = true

			if tile.tile_type == "Smoke Grenade" and tile.has_method("get_smoke_energy"):
				mech.has_smoke_grenade = true
				mech.max_smoke_charge += tile.get_smoke_energy()
				var recharge_time = tile.get_recharge_time() if tile.has_method("get_recharge_time") else 8.0
				mech.smoke_recharge_rate += mech.max_smoke_charge / max(0.1, recharge_time)
				if tile.has_method("get_smoke_radius"):
					mech.smoke_radius = tile.get_smoke_radius()
				if tile.has_method("get_smoke_duration"):
					mech.smoke_duration = tile.get_smoke_duration()

			if tile.tile_type == "Jammer Module" and tile.has_method("get_jam_energy"):
				# All modules are kept so _update_jammer_module can drain their
				# routed packet energy every frame (feeds the field's power
				# scaling) - no consume-and-discard here anymore.
				mech._jammer_tiles.append(tile)
				if not mech.has_jammer_module: # first module found sets the profile
					mech.has_jammer_module = true
					mech.jammer_pulse_radius = tile.get_pulse_radius()
					mech.jammer_pulse_interval = tile.get_pulse_interval()
					mech.jammer_effect_duration = tile.get_effect_duration()
					mech.jammer_mode = tile.jam_mode
					mech.jammer_target_synergy = tile.target_synergy
					if mech.jammer_pulse_timer <= 0.0:
						mech.jammer_pulse_timer = mech.jammer_pulse_interval

				# Corporate Sponsorships: Aegis Dynamics' AegisJammerShieldTile
				# rides on the Jammer Module capacity block above (it inherits
				# JammerModuleTile) - the shield-pulse and elemental Aegis are
				# a genuinely separate concern, detected here via brand_id.
				if tile.brand_id == "defensive" and tile.has_method("get_shield_pulse_power"):
					mech.has_elemental_aegis = true
					mech.has_shield_pulse = true
					mech.shield_pulse_power = max(mech.shield_pulse_power, tile.get_shield_pulse_power())
					mech.shield_pulse_radius = max(mech.shield_pulse_radius, tile.get_shield_pulse_radius())
					mech.shield_pulse_interval = tile.get_shield_pulse_interval()

			if tile.tile_type == "Heal Beacon" and tile.has_method("get_heal_energy"):
				mech.has_healer = true
				var _heal_e: float = tile.get_heal_energy()
				mech.heal_pulse_power += _heal_e * 0.1
				if tile.has_method("is_field_repair") and tile.is_field_repair():
					mech.has_field_repair = true
					mech.repair_energy_flow += _heal_e
				mech.heal_pulse_radius = tile.get_pulse_radius()
				mech.heal_pulse_interval = tile.get_pulse_interval()

			# Corporate Sponsorships: Velocity Works' MobilityCoreTile - a
			# self-contained reactor, so it grants capacity UNCONDITIONALLY
			# from mere presence rather than needing a routed packet like
			# JumpjetTile/ActuatorTile do (see MobilityCoreTile.gd's header).
			if tile.tile_type == "Mobility Core" and tile.brand_id == "mobility":
				mech.jumpjet_rarity = max(mech.jumpjet_rarity, tile.rarity)
				mech.thruster_accel_bonus = max(mech.thruster_accel_bonus, tile.rarity)

			# Corporate Sponsorships: Keeneye Sensing's SensorTile family - see
			# SensorTile.gd's header for what jammer_immunity/cloak_detection
			# actually resolve to.
			if tile.tile_type == "Sensor Array" and tile.has_method("get_sensor_mode"):
				var sensor_mode = tile.get_sensor_mode()
				if sensor_mode == "jammer" or sensor_mode == "both":
					mech.has_jammer_immunity = true
				if sensor_mode == "cloak" or sensor_mode == "both":
					mech.has_cloak_detection = true
				if tile.has_method("get_sight_bonus"):
					mech.sensor_sight_bonus = max(mech.sensor_sight_bonus, tile.get_sight_bonus())

			# Elemental armor (Structural Strut, design request). Passive,
			# no routing required - RAW means unconfigured/inert, same
			# convention as Elemental Infuser. Stacks MULTIPLICATIVELY per
			# tile (like layered armor plates) rather than additively, so
			# it approaches but never reaches full immunity to an element
			# no matter how many Struts are piled on.
			if tile.tile_type == "Structural Strut" and tile.secondary_synergy != EnergyPacket.SynergyType.RAW:
				var armor_element = EnergyPacket.element_name(tile.secondary_synergy)
				var per_strut_reduction = clamp(
					TileStatsRegistry.get_stat("StructuralStrutTile", "armor_reduction_base", 0.03)
						+ (tile.rarity * TileStatsRegistry.get_stat("StructuralStrutTile", "armor_reduction_rarity_coeff", 0.02)),
					0.0, 0.5)
				mech.elemental_resistances[armor_element] = mech.elemental_resistances.get(armor_element, 1.0) * (1.0 - per_strut_reduction)

			# Stun / Shock / Freeze Guards: passive, unconditional from presence. Stack multiplicatively with a floor
			# (the tile's max_resist), so piling on cells has diminishing returns and never reaches full immunity.
			if tile.has_method("get_guard_energy") and not tile.get_resisted_statuses().is_empty():
				# Resistance is proportional to the energy fed in (see StatusResistTile.gd); several Guards of one
				# kind add up, capped at the tile's max_resist, so nobody is ever fully immune. The energy is read ONCE
				# and applies to every status the tile covers (a Remediation Matrix covers them all).
				var guard_resist: float = tile.resist_for_energy(tile.get_guard_energy())
				for status_name in tile.get_resisted_statuses():
					var total_resist: float = minf(mech._status_resist_sum.get(status_name, 0.0) + guard_resist, tile.get_max_resist())
					mech._status_resist_sum[status_name] = total_resist
					mech.status_duration_mult[status_name] = 1.0 - total_resist

			# Reactive Plating (design request: "reactive armor options
			# which melee mechs will abuse" - see the field comment on
			# has_reactive_plating for the full trigger design). Passive,
			# unconditional from presence, same as Anchor. Stacks
			# ADDITIVELY (not multiplicatively like the armor above) but
			# capped, since this is "how much of a single incoming hit
			# bounces back" rather than a per-plate independent mitigation
			# layer - uncapped additive stacking could reflect MORE than
			# 100% of a hit with enough plates.
			if tile.tile_type == "Reactive Plating":
				mech.has_reactive_plating = true
				var per_plate_pct = TileStatsRegistry.get_stat("ReactivePlatingTile", "reflect_pct_base", 0.08) \
					+ (tile.rarity * TileStatsRegistry.get_stat("ReactivePlatingTile", "reflect_pct_rarity_coeff", 0.05))
				var reflect_cap = TileStatsRegistry.get_stat("ReactivePlatingTile", "reflect_pct_cap", 0.6)
				mech.reactive_plating_reflect_pct = min(mech.reactive_plating_reflect_pct + per_plate_pct, reflect_cap)

func _finalize_grid_state():
	# Find dominant shield synergy
	var max_syn_val = 0.0
	for k in mech.shield_synergies:
		if mech.shield_synergies[k] > max_syn_val:
			max_syn_val = mech.shield_synergies[k]
			mech.dominant_shield_synergy = str(k)

	# Keep shield HP within bounds
	mech.shield_hp = min(mech.shield_hp, mech.max_shield_hp)
	if not mech.has_shield_generator:
		mech.shield_hp = 0.0

	# Heat profile of this circuit - commented out along with the rest of the
	# thermal system (see HEAT_CAPACITY's comment above). Self-contained:
	# heat_rate/heat_ice_frac/heat_ltg_frac are only ever read by the now-
	# commented _update_heat(), so nothing else in _recalculate_grid depends
	# on this block running.
	#heat_rate = 0.0
	#var _syn_totals: Dictionary = {}
	#var _syn_sum: float = 0.0
	#for data in precalculated_weapons:
	#	heat_rate += data.packet.charge_required * 0.03
	#	for k in data.packet.synergies:
	#		_syn_totals[k] = _syn_totals.get(k, 0.0) + data.packet.synergies[k]
	#		_syn_sum += data.packet.synergies[k]
	#heat_ice_frac = (_syn_totals.get(EnergyPacket.SynergyType.ICE, 0.0) / _syn_sum) if _syn_sum > 0.0 else 0.0
	#heat_ltg_frac = (_syn_totals.get(EnergyPacket.SynergyType.LIGHTNING, 0.0) / _syn_sum) if _syn_sum > 0.0 else 0.0
	#heat_rate *= (1.0 - 2.0 * heat_ice_frac)

	# Enemy element doctrine (ElementCombos): a combo bot's finished weapons lean into its interacting element pair.
	if not mech.is_player and not mech.element_combo.is_empty():
		ElementCombos.retint_weapons(mech)

	# Enemies deploy mostly pre-primed (70-100% charged): a fresh squad
	# shouldn't spend its opening seconds unable to shoot, and the player
	# shouldn't get a free alpha-strike window on every spawn. Once only -
	# mid-fight grid recalcs (damage, jamming) must NOT re-fill charges.
	if not mech.is_player and not mech._spawn_primed:
		mech._spawn_primed = true
		for data in mech.precalculated_weapons:
			var frac = SimRng.stream("combat").randf_range(0.7, 1.0)
			if data.get("bank_mode", "") == "bank":
				data.mount.bank_current_charge = data.packet.charge_required * frac
			else:
				data.mount.current_charge = data.packet.charge_required * frac
		mech._charges_idle = false # priming left weapons partly charged: they have to recharge

	for comp in mech.components.values():
		_sync_contiguous_accumulator_shortcuts(comp.hex_grid)

	mech.is_grid_dirty = false

# Every Accumulator in a hex-contiguous cluster shares one bank/shortcut
# feel: manually keying each one individually was the actual friction (place
# 3 Accumulators, set the same key 3 times) rather than a meaningful
# choice, so a cluster now auto-adopts whichever explicit key (if any) one
# of its members already has. "Lowest" key wins on a conflicting cluster
# (two different keys placed in one contiguous group) so the outcome is
# deterministic rather than depending on flood-fill visit order.
func _sync_contiguous_accumulator_shortcuts(grid: HexGridComponent):
	var visited: Dictionary = {}
	for coord_v in grid.grid.keys():
		if visited.has(coord_v):
			continue
		var tile = grid.grid[coord_v]
		if tile.tile_type != "Accumulator":
			continue

		var cluster: Array = []
		var queue = [coord_v]
		visited[coord_v] = true
		while queue.size() > 0:
			var cur_v = queue.pop_back()
			cluster.append(grid.grid[cur_v])
			var cur_coord = HexCoord.new(cur_v.x, cur_v.y)
			for d in range(6):
				var n = cur_coord.neighbor(d)
				var nv = Vector2i(n.q, n.r)
				if visited.has(nv) or not grid.grid.has(nv):
					continue
				if grid.grid[nv].tile_type == "Accumulator":
					visited[nv] = true
					queue.append(nv)

		if cluster.size() <= 1:
			continue

		var best_key = "None"
		for t in cluster:
			if t.trigger_key != "None" and (best_key == "None" or t.trigger_key < best_key):
				best_key = t.trigger_key
		if best_key != "None":
			for t in cluster:
				t.trigger_key = best_key

# Sums get_bank_charge()/get_bank_amplify() from every Accumulator tile
# directly hex-adjacent to `coord` within `grid` - see AccumulatorTile.gd
# and the capacitor-bank branch in the precalculated_weapons loop above.
# static: uses no instance state at all (pure function of grid/coord), so
# WeaponMountTile.get_threshold_options() can call it directly without
# needing a live Mech instance around - see that function's own comment.
static func _get_adjacent_accumulator_bonus(grid: HexGridComponent, coord: HexCoord) -> Dictionary:
	var total_charge = 0.0
	var total_amplify = 0.0
	var worst_quality = 1.0
	var max_auto_dump = 0.0
	for d in range(6):
		var n = coord.neighbor(d)
		if grid.has_tile(n):
			var neighbor_tile = grid.get_tile(n)
			if neighbor_tile.tile_type == "Accumulator" and neighbor_tile.has_method("get_bank_charge"):
				total_charge += neighbor_tile.get_bank_charge()
				total_amplify += neighbor_tile.get_bank_amplify()
				if neighbor_tile.has_method("get_quality_factor"):
					worst_quality = min(worst_quality, neighbor_tile.get_quality_factor())
				max_auto_dump = max(max_auto_dump, float(neighbor_tile.get("auto_dump_threshold")))
	return {"charge": total_charge, "amplify": total_amplify, "quality": worst_quality, "auto_dump": max_auto_dump}

# Mirror of _get_adjacent_accumulator_bonus above, for ReverseAccumulatorTile
# (the literal inverse - shaves charge_required down instead of up). Kept as
# a separate scan rather than folded into the one above since the two tile
# types contribute to entirely different things (bank charge/amplify vs a
# flat discount on whatever charge_required a mount already has) and mixing
# them into one Dictionary return would make both harder to read. Multiple
# adjacent Reverse Accumulators stack additively; floored at the call site
# (see below) so a mount can never reach free/negative charge time.
static func _get_adjacent_reverse_accumulator_discount(grid: HexGridComponent, coord: HexCoord) -> float:
	var total_discount = 0.0
	for d in range(6):
		var n = coord.neighbor(d)
		if grid.has_tile(n):
			var neighbor_tile = grid.get_tile(n)
			# tile_type is "Chopper" now (renamed in place from "Reverse
			# Accumulator" - see ReverseAccumulatorTile.gd's _init()); the
			# class/file/get_charge_discount() are unchanged.
			if neighbor_tile.tile_type == "Chopper" and neighbor_tile.has_method("get_charge_discount"):
				total_discount += neighbor_tile.get_charge_discount()
	return total_discount

# New, separate from _get_adjacent_accumulator_bonus's dict above (a
# different stat - the capacity CEILING, not bank_charge/bank_amplify) -
# see HexTile.get_frame_multiplier_options().
# Returns the highest HexTile.Rarity tier this mount's adjacent
# Accumulators collectively qualify for (see HexTile.ACCUMULATOR_CAPACITY_
# TIERS/ACCUMULATOR_TIER_CHECK_ORDER for the ceiling+count-required table),
# or -1 if no Accumulator is adjacent at all (Auto only). Counting is
# cumulative (rarity-or-higher): a mix of rarities all count toward a
# lower tier's requirement, since a higher-rarity Accumulator is always at
# least as good as a lower one - only the ACHIEVED tier (the highest one
# whose count requirement is met) matters, not which specific rarities
# made it up.
static func _get_adjacent_accumulator_capacity_tier(grid: HexGridComponent, coord: HexCoord) -> int:
	var counts_by_rarity: Dictionary = {}
	for d in range(6):
		var n = coord.neighbor(d)
		if grid.has_tile(n):
			var neighbor_tile = grid.get_tile(n)
			if neighbor_tile.tile_type == "Accumulator":
				counts_by_rarity[neighbor_tile.rarity] = counts_by_rarity.get(neighbor_tile.rarity, 0) + 1
	if counts_by_rarity.is_empty():
		return -1

	for check_rarity in HexTile.ACCUMULATOR_TIER_CHECK_ORDER:
		var cumulative_count = 0
		for r in counts_by_rarity:
			if int(r) >= check_rarity:
				cumulative_count += counts_by_rarity[r]
		var required = HexTile.ACCUMULATOR_CAPACITY_TIERS[check_rarity][1]
		if cumulative_count >= required:
			return check_rarity
	return -1

# Mirrors the shape above for Chopper. Unlike the capacity bonus (which
# EXTENDS a mount's own pre-existing dial), a mount has no split ability
# at all without a Chopper present, so this IS the split factor outright,
# not an addend: zero/only-default-dialed adjacent Choppers correctly
# floors to 1 (no split); one Chopper dialed to 2 gives a 2-way split;
# two Choppers each dialed to 2 combine additively to a 4-way split.
static func _get_adjacent_chopper_split_factor(grid: HexGridComponent, coord: HexCoord) -> int:
	var total = 0
	for d in range(6):
		var n = coord.neighbor(d)
		if grid.has_tile(n):
			var neighbor_tile = grid.get_tile(n)
			# dial == 1 is the off/default state - excluded, not just summed
			# (a default-dialed Chopper sitting next to a REAL dialed one
			# must not silently add a spurious +1 to the split factor).
			if neighbor_tile.tile_type == "Chopper" and neighbor_tile.rarity == HexTile.Rarity.MYTHIC and "mythic_split_factor" in neighbor_tile and int(neighbor_tile.mythic_split_factor) > 1:
				total += int(neighbor_tile.mythic_split_factor)
	return max(1, total)

func _collect_transfers(comp) -> Dictionary:
	var result = {}
	for t in comp.hex_grid.get_all_tiles():
		if t.tile_type.ends_with("Link") or t.tile_type == "Accessory Return" or t.tile_type == "Torso Return":
			if t.has_method("get_pending_transfers"):
				var transfer_pkts = t.get_pending_transfers()
				if transfer_pkts.size() > 0:
					if not result.has(t.target_slot):
						result[t.target_slot] = []
					result[t.target_slot].append_array(transfer_pkts)
	return result

func _route_to_peripheral(pkts: Array, comp):
	for pkt in pkts:
		var opp_dir = (pkt.direction + 3) % 6
		pkt.position = HexCoord.new(0, 0).neighbor(opp_dir)
		pkt.is_active = true

# force_gdscript: parity-harness escape hatch (RustGridSimParityCheck.gd
# runs both paths on identical grids and diffs the results) - never set in
# real gameplay.
func _simulate_grid(grid: HexGridComponent, starting_packets: Array, force_gdscript: bool = false):
	# Rust fast path (rust_ext/src/hexgrid_sim.rs, Phase 1 of the
	# pixbots_core split): one FFI call runs the whole packet-routing loop
	# for grids composed entirely of supported tile kinds, with results
	# written back onto the real tiles - identical to the loop below by
	# construction and held identical by the parity check. Any grid with an
	# unsupported (stateful/conditional) tile falls through to the original
	# GDScript path automatically.
	if not force_gdscript and Mech.RustGridSimBridge.try_simulate(grid, starting_packets):
		Mech._perf_sim_rust_calls += 1
		return
	Mech._perf_sim_gd_calls += 1

	var active_packets: Array[EnergyPacket] = []
	for pkt in starting_packets:
		if pkt.position == null:
			pkt.position = HexCoord.new(0, 0)
		pkt.traversal_steps = 0
		active_packets.append(pkt)
		
	var steps = 0
	# Safety cap to prevent infinite loops from closed circuits (this still
	# runs once per loadout change via _recalculate_grid, never per-frame,
	# so a generous cap costs nothing in practice). Raised from the
	# original 100 - the Mythic-overcharge feature (see EnergyPacket.
	# NORMAL_MAGNITUDE_CAP) deliberately rewards long closed annexes of
	# Mythic tiles that build energy for a while before dropping it to a
	# sink/weapon; on a large Mythic torso, simply CROSSING the grid once
	# can take well over 100 steps on its own, which silently dropped every
	# packet before it ever reached a Link tile - "tons of energy going to
	# the left arm link, nothing inside the left arm" (the Torso's own live
	# view uses a separate, uncapped-until-natural-drain engine, so it
	# looked like the energy was there and simply never arriving).
	# Lowered from 1000 (2026-08-10 live playtest: wave 9-12 bot spawning
	# collapsed to 2-7fps - _recalculate_grid() was costing ~200ms PER BOT,
	# because common-rarity builds with no Mythic-overcharge intent at all
	# were routinely hitting the full 1000-step cap on plain Reflector/edge-
	# bounce loops that never resolve to zero active packets on their own -
	# NOT the intentional Mythic-overcharge mechanic (that's explicitly
	# about all-Mythic annexes building magnitude before releasing it, and
	# is unaffected by this: MythicOverchargeSplitCheck.gd's split/bounce
	# behavior resolves in a handful of steps regardless of this cap, and
	# LongPathStepCapCheck.gd's legitimate 150-step straight-line crossing
	# stays comfortably inside 200). Combined with the negligible-packet
	# cull just below (user's own proposal), which lets DECAY-capable loops
	# (ones crossing empty hexes, which lose 5% magnitude per pass) resolve
	# well before ever reaching this cap - pure Reflector/edge-bounce loops
	# never decay at all, so for THOSE this cap is what actually bounds the
	# cost, not the cull.
	const SIMULATE_GRID_STEP_CAP = 200
	# Negligible-packet culling (user's own proposal, 2026-08-10): a packet
	# that's decayed to a trivial fraction of the energy actually in play
	# is rounding-error noise, not a meaningful part of the build - letting
	# it keep consuming simulation steps forever (it can never merge away
	# since merge only fires for exact position+direction matches) is pure
	# waste. Two floors, matching the user's own framing exactly:
	#   - an absolute floor for low-total builds (their own example: "some
	#     4 energy packets running around" - well under the ~600 energy
	#     single-packet baseline this game's payload scale standardizes
	#     around, per Status.md's own design directive).
	#   - a floor relative to the CURRENT total active energy for high-
	#     total (Mythic-overcharge-scale) builds - "greater than 1,200,000
	#     energy total" is their own number; 0.05% of that (~600, the same
	#     baseline) is "a rounding error" by comparison to a real overcharge
	#     loop, without touching the loop's actual dominant packets at all.
	const NEGLIGIBLE_MAGNITUDE_FLOOR = 2.0
	const HIGH_TOTAL_ENERGY_THRESHOLD = 1200000.0
	const HIGH_TOTAL_RELATIVE_CULL_FRACTION = 0.0005
	while active_packets.size() > 0 and steps < SIMULATE_GRID_STEP_CAP:
		steps += 1

		var next_packets: Array[EnergyPacket] = []

		for p in active_packets:
			if not p.is_active: continue
			var dir = p.direction
			var next_pos = p.position.neighbor(dir)

			if grid.has_tile(next_pos):
				var tile = grid.get_tile(next_pos)
				p.traversal_steps += 1
				if "sync_adjustment" in tile:
					p.traversal_steps += tile.sync_adjustment
					p.traversal_steps = max(0, p.traversal_steps)

				var entering = p
				# Mythic overcharge cap (EnergyPacket.NORMAL_MAGNITUDE_CAP):
				# a packet that built past the normal cap by staying inside
				# an all-Mythic path/loop can't dump all of that into a
				# lesser tile - only NORMAL_MAGNITUDE_CAP worth enters, the
				# rest reflects back into the loop it came from.
				if tile.rarity != HexTile.Rarity.MYTHIC and p.magnitude > EnergyPacket.NORMAL_MAGNITUDE_CAP:
					if not p.reflected and tile.grid_position and grid.has_method("record_overload"):
						grid.record_overload(Vector2i(tile.grid_position.q, tile.grid_position.r), p.magnitude)
					entering = p.split(EnergyPacket.NORMAL_MAGNITUDE_CAP / p.magnitude)
					p.direction = (dir + 3) % 6
					p.reflected = true
					next_packets.append(p)
				else:
					p.reflected = false

				grid.record_flow(Vector2i(tile.grid_position.q, tile.grid_position.r) if tile.grid_position else Vector2i(next_pos.q, next_pos.r), 1.0, entering.magnitude, -1, false)
				if grid.has_method("record_entry"):
					grid.record_entry(Vector2i(tile.grid_position.q, tile.grid_position.r) if tile.grid_position else Vector2i(next_pos.q, next_pos.r), (dir + 3) % 6)
				var out_pkts = tile.process_energy(entering, (dir + 3) % 6, grid, next_pos)
				for out in out_pkts:
					out.position = next_pos
					out.traversal_steps = p.traversal_steps
				next_packets.append_array(out_pkts)
			else:
				var comp = grid.get_parent()
				var is_valid_empty = false
				# O(1) membership check via ComponentEquipment's _valid_hex_set
				# mirror instead of a linear valid_hexes scan - this runs every
				# routing step for every packet crossing an empty hex, so on a
				# 72-100 hex Mythic component this was a real per-step cost.
				if comp and "_valid_hex_set" in comp and comp.has_method("_hex_key"):
					is_valid_empty = comp._valid_hex_set.has(comp._hex_key(next_pos.q, next_pos.r))
				elif comp and "valid_hexes" in comp:
					for h in comp.valid_hexes:
						if h.q == next_pos.q and h.r == next_pos.r:
							is_valid_empty = true
							break
							
				if is_valid_empty:
					# Pass straight through empty hex with 5% energy loss
					var pass_p = p.copy()
					pass_p.position = next_pos
					pass_p.traversal_steps += 1
					pass_p.magnitude *= 0.95
					for k in pass_p.synergies.keys():
						pass_p.synergies[k] *= 0.95
					next_packets.append(pass_p)
				else:
					# Edge bounce: reflect 180 degrees
					var bounce_p = p.copy()
					bounce_p.direction = (dir + 3) % 6
					bounce_p.position = p.position # Stay on the current tile
					bounce_p.traversal_steps = p.traversal_steps
					next_packets.append(bounce_p)
		
		var merged_packets = {}
		for p in next_packets:
			if not p.is_active: continue
			# Merge packets arriving at same tile with same direction. Packed
			# into a single int key instead of a concatenated String - this
			# runs every routing step for every active packet (up to 100
			# steps x every packet on the grid), and integer hashing/equality
			# is far cheaper than allocating+hashing a new String each time.
			# Offset is generous headroom well beyond any real mech's hex
			# grid extents, so q/r never collide even if negative.
			var key = ((p.position.q + 4096) * 8192 + (p.position.r + 4096)) * 8 + p.direction
			if merged_packets.has(key):
				merged_packets[key].merge(p)
			else:
				merged_packets[key] = p
				
		active_packets.assign(merged_packets.values())

		# Negligible-packet cull (user's own proposal, 2026-08-10). Exempts
		# any packet whose NEXT hop would land on a real tile (2026-08-11
		# fix) - simply moving this check to run after movement instead of
		# before it turned out to be a no-op (a packet's "after this step"
		# state IS the array the next iteration's "before movement" check
		# sees - textually different position, same point in the timeline).
		# The real bug: a packet freshly split off by a Splitter is created
		# AT the splitter's own hex, not yet moved into whatever real tile
		# is one hex further along its intended path - it still needs a
		# genuine SECOND loop iteration to actually reach and register at
		# that tile (a Link capturing it, another Splitter branching it
		# further, a Reflector redirecting it). The floor was killing it in
		# the gap between those two iterations, even though it was already
		# correctly routed and about to complete real, intended progress -
		# not "wandering pointlessly," which is what this cull is actually
		# for (Reflector/edge-bounce loops and empty-hex passes that never
		# resolve on their own). Real, demonstrated impact: a Common-rarity
		# starter Torso's single-active-face Core (Core.get_max_faces()==1
		# by design) forces every one of its 6 limb links through one
		# serial daisy-chain of splits, each roughly halving the packet's
		# magnitude - anything past ~2 hops deep got killed one hop short
		# of its real target every time, even though the solver had
		# genuinely wired a real, connected path to it (AutoEquipSolver
		# TorsoCheck.gd's own real-simulation assertions catch exactly
		# this). Exempting "about to hit a real tile" packets preserves the
		# original perf intent exactly: a packet that's ACTUALLY just
		# bouncing/passing through empty space with nothing left to
		# contribute still gets culled the moment that becomes true, same
		# as before - only genuinely-still-in-transit packets survive.
		var total_active_magnitude = 0.0
		for p in active_packets:
			if p.is_active:
				total_active_magnitude += p.magnitude
		var relative_floor = 0.0
		if total_active_magnitude > HIGH_TOTAL_ENERGY_THRESHOLD:
			relative_floor = total_active_magnitude * HIGH_TOTAL_RELATIVE_CULL_FRACTION
		var cull_floor = max(NEGLIGIBLE_MAGNITUDE_FLOOR, relative_floor)
		for p in active_packets:
			if p.is_active and p.magnitude < cull_floor:
				var about_to_hit_tile = grid.has_tile(p.position.neighbor(p.direction))
				if not about_to_hit_tile:
					p.is_active = false
	if active_packets.size() > 0 and steps >= SIMULATE_GRID_STEP_CAP:
		grid.sim_saturated = true

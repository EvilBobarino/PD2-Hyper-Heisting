local mvec3_set = mvector3.set
local mvec3_add = mvector3.add
local mvec3_dot = mvector3.dot
local mvec3_sub = mvector3.subtract
local mvec3_mul = mvector3.multiply
local mvec3_norm = mvector3.normalize
local mvec3_dir = mvector3.direction
local mvec3_set_l = mvector3.set_length
local mvec3_len = mvector3.length
local math_clamp = math.clamp
local math_lerp = math.lerp
local tmp_vec1 = Vector3()
local tmp_vec2 = Vector3()
local tmp_rot1 = Rotation()

Hooks:PostHook(PlayerDamage, "init", "hhpost_lives", function(self, unit)
	self._lives_init = tweak_data.player.damage.LIVES_INIT

	if Global.game_settings.one_down then
		self._lives_init = tweak_data.player.damage.LIVES_INIT
	end

	self._lives_init = managers.modifiers:modify_value("PlayerDamage:GetMaximumLives", self._lives_init)
	self._unit = unit
	self._max_health_reduction = managers.player:upgrade_value("player", "max_health_reduction", 1)
	self._healing_reduction = managers.player:upgrade_value("player", "healing_reduction", 1)
	self._revives = Application:digest_value(0, true)
	self._uppers_elapsed = 0

	self:replenish()

	local player_manager = managers.player
	self._bleed_out_health = Application:digest_value(tweak_data.player.damage.BLEED_OUT_HEALTH_INIT * player_manager:upgrade_value("player", "bleed_out_health_multiplier", 1), true)
	self._god_mode = Global.god_mode
	self._invulnerable = false
	self._mission_damage_blockers = {}
	self._gui = Overlay:newgui()
	self._ws = self._gui:create_screen_workspace()
	self._focus_delay_mul = 1
	self._dmg_interval = tweak_data.player.damage.MIN_DAMAGE_INTERVAL
	self._next_allowed_dmg_t = Application:digest_value(-100, true)
	self._last_received_dmg = 0
	self._next_allowed_sup_t = -100
	self._last_received_sup = 0
	self._supperssion_data = {}
	self._inflict_damage_body = self._unit:body("inflict_reciever")

	self._inflict_damage_body:set_extension(self._inflict_damage_body:extension() or {})

	local body_ext = PlayerBodyDamage:new(self._unit, self, self._inflict_damage_body)
	self._inflict_damage_body:extension().damage = body_ext

	managers.sequence:add_inflict_updator_body("fire", self._unit:key(), self._inflict_damage_body:key(), self._inflict_damage_body:extension().damage)

	self._doh_data = tweak_data.upgrades.damage_to_hot_data or {}
	self._damage_to_hot_stack = {}
	self._armor_stored_health = 0
	self._can_take_dmg_timer = 0
	self._regen_on_the_side_timer = 0
	self._regen_on_the_side = false
	self._interaction = managers.interaction
	self._armor_regen_mul = managers.player:upgrade_value("player", "armor_regen_time_mul", 1)
	self._dire_need = managers.player:has_category_upgrade("player", "armor_depleted_stagger_shot")
	self._has_damage_speed = managers.player:has_inactivate_temporary_upgrade("temporary", "damage_speed_multiplier")
	self._has_damage_speed_team = managers.player:upgrade_value("player", "team_damage_speed_multiplier_send", 0) ~= 0

	local function revive_player()
		self:revive(true)
	end

	managers.player:register_message(Message.RevivePlayer, self, revive_player)

	self._current_armor_fill = 0
	local has_swansong_skill = player_manager:has_category_upgrade("temporary", "berserker_damage_multiplier")
	self._current_state = nil
	self._listener_holder = unit:event_listener()

	if player_manager:has_category_upgrade("player", "damage_to_armor") then
		local damage_to_armor_data = player_manager:upgrade_value("player", "damage_to_armor", nil)
		local armor_data = tweak_data.blackmarket.armors[managers.blackmarket:equipped_armor(true, true)]

		if damage_to_armor_data and armor_data then
			local idx = armor_data.upgrade_level
			self._damage_to_armor = {
				armor_value = damage_to_armor_data[idx][1],
				target_tick = damage_to_armor_data[idx][2],
				elapsed = 0
			}

			local function on_damage(damage_info)
				local attacker_unit = damage_info and damage_info.attacker_unit

				if alive(attacker_unit) and attacker_unit:base() and attacker_unit:base().thrower_unit then
					attacker_unit = attacker_unit:base():thrower_unit()
				end

				if self._unit == attacker_unit then
					local time = Application:time()

					if self._damage_to_armor.target_tick < time - self._damage_to_armor.elapsed then
						self._damage_to_armor.elapsed = time

						self:restore_armor(self._damage_to_armor.armor_value, true)
					end
				end
			end

			CopDamage.register_listener("on_damage", {
				"on_damage"
			}, on_damage)
		end
	end

	self._listener_holder:add("on_use_armor_bag", {
		"on_use_armor_bag"
	}, callback(self, self, "_on_use_armor_bag_event"))

	if self:_init_armor_grinding_data() then
		function self._on_damage_callback_func()
			return callback(self, self, "_on_damage_armor_grinding")
		end

		self:_add_on_damage_event()
		self._listener_holder:add("on_enter_bleedout", {
			"on_enter_bleedout"
		}, callback(self, self, "_on_enter_bleedout_event"))

		if has_swansong_skill then
			self._listener_holder:add("on_enter_swansong", {
				"on_enter_swansong"
			}, callback(self, self, "_on_enter_swansong_event"))
			self._listener_holder:add("on_exit_swansong", {
				"on_enter_bleedout"
			}, callback(self, self, "_on_exit_swansong_event"))
		end

		self._listener_holder:add("on_revive", {
			"on_revive"
		}, callback(self, self, "_on_revive_event"))
	else
		self:_init_standard_listeners()
	end

	if player_manager:has_category_upgrade("temporary", "revive_damage_reduction") then
		self._listener_holder:add("combat_medic_damage_reduction", {
			"on_revive"
		}, callback(self, self, "_activate_combat_medic_damage_reduction"))
	end

	if player_manager:has_category_upgrade("player", "revive_damage_reduction") and player_manager:has_category_upgrade("player", "revive_damage_reduction") then
		local function on_revive_interaction_start()
			managers.player:set_property("revive_damage_reduction", player_manager:upgrade_value("player", "revive_damage_reduction"), 1)
		end

		local function on_exit_interaction()
			managers.player:remove_property("revive_damage_reduction")
		end

		local function on_revive_interaction_success()
			managers.player:activate_temporary_upgrade("temporary", "revive_damage_reduction")
		end

		self._listener_holder:add("on_revive_interaction_start", {
			"on_revive_interaction_start"
		}, on_revive_interaction_start)
		self._listener_holder:add("on_revive_interaction_interrupt", {
			"on_revive_interaction_interrupt"
		}, on_exit_interaction)
		self._listener_holder:add("on_revive_interaction_success", {
			"on_revive_interaction_success"
		}, on_revive_interaction_success)
	end

	managers.mission:add_global_event_listener("player_regenerate_armor", {
		"player_regenerate_armor"
	}, callback(self, self, "_regenerate_armor"))
	managers.mission:add_global_event_listener("player_force_bleedout", {
		"player_force_bleedout"
	}, callback(self, self, "force_into_bleedout", false))

	local level_tweak = tweak_data.levels[managers.job:current_level_id()]

	if level_tweak and level_tweak.is_safehouse and not level_tweak.is_safehouse_combat then
		self:set_mission_damage_blockers("damage_fall_disabled", true)
		self:set_mission_damage_blockers("invulnerable", true)
	end

	self._delayed_damage = {
		epsilon = 0.001,
		chunks = {}
	}

	self:clear_delayed_damage()
end)

Hooks:PostHook(PlayerDamage, "damage_melee", "hhpost_dmgmelee", function(self, attack_data)
	local player_unit = managers.player:player_unit()
	local cur_state = self._unit:movement():current_state_name()
	if attack_data then
		local next_allowed_dmg_t = type(self._next_allowed_dmg_t) == "number" and self._next_allowed_dmg_t or Application:digest_value(self._next_allowed_dmg_t, false)
		local t = managers.player:player_timer():time()
		
		--enemies were meleeing players and taking their guns away during invincibility frames and thats no bueno
		
		if alive(attack_data.attacker_unit) and not self:is_downed() and not self._bleed_out and not self._dead and cur_state ~= "fatal" and cur_state ~= "bleedout" and not self._invulnerable and not self._unit:character_damage().swansong and not self._unit:movement():tased() and not self._mission_damage_blockers.invulnerable and not self._god_mode and not self:incapacitated() and not self._unit:movement():current_state().immortal and next_allowed_dmg_t and next_allowed_dmg_t < t then
			if alive(player_unit) and self._unit:movement():current_state().on_melee_stun and tostring(attack_data.attacker_unit:base()._tweak_table) ~= "fbi" and tostring(attack_data.attacker_unit:base()._tweak_table) ~= "fbi_xc45" then
				self._unit:movement():current_state():on_melee_stun(managers.player:player_timer():time(), 0.8)
			end
		end
		
		if alive(attack_data.attacker_unit) and not self:is_downed() and not self._bleed_out and not self._dead and cur_state ~= "fatal" and cur_state ~= "bleedout" and not self._invulnerable and not self._unit:character_damage().swansong and not self._unit:movement():tased() and not self._mission_damage_blockers.invulnerable and not self._god_mode and not self:incapacitated() and not self._unit:movement():current_state().immortal and Global.game_settings.one_down then
			if tostring(attack_data.attacker_unit:base()._tweak_table) == "fbi" or tostring(attack_data.attacker_unit:base()._tweak_table) == "fbi_xc45" then
				if alive(player_unit) then
					managers.player:set_player_state("arrested") --fbis can cuff players on shin mode
				end
			end	
		end
	end
end)

function PlayerDamage:clbk_kill_taunt(attack_data) -- just a nice little detail
	if attack_data.attacker_unit and attack_data.attacker_unit:alive() then
		if not attack_data.attacker_unit:base()._tweak_table then
			return
		end
		
		self._kill_taunt_clbk_id = nil
		if attack_data.attacker_unit:base():has_tag("tank") then
			attack_data.attacker_unit:sound():say("post_kill_taunt")
		elseif attack_data.attacker_unit:base():has_tag("law") and not attack_data.attacker_unit:base():has_tag("special") then	
			attack_data.attacker_unit:sound():say("i03")
		else
			--nothing
		end
	end
end

function PlayerDamage:has_jackpot_token()
	return self._jackpot_token
end

function PlayerDamage:activate_jackpot_token()
	self._jackpot_token = true
	--log("this party's gettin crazy")
end

function PlayerDamage:_regenerated(no_messiah)
	self:set_health(self:_max_health())
	self:_send_set_health()
	self:_set_health_effect()
	self._jackpot_token = nil

	self._said_hurt = false
	self._revives = Application:digest_value(self._lives_init + managers.player:upgrade_value("player", "additional_lives", 0), true)
	self._revive_health_i = 1

	managers.environment_controller:set_last_life(false)

	self._down_time = tweak_data.player.damage.DOWNED_TIME

	if not no_messiah then
		self._messiah_charges = managers.player:upgrade_value("player", "pistol_revive_from_bleed_out", 0)
	end
end

function PlayerDamage:_chk_dmg_too_soon(damage, ...)
	local next_allowed_dmg_t = type(self._next_allowed_dmg_t) == "number" and self._next_allowed_dmg_t or Application:digest_value(self._next_allowed_dmg_t, false)
	local t = managers.player:player_timer():time()
	if damage <= self._last_received_dmg + 0.01 and next_allowed_dmg_t > t then
		self._old_last_received_dmg = nil
		self._old_next_allowed_dmg_t = nil
		return true
	end
	
	if next_allowed_dmg_t > t then
		self._old_last_received_dmg = self._last_received_dmg
		self._old_next_allowed_dmg_t = next_allowed_dmg_t
	end
end

Hooks:PostHook(PlayerDamage, "damage_bullet", "hhpost_dmgbullet", function(self, attack_data)
	local armor_damage = self:_max_armor() > 0 and self:get_real_armor() < self:_max_armor()
	local cur_state = self._unit:movement():current_state_name()
	
	if self._bleed_out and self._akuma_effect then
		managers.groupai:state():chk_taunt()
	end
	
	if attack_data then
		if alive(attack_data.attacker_unit) and not self:is_downed() and not self._dead and cur_state ~= "fatal" and cur_state ~= "bleedout" and not self._invulnerable and not self._unit:character_damage().swansong and not self._unit:movement():tased() and not self._mission_damage_blockers.invulnerable and not self._god_mode and not self:incapacitated() and not self._unit:movement():current_state().immortal then
			if tostring(attack_data.attacker_unit:base()._tweak_table) == "akuma" then
				if alive(player_unit) then
					--self._akuma_effect = true
					self:build_suppression(99)
					return
				end
			end
		end
	end
	
	--local testing = true
	local state_chk = cur_state == "standard" or cur_state == "carry" or cur_state == "bipod"
	if Global.game_settings.bulletknock or testing then
		if alive(attack_data.attacker_unit) and state_chk then
			local from_pos = nil

			--probably unnecessary but you never know
			if attack_data.attacker_unit:movement() then
				if attack_data.attacker_unit:movement().m_head_pos then
					from_pos = attack_data.attacker_unit:movement():m_head_pos()
				elseif attack_data.attacker_unit:movement().m_pos then
					from_pos = attack_data.attacker_unit:movement():m_pos()
				else
					from_pos = attack_data.attacker_unit:position()
				end
			else
				from_pos = attack_data.attacker_unit:position()
			end

			local push_vec = Vector3()
			local distance = mvector3.direction(push_vec, from_pos, self._unit:movement():m_head_pos())
			mvector3.normalize(push_vec)

			local dis_lerp_value = math.clamp(distance, 0, 1000) / 1000
			local push_amount = math.lerp(1000, 0, dis_lerp_value)

			self._unit:movement():push(push_vec * push_amount)
		end
	end
	
	if not self:_chk_can_take_dmg() then
		return
	end
	
	local armor_subtracted = self:_calc_armor_damage(attack_data)
	if not self._bleed_out and armor_subtracted > 0 then
		managers.groupai:state():criminal_hurt_drama_armor(self._unit, attacker)
	end

end)

local _calc_armor_damage_original = PlayerDamage._calc_armor_damage
function PlayerDamage:_calc_armor_damage(attack_data, ...)
	attack_data.damage = attack_data.damage - (self._old_last_received_dmg or 0)
	self._next_allowed_dmg_t = self._old_next_allowed_dmg_t and Application:digest_value(self._old_next_allowed_dmg_t, true) or self._next_allowed_dmg_t
	self._old_last_received_dmg = nil
	self._old_next_allowed_dmg_t = nil
	return _calc_armor_damage_original(self, attack_data, ...)
end

function PlayerDamage:_calc_health_damage(attack_data)

	attack_data.damage = attack_data.damage - (self._old_last_received_dmg or 0)
	if self._unit then
		local state = self._unit:movement():current_state_name()
		if state == "driving" or self._unit:movement():zipline_unit() then
			attack_data.damage = attack_data.damage * 0.5
		end
	end
	self._next_allowed_dmg_t = self._old_next_allowed_dmg_t and Application:digest_value(self._old_next_allowed_dmg_t, true) or self._next_allowed_dmg_t
	self._old_last_received_dmg = nil
	self._old_next_allowed_dmg_t = nil
	
	local health_subtracted = 0
	local death_prevented = nil
	health_subtracted = self:get_real_health()
	
	if self._jackpot_token and self:get_real_health() - attack_data.damage <= 0 then
		death_prevented = true
	else
		self:change_health(-attack_data.damage)
	end

	health_subtracted = health_subtracted - self:get_real_health()
	local trigger_skills = table.contains({
		"bullet",
		"explosion",
		"melee",
		"delayed_tick"
	}, attack_data.variant)

	if self:get_real_health() == 0 and trigger_skills then
		self:_chk_cheat_death()
	end

	self:_damage_screen()
	self:_check_bleed_out(trigger_skills)
	managers.hud:set_player_health({
		current = self:get_real_health(),
		total = self:_max_health(),
		revives = Application:digest_value(self._revives, false)
	})
	self:_send_set_health()
	self:_set_health_effect()
	managers.statistics:health_subtracted(health_subtracted)
	
	if self._jackpot_token and death_prevented then
		self._jackpot_token = nil
		self._unit:sound():play("pickup_fak_skill")
		--log("Jackpot just saved you!")
		return 0
	else
		return health_subtracted
	end
end

function PlayerDamage:is_friendly_fire(unit)
	if not unit or not unit:movement() or unit:base().is_grenade then
		return false
	end

	if unit:movement() and unit:movement():team() and unit:movement():team() ~= self._unit:movement():team() and unit:movement():friendly_fire() then
		return false
	end

	local friendly_fire = not unit:movement():team().foes[self._unit:movement():team().id]
	friendly_fire = managers.mutators:modify_value("PlayerDamage:FriendlyFire", friendly_fire)

	return friendly_fire
end

function PlayerDamage:build_suppression(amount)
	--if self:_chk_suppression_too_soon(amount) then
		--return
	--end

	local data = self._supperssion_data
	amount = amount * managers.player:upgrade_value("player", "suppressed_multiplier", 1)
	local armor_damage = self:_max_armor() > 0 and self:get_real_armor() < self:_max_armor()
	
	if amount >= 99 then
		self._akuma_effect = true
		self._akuma_dampen = 50
		SoundDevice:set_rtpc("downed_state_progression", self._akuma_dampen)
	end
		
	local morale_boost_bonus = self._unit:movement():morale_boost()

	if morale_boost_bonus then
		amount = amount * morale_boost_bonus.suppression_resistance
	end

	amount = amount * tweak_data.player.suppression.receive_mul
	data.value = math.min(tweak_data.player.suppression.max_value, (data.value or 0) + amount * tweak_data.player.suppression.receive_mul)
	self._last_received_sup = amount
	self._next_allowed_sup_t = managers.player:player_timer():time() + self._dmg_interval
	if not data.decay_start_t then
		if self._akuma_effect then
			data.decay_start_t = managers.player:player_timer():time() + 4
		else
			data.decay_start_t = managers.player:player_timer():time() + 1
		end
	else
		if self._akuma_effect then
			data.decay_start_t = managers.player:player_timer():time() + 4
		else
			local raw_decay_start_t = data.decay_start_t - managers.player:player_timer():time()
			if raw_decay_start_t <= 0.95 then
				data.decay_start_t = data.decay_start_t + 0.05
			end
		end
	end
end

function PlayerDamage:_upd_suppression(t, dt)
	local data = self._supperssion_data

	if data.value then
		if data.decay_start_t < t then
			data.value = data.value - data.value

			if data.value <= 0 then
				data.value = nil
				data.decay_start_t = nil

				managers.environment_controller:set_suppression_value(0, 0)
			end
		elseif data.value == tweak_data.player.suppression.max_value and self._regenerate_timer then
			self._listener_holder:call("suppression_max")
		end

		if data.value then
			managers.environment_controller:set_suppression_value(self:effective_suppression_ratio(), self:suppression_ratio())
		end
	end
end

function PlayerDamage:_begin_akuma_snddedampen()
	if self._akuma_dampen and self._akuma_dampen > 0 then
		self._akuma_dampen = 0
		SoundDevice:set_rtpc("downed_state_progression", self._akuma_dampen)		
	end
end

Hooks:PostHook(PlayerDamage, "_regenerate_armor", "hh_regenarmor", function(self, no_sound)
	self._akuma_effect = nil
	if self._akuma_dampen then
		--self._is_damping = true
		self:_begin_akuma_snddedampen()
	end
end)


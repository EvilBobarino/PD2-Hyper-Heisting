--Added a bunch of chatter stuff with permission from EvilBobarino, along with a few tweaks to keep things consistent

--Hooks:PostHook(GroupAIStateBase, "init", "shin_debug", function(self, group_ai_state)
	--self:set_debug_draw_state(true)
--end)

function GroupAIStateBesiege:init(group_ai_state)
	GroupAIStateBesiege.super.init(self)

	if Network:is_server() and managers.navigation:is_data_ready() then
		self:_queue_police_upd_task()
	end

	self._tweak_data = tweak_data.group_ai[group_ai_state]
	self._spawn_group_timers = {}
	self._graph_distance_cache = {}
	self._had_hostages = nil
	self._feddensityhigh = nil	
	self._feddensityhighfrequency = 1
	self._downleniency = 1
	self._enemies_killed_sustain = 0
	self._enemies_killed_sustain_guaranteed_break = 50
	self._downcountleniency = 0
	self._feddensity_active_t = nil
	self._next_allowed_hunter_upd_t = nil
	self._next_allowed_drama_reveal_t = nil
	self._activeassaultbreak = nil
	self._activeassaultnextbreak_t = nil
	self._stopassaultbreak_t = nil
end

function GroupAIStateBesiege:_queue_police_upd_task()
	if not self._police_upd_task_queued then
		local next_upd_t = 0.8
		if next(self._spawning_groups) then
			next_upd_t = 0.4
		end
		self._police_upd_task_queued = true

		managers.enemy:queue_task("GroupAIStateBesiege._upd_police_activity", self._upd_police_activity, self, self._t + next_upd_t) --please dont let your own algorithms implode like that, ovk, thanks
	end
end

function GroupAIStateBesiege:update(t, dt)
	GroupAIStateBesiege.super.update(self, t, dt)
	
	if Network:is_server() then
		self:_queue_police_upd_task()
		local diff_index = tweak_data:difficulty_to_index(Global.game_settings.difficulty)
		
		if self._downcountleniency > 5 then
			self._downcountleniency = 5
		end
		
		self:_claculate_drama_value()
		
		local activedrama = self._drama_data.amount >= tweak_data.drama.consistentcombat
		local highdrama = self._drama_data.amount == tweak_data.drama.peak
		
		self._max_fedfuck_t_add = 3 * self._feddensityhighfrequency
		
		--if not self._feddensity_reset_t then
			--log("noresettime")
		--end
		
		self._feddensity_active_t = 5 + self._downcountleniency
			
		if self._downleniency and self._max_fedfuck_t_add then
			self._max_fedfuck_t_add = math.floor(self._max_fedfuck_t_add * self._downleniency)
		end
		
		if not self._max_fedfuck_t and activedrama and not self._feddensityhigh then
			--log("tick tock")
			self._max_fedfuck_t = self._t + self._max_fedfuck_t_add
		end
		
		if not activedrama and self._max_fedfuck_t then
			--log("beepbeepbeep")
			self._max_fedfuck_t = nil
		end
		
		if not self._feddensityhigh then
			if activedrama and self._max_fedfuck_t and self._max_fedfuck_t < self._t or highdrama then
				self._feddensityhigh = true
				self._max_fedfuck_t = nil
				self:chk_random_drama_comment()
				self._feddensity_reset_t = self._t + self._feddensity_active_t
				self._feddensityhighfrequency = self._feddensityhighfrequency + 0.5
				--log("feddensityhigh active")
			end
		end
		
		if self._feddensityhigh and self._feddensity_reset_t and self._feddensity_reset_t < self._t or self._feddensityhigh and not self._task_data.assault.active then
			self._feddensityhigh = nil
			self._feddensity_reset_t = nil
			self._max_fedfuck_t = nil
			self._rolled_dramatalk_chance = nil
			--log("resetting feddensity")
		end
		
		if self._task_data.assault and self._task_data.assault.phase == "build" or self._task_data.assault and self._task_data.assault.phase == "sustain" then
			if not self._activeassaultbreak then
				if not self._activeassaultnextbreak_t then
					--log("assaultstartedbreakset")
					self._activeassaultnextbreak_t = self._t + math.random(20, 40) 
					if diff_index >= 6 or Global.game_settings.aggroAI then
						self._activeassaultnextbreak_t = self._activeassaultnextbreak_t + math.random(10, 20)
						--log("breaksetforDW")
					end
				end
			end
			
			if self._activeassaultnextbreak_t and self._activeassaultnextbreak_t < self._t and not self._stopassaultbreak_t or self._enemies_killed_sustain_guaranteed_break < self._enemies_killed_sustain and not self._stopassaultbreak_t then
				self._activeassaultbreak = true
				if managers.skirmish:is_skirmish() then
					self._stopassaultbreak_t = self._t + 5
				else
					self._stopassaultbreak_t = self._t + math.random(5, 10)
				end
				self._task_data.assault.phase_end_t = self._task_data.assault.phase_end_t + 10
				if self._enemies_killed_sustain_guaranteed_break < self._enemies_killed_sustain then
					self._enemies_killed_sustain_guaranteed_break = self._enemies_killed_sustain_guaranteed_break + 50
				end
				--log("assaultbreakon")
			end
			
			if self._activeassaultbreak and self._stopassaultbreak_t and self._stopassaultbreak_t < self._t then
				self._stopassaultbreak_t = nil
				self._activeassaultbreak = nil
				self._activeassaultnextbreak_t = self._t + math.random(20, 40) 
				if diff_index >= 6 or Global.game_settings.aggroAI then
					self._activeassaultnextbreak_t = self._activeassaultnextbreak_t + math.random(10, 20) 
				end
				--log("assaultbreakreset")
			end
		else
			self._stopassaultbreak_t = nil
			self._activeassaultbreak = nil
			self._activeassaultnextbreak_t = nil
		end
		

		if managers.navigation:is_data_ready() and self._draw_enabled then
			self:_draw_enemy_activity(t)
			self:_draw_spawn_points()
		end
	end
end

-- Fix for the bug when there is too many dozers/specials thank you andole im sorry
local fixed = false
local origfunc2 = GroupAIStateBesiege._get_special_unit_type_count
function GroupAIStateBesiege:_get_special_unit_type_count(special_type, ...)
	if special_type == 'tank_mini' and special_type == 'tank_medic' and special_type == 'tank_ftsu' and special_type == 'spooc_heavy' and special_type == 'phalanx_minion' and special_type == 'tank_hw' and special_type == 'akuma' then
		fixed = true
	end
	
	if not fixed and special_type == 'tank' then
		local res1 = origfunc2(self, 'tank', ...) or 0
		res1 = res1 + (origfunc2(self, 'tank_mini', ...) or 0)
		res1 = res1 + (origfunc2(self, 'tank_medic', ...) or 0)
		res1 = res1 + (origfunc2(self, 'tank_ftsu', ...) or 0)
		res1 = res1 + (origfunc2(self, 'tank_hw', ...) or 0)
		return res1
	end
	
	if not fixed and special_type == 'spooc' then
		local res2 = origfunc2(self, 'spooc', ...) or 0
		res2 = res2 + (origfunc2(self, 'spooc_heavy', ...) or 0)
		return res2
	end
	
	if not fixed and special_type == 'shield' then 
		local res3 = origfunc2(self, 'shield', ...) or 0
		res3 = res3 + (origfunc2(self, 'phalanx_minion', ...) or 0)
		res3 = res3 + (origfunc2(self, 'akuma', ...) or 0)
		return res3
	end
	
	return origfunc2(self, special_type, ...)
end

function GroupAIStateBesiege:chk_high_fed_density()

	if not self._feddensityhigh then
		return
		--log("not my fucking dick")
	end
	
	return true
end

function GroupAIStateBesiege:chk_assault_number()
	if not self._assault_number then
		return 1
	end
	
	return self._assault_number
end

function GroupAIStateBesiege:chk_no_fighting_atm()

	if self._drama_data.amount > tweak_data.drama.consistentcombat then
		return
	end
	
	return true
end

function GroupAIStateBesiege:chk_active_assault_break()

	if not self._activeassaultbreak then
		return
	end
	
	return true
end

function GroupAIStateBesiege:chk_assault_active_atm()

	if not self._task_data.assault.phase == "build" or not self._task_data.assault.phase == "sustain" then
		return
		--log("not assault active")
	end
	
	return true
end

function GroupAIStateBesiege:get_hostage_count_for_chatter()
	
	if self._hostage_headcount > 0 then
		return self._hostage_headcount
	end
	
	return 0
end

function GroupAIStateBesiege:_begin_new_tasks()
	local all_areas = self._area_data
	local nav_manager = managers.navigation
	local all_nav_segs = nav_manager._nav_segments
	local task_data = self._task_data
	local t = self._t
	local reenforce_candidates = nil
	local reenforce_data = task_data.reenforce

	if reenforce_data.next_dispatch_t and reenforce_data.next_dispatch_t < t then
		reenforce_candidates = {}
	end

	local recon_candidates, are_recon_candidates_safe = nil
	local recon_data = task_data.recon

	if recon_data.next_dispatch_t and recon_data.next_dispatch_t < t and not task_data.assault.active and not task_data.regroup.active then
		recon_candidates = {}
	end

	local assault_candidates = nil
	local assault_data = task_data.assault

	if self._difficulty_value > 0 and assault_data.next_dispatch_t and assault_data.next_dispatch_t < t and not task_data.regroup.active then
		assault_candidates = {}
	end

	if not reenforce_candidates and not recon_candidates and not assault_candidates then
		return
	end

	local found_areas = {}
	local to_search_areas = {}

	for area_id, area in pairs(all_areas) do
		if area.spawn_points then
			for _, sp_data in pairs(area.spawn_points) do
				if sp_data.delay_t <= t and not all_nav_segs[sp_data.nav_seg].disabled then
					table.insert(to_search_areas, area)

					found_areas[area_id] = true

					break
				end
			end
		end

		if not found_areas[area_id] and area.spawn_groups then
			for _, sp_data in pairs(area.spawn_groups) do
				if sp_data.delay_t <= t and not all_nav_segs[sp_data.nav_seg].disabled then
					table.insert(to_search_areas, area)

					found_areas[area_id] = true

					break
				end
			end
		end
	end

	if #to_search_areas == 0 then
		return
	end

	if assault_candidates and self._hunt_mode then
		for criminal_key, criminal_data in pairs(self._char_criminals) do
			if not criminal_data.status then
				local nav_seg = criminal_data.tracker:nav_segment()
				local area = self:get_area_from_nav_seg_id(nav_seg)
				found_areas[area] = true

				table.insert(assault_candidates, area)
			end
		end
	end

	local i = 1

	repeat
		local area = to_search_areas[i]
		local force_factor = area.factors.force
		local demand = force_factor and force_factor.force
		local nr_police = table.size(area.police.units)
		local nr_criminals = table.size(area.criminal.units)

		if reenforce_candidates and demand and demand > 0 and nr_criminals == 0 then
			local area_free = true

			if area_free then
				table.insert(reenforce_candidates, area)
			end
		end

		if recon_candidates and area.loot or recon_candidates and area.hostages then
			local occupied = nil

			if not occupied then
				local is_area_safe = nr_criminals == 0

				if is_area_safe then
					if are_recon_candidates_safe then
						table.insert(recon_candidates, area)
					else
						are_recon_candidates_safe = true
						recon_candidates = {
							area
						}
					end
				elseif not are_recon_candidates_safe then
					table.insert(recon_candidates, area)
				end
			end
		end

		if assault_candidates then
			for criminal_key, _ in pairs(area.criminal.units) do
				if not self._criminals[criminal_key].is_deployable then
					table.insert(assault_candidates, area)

					break
				end
			end
		end

		if nr_criminals == 0 then
			for neighbour_area_id, neighbour_area in pairs(area.neighbours) do
				if not found_areas[neighbour_area_id] then
					table.insert(to_search_areas, neighbour_area)

					found_areas[neighbour_area_id] = true
				end
			end
		end

		i = i + 1
	until i > #to_search_areas

	if assault_candidates and #assault_candidates > 0 then
		self:_begin_assault_task(assault_candidates)

		recon_candidates = nil
	end

	if recon_candidates and #recon_candidates > 0 then
		local recon_area = recon_candidates[math.random(#recon_candidates)]

		self:_begin_recon_task(recon_area)
	end

	if reenforce_candidates and #reenforce_candidates > 0 then
		local lucky_i_candidate = math.random(#reenforce_candidates)
		local reenforce_area = reenforce_candidates[lucky_i_candidate]

		self:_begin_reenforce_task(reenforce_area)

		recon_candidates = nil
	end
end
	
function GroupAIStateBesiege:_begin_assault_task(assault_areas)
	local assault_task = self._task_data.assault
	assault_task.active = true
	assault_task.next_dispatch_t = nil
	assault_task.target_areas = assault_areas
	assault_task.phase = "anticipation"
	assault_task.start_t = self._t
	local anticipation_duration = self:_get_anticipation_duration(self._tweak_data.assault.anticipation_duration, assault_task.is_first)
	assault_task.force_anticipation = 16
	assault_task.is_first = nil
	self._enemies_killed_sustain = 0
	self._enemies_killed_sustain_guaranteed_break = 50
	assault_task.phase_end_t = self._t + anticipation_duration
	
	if not self._downleniency or self._downleniency < 1 then
		self._downleniency = 1
		--log("resetting down leniency")
	end
	
	if self._assault_was_hell then
		--log("resetting break from hell")
		self._assault_was_hell = nil
	end
	
	if assault_task.is_first or self._assault_number and self._assault_number == 1 or not self._assault_number then
		assault_task.force = math.ceil(self:_get_difficulty_dependent_value(self._tweak_data.assault.force) * 0.75 * self:_get_balancing_multiplier(self._tweak_data.assault.force_balance_mul))
	elseif self._assault_number == 2 then
		assault_task.force = math.ceil(self:_get_difficulty_dependent_value(self._tweak_data.assault.force) * 0.85 * self:_get_balancing_multiplier(self._tweak_data.assault.force_balance_mul))
	elseif self._assault_number == 3 then
		assault_task.force = math.ceil(self:_get_difficulty_dependent_value(self._tweak_data.assault.force) * 0.9 * self:_get_balancing_multiplier(self._tweak_data.assault.force_balance_mul))
	else
		assault_task.force = math.ceil(self:_get_difficulty_dependent_value(self._tweak_data.assault.force) * self:_get_balancing_multiplier(self._tweak_data.assault.force_balance_mul))
	end
	
	assault_task.use_smoke = true
	assault_task.use_smoke_timer = 0
	assault_task.use_spawn_event = true
	assault_task.force_spawned = 0

	if self._hostage_headcount > 0 then
		assault_task.phase_end_t = assault_task.phase_end_t + self:_get_difficulty_dependent_value(self._tweak_data.assault.hostage_hesitation_delay)
		assault_task.is_hesitating = true
		assault_task.voice_delay = self._t + (assault_task.phase_end_t - self._t) / 2
	end

	self._downs_during_assault = 0

	if self._hunt_mode then
		assault_task.phase_end_t = 0
	else
		managers.hud:setup_anticipation(anticipation_duration)
		managers.hud:start_anticipation()
	end

	if self._draw_drama then
		table.insert(self._draw_drama.assault_hist, {
			self._t
		})
	end

	self._task_data.recon.tasks = {}
end

function GroupAIStateBesiege:assault_phase_end_time()
	local task_data = self._task_data.assault
	local end_t = task_data and task_data.phase_end_t
	
	local assault_number_sustain_t_mul = nil
	
	if task_data.is_first or self._assault_number and self._assault_number <= 2 or not self._assault_number then
		assault_number_sustain_t_mul = 0.75
	elseif self._assault_number >= 3 then
		assault_number_sustain_t_mul = 1
	end

	if end_t and task_data.phase == "sustain" then
		end_t = managers.modifiers:modify_value("GroupAIStateBesiege:SustainEndTime", end_t) * assault_number_sustain_t_mul
	end

	return end_t
end
		
function GroupAIStateBesiege:_upd_assault_task()
	
	local low_carnage = self:_count_criminals_engaged_force(4) <= 4  
	local task_data = self._task_data.assault
	local assault_number_sustain_t_mul = nil
	
	--if task_data.phase == "anticipation" then
		--self._task_data.assault.force = task_data.force_anticipation
	--else
		--if task_data.is_first or self._assault_number and self._assault_number == 1 or not self._assault_number then
			--self._task_data.assault.force = math.ceil(self:_get_difficulty_dependent_value(self._tweak_data.assault.force) * 0.75 * self:_get_balancing_multiplier(self._tweak_data.assault.force_balance_mul))
		--elseif self._assault_number == 2 then
			--self._task_data.assault.force = math.ceil(self:_get_difficulty_dependent_value(self._tweak_data.assault.force) * 0.85 * self:_get_balancing_multiplier(self._tweak_data.assault.force_balance_mul))
		--elseif self._assault_number == 3 then
			--self._task_data.assault.force = math.ceil(self:_get_difficulty_dependent_value(self._tweak_data.assault.force) * 0.9 * self:_get_balancing_multiplier(self._tweak_data.assault.force_balance_mul))
		--else
			--self._task_data.assault.force = math.ceil(self:_get_difficulty_dependent_value(self._tweak_data.assault.force) * self:_get_balancing_multiplier(self._tweak_data.assault.force_balance_mul))
		--end
	--end
	
	if task_data.is_first or self._assault_number and self._assault_number <= 2 or not self._assault_number then
		assault_number_sustain_t_mul = 0.75 
	elseif self._assault_number >= 3 then
		assault_number_sustain_t_mul = 1
	end
	
	if not task_data.active then
		return
	end

	local t = self._t

	self:_assign_recon_groups_to_retire()

	local force_pool = nil 
	
	if task_data.is_first or self._assault_number and self._assault_number <= 1 or not self._assault_number then
		force_pool = self:_get_difficulty_dependent_value(self._tweak_data.assault.force_pool) * 0.75 * self:_get_balancing_multiplier(self._tweak_data.assault.force_pool_balance_mul)
	elseif self._assault_number == 2 then
		force_pool = self:_get_difficulty_dependent_value(self._tweak_data.assault.force_pool) * 0.75 * self:_get_balancing_multiplier(self._tweak_data.assault.force_pool_balance_mul)
	elseif self._assault_number >= 3 then
		force_pool = self:_get_difficulty_dependent_value(self._tweak_data.assault.force_pool) * self:_get_balancing_multiplier(self._tweak_data.assault.force_pool_balance_mul)
	end
	
	local task_spawn_allowance = force_pool - (self._hunt_mode and 0 or task_data.force_spawned)
	
	if task_data.phase == "anticipation" then
		if task_spawn_allowance <= 0 then
			--fade
			task_data.phase = "fade"
			task_data.phase_end_t = t + self._tweak_data.assault.fade_duration
		elseif task_data.phase_end_t < t and self._drama_data.amount >= tweak_data.drama.assaultstart or self._drama_data.zone == "high" and not low_carnage then --if drama is high and there are 5 or more enemies engaging all players, start the assault and drop the bass
			self._assault_number = self._assault_number + 1

			managers.mission:call_global_event("start_assault")
			managers.hud:start_assault(self._assault_number)
			managers.groupai:dispatch_event("start_assault", self._assault_number)
			self:_set_rescue_state(false)
			
			for group_id, group in pairs(self._groups) do
				for u_key, u_data in pairs(group.units) do
					u_data.unit:sound():say("att", true)
				end
			end

			task_data.phase = "build"
			task_data.phase_end_t = self._t + self._tweak_data.assault.build_duration
			task_data.is_hesitating = nil

			self:set_assault_mode(true)
			managers.trade:set_trade_countdown(false)
		else
			managers.hud:check_anticipation_voice(task_data.phase_end_t - t)
			managers.hud:check_start_anticipation_music(task_data.phase_end_t - t)

			if task_data.is_hesitating and task_data.voice_delay < self._t then
				if self._hostage_headcount > 0 then
					local best_group = nil

					for _, group in pairs(self._groups) do
						if group.objective.type == "reenforce_area" then
							best_group = group
						elseif group.objective.type ~= "reenforce_area" and group.objective.type ~= "retire" then
							best_group = group
						elseif not best_group then
							best_group = group
						end
					end

					if best_group and self:_voice_delay_assault(best_group) then
						self._task_data.assault.is_hesitating = nil
					end
				else
					self._task_data.assault.is_hesitating = nil
				end
			end
		end
	elseif task_data.phase == "build" then
		if task_spawn_allowance <= 0 then
			task_data.phase = "fade"
			task_data.phase_end_t = t + self._tweak_data.assault.fade_duration
			local time = self._t
			for group_id, group in pairs(self._groups) do
				for u_key, u_data in pairs(group.units) do
					local nav_seg_id = u_data.tracker:nav_segment()
					local current_objective = group.objective
					if current_objective.coarse_path then
						if not u_data.unit:sound():speaking(time) then
							u_data.unit:sound():say("m01", true)
						end	
					end					   
				end	
			end
		elseif task_data.phase_end_t < t or self._drama_data.zone == "high" then
			local sustain_duration = math.lerp(self:_get_difficulty_dependent_value(self._tweak_data.assault.sustain_duration_min), self:_get_difficulty_dependent_value(self._tweak_data.assault.sustain_duration_max), math.random()) * self:_get_balancing_multiplier(self._tweak_data.assault.sustain_duration_balance_mul) * assault_number_sustain_t_mul
			
			managers.modifiers:run_func("OnEnterSustainPhase", sustain_duration)

			self._task_data.assault.phase = "sustain"
			self._task_data.assault.phase_end_t = t + sustain_duration
		end
	elseif task_data.phase == "sustain" then
		local end_t = self:assault_phase_end_time()
		task_spawn_allowance = managers.modifiers:modify_value("GroupAIStateBesiege:SustainSpawnAllowance", task_spawn_allowance, force_pool)

		if task_spawn_allowance <= 0 then
			task_data.phase = "fade"
			task_data.phase_end_t = t + self._tweak_data.assault.fade_duration
			
			local time = self._t
				for group_id, group in pairs(self._groups) do
					for u_key, u_data in pairs(group.units) do
						local nav_seg_id = u_data.tracker:nav_segment()
						local current_objective = group.objective
						if current_objective.coarse_path then
							if not u_data.unit:sound():speaking(time) then
								u_data.unit:sound():say("m01", true)
							end	
						end					   
					end	
				end	
		elseif end_t < t and not self._hunt_mode and self._enemies_killed_sustain > 50 then
			task_data.phase = "fade"
			task_data.phase_end_t = t + self._tweak_data.assault.fade_duration
			local time = self._t
			for group_id, group in pairs(self._groups) do
				for u_key, u_data in pairs(group.units) do
					local nav_seg_id = u_data.tracker:nav_segment()
					local current_objective = group.objective
					if current_objective.coarse_path then
						if not u_data.unit:sound():speaking(time) then
							u_data.unit:sound():say("m01", true)
						end	
					end					   
				end	
			end
		end
	else
		local end_assault = false
		local enemies_left = self:_count_police_force("assault")

		if not self._hunt_mode then
			local enemies_defeated_time_limit = 60
			local drama_engagement_time_limit = 60

			if managers.skirmish:is_skirmish() then
				enemies_defeated_time_limit = 0
				drama_engagement_time_limit = 0
			end

			local min_enemies_left = 30 --enemies remaining before considering all enemies defeated
			local enemies_defeated = enemies_left < min_enemies_left
			local taking_too_long = t > task_data.phase_end_t + enemies_defeated_time_limit
			local fade_time_over = t > task_data.phase_end_t 
			self:_assign_assault_groups_to_retire()
			if enemies_defeated and fade_time_over or taking_too_long then
				if not task_data.said_retreat then
					self._task_data.assault.said_retreat = true

					self:_police_announce_retreat()
					self:_assign_assault_groups_to_retire()
					local time = self._t
					for group_id, group in pairs(self._groups) do
						for u_key, u_data in pairs(group.units) do
							local nav_seg_id = u_data.tracker:nav_segment()
							local current_objective = group.objective
							if current_objective.coarse_path then
								if not u_data.unit:sound():speaking(time) then
									u_data.unit:sound():say("m01", true)
								end	
							end					   
						end	
					end
				elseif task_data.phase_end_t < t and not self._feddensityhigh then
					local drama_pass = self._drama_data.amount < tweak_data.drama.assault_fade_end --if there is no active fighting going on
					local engagement_pass = self:_count_criminals_engaged_force(4) < 5 --if theres less than 5 enemies engaging all players
					local taking_too_long = t > task_data.phase_end_t + drama_engagement_time_limit
					
					--if engagement_pass then
						--log("engagement check")
					--end
					
					--if drama_pass then
						--log("drama check")
					--end
					
					--if taking_too_long then 
						--log("i cant believe they kited cops fuglore would never do this im literally shaking and crying right now")
					--end
					
					if drama_pass and engagement_pass and t > task_data.phase_end_t or taking_too_long then
						end_assault = true
					end
				end
			end

			if task_data.force_end or end_assault then
				--print("assault task clear")

				task_data.active = nil
				task_data.phase = nil
				task_data.said_retreat = nil
				task_data.force_end = nil
				local force_regroup = task_data.force_regroup
				task_data.force_regroup = nil

				if self._draw_drama then
					self._draw_drama.assault_hist[#self._draw_drama.assault_hist][2] = t
				end

				managers.mission:call_global_event("end_assault")
				self:_begin_regroup_task(force_regroup)
				
				return
			end
		end
	end
	
	local assaultactive = task_data.phase == "build" or task_data.phase == "sustain"
	local revealchk = not self._next_allowed_drama_reveal_t or self._next_allowed_drama_reveal_t < t
	
	if assaultactive then
		if low_carnage and not self._feddensityhigh and revealchk and not self._activeassaultbreak or self._drama_data.amount <= self._drama_data.low_p and not self._feddensityhigh and not self._activeassaultbreak and revealchk then --drama is too low, or all players arent actively being attacked by at least one spawngroup during assault right now, reveal their location
			if not assaultactive then
				--log("AAAAAAAA FUCK YOU")
			end
			--if low_carnage then
				--log("YOU...WILL...FIIIIIIIIIIIIIIGHT!!!!!!")
			--end
			self._next_allowed_drama_reveal_t = t + math.random(5, 10)
			for criminal_key, criminal_data in pairs(self._player_criminals) do
				self:criminal_spotted(criminal_data.unit)
				--this is some insane over-weight code for some chatter randomness but hot damn am i happy with it
				local time = self._t
				for group_id, group in pairs(self._groups) do
					for u_key, u_data in pairs(group.units) do
						u_data.unit:brain():clbk_group_member_attention_identified(nil, criminal_key)
						if not u_data.unit:sound():speaking(time) then
							local chance = math.random(1, 100)
							local do_pus = 33
							local not_mov = 65
							if chance <= do_pus then
								u_data.unit:sound():say("pus", true) --GOGOGO/PUSH!
							elseif chance > not_mov then
								--nothing, keeps things less spammy
							else
							u_data.unit:sound():say("mov", true) --Move out/Move!
							end
						end
					end
				end				
			end
		end
	end

	local primary_target_area = task_data.target_areas[1]

	if self:is_area_safe_assault(primary_target_area) then
		local target_pos = primary_target_area.pos
		local nearest_area, nearest_dis = nil
		

		for criminal_key, criminal_data in pairs(self._player_criminals) do
			if not criminal_data.status then
				local dis = mvector3.distance_sq(target_pos, criminal_data.m_pos)

				if not self._current_assault_nearest_dis or dis < self._current_assault_nearest_dis then
					self._current_assault_nearest_dis = dis
					self._current_assault_nearest_area = self:get_area_from_nav_seg_id(criminal_data.tracker:nav_segment())
				end
			end
		end

		if self._current_assault_nearest_area then
			primary_target_area = self._current_assault_nearest_area
			task_data.target_areas[1] = self._current_assault_nearest_area
		end
	end
	
	if task_data.use_smoke_timer < t then
		task_data.use_smoke = true
	end

	self:detonate_queued_smoke_grenades()
	
	local enemy_count = self:_count_police_force("assault")
	local nr_wanted = task_data.force - self:_count_police_force("assault")
	local anticipation_count = task_data.force * 0.25

	nr_wanted = task_data.force - self:_count_police_force("assault")

	if nr_wanted > 0 and task_data.phase ~= "fade" and not self._activeassaultbreak and not self._feddensityhigh then
		local used_event = nil

		if task_data.use_spawn_event and task_data.phase ~= "anticipation" then
			task_data.use_spawn_event = false

			if self:_try_use_task_spawn_event(t, primary_target_area, "assault") then
				used_event = true
			end
		end

		if not used_event then
			if next(self._spawning_groups) then
				-- Nothing
			else
				local spawn_group, spawn_group_type = self:_find_spawn_group_near_area(primary_target_area, self._tweak_data.assault.groups, nil, nil, nil)

				if spawn_group then
					local grp_objective = {
						attitude = "avoid",
						stance = "hos",
						pose = "stand",
						type = "assault_area",
						area = spawn_group.area,
						coarse_path = {
							{
								spawn_group.area.pos_nav_seg,
								spawn_group.area.pos
							}
						}
					}

					self:_spawn_in_group(spawn_group, spawn_group_type, grp_objective, task_data)
				end
			end
		end
	end

	self:_assign_enemy_groups_to_assault(task_data.phase)
end

function GroupAIStateBesiege:_set_reenforce_objective_to_group(group)
	if not group.has_spawned then
		return
	end

	local current_objective = group.objective

	if current_objective.target_area then
		if current_objective.moving_out and not current_objective.moving_in then
			local forwardmost_i_nav_point = self:_get_group_forwardmost_coarse_path_index(group)

			if forwardmost_i_nav_point then
				for i = forwardmost_i_nav_point + 1, #current_objective.coarse_path, 1 do
					local nav_point = current_objective.coarse_path[forwardmost_i_nav_point]

					if not self:is_nav_seg_safe(nav_point[1]) then
						for i = 0, #current_objective.coarse_path - forwardmost_i_nav_point, 1 do
							table.remove(current_objective.coarse_path)
						end

						local grp_objective = {
							attitude = "engage",
							scan = true,
							pose = "stand",
							type = "reenforce_area",
							stance = "hos",
							area = self:get_area_from_nav_seg_id(current_objective.coarse_path[#current_objective.coarse_path][1]),
							target_area = current_objective.target_area
						}

						self:_set_objective_to_enemy_group(group, grp_objective)

						return
					end
				end
			end
		end

		if not current_objective.moving_out and not current_objective.area.neighbours[current_objective.target_area.id] then
			local search_params = {
				id = "GroupAI_reenforce",
				from_seg = current_objective.area.pos_nav_seg,
				to_seg = current_objective.target_area.pos_nav_seg,
				access_pos = self._get_group_acces_mask(group),
				verify_clbk = callback(self, self, "is_nav_seg_safe")
			}
			local coarse_path = managers.navigation:search_coarse(search_params)

			if coarse_path then
				local clean_path = self:_merge_coarse_path_by_area(coarse_path)
				
				if clean_path then
					coarse_path = clean_path
				end
				
				local grp_objective = {
					scan = true,
					pose = "stand",
					type = "reenforce_area",
					stance = "hos",
					attitude = "engage",
					area = self:get_area_from_nav_seg_id(coarse_path[#coarse_path][1]),
					target_area = current_objective.target_area,
					coarse_path = coarse_path
				}

				self:_set_objective_to_enemy_group(group, grp_objective)
				table.remove(coarse_path)
			end
		end

		if not current_objective.moving_out and current_objective.area.neighbours[current_objective.target_area.id] then
			local grp_objective = {
				stance = "hos",
				scan = true,
				pose = "stand",
				type = "reenforce_area",
				attitude = "engage",
				area = current_objective.target_area
			}

			self:_set_objective_to_enemy_group(group, grp_objective)

			group.objective.moving_in = true
		end
	end
end

function GroupAIStateBesiege:_upd_groups()
	for group_id, group in pairs(self._groups) do
		self:_verify_group_objective(group)

		for u_key, u_data in pairs(group.units) do
			local brain = u_data.unit:brain()
			local current_objective = brain:objective()
			local noobjordefaultorgrpobjchkandnoretry = not current_objective or current_objective.is_default or current_objective.grp_objective and current_objective.grp_objective ~= group.objective and not current_objective.grp_objective.no_retry
			local notfollowingorfollowingaliveunit = not group.objective.follow_unit or alive(group.objective.follow_unit)

			if noobjordefaultorgrpobjchkandnoretry and notfollowingorfollowingaliveunit then
				local objective = self._create_objective_from_group_objective(group.objective, u_data.unit)

				if objective and brain:is_available_for_assignment(objective) then
					self:set_enemy_assigned(objective.area or group.objective.area, u_key)

					if objective.element then
						objective.element:clbk_objective_administered(u_data.unit)
					end

					u_data.unit:brain():set_objective(objective)
				end
			end
		end
	end
end

function GroupAIStateBesiege._create_objective_from_group_objective(grp_objective, receiving_unit)
	local objective = {
		grp_objective = grp_objective
	}

	if grp_objective.element then
		objective = grp_objective.element:get_random_SO(receiving_unit)

		if not objective then
			return
		end

		objective.grp_objective = grp_objective

		return
	elseif grp_objective.type == "defend_area" or grp_objective.type == "recon_area" or grp_objective.type == "reenforce_area" then
		objective.type = "defend_area"
		objective.stance = "hos"
		objective.pose = "stand"
		objective.scan = true
		objective.interrupt_dis = 200
		objective.interrupt_suppression = nil
	elseif grp_objective.type == "retire" then
		objective.type = "defend_area"
		objective.stance = "hos"
		objective.pose = "stand"
		objective.scan = true
		objective.interrupt_dis = 200
	elseif grp_objective.type == "assault_area" then
		objective.type = "defend_area"

		if grp_objective.follow_unit then
			objective.follow_unit = grp_objective.follow_unit
			objective.distance = grp_objective.distance
		end

		objective.stance = "hos"
		objective.pose = "stand"
		objective.scan = true
		objective.interrupt_dis = 200
		objective.interrupt_suppression = true
	elseif grp_objective.type == "create_phalanx" then
		objective.type = "phalanx"
		objective.stance = "hos"
		objective.interrupt_dis = nil
		objective.interrupt_health = nil
		objective.interrupt_suppression = nil
		objective.attitude = "avoid"
		objective.path_ahead = true
	elseif grp_objective.type == "hunt" then
		objective.type = "hunt"
		objective.stance = "hos"
		objective.scan = true
		objective.interrupt_dis = 200
	end

	objective.stance = grp_objective.stance or objective.stance
	objective.pose = grp_objective.pose or objective.pose
	objective.area = grp_objective.area
	objective.nav_seg = grp_objective.nav_seg or objective.area.pos_nav_seg
	objective.attitude = grp_objective.attitude or objective.attitude
	objective.interrupt_dis = grp_objective.interrupt_dis or objective.interrupt_dis
	objective.interrupt_health = grp_objective.interrupt_health or objective.interrupt_health
	objective.interrupt_suppression = nil
	objective.pos = grp_objective.pos

	if grp_objective.scan ~= nil then
		objective.scan = grp_objective.scan
	end

	if grp_objective.coarse_path then
		objective.path_style = "coarse_complete"
		objective.path_data = grp_objective.coarse_path
	end

	return objective
end

function GroupAIStateBesiege:_voice_groupentry(group)
	local group_leader_u_key, group_leader_u_data = self._determine_group_leader(group.units)
	if group_leader_u_data and group_leader_u_data.tactics and group_leader_u_data.char_tweak.chatter.entry then
		for i_tactic, tactic_name in ipairs(group_leader_u_data.tactics) do
			local randomgroupcallout = math.random(1, 100) 
			if tactic_name == "groupcs1" then
				self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "csalpha")
			elseif tactic_name == "groupcs2" then
				self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "csbravo")
			elseif tactic_name == "groupcs3" then
				self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "cscharlie")
			elseif tactic_name == "groupcs4" then
				self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "csdelta")
			elseif tactic_name == "grouphrt1" then
				self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtalpha")
			elseif tactic_name == "grouphrt2" then
				self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtbravo")
			elseif tactic_name == "grouphrt3" then
				self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtcharlie")
			elseif tactic_name == "grouphrt4" then
				self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtdelta")
			elseif tactic_name == "groupcsr" then
				if randomgroupcallout < 25 then
					self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "csalpha")
				elseif randomgroupcallout > 25 and randomgroupcallout < 50 then
					self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "csbravo")
				elseif randomgroupcallout < 74 and randomgroupcallout > 50 then
					self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "cscharlie")
				else
					self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "csdelta")
				end
			elseif tactic_name == "grouphrtr" then
				if randomgroupcallout < 25 then
					self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtalpha")
				elseif randomgroupcallout > 25 and randomgroupcallout < 50 then
					self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtbravo")
				elseif randomgroupcallout < 74 and randomgroupcallout > 50 then
					self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtcharlie")
				else
					self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtdelta")
				end
			elseif tactic_name == "groupany" then
				if self._task_data.assault.active then
					if randomgroupcallout < 25 then
						self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "csalpha")
					elseif randomgroupcallout > 25 and randomgroupcallout < 50 then
						self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "csbravo")
					elseif randomgroupcallout < 74 and randomgroupcallout > 50 then
						self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "cscharlie")
					else
						self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "csdelta")
					end
				else
					if randomgroupcallout < 25 then
						self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtalpha")
					elseif randomgroupcallout > 25 and randomgroupcallout < 50 then
						self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtbravo")
					elseif randomgroupcallout < 74 and randomgroupcallout > 50 then
						self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtcharlie")
					else
						self:chk_say_enemy_chatter(group_leader_u_data.unit, group_leader_u_data.m_pos, "hrtdelta")
					end
				end
			end
		end
	end
end

function GroupAIStateBesiege:_voice_looking_for_angle(group)
	for u_key, unit_data in pairs(group.units) do
		if unit_data.char_tweak.chatter.ready and self:chk_say_enemy_chatter(unit_data.unit, unit_data.m_pos, "look_for_angle") then
			else
		end
	end
end

function GroupAIStateBesiege:_voice_friend_dead(group)
	for u_key, unit_data in pairs(group.units) do
		if unit_data.char_tweak.chatter.enemyidlepanic and self:chk_say_enemy_chatter(unit_data.unit, unit_data.m_pos, "assaultpanic") then
			else
		end
	end
end

function GroupAIStateBesiege:_voice_saw()
	for group_id, group in pairs(self._groups) do
		for u_key, u_data in pairs(group.units) do
			if u_data.char_tweak.chatter.saw then
				self:chk_say_enemy_chatter(u_data.unit, u_data.m_pos, "saw")
			else
				
			end
		end
	end
end

function GroupAIStateBesiege:_voice_sentry()
	for group_id, group in pairs(self._groups) do
		for u_key, u_data in pairs(group.units) do
			if u_data.char_tweak.chatter.sentry then
				self:chk_say_enemy_chatter(u_data.unit, u_data.m_pos, "sentry")
			else
				
			end
		end
	end
end	

function GroupAIStateBesiege:_voice_affirmative(group)
	for u_key, unit_data in pairs(group.units) do
		if unit_data.char_tweak.chatter.affirmative and self:chk_say_enemy_chatter(unit_data.unit, unit_data.m_pos, "affirmative") then
			else
		end
	end
end	
	
function GroupAIStateBesiege:_voice_open_fire_start(group)
	for u_key, unit_data in pairs(group.units) do
		if unit_data.char_tweak.chatter.ready and self:chk_say_enemy_chatter(unit_data.unit, unit_data.m_pos, "open_fire") then
			else
		end
	end
end

function GroupAIStateBesiege:_voice_push_in(group)
	for u_key, unit_data in pairs(group.units) do
		if unit_data.char_tweak.chatter.ready and self:chk_say_enemy_chatter(unit_data.unit, unit_data.m_pos, "push") then
			else
		end
	end
end

function GroupAIStateBesiege:_voice_gtfo(group)
	for u_key, unit_data in pairs(group.units) do
		if unit_data.char_tweak.chatter.ready and self:chk_say_enemy_chatter(unit_data.unit, unit_data.m_pos, "retreat") then
			else
		end
	end
end
	
function GroupAIStateBesiege:_voice_deathguard_start(group)
	for u_key, unit_data in pairs(group.units) do
		if unit_data.char_tweak.chatter.ready and self:chk_say_enemy_chatter(unit_data.unit, unit_data.m_pos, "deathguard") then
			else
		end
	end
end	
	
function GroupAIStateBesiege:_voice_smoke(group)
	for u_key, unit_data in pairs(group.units) do
		if unit_data.char_tweak.chatter.ready and self:chk_say_enemy_chatter(unit_data.unit, unit_data.m_pos, "smoke") then
			else
		end
	end
end	
	
function GroupAIStateBesiege:_voice_flash(group)
	for u_key, unit_data in pairs(group.units) do
		if unit_data.char_tweak.chatter.ready and self:chk_say_enemy_chatter(unit_data.unit, unit_data.m_pos, "flash_grenade") then
		else
		end
	end
end

function GroupAIStateBesiege:_voice_dont_delay_assault(group)
	local time = self._t
	for u_key, unit_data in pairs(group.units) do
		if not unit_data.unit:sound():speaking(time) then
			unit_data.unit:sound():say("p01", true, nil)
			return true
		end
	end
	return false
end

function GroupAIStateBesiege:_chk_group_use_smoke_grenade(group, task_data, detonate_pos)
	if task_data.use_smoke then
		local shooter_pos, shooter_u_data = nil
		local duration = tweak_data.group_ai.smoke_grenade_lifetime

		for u_key, u_data in pairs(group.units) do
			shooter_pos = mvector3.copy(u_data.m_pos)
			shooter_u_data = u_data
			if u_data.tactics_map and u_data.tactics_map.smoke_grenade then
				if not detonate_pos or math.random() < 0.5 then
					local smoke_pos_chance = math.random()
					local nav_seg_id = u_data.tracker:nav_segment()
					local nav_seg = managers.navigation._nav_segments[nav_seg_id]
					if u_data.group and u_data.group.objective and u_data.group.objective.area and u_data.group.objective.type == "assault_area" and smoke_pos_chance < 0.5 or u_data.group and u_data.group.objective and u_data.group.objective.area and u_data.group.objective.type == "retire" and smoke_pos_chance < 0.5 then
						detonate_pos = mvector3.copy(u_data.group.objective.area.pos)
					else
						for neighbour_nav_seg_id, door_list in pairs(nav_seg.neighbours) do
							if task_data.target_areas[1].nav_segs[neighbour_nav_seg_id] then
								local random_door_id = door_list[math.random(#door_list)]

								if type(random_door_id) == "number" then
									detonate_pos = managers.navigation._room_doors[random_door_id].center
								else
									detonate_pos = random_door_id:script_data().element:nav_link_end_pos()
								end

								break
							end
						end
					end
				end

				if detonate_pos and shooter_u_data then
					self:detonate_smoke_grenade(detonate_pos, shooter_pos, duration, false)

					task_data.use_smoke_timer = self._t + math.lerp(tweak_data.group_ai.smoke_and_flash_grenade_timeout[1], tweak_data.group_ai.smoke_and_flash_grenade_timeout[2], math.random())
					task_data.use_smoke = false

					if shooter_u_data.char_tweak.chatter.smoke and not shooter_u_data.unit:sound():speaking(self._t) then
						u_data.unit:sound():say("d01", true)	
					end

					return true
				end
			end
		end
	end
	
	return nil
end

function GroupAIStateBesiege:_chk_group_use_flash_grenade(group, task_data, detonate_pos)
	if task_data.use_smoke and not self._activeassaultbreak then
		local shooter_pos, shooter_u_data = nil
		local duration = tweak_data.group_ai.flash_grenade_lifetime

		for u_key, u_data in pairs(group.units) do
			shooter_pos = mvector3.copy(u_data.m_pos)
			shooter_u_data = u_data
			if u_data.tactics_map and u_data.tactics_map.flash_grenade then
				if not detonate_pos then
					local flash_pos_chance = math.random()
					local nav_seg_id = u_data.tracker:nav_segment()
					local nav_seg = managers.navigation._nav_segments[nav_seg_id]
					if u_data.group and u_data.group.objective and u_data.group.objective.area and u_data.group.objective.type == "assault_area" and flash_pos_chance < 0.5 then
						detonate_pos = mvector3.copy(u_data.group.objective.area.pos)
					else
						for neighbour_nav_seg_id, door_list in pairs(nav_seg.neighbours) do
							if task_data.target_areas[1].nav_segs[neighbour_nav_seg_id] then
								local random_door_id = door_list[math.random(#door_list)]

								if type(random_door_id) == "number" then
									detonate_pos = managers.navigation._room_doors[random_door_id].center
								else
									detonate_pos = random_door_id:script_data().element:nav_link_end_pos()
								end

								break
							end
						end
					end
				end
				

				if detonate_pos and shooter_u_data then
					self:detonate_smoke_grenade(detonate_pos, shooter_pos, duration, true)

					task_data.use_smoke_timer = self._t + math.lerp(tweak_data.group_ai.smoke_and_flash_grenade_timeout[1], tweak_data.group_ai.smoke_and_flash_grenade_timeout[2], math.random())
					task_data.use_smoke = false

					if shooter_u_data.char_tweak.chatter.flash_grenade and not shooter_u_data.unit:sound():speaking(self._t) then
						u_data.unit:sound():say("d02", true)	
					end

					return true
				end
			end
		end
	end
end

function GroupAIStateBesiege:_set_recon_objective_to_group(group)
	local current_objective = group.objective
	local target_area = current_objective.target_area or current_objective.area

	if not target_area.loot and not target_area.hostages or not current_objective.moving_out and current_objective.moved_in and group.in_place_t and self._t - group.in_place_t > 5 then
		local recon_area = nil
		local to_search_areas = {
			current_objective.area
		}
		local found_areas = {
			[current_objective.area] = "init"
		}

		repeat
			local search_area = table.remove(to_search_areas, 1)

			if search_area.loot or search_area.hostages then
				local occupied = nil

				for test_group_id, test_group in pairs(self._groups) do
					if test_group ~= group and (test_group.objective.target_area == search_area or test_group.objective.area == search_area) then
						occupied = true

						break
					end
				end

				if not occupied and group.visited_areas and group.visited_areas[search_area] then
					occupied = true
				end

				if not occupied then
					local is_area_safe = not next(search_area.criminal.units)

					if is_area_safe then
						recon_area = search_area

						break
					else
						recon_area = recon_area or search_area
					end
				end
			end

			if not next(search_area.criminal.units) then
				for other_area_id, other_area in pairs(search_area.neighbours) do
					if not found_areas[other_area] then
						table.insert(to_search_areas, other_area)

						found_areas[other_area] = search_area
					end
				end
			end
		until #to_search_areas == 0

		if recon_area then
			local coarse_path = {
				{
					recon_area.pos_nav_seg,
					recon_area.pos
				}
			}
			local last_added_area = recon_area

			while found_areas[last_added_area] ~= "init" do
				last_added_area = found_areas[last_added_area]

				table.insert(coarse_path, 1, {
					last_added_area.pos_nav_seg,
					last_added_area.pos
				})
			end

			local grp_objective = {
				scan = true,
				pose = math.random() < 0.5 and "crouch" or "stand",
				type = "recon_area",
				stance = "hos",
				attitude = "avoid",
				area = current_objective.area,
				target_area = recon_area,
				coarse_path = coarse_path
			}

			self:_set_objective_to_enemy_group(group, grp_objective)
			self:_voice_looking_for_angle(group)

			current_objective = group.objective
		end
	end

	if current_objective.target_area then
		if current_objective.moving_out and not current_objective.moving_in and current_objective.coarse_path then
			local forwardmost_i_nav_point = self:_get_group_forwardmost_coarse_path_index(group)

			if forwardmost_i_nav_point and forwardmost_i_nav_point > 1 then
				for i = forwardmost_i_nav_point + 1, #current_objective.coarse_path, 1 do
					local nav_point = current_objective.coarse_path[forwardmost_i_nav_point]

					if not self:is_nav_seg_safe(nav_point[1]) then
						for i = 0, #current_objective.coarse_path - forwardmost_i_nav_point, 1 do
							table.remove(current_objective.coarse_path)
						end

						local grp_objective = {
							attitude = "avoid",
							scan = true,
							pose = math.random() < 0.5 and "crouch" or "stand",
							type = "recon_area",
							stance = "hos",
							area = self:get_area_from_nav_seg_id(current_objective.coarse_path[#current_objective.coarse_path][1]),
							target_area = current_objective.target_area
						}

						self:_set_objective_to_enemy_group(group, grp_objective)

						return
					end
				end
			end
		end

		if not current_objective.moving_out and not current_objective.area.neighbours[current_objective.target_area.id] then
			local search_params = {
				id = "GroupAI_recon",
				from_seg = current_objective.area.pos_nav_seg,
				to_seg = current_objective.target_area.pos_nav_seg,
				access_pos = self._get_group_acces_mask(group),
				verify_clbk = callback(self, self, "is_nav_seg_safe")
			}
			local coarse_path = managers.navigation:search_coarse(search_params)

			if coarse_path then
				self:_merge_coarse_path_by_area(coarse_path)
				table.remove(coarse_path)

				local grp_objective = {
					scan = true,
					pose = "stand",
					type = "recon_area",
					stance = "hos",
					attitude = "avoid",
					area = self:get_area_from_nav_seg_id(coarse_path[#coarse_path][1]),
					target_area = current_objective.target_area,
					coarse_path = coarse_path
				}

				self:_set_objective_to_enemy_group(group, grp_objective)
			end
		end

		if not current_objective.moving_out and current_objective.area.neighbours[current_objective.target_area.id] then
			local grp_objective = {
				stance = "hos",
				scan = true,
				pose = math.random() < 0.5 and "crouch" or "stand",
				type = "recon_area",
				attitude = "avoid",
				area = current_objective.target_area
			}

			self:_set_objective_to_enemy_group(group, grp_objective)

			group.objective.moving_in = true
			group.objective.moved_in = true

			if next(current_objective.target_area.criminal.units) then
				self:_chk_group_use_smoke_grenade(group, {
					use_smoke = true,
					target_areas = {
						grp_objective.area
					}
				})
			end
		end
	end
end

function GroupAIStateBesiege:_verify_anticipation_spawn_point(sp_data)
	local sp_nav_seg = sp_data.nav_seg
	local area = self:get_area_from_nav_seg_id(sp_nav_seg)

	for criminal_key, c_data in pairs(self._criminals) do
		local not_safe_for_spawn = mvector3.distance(sp_data.pos, c_data.m_pos) < 2000 and math.abs(sp_data.pos.z - c_data.m_pos.z) < 300 or mvector3.distance(sp_data.pos, c_data.m_pos) < 1200
		if not c_data.status and not c_data.is_deployable and not_safe_for_spawn then
			return
		end
	end

	return true
end

function GroupAIStateBesiege:_set_assault_objective_to_group(group, phase)
	if not group.has_spawned then
		return
	end

	local phase_is_anticipation = phase == "anticipation"
	local phase_is_fade = phase == "fade"
	local current_objective = group.objective
	local approach, open_fire, push, pull_back, charge = nil
	local obstructed_area = self:_chk_group_areas_tresspassed(group)
	local group_leader_u_key, group_leader_u_data = self._determine_group_leader(group.units)
	local tactics_map = nil
	local low_carnage = self:_count_criminals_engaged_force(4) <= 4
	local task_data = self._task_data.assault
	local assaultactive = nil
	local can_update_hunter = not self._next_allowed_hunter_upd_t or self._next_allowed_hunter_upd_t < self._t
	
	if phase == "build" or phase == "sustain" then
		assaultactive = true
	end
	
	if group_leader_u_data and group_leader_u_data.tactics then
		tactics_map = {}

		for _, tactic_name in ipairs(group_leader_u_data.tactics) do
			tactics_map[tactic_name] = true
		end

		if current_objective.tactic and not tactics_map[current_objective.tactic] then
			current_objective.tactic = nil
		end

		for i_tactic, tactic_name in ipairs(group_leader_u_data.tactics) do
			if tactic_name == "deathguard" and not phase_is_anticipation then
				if current_objective.tactic == tactic_name then
					for u_key, u_data in pairs(self._char_criminals) do
						if u_data.status and current_objective.follow_unit == u_data.unit then
							local crim_nav_seg = u_data.tracker:nav_segment()

							if current_objective.area.nav_segs[crim_nav_seg] then
								--return
							end
						end
					end
				end

				local closest_crim_u_data, closest_crim_dis_sq = nil
				local crim_dis_sq_chk = not closest_crim_dis_sq or closest_u_dis_sq < closest_crim_dis_sq
				for u_key, u_data in pairs(self._char_criminals) do
					if u_data.status then
						local closest_u_id, closest_u_data, closest_u_dis_sq = self._get_closest_group_unit_to_pos(u_data.m_pos, group.units)

						if closest_u_dis_sq and crim_dis_sq_chk then
							closest_crim_u_data = u_data
							closest_crim_dis_sq = closest_u_dis_sq
						end
					end
				end

				if closest_crim_u_data then
					local search_params = {
						id = "GroupAI_deathguard",
						from_tracker = group_leader_u_data.unit:movement():nav_tracker(),
						to_tracker = closest_crim_u_data.tracker,
						access_pos = self._get_group_acces_mask(group)
					}
					local coarse_path = managers.navigation:search_coarse(search_params)

					if coarse_path then
						local grp_objective = {
							distance = 800,
							type = "assault_area",
							attitude = "engage",
							tactic = "deathguard",
							moving_in = true,
							follow_unit = closest_crim_u_data.unit,
							area = self:get_area_from_nav_seg_id(coarse_path[#coarse_path][1]),
							coarse_path = coarse_path
						}
						group.is_chasing = true

						self:_set_objective_to_enemy_group(group, grp_objective)
						self:_voice_deathguard_start(group)

						return
					end
				end
			elseif tactic_name == "hunter" and not phase_is_anticipation and can_update_hunter then
					if current_objective.tactic == tactic_name then
						for u_key, u_data in pairs(self._char_criminals) do
							if u_data.unit then
								local players_nearby = managers.player:_chk_fellow_crimin_proximity(u_data.unit)
								local crim_nav_seg = u_data.tracker:nav_segment()
								if players_nearby and players_nearby <= 0 then
									if current_objective.area.nav_segs[crim_nav_seg] then
										--return
									end
								end
							end
						end
					end
					local closest_crim_u_data, closest_crim_dis_sq = nil
					local crim_dis_sq_chk = not closest_crim_dis_sq or closest_crim_dis_sq > closest_u_dis_sq
					for u_key, u_data in pairs(self._char_criminals) do
						if u_data.unit then
							local players_nearby = managers.player:_chk_fellow_crimin_proximity(u_data.unit)
							local closest_u_id, closest_u_data, closest_u_dis_sq = self._get_closest_group_unit_to_pos(u_data.m_pos, group.units)
							if players_nearby and players_nearby <= 0 then
								if closest_u_dis_sq and crim_dis_sq_chk then
									closest_crim_u_data = u_data
									closest_crim_dis_sq = closest_u_dis_sq
								end
							end
						end
					end
					if closest_crim_u_data then
						local search_params = {
							from_tracker = group_leader_u_data.unit:movement():nav_tracker(),
							to_tracker = closest_crim_u_data.tracker,
							id = "GroupAI_deathguard",
							access_pos = self._get_group_acces_mask(group)
						}
						local coarse_path = managers.navigation:search_coarse(search_params)
						if coarse_path then
							local grp_objective = {
								type = "assault_area",
								tactic = "hunter",
								distance = 9999,
								follow_unit = closest_crim_u_data.unit,
								area = self:get_area_from_nav_seg_id(coarse_path[#coarse_path][1]),
								coarse_path = coarse_path,
								attitude = "engage",
								moving_in = true
							}
							group.is_chasing = true
							self:_set_objective_to_enemy_group(group, grp_objective)
							return
						end
					end
					self._next_allowed_hunter_upd_t = self._t + 1.5
			elseif tactic_name == "charge" and not current_objective.moving_out and not self._activeassaultbreak and not current_objective.charge and not self._feddensityhigh and not tactics_map.obstacle then
				charge = true
			end
		end
	end

	local objective_area = nil

	if obstructed_area then
		if current_objective.moving_out then
			if not current_objective.open_fire and not self._feddensityhigh and not self._activeassaultbreak then
				open_fire = true
			end
		elseif not current_objective.pushed and not self._feddensityhigh and not self._activeassaultbreak or charge and not current_objective.charge and not self._feddensityhigh and not self._activeassaultbreak then
			push = true
		end
	else
		local obstructed_path_index = self:_chk_coarse_path_obstructed(group)

		if obstructed_path_index and phase_is_anticipation then
			--print("obstructed_path_index", obstructed_path_index)

			objective_area = self:get_area_from_nav_seg_id(group.coarse_path[math.max(obstructed_path_index - 1, 1)][1])
			if phase_is_anticipation then
				pull_back = true
			end
		elseif not current_objective.moving_out then
			local has_criminals_close = nil
			
			for area_id, neighbour_area in pairs(current_objective.area.neighbours) do
				if next(neighbour_area.criminal.units) then
					has_criminals_close = true

					break
				end
			end
			
			if phase_is_anticipation and current_objective.open_fire or self._feddensityhigh or self._activeassaultbreak then
				pull_back = true
			elseif not self._feddensityhigh and not self._activeassaultbreak and phase_is_anticipation and not has_criminals_close then
				approach = true
			elseif not phase_is_anticipation and not current_objective.open_fire and not self._feddensityhigh and not self._activeassaultbreak then
				open_fire = true
				self:_voice_open_fire_start(group)
			elseif charge and not phase_is_anticipation and not self._feddensityhigh and not self._activeassaultbreak or low_carnage and not phase_is_anticipation and not self._feddensityhigh and not self._activeassaultbreak then
				push = true
			elseif not self._feddensityhigh and not self._activeassaultbreak and not phase_is_anticipation and self._drama_data.amount <= self._drama_data.low_p then
				push = true
			end
		end
	end

	objective_area = objective_area or current_objective.area

	if open_fire then
		local grp_objective = {
			attitude = "engage",
			pose = "stand",
			type = "assault_area",
			stance = "hos",
			open_fire = true,
			tactic = current_objective.tactic,
			area = obstructed_area or current_objective.area,
			coarse_path = {
				{
					objective_area.pos_nav_seg,
					mvector3.copy(current_objective.area.pos)
				}
			}
		}

		self:_set_objective_to_enemy_group(group, grp_objective)
		self:_voice_open_fire_start(group)
	elseif approach or push then
		local assault_area, alternate_assault_area, alternate_assault_area_from, assault_path, alternate_assault_path = nil
		local assault_area_uno, assault_area_dos, assault_area_tres, assault_area_quatro = nil
		local assault_path_uno, assault_path_dos, assault_path_tres, assault_path_quatro = nil
		local from_seg, to_seg, access_pos, verify_clbk = nil
		local to_search_areas = {
			objective_area
		}
		local found_areas = {
			[objective_area] = "init"
		}

		repeat
			local search_area = table.remove(to_search_areas, 1)
			-- they never used this function for some reason, now i use it, so thats nice
			if self:chk_area_leads_to_enemy(current_objective.area.pos_nav_seg, search_area.pos_nav_seg, true) then
				local assault_from_here = true
				
				if search_area then
						--local cop_units = assault_from_area.police.units

						for u_key, u_data in pairs(group.units) do
							if u_data.group and u_data.group.objective.type == "assault_area" then

							if not alternate_assault_area then
								local search_params = {
									id = "GroupAI_assault",
									from_seg = current_objective.area.pos_nav_seg,
									to_seg = search_area.pos_nav_seg,
									access_pos = self._get_group_acces_mask(group),
									verify_clbk = callback(self, self, "is_nav_seg_safe")
								}
								alternate_assault_path = managers.navigation:search_coarse(search_params)

								if alternate_assault_path then
									local clean_path = self:_merge_coarse_path_by_area(alternate_assault_path)
									
									alternate_assault_path = clean_path
									
									alternate_assault_area = search_area
									alternate_assault_area_from = current_objective.area
								end
							end

							found_areas[search_area] = nil

							break
						end
					end
				
					if assault_from_here then
						local search_params = {
							id = "GroupAI_assault",
							from_seg = current_objective.area.pos_nav_seg,
							to_seg = search_area.pos_nav_seg,
							access_pos = self._get_group_acces_mask(group),
							verify_clbk = callback(self, self, "is_nav_seg_safe")
						}
						assault_path = managers.navigation:search_coarse(search_params)

						if assault_path then
							local clean_path = self:_merge_coarse_path_by_area(assault_path)
							
							assault_path = clean_path
							assault_area = search_area
							
							if not assault_area_uno then
								assault_area_uno = assault_area
							elseif not assault_area_dos then
								assault_area_dos = assault_area
							elseif not assault_area_tres then
								assault_area_tres = assault_area
							elseif not assault_area_quatro then
								assault_area_quatro = assault_area
							end
							
							if not assault_path_uno then
								assault_path_uno = assault_path
							elseif not assault_path_dos then
								assault_path_dos = assault_path
							elseif not assault_path_tres then
								assault_path_tres = assault_path
							elseif not assault_path_quatro then
								assault_path_quatro = assault_path
							end

							break
						end
					end
				else
					for other_area_id, other_area in pairs(search_area.neighbours) do
						if not found_areas[other_area] then
							table.insert(to_search_areas, other_area)

							found_areas[other_area] = search_area
						end
					end
				end
			end
		until #to_search_areas == 0

		if not assault_path_uno or not assault_area_uno then
			--log("dicks")
			if alternate_assault_area and alternate_assault_path then
				assault_area = alternate_assault_area
				found_areas[assault_area] = alternate_assault_area_from
				assault_path = alternate_assault_path
			else
				--log("couldn't find assault path for" .. group .. "in groupaistatebesiege!!!")
			end
		else
			local path_and_area_to_choose = math.random(1, 4)
			if not tactics_map or tactics_map and not tactics_map.flank then 
				assault_area = assault_area_uno
				assault_path = assault_path_uno
			elseif path_and_area_to_choose == 2 then
				assault_area = assault_area_dos
				assault_path = assault_path_dos
			elseif path_and_area_to_choose == 3 then
				assault_area = assault_area_tres
				assault_path = assault_path_tres
			elseif path_and_area_to_choose == 4 then
				assault_area = assault_area_quatro
				assault_path = assault_path_quatro
			end
		end
	
		if assault_area and assault_path then
			local assault_area = push and assault_area or found_areas[assault_area] == current_objective.area and objective_area or current_objective.area

			if #assault_path > 4 and assault_area.nav_segs[assault_path[#assault_path - 1][1]] then
				table.remove(assault_path)
			end

			local used_grenade = nil

			if push then
				local detonate_pos = nil
				
				if math.random() < 0.05 or self._drama_data.amount <= self._drama_data.low_p and math.random() < 0.5 then
					for c_key, c_data in pairs(assault_area.criminal.units) do
						detonate_pos = c_data.unit:movement():m_pos()

						break
					end
				end

				if not used_grenade or used_grenade == nil then
					used_grenade = self:_chk_group_use_smoke_grenade(group, self._task_data.assault, detonate_pos)
				end
				
				if not used_grenade or used_grenade == nil then
					used_grenade = self:_chk_group_use_flash_grenade(group, self._task_data.assault, detonate_pos)
				end
				
				if not used_grenade then
					--log("group doesnt have tactic for this")
				elseif used_grenade then
					--log("cool")
				end

				self:_voice_move_in_start(group)
			end

			local grp_objective = {
				type = "assault_area",
				stance = "hos",
				area = assault_area,
				coarse_path = assault_path,
				pose = push and math.random() < 0.5 and "crouch" or "stand",
				attitude = push and "engage" or "avoid",
				moving_in = push and true or nil,
				open_fire = push or nil,
				pushed = push or nil,
				charge = charge,
				interrupt_dis = charge and 0 or nil
			}
			group.is_chasing = group.is_chasing or push

			self:_set_objective_to_enemy_group(group, grp_objective)
		end
	elseif pull_back then
		local retreat_area, do_not_retreat = nil

		for u_key, u_data in pairs(group.units) do
			local nav_seg_id = u_data.tracker:nav_segment()

			if current_objective.area.nav_segs[nav_seg_id] then
				retreat_area = current_objective.area

				break
			end

			if self:is_nav_seg_safe(nav_seg_id) then
				retreat_area = self:get_area_from_nav_seg_id(nav_seg_id)

				break
			end
		end

		if not retreat_area and not do_not_retreat and current_objective.coarse_path then
			local forwardmost_i_nav_point = self:_get_group_forwardmost_coarse_path_index(group)

			if forwardmost_i_nav_point then
				local nearest_safe_nav_seg_id = current_objective.coarse_path(forwardmost_i_nav_point)
				retreat_area = self:get_area_from_nav_seg_id(nearest_safe_nav_seg_id)
			end
		end

		if retreat_area then
			local new_grp_objective = {
				attitude = "avoid",
				stance = "hos",
				pose = math.random() < 0.5 and "crouch" or "stand",
				type = "assault_area",
				area = retreat_area,
				coarse_path = {
					{
						retreat_area.pos_nav_seg,
						mvector3.copy(retreat_area.pos)
					}
				}
			}
			group.is_chasing = nil

			self:_set_objective_to_enemy_group(group, new_grp_objective)

			return
		end
	end
end

function GroupAIStateBesiege:_end_regroup_task()
	if self._task_data.regroup.active then
		self._task_data.regroup.active = nil

		managers.trade:set_trade_countdown(true)
		self:set_assault_mode(false)

		if not self._smoke_grenade_ignore_control then
			managers.network:session():send_to_peers_synched("sync_smoke_grenade_kill")
			self:sync_smoke_grenade_kill()
		end

		local dmg = self._downs_during_assault
		local limits = tweak_data.group_ai.bain_assault_praise_limits
		local result = dmg < limits[1] and 0 or dmg < limits[2] and 1 or 2
		
		if self._downs_during_assault > 4 then
			self._assault_was_hell = true
		end

		managers.mission:call_global_event("end_assault_late")
		managers.groupai:dispatch_event("end_assault_late", self._assault_number)
		managers.hud:end_assault(result)
		self:_mark_hostage_areas_as_unsafe()
		self:_set_rescue_state(true)

		if not self._task_data.assault.next_dispatch_t then
			local assault_delay = self._tweak_data.assault.delay
			local breaktime = self._assault_was_hell and 15 or 0
			self._task_data.assault.next_dispatch_t = self._t + self:_get_difficulty_dependent_value(assault_delay) + breaktime
		end

		if self._draw_drama then
			self._draw_drama.regroup_hist[#self._draw_drama.regroup_hist][2] = self._t
		end

		self._task_data.recon.next_dispatch_t = self._t
	end
end

function GroupAIStateBesiege:_upd_recon_tasks()
	local task_data = self._task_data.recon.tasks[1]

	self:_assign_enemy_groups_to_recon()

	if not task_data then
		return
	end

	local t = self._t

	self:_assign_assault_groups_to_retire()

	local target_pos = task_data.target_area.pos
	local nr_wanted = self:_get_difficulty_dependent_value(self._tweak_data.recon.force) - self:_count_police_force("recon")

	if nr_wanted <= 0 then
		return
	end

	local used_event, used_spawn_points, reassigned = nil

	if task_data.use_spawn_event then
		task_data.use_spawn_event = false

		if self:_try_use_task_spawn_event(t, task_data.target_area, "recon") then
			used_event = true
		end
	end

	if not used_event then
		local used_group = nil

		if next(self._spawning_groups) then
			used_group = true
		else
			local spawn_group, spawn_group_type = self:_find_spawn_group_near_area(task_data.target_area, self._tweak_data.recon.groups, nil, nil, callback(self, self, "_verify_anticipation_spawn_point"))

			if spawn_group then
				local grp_objective = {
					attitude = "avoid",
					scan = true,
					stance = "hos",
					type = "recon_area",
					area = spawn_group.area,
					target_area = task_data.target_area
				}

				self:_spawn_in_group(spawn_group, spawn_group_type, grp_objective)

				used_group = true
			end
		end
	end

	if used_event or used_spawn_points or reassigned then
		table.remove(self._task_data.recon.tasks, 1)

		self._task_data.recon.next_dispatch_t = t + math.ceil(self:_get_difficulty_dependent_value(self._tweak_data.recon.interval))
	end
end

function GroupAIStateBesiege:_upd_regroup_task()
	local regroup_task = self._task_data.regroup
	
	if regroup_task.active then
		self:_assign_assault_groups_to_retire()

		if regroup_task.end_t < self._t and self._drama_data.amount < tweak_data.drama.assault_fade_end then
			self:_end_regroup_task()
		end
	end
end

function GroupAIStateBesiege:_perform_group_spawning(spawn_task, force, use_last)
	local nr_units_spawned = 0
	local produce_data = {
		name = true,
		spawn_ai = {}
	}
	local group_ai_tweak = tweak_data.group_ai
	local spawn_points = spawn_task.spawn_group.spawn_pts

	local function _try_spawn_unit(u_type_name, spawn_entry)
		if self._feddensityhigh or self._activeassaultbreak then
			return
		end
		
		if GroupAIStateBesiege._MAX_SIMULTANEOUS_SPAWNS <= nr_units_spawned and not force then
			return
		end

		local hopeless = true
		local current_unit_type = tweak_data.levels:get_ai_group_type()

		for _, sp_data in ipairs(spawn_points) do
			local category = group_ai_tweak.unit_categories[u_type_name]
			local stop_please = sp_data.accessibility == "any" or category.access[sp_data.accessibility]
			local please_stop = not sp_data.amount or sp_data.amount > 0
			if stop_please and please_stop and sp_data.mission_element:enabled() then
				hopeless = false

				if sp_data.delay_t < self._t then
					local units = category.unit_types[current_unit_type]
					produce_data.name = units[math.random(#units)]
					produce_data.name = managers.modifiers:modify_value("GroupAIStateBesiege:SpawningUnit", produce_data.name)
					local spawned_unit = sp_data.mission_element:produce(produce_data)
					local u_key = spawned_unit:key()
					local objective = nil

					if spawn_task.objective then
						objective = self.clone_objective(spawn_task.objective)
					else
						objective = spawn_task.group.objective.element:get_random_SO(spawned_unit)

						if not objective then
							spawned_unit:set_slot(0)

							return true
						end

						objective.grp_objective = spawn_task.group.objective
					end

					local u_data = self._police[u_key]

					self:set_enemy_assigned(objective.area, u_key)

					if spawn_entry.tactics then
						u_data.tactics = spawn_entry.tactics
						u_data.tactics_map = {}

						for _, tactic_name in ipairs(u_data.tactics) do
							u_data.tactics_map[tactic_name] = true
						end
					end

					spawned_unit:brain():set_spawn_entry(spawn_entry, u_data.tactics_map)

					u_data.rank = spawn_entry.rank

					self:_add_group_member(spawn_task.group, u_key)

					if spawned_unit:brain():is_available_for_assignment(objective) then
						if objective.element then
							objective.element:clbk_objective_administered(spawned_unit)
						end

						spawned_unit:brain():set_objective(objective)
					else
						spawned_unit:brain():set_followup_objective(objective)
					end

					nr_units_spawned = nr_units_spawned + 1

					if spawn_task.ai_task then
						spawn_task.ai_task.force_spawned = spawn_task.ai_task.force_spawned + 1
						spawned_unit:brain()._logic_data.spawned_in_phase = spawn_task.ai_task.phase
					end

					sp_data.delay_t = self._t + sp_data.interval

					if sp_data.amount then
						sp_data.amount = sp_data.amount - 1
					end

					return true
				end
			end
		end

		if hopeless then
			--debug_pause("[GroupAIStateBesiege:_upd_group_spawning] spawn group", spawn_task.spawn_group.id, "failed to spawn unit", u_type_name)

			return true
		end
	end

	for u_type_name, spawn_info in pairs(spawn_task.units_remaining) do
		if not group_ai_tweak.unit_categories[u_type_name].access.acrobatic then
			for i = spawn_info.amount, 1, -1 do
				local success = _try_spawn_unit(u_type_name, spawn_info.spawn_entry)

				if success then
					spawn_info.amount = spawn_info.amount - 1
				end

				break
			end
		end
	end

	for u_type_name, spawn_info in pairs(spawn_task.units_remaining) do
		for i = spawn_info.amount, 1, -1 do
			local success = _try_spawn_unit(u_type_name, spawn_info.spawn_entry)

			if success then
				spawn_info.amount = spawn_info.amount - 1
			end

			break
		end
	end

	local complete = true

	for u_type_name, spawn_info in pairs(spawn_task.units_remaining) do
		if spawn_info.amount > 0 then
			complete = false

			break
		end
	end

	if complete then
		spawn_task.group.has_spawned = true
		self:_voice_groupentry(spawn_task.group)
		table.remove(self._spawning_groups, use_last and #self._spawning_groups or 1)

		if spawn_task.group.size <= 0 then
			self._groups[spawn_task.group.id] = nil
		end
	end
end



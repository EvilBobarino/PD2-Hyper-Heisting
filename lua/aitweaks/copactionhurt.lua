local mvec3_set = mvector3.set
local mvec3_set_z = mvector3.set_z
local mvec3_set_l = mvector3.set_length
local mvec3_sub = mvector3.subtract
local mvec3_add = mvector3.add
local mvec3_mul = mvector3.multiply
local mvec3_dot = mvector3.dot
local mvec3_cross = mvector3.cross
local mvec3_norm = mvector3.normalize
local mvec3_dir = mvector3.direction
local mvec3_rand_orth = mvector3.random_orthogonal
local mvec3_dis = mvector3.distance
local tmp_vec1 = Vector3()
local tmp_vec2 = Vector3()
local tmp_vec3 = Vector3()
CopActionHurt = CopActionHurt or class()
CopActionHurt.running_death_anim_variants = {
	male = 26,
	female = 5
}
CopActionHurt.death_anim_variants = {
	normal = {
		crouching = {
			fwd = {
				high = 14,
				low = 5
			},
			bwd = {
				high = 3,
				low = 1
			},
			l = {
				high = 3,
				low = 1
			},
			r = {
				high = 3,
				low = 1
			}
		},
		not_crouching = {
			fwd = {
				high = 14,
				low = 5
			},
			bwd = {
				high = 3,
				low = 2
			},
			l = {
				high = 3,
				low = 1
			},
			r = {
				high = 3,
				low = 1
			}
		}
	},
	heavy = {
		crouching = {
			fwd = {
				high = 7,
				low = 2
			},
			bwd = {
				high = 3,
				low = 1
			},
			l = {
				high = 3,
				low = 1
			},
			r = {
				high = 3,
				low = 1
			}
		},
		not_crouching = {
			fwd = {
				high = 6,
				low = 2
			},
			bwd = {
				high = 1,
				low = 1
			},
			l = {
				high = 1,
				low = 1
			},
			r = {
				high = 1,
				low = 1
			}
		}
	}
}
CopActionHurt.death_anim_fe_variants = {
	normal = {
		crouching = {
			fwd = {
				high = 5,
				low = 2
			},
			bwd = {
				high = 2,
				low = 0
			},
			l = {
				high = 2,
				low = 0
			},
			r = {
				high = 2,
				low = 0
			}
		},
		not_crouching = {
			fwd = {
				high = 6,
				low = 2
			},
			bwd = {
				high = 3,
				low = 0
			},
			l = {
				high = 2,
				low = 0
			},
			r = {
				high = 2,
				low = 0
			}
		}
	},
	heavy = {
		crouching = {
			fwd = {
				high = 0,
				low = 0
			},
			bwd = {
				high = 0,
				low = 0
			},
			l = {
				high = 0,
				low = 0
			},
			r = {
				high = 0,
				low = 0
			}
		},
		not_crouching = {
			fwd = {
				high = 0,
				low = 0
			},
			bwd = {
				high = 0,
				low = 0
			},
			l = {
				high = 0,
				low = 0
			},
			r = {
				high = 0,
				low = 0
			}
		}
	}
}
CopActionHurt.hurt_anim_variants_highest_num = 21
CopActionHurt.hurt_anim_variants = {
	hurt = {
		not_crouching = {
			fwd = {
				high = 13,
				low = 5
			},
			bwd = {
				high = 5,
				low = 2
			},
			l = {
				high = 5,
				low = 2
			},
			r = {
				high = 5,
				low = 2
			}
		}
	},
	heavy_hurt = {
		not_crouching = {
			fwd = {
				high = 21,
				low = 7
			},
			bwd = {
				high = 14,
				low = 7
			},
			l = {
				high = 11,
				low = 4
			},
			r = {
				high = 11,
				low = 4
			}
		}
	},
	expl_hurt = {
		bwd = 15,
		l = 13,
		fwd = 15,
		r = 13
	},
	fire_hurt = {
		bwd = 8,
		l = 7,
		fwd = 8,
		r = 7
	}
}
CopActionHurt.running_hurt_anim_variants = {
	fwd = 14
}
CopActionHurt.shield_knock_variants = 5
ShieldActionHurt = ShieldActionHurt or class(CopActionHurt)
ShieldActionHurt.hurt_anim_variants = deep_clone(CopActionHurt.hurt_anim_variants)
ShieldActionHurt.hurt_anim_variants.expl_hurt = {
	bwd = 2,
	l = 2,
	fwd = 2,
	r = 2
}
ShieldActionHurt.hurt_anim_variants.fire_hurt = {
	bwd = 2,
	l = 2,
	fwd = 2,
	r = 2
}
CopActionHurt.fire_death_anim_variants_length = {
	9,
	5,
	5,
	7,
	4
}
CopActionHurt.network_allowed_hurt_types = {
	light_hurt = true,
	shield_knock = true,
	hurt = true,
	heavy_hurt = true,
	death = true,
	fatal = true,
	fire_hurt = true,
	poison_hurt = true,
	bleedout = true,
	knock_down = true,
	expl_hurt = true,
	stagger = true
}

function CopActionHurt:init(action_desc, common_data)
	self._common_data = common_data
	self._ext_movement = common_data.ext_movement
	self._ext_inventory = common_data.ext_inventory
	self._ext_anim = common_data.ext_anim
	self._body_part = action_desc.body_part
	self._unit = common_data.unit
	self._machine = common_data.machine
	self._attention = common_data.attention
	self._action_desc = action_desc
	local t = TimerManager:game():time()
	local tweak_table = self._unit:base()._tweak_table
	local is_civilian = CopDamage.is_civilian(tweak_table)
	local is_female = (self._machine:get_global("female") or 0) == 1
	local crouching = self._unit:anim_data().crouch or self._unit:anim_data().hurt and self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "crh") > 0
	local redir_res = nil
	local action_type = action_desc.hurt_type
	local ignite_character = action_desc.ignite_character
	local start_dot_dance_antimation = action_desc.fire_dot_data and action_desc.fire_dot_data.start_dot_dance_antimation
	local common_cop = self._unit:base():has_tag("law") and not self._unit:base():has_tag("special")

	if action_type == "knock_down" then
		action_type = "heavy_hurt"
	end

	if action_type == "fatal" then
		redir_res = self._ext_movement:play_redirect("fatal")

		if not redir_res then
			debug_pause("[CopActionHurt:init] fatal redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		managers.hud:set_mugshot_downed(self._unit:unit_data().mugshot_id)
	elseif action_desc.variant == "tase" then
		if not managers.groupai:state():is_unit_team_AI(self._unit) then
			local tase_time = self._unit:character_damage() ~= nil and self._unit:character_damage()._tased_time
			local down_time = self._unit:character_damage() ~= nil and self._unit:character_damage()._tased_down_time --in case you want to set it up

			if tase_time then
				self._tased_time = t + tase_time
				self._unit:character_damage()._tased_time = nil

				if down_time then
					self._tased_down_time = t + down_time
					self._unit:character_damage()._tased_down_time = nil
				end

				redir_res = self._ext_movement:play_redirect("tased")

				if not redir_res then
					debug_pause("[CopActionHurt:init] tased redirect failed in", self._machine:segment_state(Idstring("base")))

					return
				end

				if self._unit:base():has_tag("taser") then
					self._unit:sound():say("tasered", true)
				else
					self._unit:sound():say("x01a_any_3p", true) --standard hurt line
				end

				self._tased_effect = nil
				local tase_effect_table = self._unit:character_damage() ~= nil and self._unit:character_damage()._tase_effect_table

				--spawn blue tase effect
				if tase_effect_table then
					self._tased_effect = World:effect_manager():spawn(tase_effect_table)
				end

				self.update = self._upd_tased
			else
				return
			end
		else
			redir_res = self._ext_movement:play_redirect("tased")

			if not redir_res then
				debug_pause("[CopActionHurt:init] tased redirect failed in", self._machine:segment_state(Idstring("base")))

				return
			end

			managers.hud:set_mugshot_tased(self._unit:unit_data().mugshot_id)
		end
	elseif action_type == "fire_hurt" or action_type == "light_hurt" and action_desc.variant == "fire" then
		local char_tweak = tweak_data.character[self._unit:base()._tweak_table]
		local use_animation_on_fire_damage = nil

		if char_tweak.use_animation_on_fire_damage == nil then
			use_animation_on_fire_damage = true
		else
			use_animation_on_fire_damage = char_tweak.use_animation_on_fire_damage
		end

		if start_dot_dance_antimation then
			if ignite_character == "dragonsbreath" then
				self:_dragons_breath_sparks()
			end

			if self._unit:character_damage() ~= nil and self._unit:character_damage().get_last_time_unit_got_fire_damage ~= nil then
				local last_fire_recieved = self._unit:character_damage():get_last_time_unit_got_fire_damage()

				if last_fire_recieved == nil or t - last_fire_recieved > 1 then
					if use_animation_on_fire_damage then
						redir_res = self._ext_movement:play_redirect("fire_hurt")
						local dir_str = nil
						local fwd_dot = action_desc.direction_vec:dot(common_data.fwd)

						if fwd_dot < 0 then
							local hit_pos = action_desc.hit_pos
							local hit_vec = (hit_pos - common_data.pos):with_z(0):normalized()

							if mvector3.dot(hit_vec, common_data.right) > 0 then
								dir_str = "r"
							else
								dir_str = "l"
							end
						else
							dir_str = "bwd"
						end

						self._machine:set_parameter(redir_res, dir_str, 1)
					end

					self._unit:character_damage():set_last_time_unit_got_fire_damage(t)
				end
			end
		end
	elseif action_type == "taser_tased" then
		local char_tweak = tweak_data.character[self._unit:base()._tweak_table]

		if (char_tweak.can_be_tased == nil or char_tweak.can_be_tased) and self._unit:brain() and self._unit:brain()._current_logic_name ~= "intimidated" then
			redir_res = self._ext_movement:play_redirect("taser")
			local variant = self:_pseudorandom(4)
			local dir_str = nil

			if variant == 1 then
				dir_str = "var1"
			elseif variant == 2 then
				dir_str = "var2"
			elseif variant == 3 then
				dir_str = "var3"
			elseif variant == 4 then
				dir_str = "var4"
			else
				dir_str = "fwd"
			end

			self._tased_effect = nil
			local tase_effect_table = self._unit:character_damage() ~= nil and self._unit:character_damage()._tase_effect_table

			--add tase effect for the usual tase (like against Shields)
			if tase_effect_table then
				self._tased_effect = World:effect_manager():spawn(tase_effect_table)
			end

			self._machine:set_parameter(redir_res, dir_str, 1)
		end
	elseif action_type == "light_hurt" then
		--prevent light_hurt from showing when doing animations like climbing, etc
		if self._unit:anim_data() and self._unit:anim_data().act then
			return
		end

		if not self._ext_anim.upper_body_active or self._ext_anim.upper_body_empty or self._ext_anim.recoil then
			redir_res = self._ext_movement:play_redirect(action_type)

			if not redir_res then
				debug_pause("[CopActionHurt:init] light_hurt redirect failed in", self._machine:segment_state(Idstring("upper_body")))

				return
			end

			local dir_str = nil
			local fwd_dot = action_desc.direction_vec:dot(common_data.fwd)

			if fwd_dot < 0 then
				local hit_pos = action_desc.hit_pos
				local hit_vec = (hit_pos - common_data.pos):with_z(0):normalized()

				if mvector3.dot(hit_vec, common_data.right) > 0 then
					dir_str = "r"
				else
					dir_str = "l"
				end
			else
				dir_str = "bwd"
			end

			self._machine:set_parameter(redir_res, dir_str, 1)

			local height_str = self._ext_movement:m_com().z < action_desc.hit_pos.z and "high" or "low"

			self._machine:set_parameter(redir_res, height_str, 1)
		end

		self._expired = true

		return true
	elseif action_type == "concussion" then
		redir_res = self._ext_movement:play_redirect("concussion_stun")
		local rnd_max = 9
		local rnd_anim = self:_pseudorandom(rnd_max)
		local rnd_anim_str = "var" .. tostring(rnd_anim)

		self._machine:set_parameter(redir_res, rnd_anim_str, 1)

		self._sick_time = t + 3
	elseif action_type == "hurt_sick" then
		local ecm_hurts_table = self._common_data.char_tweak.ecm_hurts

		if not ecm_hurts_table then
			debug_pause_unit(self._unit, "[CopActionHurt:init] Unit missing ecm_hurts in Character Tweak Data", self._unit)

			return
		end

		redir_res = self._ext_movement:play_redirect("hurt_sick")

		if not redir_res then
			debug_pause("[CopActionHurt:init] hurt_sick redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		local is_cop = true

		if is_civilian then
			is_cop = false
		end

		local sick_variants = {}

		for i, d in pairs(ecm_hurts_table) do
			table.insert(sick_variants, i)
		end

		local variant = sick_variants[self:_pseudorandom(#sick_variants)]
		local duration_diff = ecm_hurts_table[variant].max_duration - ecm_hurts_table[variant].min_duration
		local duration = ecm_hurts_table[variant].min_duration + duration_diff * self:_pseudorandom()

		for _, hurt_sick in ipairs(sick_variants) do
			self._machine:set_global(hurt_sick, hurt_sick == variant and 1 or 0)
		end

		self._sick_time = t + duration
	elseif action_type == "poison_hurt" then
		redir_res = self._ext_movement:play_redirect("hurt_poison")

		if not redir_res then
			debug_pause("[CopActionHurt:init] hurt_sick redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		self._sick_time = t + 2
	elseif action_type == "bleedout" then
		redir_res = self._ext_movement:play_redirect("bleedout")

		if not redir_res then
			debug_pause("[CopActionHurt:init] bleedout redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end
	elseif action_type == "death" and action_desc.variant == "fire" then
		local variant = 1
		local variant_count = #CopActionHurt.fire_death_anim_variants_length or 5

		if variant_count > 1 then
			variant = self:_pseudorandom(variant_count)
		end

		if not self._ext_movement:died_on_rope() then
			self:_prepare_ragdoll()
			
			redir_res = self._ext_movement:play_redirect("death_fire")

			if not redir_res then
				debug_pause("[CopActionHurt:init] death_fire redirect failed in", self._machine:segment_state(Idstring("base")))

				return
			end

			for i = 1, variant_count do
				local state_value = 0

				if i == variant then
					state_value = 1
				end

				self._machine:set_parameter(redir_res, "var" .. tostring(i), state_value)
			end
		else
			self:force_ragdoll()
		end

		self:_start_enemy_fire_effect_on_death(variant)
		managers.fire:check_achievemnts(self._unit, t)
	elseif action_type == "death" and action_desc.variant == "poison" then
		self:force_ragdoll()
	elseif action_type == "death" and (self._ext_anim.run and self._ext_anim.move_fwd or self._ext_anim.sprint) and not common_data.char_tweak.no_run_death_anim then
		self:_prepare_ragdoll()
		
		redir_res = self._ext_movement:play_redirect("death_run")

		if not redir_res then
			debug_pause("[CopActionHurt:init] death_run redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		local variant = self.running_death_anim_variants[is_female and "female" or "male"] or 1

		if variant > 1 then
			variant = self:_pseudorandom(variant)
		end

		self._machine:set_parameter(redir_res, "var" .. tostring(variant), 1)
	elseif action_type == "death" and (self._ext_anim.run or self._ext_anim.ragdoll) and self:_start_ragdoll() then
		self.update = self._upd_ragdolled
	elseif action_type == "heavy_hurt" and (self._ext_anim.run or self._ext_anim.sprint) and not common_data.is_suppressed and not crouching then
		redir_res = self._ext_movement:play_redirect("heavy_run")

		if not redir_res then
			debug_pause("[CopActionHurt:init] heavy_run redirect failed in", self._machine:segment_state(Idstring("base")))

			return
		end

		local variant = self.running_hurt_anim_variants.fwd or 1

		if variant > 1 then
			variant = self:_pseudorandom(variant)
		end

		self._machine:set_parameter(redir_res, "var" .. tostring(variant), 1)
	else
		local variant, height, old_variant, old_info = nil

		if (action_type == "hurt" or action_type == "heavy_hurt") and self._ext_anim.hurt then
			for i = 1, self.hurt_anim_variants_highest_num do
				if self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "var" .. i) then
					old_variant = i

					break
				end
			end

			if old_variant ~= nil then
				old_info = {
					fwd = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "fwd"),
					bwd = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "bwd"),
					l = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "l"),
					r = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "r"),
					high = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "high"),
					low = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "low"),
					crh = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "crh"),
					mod = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "mod"),
					hvy = self._machine:get_parameter(self._machine:segment_state(Idstring("base")), "hvy")
				}
			end
		end
		
		local redirect = action_type

		if action_type == "shield_knock" then
			local rand = self:_pseudorandom(CopActionHurt.shield_knock_variants, 0)
			redirect = "shield_knock_var" .. tostring(rand)
		end

		if redirect then
			redir_res = self._ext_movement:play_redirect(redirect)
		else
			Application:stack_dump_error("There's no redirect in CopActionHurt!")
		end

		if not redir_res then
			debug_pause_unit(self._unit, "[CopActionHurt:init]", redirect, "redirect failed in", self._machine:segment_state(Idstring("base")), self._unit)

			return
		end

		if action_desc.variant == "bleeding" then
			-- Nothing
		else
			local nr_variants = self._ext_anim.base_nr_variants
			local death_type = nil

			if nr_variants then
				variant = self:_pseudorandom(nr_variants)
			else
				local fwd_dot = action_desc.direction_vec:dot(common_data.fwd)
				local right_dot = action_desc.direction_vec:dot(common_data.right)
				local dir_str = nil
				
				if math.abs(right_dot) < math.abs(fwd_dot) then
					if fwd_dot < 0 then
						dir_str = "fwd"
					else
						dir_str = "bwd"
					end
				elseif right_dot > 0 then
					dir_str = "l"
				else
					dir_str = "r"
				end

				self._machine:set_parameter(redir_res, dir_str, 1)

				local hit_z = action_desc.hit_pos.z

				if self._ext_movement:m_com().z < hit_z then
					height = "high"
				else
					height = "low"
				end

				if action_type == "death" then
					if is_civilian then
						death_type = "normal"
					else
						death_type = action_desc.death_type
					end
					
					local variant_chk = not is_female or self.death_anim_fe_variants[death_type][crouching and "crouching" or "not_crouching"][dir_str][height]

					variant = variant_chk and self.death_anim_variants[death_type][crouching and "crouching" or "not_crouching"][dir_str][height]

					if variant > 1 then
						variant = self:_pseudorandom(variant)
					end
					
					self:_prepare_ragdoll()
				elseif action_type ~= "shield_knock" and action_type ~= "counter_tased" and action_type ~= "taser_tased" then
					local old_info_chk = old_info and old_info[dir_str] == 1 and old_info[height] == 1 and old_info.mod == 1 and action_type == "hurt" or old_info and old_info.hvy and old_info.hvy == 1 and action_type == "heavy_hurt"
					
					if old_variant and old_info_chk then
						variant = old_variant
					end

					if not variant then
						if action_type == "expl_hurt" then
							variant = self.hurt_anim_variants[action_type][dir_str]
						else
							variant = self.hurt_anim_variants[action_type].not_crouching[dir_str][height]
						end

						if variant > 1 then
							variant = self:_pseudorandom(variant)
						end
					end
				elseif action_type == "shield_knock" then
					-- Nothing
				end
			end

			variant = variant or 1

			if variant then
				self._machine:set_parameter(redir_res, "var" .. tostring(variant), 1)
			end

			if height then
				self._machine:set_parameter(redir_res, height, 1)
			end

			if crouching then
				self._machine:set_parameter(redir_res, "crh", 1)
			end

			if action_type == "hurt" then
				self._machine:set_parameter(redir_res, "mod", 1)
			elseif action_type == "heavy_hurt" then
				self._machine:set_parameter(redir_res, "hvy", 1)
			elseif action_type == "death" and (death_type or action_desc.death_type) == "heavy" and not is_civilian then
				self._machine:set_parameter(redir_res, "heavy", 1)
			elseif action_type == "expl_hurt" then
				self._machine:set_parameter(redir_res, "expl", 1)
			end
		end
	end

	if self._ext_anim.upper_body_active and not self._ragdolled then
		self._ext_movement:play_redirect("up_idle")
	end

	self._last_vel_z = 0
	self._hurt_type = action_type
	self._variant = action_desc.variant
	self._body_part = action_desc.body_part

	if action_type == "bleedout" then
		self.update = self._upd_bleedout
		self._shoot_t = t + 1

		if Network:is_server() then
			self._ext_inventory:equip_selection(1, true)
		end

		local weapon_unit = self._ext_inventory:equipped_unit()
		self._weapon_base = weapon_unit:base()
		local weap_tweak = weapon_unit:base():weapon_tweak_data()
		local weapon_usage_tweak = common_data.char_tweak.weapon[weap_tweak.usage]
		self._weapon_unit = weapon_unit
		self._weap_tweak = weap_tweak
		self._w_usage_tweak = weapon_usage_tweak
		self._reload_speed = weapon_usage_tweak.RELOAD_SPEED
		self._spread = weapon_usage_tweak.spread
		self._falloff = weapon_usage_tweak.FALLOFF
		self._head_modifier_name = Idstring("look_head")
		self._arm_modifier_name = Idstring("aim_r_arm")
		self._head_modifier = self._machine:get_modifier(self._head_modifier_name)
		self._arm_modifier = self._machine:get_modifier(self._arm_modifier_name)
		self._aim_vec = mvector3.copy(common_data.fwd)
		self._anim = redir_res

		if not self._shoot_history then
			self._shoot_history = {
				focus_error_roll = self:_pseudorandom(360),
				focus_start_t = t,
				focus_delay = weapon_usage_tweak.focus_delay,
				m_last_pos = common_data.pos + common_data.fwd * 500
			}
		end
	elseif action_type == "hurt_sick" or action_type == "poison_hurt" or action_type == "concussion" then
		self.update = self._upd_sick
	elseif action_desc.variant == "tase" then
		-- Nothing
	elseif self._ragdolled then
		-- Nothing
	elseif self._unit:anim_data().skip_force_to_graph then
		self.update = self._upd_empty
	else
		self.update = self._upd_hurt
	end

	local shoot_chance = nil

	if self._ext_inventory and not self._weapon_dropped and common_data.char_tweak.shooting_death and not self._ext_movement:cool() then
		local weapon_unit = self._ext_inventory:equipped_unit()

		if weapon_unit then
			if action_type == "counter_tased" or action_type == "taser_tased" or action_desc.variant == "tase" then
				shoot_chance = 1
			else
				local difficulty = Global.game_settings and Global.game_settings.difficulty

				if difficulty == "overkill_290" or difficulty == "sm_wish" then
					if managers.groupai:state():whisper_mode() and action_type == "hurt" or action_type == "heavy_hurt" or action_type == "expl_hurt" or action_type == "fire_hurt" then
						shoot_chance = 1
					end
				else
					if not managers.groupai:state():whisper_mode() and action_type == "death" or action_type == "hurt" or action_type == "heavy_hurt" or action_type == "expl_hurt" or action_type == "fire_hurt" then
						shoot_chance = 0.1
					end
				end
			end
		end
	end

	if shoot_chance then
		local equipped_weapon = self._ext_inventory:equipped_unit()
		local rand = self:_pseudorandom()

		if equipped_weapon and (not equipped_weapon:base().clip_empty or not equipped_weapon:base():clip_empty()) and rand <= shoot_chance then
			self._weapon_unit = equipped_weapon

			self._unit:movement():set_friendly_fire(true)

			self._friendly_fire = true

			if equipped_weapon:base():weapon_tweak_data().auto then
				equipped_weapon:base():start_autofire()

				self._shooting_hurt = true
			else
				self._delayed_shooting_hurt_clbk_id = "shooting_hurt" .. tostring(self._unit:key())

				managers.enemy:add_delayed_clbk(self._delayed_shooting_hurt_clbk_id, callback(self, self, "clbk_shooting_hurt"), TimerManager:game():time() + math.lerp(0.2, 0.4, self:_pseudorandom()))
			end
		end
	end

	if not self._unit:base().nick_name then
		if action_desc.variant == "fire" then
			if action_desc.hurt_type == "fire_hurt" then
				self._unit:sound():say("burnhurt", true)
			elseif action_desc.hurt_type == "death" then
				if self._unit:base():has_tag("tank") then
					self._unit:sound():say("x02a_any_3p", true, nil, true, nil)
				else
					self._unit:sound():say("burndeath", true)
				end
			end
		elseif action_type == "death" then
			self._unit:sound():say("x02a_any_3p", true, nil, true, nil) --im sorry but i need to make sure this shit actually goddamn plays
		elseif action_type == "counter_tased" or action_type == "taser_tased" then
			if self._unit:base():has_tag("taser") then
				self._unit:sound():say("tasered", true)
			else
				self._unit:sound():say("x01a_any_3p", true)
			end
		elseif action_type == "hurt_sick" then
			

			if common_cop or self._unit:base():has_tag("shield") then
				self._unit:sound():say("ch3", true)
			elseif self._unit:base():has_tag("medic") or self._unit:base():has_tag("taser") then
				self._unit:sound():say("burndeath", true)
			else
				self._unit:sound():say("x01a_any_3p", true)
			end
		else
			self._unit:sound():say("x01a_any_3p", true)
		end

		local char_tweak = tweak_data.character[self._unit:base()._tweak_table]
		local speed_mul = nil
		
		if char_tweak.hurt_speed_mul then
			speed_mul = char_tweak.hurt_speed_mul
		else
			--
		end

		if speed_mul then
			self._machine:set_speed(redir_res, speed_mul)
		end

		if self._unit:base():has_tag("tank") and action_type == "death" then
			local unit_id = self._unit:id()

			managers.fire:remove_dead_dozer_from_overgrill(unit_id)
		end

		if Network:is_server() then
			local radius, filter_name = nil
			local default_radius = managers.groupai:state():whisper_mode() and tweak_data.upgrades.cop_hurt_alert_radius_whisper or tweak_data.upgrades.cop_hurt_alert_radius

			if action_desc.attacker_unit and alive(action_desc.attacker_unit) and action_desc.attacker_unit:base().upgrade_value then
				radius = action_desc.attacker_unit:base():upgrade_value("player", "silent_kill") or default_radius
			elseif action_desc.attacker_unit and alive(action_desc.attacker_unit) and action_desc.attacker_unit:base().is_local_player then
				radius = managers.player:upgrade_value("player", "silent_kill", default_radius)
			end

			local new_alert = {
				"vo_distress",
				common_data.ext_movement:m_head_pos(),
				radius or default_radius,
				self._unit:brain():SO_access(),
				self._unit
			}

			managers.groupai:state():propagate_alert(new_alert)
		end
	end

	if action_type == "death" or action_type == "bleedout" or action_desc.variant == "tased" or action_type == "fatal" then
		self._floor_normal = self:_get_floor_normal(common_data.pos, common_data.fwd, common_data.right)
	end

	CopActionAct._create_blocks_table(self, action_desc.blocks)
	self._ext_movement:enable_update()

	if (self._body_part == 1 or self._body_part == 2) and Network:is_server() then
		local stand_rsrv = self._unit:brain():get_pos_rsrv("stand")

		if not stand_rsrv or mvector3.distance_sq(stand_rsrv.position, common_data.pos) > 400 then
			self._unit:brain():add_pos_rsrv("stand", {
				radius = 30,
				position = mvector3.copy(common_data.pos)
			})
		end
	end

	if self:is_network_allowed(action_desc) then
		local params = {
			CopActionHurt.hurt_type_to_idx(action_desc.hurt_type),
			action_desc.body_part,
			CopActionHurt.death_type_to_idx(action_desc.death_type),
			CopActionHurt.type_to_idx(action_desc.type),
			CopActionHurt.variant_to_idx(action_desc.variant),
			action_desc.direction_vec or Vector3(),
			action_desc.hit_pos or Vector3()
		}

		self._common_data.ext_network:send("action_hurt_start", unpack(params))
	end

	return true
end

function CopActionHurt:on_exit()
	if self._shooting_hurt then
		self._shooting_hurt = false

		self._weapon_unit:base():stop_autofire()
	end
	
	local diff_index = tweak_data:difficulty_to_index(Global.game_settings.difficulty)
	
	--punk rage buff will only apply on Death Sentence
	if diff_index == 8 or Global.game_settings.use_intense_AI then
		if self._unit:base()._tweak_table == "cop_moss" then
			self._unit:base():add_buff("base_damage", 2)
			self._unit:character_damage():activate_punk_visual_effect()
		end
	end

	--remove tase effect from tased enemies whenever they exit a hurt (like death if killed while being tased)
	if not managers.groupai:state():is_unit_team_AI(self._unit) then
		if self._tased_effect then
			World:effect_manager():fade_kill(self._tased_effect)
		end
	end

	if self._delayed_shooting_hurt_clbk_id then
		managers.enemy:remove_delayed_clbk(self._delayed_shooting_hurt_clbk_id)

		self._delayed_shooting_hurt_clbk_id = nil
	end

	if self._friendly_fire then
		self._unit:movement():set_friendly_fire(false)

		self._friendly_fire = nil
	end

	if self._modifier_on then
		self._machine:allow_modifier(self._head_modifier_name)
		self._machine:allow_modifier(self._arm_modifier_name)
	end

	if self._expired then
		CopActionWalk._chk_correct_pose(self)
	end

	if not self._expired and Network:is_server() then
		if self._hurt_type == "bleedout" or self._hurt_type == "fatal" or self._variant == "tase" then
			self._unit:network():send("action_hurt_end")
		end

		if self._hurt_type == "bleedout" or self._hurt_type == "fatal" then
			self._ext_inventory:equip_selection(2, true)
		end
	end

	if self._hurt_type == "fatal" or self._variant == "tase" then
		managers.hud:set_mugshot_normal(self._unit:unit_data().mugshot_id)
	end

	if self._unit and alive(self._unit) and self._unit.character_damage and self._unit:character_damage().call_listener then
		self._unit:character_damage():call_listener("on_exit_hurt")
	end
end

function CopActionHurt:_upd_tased(t)
	--allow wild (harmless) shooting while being tased (singleshot weapons only fire once as usual, still better than no firing)
	if self._shooting_hurt then
		local weap_unit = self._weapon_unit
		local weap_unit_base = weap_unit:base()
		local shoot_from_pos = weap_unit:position()
		local shoot_fwd = weap_unit:rotation():y()

		weap_unit_base:trigger_held(shoot_from_pos, shoot_fwd, 3)

		if weap_unit_base.clip_empty and weap_unit_base:clip_empty() then
			self._shooting_hurt = false

			weap_unit_base:stop_autofire()
		end
	end

	if not self._tased_time or self._tased_time < t then
		if dont and self._tased_down_time and t < self._tased_down_time then --leaving this with a dummy check for now until i figure out some reason to use this
			local redir_res = self._ext_movement:play_redirect("fatal")

			if not redir_res then
				debug_pause("[CopActionHurt:init] fatal redirect failed in", self._machine:segment_state(Idstring("base")))
			end

			self.update = self._upd_tased_down
		else
			--don't use self._tased_down_time on cops as they'll go into fatal and immediately get back up because it's not set up for them

			--remove tase effect from tased enemies when the tase stops
			if not managers.groupai:state():is_unit_team_AI(self._unit) then
				if self._tased_effect then
					World:effect_manager():fade_kill(self._tased_effect)
				end
			end

			--stop the tase and let the unit regain control again
			self._expired = true
		end
	end
end

--prevent some hurt animations from overlapping/replaying until they actually expire (shield_knock is the most noticeable one)
function CopActionHurt:chk_block(action_type, t)
	if CopActionAct.chk_block(self, action_type, t) then
		return true
	elseif action_type == "death" then
		-- Nothing
	elseif (action_type == "hurt" or action_type == "heavy_hurt" or action_type == "stagger" or action_type == "knock_down" or action_type == "hurt_sick" or action_type == "poison_hurt" or action_type == "shield_knock") and not self._ext_anim.hurt_exit then
		return true
	elseif action_type == "turn" then
		return true
	end
end

function CopActionHurt:is_network_allowed(action_desc)
	if not CopActionHurt.network_allowed_hurt_types[action_desc.hurt_type] then
		return false
	else
		--allow enemy tase to sync properly through copdamage alone
		if action_desc.variant == "tase" and not managers.groupai:state():is_unit_team_AI(self._unit) then
			return false
		end
	end

	--prevent synced damage hurts from syncing right back
	if action_desc.allow_network == false or action_desc.is_synced then
		return false
	end

	if self._unit:in_slot(managers.slot:get_mask("criminals")) then
		return false
	end

	return true
end

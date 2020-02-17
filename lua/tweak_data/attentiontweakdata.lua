Hooks:PostHook(AttentionTweakData, "init", "fuck_init", function(self, tweakdata)
	self.settings.pl_mask_on_foe_combatant_whisper_mode_stand = {
		max_range = 2000,
		reaction = "REACT_COMBAT",
		notice_interval = 0.1,
		notice_delay_mul = 0.5,
		relation = "foe",
		filter = "combatant",
		uncover_range = 100,
		notice_requires_FOV = true,
		notice_clbk = "clbk_attention_notice_sneak",
		verification_interval = 0.1,
		release_delay = 0.35
	}
	self.settings.pl_mask_on_foe_non_combatant_whisper_mode_stand = {
		uncover_range = 100,
		reaction = "REACT_COMBAT",
		notice_interval = 0.1,
		notice_delay_mul = 0.5,
		notice_requires_FOV = true,
		notice_clbk = "clbk_attention_notice_sneak",
		verification_interval = 0.1,
		release_delay = 0.35,
		filter = "non_combatant"
	}
	self.settings.pl_mask_on_foe_non_combatant_whisper_mode_crouch = {
		max_range = 1000,
		reaction = "REACT_COMBAT",
		notice_interval = 0.1,
		notice_delay_mul = 0.5,
		filter = "non_combatant",
		uncover_range = 100,
		notice_requires_FOV = true,
		notice_clbk = "clbk_attention_notice_sneak",
		verification_interval = 0.1,
		release_delay = 0.35
	}
	self.settings.pl_mask_on_foe_combatant_whisper_mode_crouch = {
		max_range = 1000,
		reaction = "REACT_COMBAT",
		notice_interval = 0.1,
		notice_delay_mul = 0.5,
		relation = "foe",
		filter = "combatant",
		uncover_range = 100,
		notice_requires_FOV = true,
		notice_clbk = "clbk_attention_notice_sneak",
		verification_interval = 0.1,
		release_delay = 0.35
	}
	self.settings.pl_foe_combatant_cbt_crouch = {
		uncover_range = 500,
		reaction = "REACT_COMBAT",
		notice_interval = 0.1,
		notice_delay_mul = 0.5,
		release_delay = 0.35,
		notice_requires_FOV = true,
		verification_interval = 0.1,
		relation = "foe",
		filter = "combatant"
	}
	self.settings.pl_foe_combatant_cbt_stand = {
		reaction = "REACT_COMBAT",
		notice_interval = 0.1,
		notice_delay_mul = 0.5,
		relation = "foe",
		filter = "combatant",
		uncover_range = 500,
		notice_requires_FOV = true,
		notice_clbk = "clbk_attention_notice_sneak",
		verification_interval = 0.1,
		release_delay = 0.35
	}
	
	self.settings.team_enemy_cbt = {
		max_range = 20000,
		reaction = "REACT_COMBAT",
		notice_interval = 1,
		relation = "foe",
		filter = "all",
		uncover_range = 400,
		notice_requires_FOV = true,
		verification_interval = 0.5,
		release_delay = 1,
		weight_mul = 1
	}
	self.settings.custom_enemy_suburbia_shootout = {
		max_range = 12000,
		reaction = "REACT_SHOOT",
		notice_requires_FOV = true,
		turn_around_range = 15000,
		weight_mul = 1.25,
		verification_interval = 0.5,
		release_delay = 5,
		filter = "all_enemy"
	}
	self.settings.sentry_gun_enemy_cbt_hacked = {
		uncover_range = 300,
		reaction = "REACT_COMBAT",
		release_delay = 1,
		weight_mul = 1.25,
		verification_interval = 1,
		relation = "foe",
		filter = "combatant"
	}
	
end)
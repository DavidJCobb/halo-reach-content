
alias monitor_traits = script_traits[0]

alias ui_aa_warp_a = script_widget[0]
alias ui_aa_warp_b = script_widget[1]

-- Unnamed Forge labels:
alias all_initial_spawns = 0

enum func_stage
   none
   swap
   warp
   reset
end

alias temp_int_00  = global.number[0]
alias temp_int_01  = global.number[1]
alias temp_obj_00  = global.object[0]
alias temp_obj_01  = global.object[1]
alias temp_obj_02  = global.object[2]
alias temp_plr_00  = global.player[0]
alias func_stage   = player.number[0] -- see (func_stage) enum
alias failsafe_on  = player.number[1]
alias queued_teleport       = player.object[0]
alias func_timer   = player.timer[0]
alias ui_timer     = player.timer[1]

declare temp_int_00 with network priority local
declare temp_int_01 with network priority local
declare temp_obj_00 with network priority local
declare temp_obj_01 with network priority local
declare temp_obj_02 with network priority local
declare temp_plr_00 with network priority local
declare player.func_stage      with network priority low = func_stage.none
declare player.queued_teleport with network priority low
declare player.func_timer = 10
declare player.ui_timer   = 10

for each player do -- loadout palettes
   if current_player.is_elite() then 
      current_player.set_loadout_palette(elite_tier_1)
   end
   if not current_player.is_elite() then 
      current_player.set_loadout_palette(spartan_tier_1)
   end
end

for each player do
   --
   -- There are cases where we need to queue the player to be teleported to some location 
   -- on the next frame; this handles that.
   --
   if current_player.biped != no_object and current_player.queued_teleport != no_object then
      current_player.biped.attach_to(current_player.queued_teleport, 0, 0, 0, relative)
      current_player.biped.detach()
      current_player.biped.copy_rotation_from(current_player.queued_teleport, false)
      if current_player.queued_teleport.is_of_type(monitor) then
         --
         -- Special case used to preserve momentum when switching from a Monitor back to a 
         -- combatant biped.
         --
         temp_obj_00 = current_player.biped
         temp_obj_01 = current_player.queued_teleport.place_at_me(hill_marker, none, none, 0, 0, 0, none)
         temp_obj_01.attach_to(current_player.queued_teleport, 10, 0, 0, relative)
         temp_obj_01.detach()
         current_player.set_biped(current_player.queued_teleport)
         temp_obj_00.face_toward(temp_obj_01, 0, 0, 0) -- BUG: THIS AND copy_rotation_from DO NOTHING; PLAYER RETAINS THEIR ORIGINAL SPAWNING ROTATION
         temp_obj_01.delete()
         current_player.set_biped(temp_obj_00)
      end
      current_player.queued_teleport.delete()
   end
end
for each player do -- handling for player monitors
   if current_player.biped.is_of_type(monitor) then
      current_player.apply_traits(monitor_traits)
      --
      -- Sometimes, the player can swap bipeds in a REALLY bad location out-of-map, 
      -- such that we can't spawn an Active Camo AA at them.
      --
      alias aa    = temp_obj_00
      alias spawn = temp_obj_01
      --
      aa = current_player.get_armor_ability()
      if aa != no_object then
         current_player.failsafe_on = 0
      end
      if aa == no_object then
         spawn = no_object
         if current_player.failsafe_on == 0 then
            for each object with label all_initial_spawns do
               if not current_object.is_out_of_bounds() then
                  spawn = current_object
               end
            end
            current_player.failsafe_on = 1
         end
         if spawn == no_object then
            current_player.biped.delete()
            game.show_message_to(current_player, none, "You didn't have an AA. Returned you to the map as a failsafe.")
         end
         if spawn != no_object then
            current_player.queued_teleport = current_player.biped.place_at_me(hill_marker, none, none, 0, 0, 0, none)
            current_player.queued_teleport.copy_rotation_from(current_player.biped, false)
            current_player.queued_teleport.attach_to(current_player.biped, 0, 0, 0, relative)
            current_player.queued_teleport.detach()
            --
            current_player.biped.attach_to(spawn, 0, 0, 0, relative)
            current_player.biped.detach()
            --
            spawn.place_at_me(active_camo_aa, none, none, 0, 0, 2, none)
         end
      end
   end
end
for each player do -- handle Armor Ability as script function selector
   if current_player.biped != no_object then
      current_player.biped.set_invincibility(1)
      current_player.func_timer.set_rate(0%)
      current_player.ui_timer.set_rate(0%)
      ui_aa_warp_a.set_visibility(current_player, false)
      ui_aa_warp_b.set_visibility(current_player, false)
      ui_aa_warp_a.set_text("Swap Biped | Warp Forward")
      ui_aa_warp_b.set_text("Warp Forward | Return to Map")
      ui_aa_warp_a.set_meter_params(timer, hud_player.ui_timer)
      ui_aa_warp_b.set_meter_params(timer, hud_player.ui_timer)
      --
      alias aa = temp_obj_00
      aa = current_player.get_armor_ability()
      if aa == no_object or not aa.is_of_type(active_camo_aa) then
         current_player.func_stage = func_stage.none
      alt
         if aa.is_in_use() then
            if current_player.func_stage == func_stage.none then
               current_player.func_timer = 0
            end
            if current_player.func_timer.is_zero() then
               current_player.func_timer.reset()
               current_player.ui_timer    = 0
               current_player.func_stage += 1
               if current_player.func_stage > func_stage.reset then -- don't exceed max
                  current_player.func_stage -= 1
                  current_player.ui_timer.reset()
               end
            end
            ui_aa_warp_b.set_visibility(current_player, true)
            if current_player.func_stage == func_stage.swap then
               ui_aa_warp_a.set_visibility(current_player, true)
               ui_aa_warp_b.set_visibility(current_player, false)
               current_player.func_timer.set_rate(-1000%)
               current_player.ui_timer.set_rate(1000%)
            end
            if current_player.func_stage == func_stage.warp then
               current_player.func_timer.set_rate(-400%)
               current_player.ui_timer.set_rate(400%)
            end
         alt
            --
            -- The Armor Ability is not in use.
            --
            current_player.func_timer.reset()
            current_player.func_timer.set_rate(0%)
            if current_player.func_stage == func_stage.swap then
               alias old_biped = temp_obj_00
               alias new_biped = temp_obj_01
               --
               temp_int_00 = 0
               if current_player.biped.is_of_type(monitor) then
                  alias aa = temp_obj_01
                  --
                  aa = current_player.get_armor_ability()
                  aa.delete()
                  current_player.queued_teleport = current_player.biped
                  --
                  -- The straightforward approach to this would be to spawn a "queued teleport marker" 
                  -- at the player's current biped, and then delete that biped. However, we want to 
                  -- preserve the player's momentum through the biped switch. The best way to do that 
                  -- is to, instead of deleting their biped, simply force them to abandon it: set the 
                  -- current biped AS the player's current queued teleport marker, and then force the 
                  -- player into a new biped which we delete immediately.
                  --
                  -- When we handle the queued teleport marker, we will check if it is a biped; if so, 
                  -- we will force the player into it, move their biped to it, force them back into 
                  -- their biped, and then delete the "marker."
                  --
                  temp_obj_00 = current_player.biped.place_at_me(monitor, none, none, 0, 0, 0, none)
                  current_player.set_biped(temp_obj_00)
                  current_player.biped.delete()
                  temp_int_00 = 1
               end
               if temp_int_00 == 0 then
                  if not current_player.biped.is_of_type(monitor) then
                     new_biped   = current_player.biped.place_at_me(monitor, none, none, 0, 0, 0, none)
                     temp_int_00 = 1
                  end
                  if temp_int_00 == 0 then
                     new_biped = current_player.biped.place_at_me(spartan, none, none, 0, 0, 0, female)
                  end
                  new_biped.attach_to(current_player.biped, 0, 0, 8, relative)
                  new_biped.detach()
                  old_biped = current_player.biped
                  current_player.set_biped(new_biped)
                  old_biped.delete()
                  current_player.biped.place_at_me(active_camo_aa, none, never_garbage_collect, 0, 0, 2, none)
               end
            end
            if current_player.func_stage == func_stage.warp then
               temp_obj_00 = current_player.biped.place_at_me(hill_marker, none, none, 0, 0, 0, none)
               temp_obj_00.attach_to(current_player.biped, 50, 0, 0, relative)
               temp_obj_00.detach()
               current_player.biped.attach_to(temp_obj_00, 0, 0, 0, relative)
               current_player.biped.detach()
               temp_obj_00.delete()
            end
            if current_player.func_stage == func_stage.reset then
               current_player.biped.delete()
            end
            current_player.func_stage = func_stage.none
         end
      end
   end
end
for each player do -- handle invulnerability and deletion
   current_player.biped.set_invincibility(1) -- do this after any biped swap to prevent single frames of vulnerability
   if current_player.biped == no_object then
      current_player.func_stage = func_stage.none
      current_player.func_timer.set_rate(0%)
      current_player.func_timer.reset()
   end
end
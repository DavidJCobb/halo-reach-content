
alias monitor_traits = script_traits[0]

alias ui_aa_warp_a = script_widget[0]
alias ui_aa_warp_b = script_widget[1]

-- Unnamed Forge labels:
alias all_initial_spawns = 0

-- BUG: swapping bipeds retains the old facing direction of the biped 
-- being recalled from storage
--
-- no in-game action seems to be able to prevent this; copy_rotation_from, 
-- face_toward, etc., have no visible effect; we should run laboratory tests 
-- on them using bipeds that have/have not been controlled by any player before

enum func_stage
   none
   swap  -- swap between being a Monitor and being a Spartan/Elite
   warp  -- teleport forward a short distance; useful for breaking barriers
   reset -- reset to a spawn point somewhere in the map
end

alias temp_int_00  = global.number[0]
alias temp_int_01  = global.number[1]
alias temp_obj_00  = global.object[0]
alias temp_obj_01  = global.object[1]
alias temp_obj_02  = global.object[2]
alias storage      = global.object[3]
alias temp_plr_00  = global.player[0]
alias func_stage   = player.number[0] -- see (func_stage) enum
alias failsafe_on  = player.number[1]
alias stored_biped = player.object[0]
alias move_to_next = player.object[1] -- marker to move the player to on the next frame
alias func_timer   = player.timer[0]
alias ui_timer     = player.timer[1]

declare temp_int_00 with network priority local
declare temp_int_01 with network priority local
declare temp_obj_00 with network priority local
declare temp_obj_01 with network priority local
declare temp_obj_02 with network priority local
declare storage     with network priority low
declare temp_plr_00 with network priority local
declare player.func_stage   with network priority low = func_stage.none
declare player.stored_biped with network priority low
declare player.move_to_next with network priority low
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

for each player do -- create storage marker
   --
   -- When the player wants to swap between Monitor and normal bipeds, we recycle 
   -- bipeds so that weapons and items that the player picks up aren't deleted. We 
   -- need someplace to store the bipeds where we know they won't be messed with; 
   -- conveniently, attaching objects to Hill Markers renders the attached objects 
   -- invisible and incorporeal.
   --
   if storage == no_object and current_player.biped != no_object then
      storage = current_player.biped.place_at_me(hill_marker, none, never_garbage_collect, 0, 0, 0, none)
      storage.attach_to(current_player.biped, 0, 0, 1, absolute)
      storage.detach()
   end
end

for each player do
   alias queued_to   = temp_obj_00
   alias prior_biped = temp_obj_01
   --
   -- There are cases where we need to queue the player to be teleported to some location 
   -- on the next frame; this handles that.
   --
   if current_player.biped != no_object then
      queued_to   = current_player.move_to_next
      prior_biped = current_player.biped
      current_player.move_to_next = no_object
      if queued_to != no_object then
         prior_biped.copy_rotation_from(queued_to, false)
         prior_biped.attach_to(queued_to, 0, 0, 0, absolute)
         prior_biped.detach()
         queued_to.delete()
      end
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
            current_player.stored_biped.delete()
            game.show_message_to(current_player, none, "You didn't have an AA. Returned you to the map as a failsafe.")
         end
         if spawn != no_object then
            current_player.move_to_next = current_player.biped.place_at_me(hill_marker, none, none, 0, 0, 0, none)
            current_player.move_to_next.copy_rotation_from(current_player.biped, false)
            current_player.move_to_next.attach_to(current_player.biped, 0, 0, 0, relative)
            current_player.move_to_next.detach()
            --
            current_player.biped.attach_to(spawn, 0, 0, 0, relative)
            current_player.biped.detach()
            --
            spawn.place_at_me(active_camo_aa, none, none, 0, 0, 1, none)
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
               alias else_flag = temp_int_00
               alias recall    = temp_obj_00
               alias store     = temp_obj_01
               alias facing    = temp_obj_02
               --
               function _recall_from_storage()
                  recall.detach()
                  recall.copy_rotation_from(store, true)
                  recall.attach_to(store, 0, 0, 0, relative)
                  recall.detach()
                  current_player.set_biped(recall)
                  --
                  current_player.stored_biped = store
                  store.attach_to(storage, 0, 0, 0, absolute)
               end
               function _enter_into_storage()
                  current_player.stored_biped = store
                  current_player.set_biped(recall)
                  store.attach_to(storage, 0, 0, 0, absolute)
               end
               --
               else_flag = 0
               recall    = current_player.stored_biped
               store     = current_player.biped
               if store.is_of_type(monitor) then
                  --
                  -- Switch from a Monitor to a combat biped.
                  --
                  if recall == no_object then -- if no existing combat biped available
                     recall = current_player.biped.place_at_me(spartan, none, none, 0, 0, 0, female)
                     _enter_into_storage()
                     --
                     else_flag = 1
                  end
                  if else_flag == 0 then -- else, recall existing combat biped
                     _recall_from_storage()
                     else_flag = 1
                  end
               end
               if else_flag == 0 then
                  --
                  -- Switch from a combat biped to a Monitor.
                  --
                  if current_player.stored_biped == no_object then -- if no existing Monitor biped available
                     recall = current_player.biped.place_at_me(monitor, none, none, 0, 0, 0, none)
                     _enter_into_storage()
                     --
                     else_flag = 1
                  end
                  if else_flag == 0 then -- else, recall existing Monitor biped
                     _recall_from_storage()
                  end
               end
            end
            if current_player.func_stage == func_stage.warp then
               alias warp_marker = temp_obj_00
               --
               warp_marker = current_player.biped.place_at_me(hill_marker, none, none, 0, 0, 0, none)
               warp_marker.attach_to(current_player.biped, 50, 0, 0, relative)
               warp_marker.detach()
               current_player.biped.attach_to(warp_marker, 0, 0, 0, relative)
               current_player.biped.detach()
               warp_marker.delete()
            end
            if current_player.func_stage == func_stage.reset then
               current_player.biped.delete()
               current_player.stored_biped.delete()
            end
            current_player.func_stage = func_stage.none
         end
      end
   end
end
for each player do -- handle invulnerability and deletion
   current_player.biped.set_invincibility(1) -- do this after any biped swap to prevent single frames of vulnerability
   current_player.stored_biped.set_invincibility(1)
   if current_player.biped == no_object then
      current_player.func_stage = func_stage.none
      current_player.func_timer.set_rate(0%)
      current_player.func_timer.reset()
   end
end
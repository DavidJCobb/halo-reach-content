
alias MAX_INT = 32767

enum monitor_gear_pref
   show
   hide_aa
   hide_all
end

alias opt_hide_monitor_gear  = script_option[0]
alias opt_show_warp_distance = script_option[1]

alias monitor_traits = script_traits[0]

alias ui_aa_warp_a = script_widget[0]
alias ui_aa_warp_b = script_widget[1]

-- Unnamed Forge labels:
alias all_initial_spawns = 0

enum func_stage
   none
   swap  -- swap between being a Monitor and being a Spartan/Elite
   warp  -- teleport forward a short distance; useful for breaking barriers
   reset -- reset to a spawn point somewhere in the map
   swap_in_progress
end

--
-- Biped swaps work as follows:
--
-- Instead of creating and destroying bipeds for the player, we try to hold onto 
-- old bipeds and recycle them. Specifically, the player has at any given moment 
-- one "stored biped" in addition to their current biped. If the player is curr-
-- ently a Monitor, then the stored biped is a Spartan or Elite, and vice versa. 
--
-- We can "store" bipeds by attaching them to Hill Markers. This renders them 
-- invisible and incorporeal, with the sole unfortunate side-effect that storing 
-- a Monitor may result in its whirring noise being audible when standing near 
-- the Hill Marker.
--
-- This approach is enough to ensure that we don't delete items that the player 
-- has picked up off the map when swapping their bipeds. Moreover, if we carry 
-- out the biped swap quickly (such that there is never a frame in which the 
-- player is not in control of a biped), then we can even preserve momentum 
-- through the swap. However, we cannot preserve the player's facing direction. 
-- It seems that if a biped has previously been controlled by the player, and we 
-- rotate it through script on the same frame that we place the player inside of 
-- it, then the rotation fails and it retains the last facing direction it had. 
-- This doesn't seem to affect Monitors, but it very much affects Spartans and 
-- likely Elites.
--
-- As such, we need to carry out the biped swap over multiple frames. On the 
-- first frame of the swap, we recall the player's old biped (the "target") from 
-- storage, move it to the player's current biped (the "subject"), and then we 
-- queue to finish the action on the next frame. On that next frame, we have the 
-- player possess the target and we place the subject into storage.
--

alias temp_int_00  = global.number[0]
alias temp_int_01  = global.number[1]
alias temp_int_02  = global.number[2]
alias temp_obj_00  = global.object[0]
alias temp_obj_01  = global.object[1]
alias temp_obj_02  = global.object[2]
alias storage      = global.object[3]
alias aa_storage   = global.object[4]
alias temp_plr_00  = global.player[0]
alias is_scaled    = object.number[0]
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
declare object.is_scaled    with network priority low
declare player.func_stage   with network priority low = func_stage.none
declare player.stored_biped with network priority low
declare player.move_to_next with network priority low
declare player.func_timer = 10
declare player.ui_timer   = 10

for each player do -- loadout palettes
   current_player.set_round_card_title("Activate your Active Camo for different lengths\nof time to use different functions.")
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
if aa_storage == no_object then
   --
   -- Unlike all other known objects, player-equipped Armor Abilities do not turn 
   -- invisible or intangible when attached to Hill Markers. This means that in 
   -- order to hide a Monitor's equipped Armor Ability, we can't simply attach it 
   -- to any old marker; we need to move it somewhere entirely out of sight.
   --
   -- Let's try to find the lowest Initial Spawn Point on the map... and then 
   -- create a storage marker below that.
   --
   alias basis  = temp_obj_00
   alias above  = temp_obj_01
   alias lowest_object = temp_obj_02
   alias lowest_height = temp_int_00
   alias dist   = temp_int_01
   alias check  = temp_int_02
   --
   lowest_object = no_object
   lowest_height = MAX_INT
   basis  = lowest_object.place_at_me(hill_marker, none, none, 0, 0, 0, none)
   above  = basis.place_at_me(hill_marker, none, none, 0, 0, 127, none)
   --
   for each object with label all_initial_spawns do
      temp_int_01 = current_object.get_distance_to(basis)
      temp_int_02 = current_object.get_distance_to(above)
      if temp_int_02 > temp_int_01 then -- (current_object) is below (basis)
         temp_int_01 *= -1
      end
      if temp_int_01 < lowest_height then
         lowest_object = current_object
         lowest_height = temp_int_01
      end
   end
   basis.delete()
   above.delete()
   --
   aa_storage = lowest_object.place_at_me(hill_marker, none, none, 0, 0, 0, none)
   aa_storage.attach_to(lowest_object, 0, 0, -50, absolute)
   aa_storage.detach()
end

for each player do -- finish a biped swap-in-progress
   alias store = temp_obj_00
   if current_player.func_stage == func_stage.swap_in_progress then
      store = current_player.biped
      current_player.set_biped(current_player.stored_biped)
      store.attach_to(storage, 0, 0, 0, absolute)
      current_player.stored_biped = store
      --
      current_player.func_stage = func_stage.none
   end
end

if opt_hide_monitor_gear != monitor_gear_pref.show then
   --
   -- Code for hiding Monitors' equipped items, per a Custom Game option.
   --
   for each object do -- revert scaling on items the Monitor drops
      if current_object.is_scaled == 1 and not current_object.is_of_type(active_camo_aa) then
         temp_plr_00 = current_object.get_carrier()
         if temp_plr_00 == no_player then
            current_object.is_scaled = 0
            current_object.set_scale(100)
         end
      end
   end
   for each player do -- apply scaling to items the Monitor is carrying
      if current_player.biped.is_of_type(monitor) then
         --
         -- When a Monitor has an Armor Ability equipped, the ability continues to 
         -- project its holographic icon, and scaling the ability does not scale 
         -- the icon. Moreover, equipped Armor Abilities apparently don't undergo 
         -- the usual changes seen when attaching objects to Hill Markers: they 
         -- don't become invisible or intangible. We thus need to move them out of 
         -- sight, and we need to do so every frame to ensure they don't fall too 
         -- far out of the map.
         --
         -- Detaching them has the unfortunate side effect of locking the radar 
         -- jamming effect to the place we're moving them to (as opposed to keeping 
         -- that centered on the player or stopping it entirely).
         --
         temp_obj_00 = current_player.get_armor_ability()
         temp_obj_00.detach()
         temp_obj_00.attach_to(aa_storage, 0, 0, 0, absolute)
         --
         if opt_hide_monitor_gear == monitor_gear_pref.hide_all then
            temp_obj_00 = current_player.get_weapon(primary)
            temp_obj_00.set_scale(1)
            temp_obj_00.is_scaled = 1
            temp_obj_00 = current_player.get_weapon(secondary)
            temp_obj_00.set_scale(1)
            temp_obj_00.is_scaled = 1
         end
      end
   end
end

for each player do -- handle queued teleports
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
for each player do -- handle biped properties and Armor Ability as script function selector (including UI)
   if current_player.biped != no_object then
      current_player.biped.set_invincibility(1)
      current_player.biped.set_shape(cylinder, 50, 15, 15) -- for opt_show_warp_distance
      --
      current_player.func_timer.set_rate(0%)
      current_player.ui_timer.set_rate(0%)
      current_player.biped.set_shape_visibility(no_one)
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
               --
               if opt_show_warp_distance == 1 then
                  current_player.biped.set_shape_visibility(mod_player, current_player, 1)
               end
            end
         alt
            --
            -- The Armor Ability is not in use.
            --
            current_player.func_timer.reset()
            current_player.func_timer.set_rate(0%)
            if current_player.func_stage == func_stage.swap then
               if current_player.stored_biped == no_object then
                  if current_player.biped.is_of_type(monitor) then
                     --
                     -- The player should never be missing a combat biped, but on the off chance 
                     -- they are, spawn an emergency one.
                     --
                     current_player.stored_biped = current_player.biped.place_at_me(spartan, none, none, 0, 0, 0, female)
                  alt
                     current_player.stored_biped = current_player.biped.place_at_me(monitor, none, none, 0, 0, 0, none)
                  end
               end
               current_player.stored_biped.detach()
               current_player.stored_biped.attach_to(current_player.biped, 0, 0, 0, absolute)
               current_player.stored_biped.detach()
               current_player.stored_biped.copy_rotation_from(current_player.biped, false)
               current_player.func_stage = func_stage.swap_in_progress
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
            --
            if current_player.func_stage != func_stage.swap_in_progress then
               current_player.func_stage = func_stage.none
            end
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

if game.round_time_limit > 0 and game.round_timer.is_zero() then -- round timer
   game.end_round()
end
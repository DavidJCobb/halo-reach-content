
alias opt_use_custom_spartan = script_option[0]

alias monitor_traits = script_traits[0]

alias ui_aa_warp_a = script_widget[0]
alias ui_aa_warp_b = script_widget[1]

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
alias temp_obj_03  = global.object[3]
alias temp_obj_04  = global.object[4]
alias temp_plr_00  = global.player[0]
alias eye_counter  = object.number[0] -- on monitor.eye_light
alias eye_dir      = object.number[1] -- on monitor.eye_light
alias eye_light    = object.object[0]
alias eye_timer    = object.timer[0]
alias func_stage   = player.number[0] -- see (func_stage) enum
alias anchor       = player.object[0]
alias func_timer   = player.timer[0]
alias ui_timer     = player.timer[1]

declare temp_int_00 with network priority local
declare temp_int_01 with network priority local
declare temp_obj_00 with network priority local
declare temp_obj_01 with network priority local
declare temp_obj_02 with network priority local
declare temp_obj_03 with network priority local
declare temp_obj_04 with network priority local
declare temp_plr_00 with network priority local
declare object.eye_light  with network priority low
declare player.func_stage with network priority low = func_stage.none
declare player.anchor     with network priority low
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
   if current_player.biped != no_object then
      if current_player.biped.is_of_type(monitor) then
         current_player.apply_traits(monitor_traits)
      altif current_player.anchor != no_object then
         --
         -- We have a custom game option which lets players pick between preserving their 
         -- momentum when switching from Monitor to Biped, or preserving their armor cust-
         -- omizations. In the latter case, we accomplish that by deleting their biped to 
         -- forcibly spawn a new biped on the next frame; we then teleport that new biped 
         -- to their previous position (the "anchor").
         --
         current_player.biped.attach_to(current_player.anchor, 0, 0, 0, relative)
         current_player.biped.detach()
         current_player.biped.copy_rotation_from(current_player.anchor, false)
         current_player.anchor.delete()
      end
   end
end
for each player do
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
                  current_player.anchor = current_player.biped.place_at_me(hill_marker, none, none, 0, 0, 0, none)
                  current_player.anchor.attach_to(current_player.biped, 0, 0, 0, relative)
                  current_player.anchor.detach()
                  current_player.anchor.copy_rotation_from(current_player.biped, false)
                  aa = current_player.get_armor_ability()
                  aa.delete()
                  current_player.biped.delete()
                  temp_int_00 = 1
               end
               if temp_int_00 == 0 then
                  if not current_player.biped.is_of_type(monitor) then
                     alias witness = new_biped
                     alias light   = temp_obj_00
                     --
                     witness = current_player.biped.place_at_me(monitor, none, none, 0, 0, 0, none)
                     --light   = witness.place_at_me(light_purple, none, none, 0, 0, 0, none)
                     --light.set_scale(8)
                     --light.attach_to(witness, 1, 0, 0, relative)
                     --witness.eye_light = light
                     --
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
                  current_player.biped.place_at_me(active_camo_aa, none, none, 0, 0, 2, none)
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

-- TEST: attach a purple light to a monitor to make exuberant witness
for each player do
   alias witness = temp_obj_01
   alias light   = temp_obj_00
   alias noclip  = temp_obj_02
   if current_player.number[1] == 0 and current_player.biped != no_object then
      current_player.number[1] = 1
      --
      witness = current_player.biped.place_at_me(monitor, none, none, 0, 0, 0, none)
      light   = witness.place_at_me(light_purple, none, none, 0, 0, 0, none)
      light.set_scale(8)
      noclip  = witness.place_at_me(flag_stand, "_monitor_vfx", none, 0, 0, 0, none)
      noclip.set_scale(1)
      light.attach_to(noclip, 0, 0, 0, relative)
      noclip.attach_to(witness, 1, 0, 0, relative)
      witness.eye_light = noclip
      witness.eye_timer = 1
      noclip.eye_light  = witness
   end
end

--
-- Monitors bob up and down due to an animation baked into their model. Specifically, 
-- they bob from neutral to down and back to neutral, over the course of one second, 
-- and then from neutral to up and back to neutral over the course of the next second. 
-- The total bob distance in either direction appears to be about 0.1 Forge units.
--
for each object with label "_monitor_vfx" do
   if current_object.eye_light == no_object then -- owning Monitor was destroyed?
      current_object.delete()
   end
end
for each object do -- try to sync Monitor eye-lights with Monitor bobbing animation
   alias light = temp_obj_00
   if current_object.is_of_type(monitor) and current_object.eye_light != no_object then
      current_object.eye_timer.set_rate(-1000%)
      if current_object.eye_timer.is_zero() then
         current_object.eye_timer = 1
         current_object.eye_timer.set_rate(-1000%)
         --
         light = current_object.eye_light
         if light.eye_dir == 0 then
            light.eye_dir = -1
         end
         light.eye_counter += light.eye_dir
         light.eye_counter += light.eye_dir
         if light.eye_counter >= 10 or light.eye_counter <= -10 then
            light.eye_dir *= -1
         end
         --
         alias node_n  = temp_obj_01
         alias node_p  = temp_obj_02
         alias node_c  = temp_obj_03
         alias counter = temp_int_00
         --
         node_n = current_object.place_at_me(hill_marker, none, none, 0, 0, 0, none)
         node_c = no_object
         node_p = current_object.place_at_me(hill_marker, none, none, 0, 0, 0, none)
         node_p.attach_to(current_object, 1, 0, 0, relative)
         if light.eye_counter < 0 then
            node_n.attach_to(current_object, 1, 0, -1, relative)
         alt
            node_n.attach_to(current_object, 1, 0,  1, relative)
         end
         --
         function _halve_max_distance()
            node_c = node_n.place_between_me_and(node_p, hill_marker, 0)
            node_n.delete()
            node_n = node_c
            node_c = no_object
         end
         _halve_max_distance()
         --
         node_p.eye_counter = 0
         node_n.eye_counter = 10
         if light.eye_counter == node_n.eye_counter then
            node_c = node_n
         end
         if light.eye_counter == node_p.eye_counter then
            node_c = node_p
         end
         counter = light.eye_counter
         if counter < 0 then
            counter *= -1
         end
         if node_c == no_object then
            function _iterate()
               node_c = node_n.place_between_me_and(node_p, hill_marker, 0)
               node_c.eye_counter  = node_p.eye_counter
               node_c.eye_counter += node_n.eye_counter
               node_c.eye_counter /= 2
               if  counter            != node_c.eye_counter
               and node_p.eye_counter != node_n.eye_counter -- make sure we're not stuck
               and node_c.eye_counter != node_n.eye_counter -- make sure we're not stuck
               and node_c.eye_counter != node_p.eye_counter -- make sure we're not stuck
               then
                  if counter > node_c.eye_counter then
                     node_p.delete()
                     node_p = node_c
                  alt
                     node_n.delete()
                     node_n = node_c
                  end
                  _iterate() -- recurse
               end
            end
            _iterate()
         end
         light.detach()
         light.attach_to(node_c, 0, 0, 0, relative)
         light.detach()
         node_p.delete()
         node_c.delete()
         node_n.delete()
      end
   end
end

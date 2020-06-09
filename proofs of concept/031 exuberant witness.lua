
--
-- Proof-of-Concept: 031 Exuberant Witness Monitor
--
-- Spawns a Forge Monitor with a purple light scaled down and attached 
-- to the eye.
--
-- Monitors have an animation which makes them appear to bob up and 
-- down. Objects attached to Monitors don't take on this animation. 
-- This is because the attachment process selects the nearest node on 
-- the Monitor's model to anchor to the attached object to, but while 
-- only one node bobs up and down, all nodes have the same position; 
-- it seems the game always ends up picking a stationary node. As such, 
-- we have to manually animate our attached light.
--
-- Our method is useful for a non-player-controlled Monitor that does 
-- not move at high speeds. It is unsuitable for high-speed objects 
-- because our timer cannot fire quickly enough to track them in real 
-- time. It is unsuitable for player-controlled Monitors because the 
-- purple light is visible in first-person view and blocks a notable 
-- portion of the player's vision (along with being an eyesore in 
-- itself, at that distance).
--
-- We could potentially get a higher-resolution "timer" by eschewing 
-- timer variables in favor of integers that we increment every script 
-- tick; in practice, scripts seem to run sixty times per second and 
-- so that would provide us with the highest-resolution timing we can 
-- get.
--
-- Moving the light with any degree of precision is challenging. Our 
-- primary way of moving objects at all is by attaching them to some 
-- object with some offset, and then detaching them. However, attach 
-- offsets can be no more precise than a tenth of a Forge unit. The 
-- total size of the bobbing animation is one tenth of a Forge unit: 
-- 0.5 below and 0.5 above baseline. A bob in either direction takes 
-- one full second (from neutral to max and back to neutral), so you 
-- have to divide 0.5 by 30 frames to get the Forge unit precision 
-- we'd need for frame-perfect movement: 0.01666....
--
-- The workaround is to use object.place_between_me_and, which will 
-- spawn one object exactly between any two other objects. This can 
-- be used to get sub-unit precision, e.g. 0.5, 0.25, 0.125, 0.0625, 
-- and so on. If we divide 1 in half six times, we get 0.015625; if 
-- we divide 1 in half ten times, we get 0.0009765625; and if we 
-- add those two numbers together, then we get 0.0166015625, which 
-- is close enough to the precision needed for frame-perfect movement 
-- to produce acceptable results; however, the work needed to manage 
-- that is... less than encouraging, and less than a priority right 
-- now. For now, we use a very low degree of precision, moving the 
-- attachment in five increments per direction at tenth-of-a-second 
-- intervals.
--
-- Do remember that every division by 2 requires creating a new 
-- object, a new Hill Marker or similar, with which to position 
-- things.
--

alias spawned_monitor = global.number[0]
alias temp_int_00 = global.number[1]
alias temp_int_01 = global.number[2]
alias temp_obj_00 = global.object[0]
alias temp_obj_01 = global.object[1]
alias temp_obj_02 = global.object[2]
alias temp_obj_03 = global.object[3]
alias temp_obj_04 = global.object[4]
alias temp_plr_00 = global.player[0]
alias eye_counter = object.number[0] -- on monitor.eye_light
alias eye_dir     = object.number[1] -- on monitor.eye_light
alias eye_light   = object.object[0]
alias eye_timer   = object.timer[0]

declare temp_int_00 with network priority local
declare temp_int_01 with network priority local
declare temp_obj_00 with network priority local
declare temp_obj_01 with network priority local
declare temp_obj_02 with network priority local
declare temp_obj_03 with network priority local
declare temp_obj_04 with network priority local
declare temp_plr_00 with network priority local
declare object.eye_light  with network priority low

for each player do
   --
   -- just spawn her near the first player to load in
   --
   if spawned_monitor == 0 and current_player.biped != no_object then
      spawned_monitor = 1
      --
      alias witness = temp_obj_00
      alias light   = temp_obj_01
      alias noclip  = temp_obj_02
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
-- Code for the Exuberant Witness monitor skin.
--
-- Monitors bob up and down due to an animation baked into their model. Specifically, 
-- they bob from neutral to down and back to neutral, over the course of one second, 
-- and then from neutral to up and back to neutral over the course of the next second. 
-- The total bob distance in either direction appears to be about 0.1 Forge units.
--
-- There's really no good way to handle this. We can't intentionally and consistently 
-- attach something to the Monitor skeleton node that bobs up and down: attachment 
-- will anchor an object to the nearest node, but all of a Monitor's nodes have the 
-- same coordinates. We're just gonna have to update the decorative light's position 
-- by hand every script tick. Ugly, I know.
--
for each object with label "_monitor_vfx" do
   if current_object.eye_light == no_object then -- owning Monitor was destroyed?
      current_object.delete()
   end
end
for each object do -- try to sync Monitor eye-lights with Monitor bobbing animation
   alias light = temp_obj_00
   if current_object.is_of_type(monitor) and current_object.eye_light != no_object then
      --
      -- Running a 1-second timer at 1000% means the timer will hit zero 
      -- every tenth of a second.
      --
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
         light.eye_counter += light.eye_dir -- needed to synch our movement with the bobbing animation
         if light.eye_counter >= 10 or light.eye_counter <= -10 then
            light.eye_dir *= -1
         end
         --
         temp_int_00 = current_object.get_speed()
         if temp_int_00 > 10 then
            light.detach()
            light.attach_to(current_object, 1, 0, 0, relative)
         alt
            alias node_n  = temp_obj_01
            alias node_p  = temp_obj_02
            alias node_c  = temp_obj_03
            alias counter = temp_int_00
            --
            node_n = current_object.place_at_me(hill_marker, none, none, 0, 0, 0, none)
            node_p = current_object.place_at_me(hill_marker, none, none, 0, 0, 0, none)
            node_c = no_object
            if light.eye_counter < 0 then
               node_n.attach_to(current_object, 1, 0, -1, relative)
               node_p.attach_to(current_object, 0, 0, -1, relative)
            alt
               node_n.attach_to(current_object, 1, 0,  1, relative)
               node_p.attach_to(current_object, 0, 0,  1, relative)
            end
            node_c = node_n.place_between_me_and(node_p, hill_marker, 0) -- we want the light to be at X-offset 0.5 to fit it perfectly into the Monitor's eye
            node_n.delete()
            node_p.delete()
            node_n = node_c
            node_c = no_object
            --
            node_p = current_object.place_at_me(hill_marker, none, none, 0, 0, 0, none)
            node_p.attach_to(current_object, 1, 0, 0, relative)
            --
            function _halve_max_distance()
               node_c = node_n.place_between_me_and(node_p, hill_marker, 0)
               node_n.delete()
               node_n = node_c
               node_c = no_object
            end
            _halve_max_distance()
            _halve_max_distance() -- good enough
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
end

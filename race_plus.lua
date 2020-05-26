-- RACE PLUS
--
-- Extensions:
--
--  - Added new vehicle options: Sabre; Civilian; and None. The "Civilian" option 
--    picks a random civilian vehicle at match start and uses that for all players. 
--    The random vehicle option uses a hidden stat to avoid picking the same one 
--    for any two rounds in a row.
--
--  - Landmine proximity behavior is now configurable.
--
--  - This script uses a more accurate system for checking whether a vehicle is 
--    inside of a checkpoint or in proximity to a landmine.
--

--
-- Notes:
--
--  - Multiple checkpoints can share the same ID. The player can advance by claiming 
--    any of them, and will gain the ability to spawn at any of them upon doing so.
--

alias opt_lap_count  = script_option[0]
alias opt_vehicle    = script_option[1]
alias opt_landmines  = script_option[2]
alias opt_mine_arm_distance = script_option[3]
alias opt_mine_arm_time     = script_option[4]
alias best_lap_time  = player.script_stat[0]
alias top_speed      = player.script_stat[1]
alias total_distance = player.script_stat[2]

alias checkpoint_count   = global.number[0] -- nothing is done with this; it may exist for debugging
alias last_checkpoint_id = global.number[1]
alias civilian_vehicle   = global.number[6] -- which random vehicle to use
alias showed_spawn_failure_message = global.number[8]
alias first_checkpoint   = global.object[0] -- checkpoint with the lowest spawn sequence on the map, preferring sequence 1
alias queued_award_point_to    = global.player[0]
alias last_player_to_take_lead = global.player[1]
alias distance_traveled_update_timer = global.timer[0]
declare checkpoint_count             with network priority local
declare last_checkpoint_id           with network priority low
declare first_checkpoint             with network priority low
declare showed_spawn_failure_message with network priority low = 0
declare queued_award_point_to        with network priority low
declare last_player_to_take_lead     with network priority low
declare distance_traveled_update_timer = 1
--
alias checkpoint_id    = object.number[0]
alias mine_is_armed    = object.number[1] -- have we started the detonation timer?
alias is_created_vehicle = object.number[2]
alias next_node        = object.object[0]
alias prev_node        = object.object[1]
alias owner            = object.player[0] -- for vehicles
alias abandoned_timer  = object.timer[0] -- used to delete vehicles that stop moving for too long
alias detonation_timer = object.timer[1] -- for landmines
declare object.checkpoint_id      with network priority low
declare object.mine_is_armed      with network priority low
declare object.is_created_vehicle with network priority low
declare object.next_node          with network priority low
declare object.prev_node          with network priority low
declare object.owner              with network priority low
declare object.abandoned_timer  = 16
declare object.detonation_timer = opt_mine_arm_time

alias next_checkpoint_number      = player.number[0]
alias completed_lap_count         = player.number[1]
alias lap_completed_this_tick     = player.number[2]
alias speed_raw                   = player.number[3]
alias speed_kph                   = player.number[4]
alias distance_to_next_checkpoint = player.number[5]
alias is_in_vehicle               = player.number[6]
alias announced_game_start        = player.number[7]
alias self                        = player.player[0] -- used as a run-once flag for setting the player's current checkpoint to the map's first checkpoint
alias on_foot_timer               = player.timer[0]
alias current_lap_time            = player.timer[1]
alias announce_game_start_timer   = player.timer[2]
alias vehicle                     = player.object[0]
declare player.next_checkpoint_number      with network priority low = -1
declare player.completed_lap_count         with network priority low
declare player.lap_completed_this_tick     with network priority low
declare player.speed_raw                   with network priority local
declare player.speed_kph                   with network priority local
declare player.distance_to_next_checkpoint with network priority local
declare player.is_in_vehicle               with network priority local = 1
declare player.announced_game_start        with network priority low
declare player.vehicle       with network priority low
declare player.self          with network priority low
declare player.on_foot_timer = 10
declare player.announce_game_start_timer = 1

declare global.number[2] with network priority local -- temporary
declare global.number[3] with network priority local -- temporary
declare global.number[4] with network priority local -- temporary
declare global.number[5] with network priority local -- temporary
declare global.object[1] with network priority local -- temporary
declare global.object[2] with network priority local -- temporary
declare global.object[3] with network priority local -- temporary
declare global.object[4] with network priority local -- temporary

alias widget_speed_vehi = script_widget[0]
alias widget_speed_foot = script_widget[3]
alias widget_next_gate  = script_widget[1]
alias widget_lap_time   = script_widget[2]

alias cross_round_state = player.script_stat[0] -- bitmask, to track data across rounds
alias crs_defined      = 16384 -- 0x4000 (the sign bit isn't safe for some reason?)
alias crs_civ_veh_mask = 7     -- 0x0007

alias all_landmines = 3 -- Forge label

alias vehicle_none = 7

alias volume_node_checker = global.object[5]
declare volume_node_checker with network priority low
function volume_contains_vehicle()
   --
   -- A call to subject.shape_contains(target) only tests whether (target)'s 
   -- centerpoint is inside of (subject)'s shape. This makes racetracks with 
   -- small checkpoints unplayable for large vehicles. My original plan to 
   -- remedy this was to spawn invisible hill markers and attach them to the 
   -- players' vehicles, and test those markers against the volume along with 
   -- the vehicles and bipeds. However, if (target) is an attached object, 
   -- then the shape_contains function only tests the centerpoint of whatever 
   -- (target) is attached to.
   --
   -- The final plan, then, is to spawn those hill markers but not test them. 
   -- Instead, we spawn and retain a single "utility" marker, and we run the 
   -- shape test by teleporting that marker to each attached marker ("node") 
   -- on the vehicle in sequence.
   --
   alias volume  = global.object[1] -- must be set by the caller
   alias vehicle = global.object[2] -- must be set by the caller; will be modified
   alias result  = global.number[5]
   --
   --
   if volume_node_checker == no_object then
      volume_node_checker = volume.place_at_me(hill_marker, none, never_garbage_collect, 0, 0, 0, none)
   end
   result = 0
   function iterate()
      volume_node_checker.attach_to(vehicle, 0, 0, 0, relative)
      volume_node_checker.detach()
      if volume.shape_contains(volume_node_checker) then
         result = 1
      end
      if result != 1 then
         vehicle = vehicle.next_node
         if vehicle != no_object then
            iterate()
         end
      end
   end
   if vehicle != no_object then
      iterate()
   end
end

on init: do
   civilian_vehicle = rand(5) -- [0, 5)
   civilian_vehicle += 1
   global.number[3] = 0 -- previous round's vehicle
   for each player do
      global.number[2] = current_player.cross_round_state
      global.number[2] &= crs_defined
      if global.number[2] != 0 then
         global.number[3] = current_player.cross_round_state
         global.number[3] &= crs_civ_veh_mask
      end
   end
   if civilian_vehicle == global.number[3] then -- same vehicle as last round; re-roll once
      civilian_vehicle = rand(5)
      civilian_vehicle += 1
      if civilian_vehicle == global.number[3] then
         --
         -- The re-roll didn't work. Just cycle to an adjacent vehicle.
         --
         civilian_vehicle -= 1
         if civilian_vehicle < 1 then
            civilian_vehicle = 5 -- max
         end
      end
   end
   for each player do
      current_player.cross_round_state = civilian_vehicle
      current_player.cross_round_state |= crs_defined
   end
   --
   distance_traveled_update_timer.set_rate(-100%)
   for each player do
      current_player.set_round_card_title("Hit checkpoints to complete laps.\n%n laps to win.", opt_lap_count)
      current_player.best_lap_time = 3600
   end
   for each object with label "race_flag" do
      current_object.checkpoint_id = current_object.spawn_sequence
      current_object.team = team[1]
      current_object.set_waypoint_icon(destination)
      current_object.set_waypoint_text("%nm", hud_player.distance_to_next_checkpoint)
      current_object.set_waypoint_priority(blink)
      current_object.set_invincibility(1)
      current_object.set_spawn_location_permissions(no_one)
      checkpoint_count += 1
      if current_object.checkpoint_id == 1 then -- is first checkpoint?
         first_checkpoint = current_object
         current_object.set_waypoint_visibility(no_one)
         current_object.set_shape_visibility(no_one)
      end
   end
   for each object with label "race_flag" do
      if first_checkpoint == no_object
      or first_checkpoint.checkpoint_id > current_object.checkpoint_id
      then 
         first_checkpoint = current_object
      end
   end
   for each object with label "race_flag" do
      if current_object.checkpoint_id > last_checkpoint_id then 
         last_checkpoint_id = current_object.checkpoint_id
      end
   end
end

on double host migration: do
   for each object with label "race_spawned_vehicle" do
      current_object.delete()
   end
   for each object with label "race_flag" do
      current_object.checkpoint_id = current_object.spawn_sequence
   end
   for each object with label "race_flag" do
      if first_checkpoint == no_object
      or first_checkpoint.checkpoint_id > current_object.checkpoint_id
      then 
         first_checkpoint = current_object
      end
   end
   for each player do
      current_player.self = current_player
   end
end

for each player do -- set loadout palettes
   if current_player.is_elite() then 
      current_player.set_loadout_palette(elite_tier_1)
   else
      current_player.set_loadout_palette(spartan_tier_1)
   end
end

for each object with label "race_flag" do -- manage checkpoint shape visibility
   current_object.set_shape_visibility(no_one)
   for each player do
      if current_object.checkpoint_id == current_player.next_checkpoint_number then 
         current_object.set_shape_visibility(mod_player, current_player, 1)
      end
   end
end

for each object with label "race_spawned_vehicle" do -- delete preplaced vehicles
   if current_object.is_created_vehicle != 1 and current_object.owner == no_player then
      current_object.delete()
   end
end

for each object with label "race_spawned_node" do -- delete preplaced objects and orphaned objects
   if current_object.prev_node == no_object then
      --
      -- A vehicle was destroyed or deleted, orphaning this node.
      --
      alias subject = global.object[2]
      alias target  = global.object[1]
      subject = current_object
      target  = no_object
      function recursive_delete()
         target = subject.next_node
         subject.delete()
         if target != no_object then
            subject = target
            recursive_delete()
         end
      end
      recursive_delete()
   end
end

for each player do -- create player vehicle when there is none
   --
   -- The "On Foot" timer works by clearing the player.vehicle variable 
   -- so that this runs again. This will also run if the player dies 
   -- and respawns.
   -- 
   if current_player.vehicle == no_object then 
      alias new_vehicle = global.object[1]
      alias node_a      = global.object[2]
      alias node_b      = global.object[3]
      alias node_anchor = global.object[4]
      alias node_type   = hill_marker
      function create_node()
         --
         -- See comments for the (volume_contains_vehicle) function for 
         -- information on what we're doing here.
         --
         node_b = node_a.place_at_me(node_type, "race_spawned_node", none, 0, 0, 0, none)
         node_a.next_node = node_b
         node_b.prev_node = node_a
--node_b.set_shape(cylinder, 1, 1, 1) -- DEBUG
--node_b.set_shape_visibility(everyone) -- DEBUG
         node_a = node_b
      end
      function create_initial_node()
         --
         -- If we attach nodes directly to the vehicle, they may anchor to 
         -- specific parts of the vehicle e.g. the Warthog's tires or even 
         -- its steering wheel. Attaching to (0, 0, 0) seems to always be 
         -- safe, so we'll attach an initial node there and then attach all 
         -- subsequent nodes to the initial node.
         --
         node_anchor = new_vehicle.place_at_me(node_type, "race_spawned_node", none, 0, 0, 0, none)
         node_anchor.prev_node = new_vehicle
         new_vehicle.next_node = node_anchor
         node_anchor.copy_rotation_from(new_vehicle, true)
         node_anchor.attach_to(new_vehicle, 0, 0, 0, relative)
         node_a = node_anchor
      end
      --
      function create_nodes_for_mongoose()
         --
         -- This vehicle gets its own function because Mongooses are also the 
         -- fallback for civilian vehicles on maps that don't support them.
         --
         create_initial_node()
         create_node()
         node_a.attach_to(node_anchor, 5, 3, 0, relative)
         create_node()
         node_a.attach_to(node_anchor, 5, -3, 0, relative)
         create_node()
         node_a.attach_to(node_anchor, -5, 3, 0, relative)
         create_node()
         node_a.attach_to(node_anchor, -5, -3, 0, relative)
      end
      --
      new_vehicle = no_object
      if opt_vehicle == 1 then 
         new_vehicle = current_player.biped.place_at_me(mongoose, "race_spawned_vehicle", none, 0, 0, 0, none)
         create_nodes_for_mongoose()
      end
      if opt_vehicle == 2 then 
         new_vehicle = current_player.biped.place_at_me(warthog, "race_spawned_vehicle", none, 0, 0, 0, none)
         create_initial_node()
         create_node()
         node_a.attach_to(node_anchor, 9, 5, 0, relative)
         create_node()
         node_a.attach_to(node_anchor, -9, -5, 0, relative)
         create_node()
         node_a.attach_to(node_anchor, 9, -5, 0, relative)
         create_node()
         node_a.attach_to(node_anchor, -9, 5, 0, relative)
      end
      if opt_vehicle == 3 then 
         new_vehicle = current_player.biped.place_at_me(ghost, "race_spawned_vehicle", none, 0, 0, 0, none)
         create_initial_node()
         create_node()
         node_a.attach_to(node_anchor, -7, 0, 1, relative) -- rear
         create_node()
         node_a.attach_to(node_anchor, 4, 6, 0, relative) -- left wing
         create_node()
         node_a.attach_to(node_anchor, -4, 6, 0, relative) -- right wing
         create_node()
         node_a.attach_to(node_anchor, 6, 0, 1, relative) -- front
      end
      if opt_vehicle == 4 then 
         new_vehicle = current_player.biped.place_at_me(banshee, "race_spawned_vehicle", none, 0, 0, 0, none)
         create_initial_node()
         create_node()
         node_a.attach_to(node_anchor, 8, 0, 7, relative) -- nose
         create_node()
         node_a.attach_to(node_anchor, -4, 0, 10, relative) -- base of fin
         create_node()
         node_a.attach_to(node_anchor, -10, 0, 1, relative) -- bottom rear
         create_node()
         node_a.attach_to(node_anchor, -4, 10, 2, relative) -- left wing, near tip
         create_node()
         node_a.attach_to(node_anchor, -4, -10, 2, relative) -- right wing, near tip
      end
      if opt_vehicle == 5 then 
         new_vehicle = current_player.biped.place_at_me(sabre, none, none, 0, 0, 0, none)
         create_initial_node()
         create_node()
         node_a.attach_to(node_anchor, 31, 0, 8, relative) -- nose
         create_node()
         node_a.attach_to(node_anchor, 1, 0, 18, relative) -- dorsal
         create_node()
         node_a.attach_to(node_anchor, -46, 7, 14, relative) -- left rear fin
         create_node()
         node_a.attach_to(node_anchor, -46, -7, 14, relative) -- right rear fin
         create_node()
         node_a.attach_to(node_anchor, -22, 17, 22, relative) -- left top fin
         create_node()
         node_a.attach_to(node_anchor, -22, -17, 22, relative) -- right top fin
         create_node()
         node_a.attach_to(node_anchor, -8, 25, 8, relative) -- left front thruster
         create_node()
         node_a.attach_to(node_anchor, -8, -25, 8, relative) -- right front thruster
         create_node()
         node_a.attach_to(node_anchor, -34, 24, 8, relative) -- left rear thruster
         create_node()
         node_a.attach_to(node_anchor, -34, -24, 8, relative) -- right rear thruster
         create_node()
         node_a.attach_to(node_anchor, -38, 8, 1, relative) -- corner below left rear thruster
         create_node()
         node_a.attach_to(node_anchor, -38, -8, 1, relative) -- corner below right rear thruster
      end
      if opt_vehicle == 6 then 
         if civilian_vehicle == 1 then
            new_vehicle = current_player.biped.place_at_me(oni_van, none, none, 0, 0, 0, none)
            create_initial_node()
            create_node()
            node_a.attach_to(node_anchor, 10, 5, 0, relative)
            create_node()
            node_a.attach_to(node_anchor, -11, -5, 0, relative)
            create_node()
            node_a.attach_to(node_anchor, 10, -5, 0, relative)
            create_node()
            node_a.attach_to(node_anchor, -11, 5, 0, relative)
         end
         if civilian_vehicle == 2 then
            new_vehicle = current_player.biped.place_at_me(pickup_truck, none, none, 0, 0, 0, none)
            create_initial_node()
            create_node()
            node_a.attach_to(node_anchor, 9, 5, 0, relative)
            create_node()
            node_a.attach_to(node_anchor, -9, -5, 0, relative)
            create_node()
            node_a.attach_to(node_anchor, 9, -5, 0, relative)
            create_node()
            node_a.attach_to(node_anchor, -9, 5, 0, relative)
         end
         if civilian_vehicle == 3 then
            new_vehicle = current_player.biped.place_at_me(electric_cart, none, none, 0, 0, 0, none)
            create_initial_node()
            create_node()
            node_a.attach_to(node_anchor, 7, 4, 0, relative) -- front-left corner
            create_node()
            node_a.attach_to(node_anchor, 7, -4, 0, relative) -- front-right corner
            create_node()
            node_a.attach_to(node_anchor, -7, 4, 0, relative) -- rear-left corner
            create_node()
            node_a.attach_to(node_anchor, -7, -4, 0, relative) -- rear-right corner
         end
         if civilian_vehicle == 4 then
            new_vehicle = current_player.biped.place_at_me(forklift, none, none, 0, 0, 0, none)
            create_initial_node()
            create_node()
            node_a.attach_to(node_anchor, 7, 0, 0, relative) -- front
            create_node()
            node_a.attach_to(node_anchor, -7, 0, 0, relative) -- rear
            --
            -- If we want more precise checks for the forklift, we can use four markers to define 
            -- a box with X [-7, 7] and Y [-3, 3].
            --
         end
         if civilian_vehicle == 5 then
            new_vehicle = current_player.biped.place_at_me(semi_truck, none, none, 0, 0, 0, none)
            create_initial_node()
            create_node()
            node_a.attach_to(node_anchor, 10, 6, 0, relative)
            create_node()
            node_a.attach_to(node_anchor, -10, -6, 0, relative)
            create_node()
            node_a.attach_to(node_anchor, 10, -6, 0, relative)
            create_node()
            node_a.attach_to(node_anchor, -10, 6, 0, relative)
         end
         if new_vehicle == no_object then
            new_vehicle = current_player.biped.place_at_me(mongoose, none, none, 0, 0, 0, none)
            create_nodes_for_mongoose()
         end
      end
      current_player.vehicle = new_vehicle
      new_vehicle.owner = current_player
      new_vehicle.team = current_player.team
      new_vehicle.is_created_vehicle = 1
      current_player.force_into_vehicle(current_player.vehicle)
   end
end

for each player do -- track player vehicles
   global.object[1] = current_player.get_vehicle()
   if not global.object[1] == no_object then 
      current_player.vehicle = global.object[1]
      global.object[1].owner = current_player
   end
end

for each player do -- game start trigger (round card and some Race-specific state preparations)
   current_player.set_round_card_title("Hit checkpoints to complete laps.\n%n laps to win.", opt_lap_count)
   widget_speed_vehi.set_text("%n KPH", hud_player.speed_kph)
   widget_speed_foot.set_text("%n KPH", hud_player.speed_kph)
   widget_next_gate.set_text("next gate: %n  (%nm)", hud_player.next_checkpoint_number, hud_player.distance_to_next_checkpoint)
   widget_lap_time.set_text("lap time: %s", hud_player.current_lap_time)
   if current_player.self == no_player then 
      current_player.next_checkpoint_number = first_checkpoint.checkpoint_id
      current_player.self = current_player
   end
   current_player.announce_game_start_timer.set_rate(-100%)
   if current_player.announced_game_start == 0 and current_player.announce_game_start_timer.is_zero() then 
      send_incident(race_game_start, current_player, no_player)
      game.show_message_to(current_player, none, "Race+ v1.0.0: Race enhanced by Cobb!")
      current_player.best_lap_time = 3600
      current_player.announced_game_start = 1
      current_player.announce_game_start_timer.set_rate(0%)
   end
end

do
   distance_traveled_update_timer.set_rate(-100%)
   if distance_traveled_update_timer.is_zero() then 
      for each player do
         global.number[2] = 1
         global.number[3] = current_player.speed_raw
         global.number[2] *= global.number[3]
         global.number[2] *= 109
         global.number[2] /= 100
         current_player.total_distance += global.number[2]
         if current_player.speed_kph > current_player.top_speed then 
            current_player.top_speed = current_player.speed_kph
         end
      end
      distance_traveled_update_timer.reset()
   end
end

for each player do -- checkpoint code
   current_player.set_co_op_spawning(true)
   current_player.biped.set_spawn_location_permissions(no_one)
   --
   alias checkpoint_is_claimed  = global.number[2]
   alias scoreboard_pos         = global.number[3]
   alias next_checkpoint_id     = global.number[4]
   alias expected_id_to_move_to = global.number[5]
   --
   checkpoint_is_claimed = 0
   if current_player.is_in_vehicle == 1 or opt_vehicle == vehicle_none then 
      --
      -- Let's check if the player has claimed any checkpoint with the ID they're currently 
      -- trying to reach.
      --
      alias volume  = global.object[1]
      alias vehicle = global.object[2]
      for each object with label "race_flag" do
         if current_object.checkpoint_id == current_player.next_checkpoint_number then 
            current_object.set_waypoint_visibility(mod_player, current_player, 1)
            if checkpoint_is_claimed == 0 then
               alias result = global.number[5]
               result = 1
               if not current_object.shape_contains(current_player.biped) then
                  volume  = current_object
                  vehicle = current_player.get_vehicle()
                  volume_contains_vehicle()
               end
               if result == 1 then
                  current_object.set_waypoint_visibility(mod_player, current_player, 0)
                  checkpoint_is_claimed = 1
               end
            end
         end
      end
      if checkpoint_is_claimed == 1 then 
         current_player.score += 1 -- taking a checkpoint earns you a point
         send_incident(checkpoint_reached_team, current_player, no_player)
         scoreboard_pos = 0
         do
            scoreboard_pos = current_player.get_scoreboard_pos()
            if scoreboard_pos == 1 and last_player_to_take_lead != current_player then 
               --
               -- If taking this checkpoint makes you tie with the leader, the gametype will 
               -- subtract a point from their score to force you into the lead. It will also 
               -- queue to award another point and set you to last_player_to_take_lead.
               --
               queued_award_point_to = current_player
               last_player_to_take_lead.score -= 1 -- losing the lead to a tie costs you a point
            end
         end
         next_checkpoint_id = current_player.next_checkpoint_number
         --
         -- Let's figure out which checkpoint should be the player's (new) next checkpoint. 
         -- We're doing this a bit carefully in case any checkpoints have dynamically spawned 
         -- with IDs between the newly-claimed checkpoint and what was expected to be the 
         -- next checkpoint.
         --
         expected_id_to_move_to = last_checkpoint_id
         expected_id_to_move_to += 1
         for each object with label "race_flag" do
            if  current_object.checkpoint_id > current_player.next_checkpoint_number
            and current_object.checkpoint_id < expected_id_to_move_to
            then 
               expected_id_to_move_to = current_object.checkpoint_id
            end
         end
         current_player.next_checkpoint_number = expected_id_to_move_to
         --
         if current_player.next_checkpoint_number > last_checkpoint_id then -- queue to handle lap completion
            current_player.lap_completed_this_tick = 1
            current_player.next_checkpoint_number = first_checkpoint.checkpoint_id
         end
         --
         -- Update spawn permissions and waypoint visibility:
         --
         for each object with label "race_flag" do -- revoke all spawn permissions from the player
            current_object.set_spawn_location_permissions(mod_player, current_player, 0)
            if current_object.checkpoint_id == current_player.next_checkpoint_number then -- show the next checkpoint to the player
               current_object.set_waypoint_visibility(mod_player, current_player, 1)
            end
         end
         for each object with label "race_flag" do -- allow the player to spawn at the checkpoint(s) they've claimed
            if current_object.checkpoint_id == next_checkpoint_id then 
               current_object.set_spawn_location_permissions(mod_player, current_player, 1)
               current_player.set_primary_respawn_object(current_object)
               current_object.set_waypoint_visibility(mod_player, current_player, 0)
            end
         end
      end
   end
end

for each player do -- UI for lap completion; best lap time tracking
   current_player.current_lap_time.set_rate(100%)
   if current_player.lap_completed_this_tick == 1 then 
      game.show_message_to(current_player, none, "Lap Complete.")
      send_incident(lap_complete, current_player, no_player)
      current_player.completed_lap_count += 1
      if current_player.completed_lap_count == 1 then 
         current_player.best_lap_time = current_player.current_lap_time
      elseif current_player.current_lap_time < current_player.best_lap_time then 
         current_player.best_lap_time = current_player.current_lap_time
         game.show_message_to(current_player, none, "New best lap time!")
      end
      current_player.current_lap_time.reset()
      do
         alias complete_count_for_final_lap = global.number[2]
         --
         complete_count_for_final_lap = opt_lap_count
         complete_count_for_final_lap -= 1
         if current_player.completed_lap_count == complete_count_for_final_lap then 
            --
            -- Only play the "final lap" sound if the player hit the final lap while 
            -- they were in the lead.
            --
            alias scoreboard_pos = global.number[3]
            --
            scoreboard_pos = 0
            scoreboard_pos = current_player.get_scoreboard_pos()
            if scoreboard_pos == 1 then 
               send_incident(final_lap, current_player, all_players)
            end
         end
      end
      current_player.lap_completed_this_tick = 0
   end
end

for each player do -- hide the Race UI when the player is dead
   widget_speed_vehi.set_visibility(current_player, false)
   widget_speed_foot.set_visibility(current_player, false)
   widget_lap_time.set_visibility(current_player, false)
   widget_next_gate.set_visibility(current_player, false)
   global.object[1] = current_player.biped
   if not global.object[1] == no_object then 
      widget_speed_vehi.set_visibility(current_player, true)
      widget_lap_time.set_visibility(current_player, true)
      widget_next_gate.set_visibility(current_player, true)
   end
end

for each player do -- track whether the player is on foot, and reset them if they're on foot for too long
   global.object[1] = no_object
   current_player.is_in_vehicle = 1
   global.object[1] = current_player.try_get_vehicle()
   if global.object[1] == no_object then
      current_player.is_in_vehicle = 0
      widget_speed_vehi.set_visibility(current_player, false)
      script_widget[3].set_visibility(current_player, true)
      if opt_vehicle != vehicle_none then
         widget_speed_vehi.set_visibility(current_player, false) -- hide the Race UI when the player is on foot
         widget_lap_time.set_visibility(current_player, false)
         widget_next_gate.set_visibility(current_player, false)
         script_widget[3].set_visibility(current_player, false)
         --
         -- Manage the on-foot timer:
         --
         current_player.on_foot_timer.set_rate(-100%)
         if current_player.on_foot_timer.is_zero() then 
            do
               alias vehicle = global.object[2]
               --
               vehicle = current_player.vehicle
               if vehicle.owner == current_player or vehicle.owner == no_player then 
                  current_player.vehicle.delete()
               end
            end
            current_player.vehicle = no_object
            game.show_message_to(current_player, announce_race, "On foot for too long!")
            current_player.on_foot_timer.reset()
         end
      end
   end
end

for each player do -- reset the on-foot timer every tick that the player is in a vehicle
   global.object[1] = current_player.get_vehicle()
   if not global.object[1] == no_object then 
      current_player.on_foot_timer.reset()
   end
end

for each object with label all_landmines do -- landmines
   if opt_landmines == 0 then 
      current_object.delete()
   end
   alias waypoint_range = global.number[7]
   waypoint_range = opt_mine_arm_distance
   waypoint_range += 10
   --
   -- If we didn't delete the landmine, then let's give it a barely-visible waypoint 
   -- with a short range -- just something to help the player out, yes?
   --
   current_object.set_waypoint_visibility(everyone)
   current_object.set_waypoint_priority(low)
   current_object.set_waypoint_range(0, waypoint_range)
   current_object.set_shape(sphere, opt_mine_arm_distance)
   current_object.set_shape_visibility(no_one)
   --
   -- Let's have a little more fun: if the landmine has a shape set, then when the 
   -- player enters that shape, we should set the landmine to detonate on a timed 
   -- delay even if the player never touches it!
   --
   -- Yes, this really is in the vanilla gametype script.
   --
   if opt_mine_arm_distance > 0 then
      alias volume = global.object[1]
      volume = current_object
      for each player do
         if volume.mine_is_armed == 0 then
            alias vehicle = global.object[2]
            alias result  = global.number[5]
            --
            result = 1
            if not volume.shape_contains(current_player.biped) then
               vehicle = current_player.get_vehicle()
               volume_contains_vehicle()
            end
            if result == 1 then
               volume.mine_is_armed = 1
               volume.detonation_timer.set_rate(-100%)
               volume.set_waypoint_priority(blink)
               volume.set_waypoint_icon(bomb)
            end
         end
      end
      if current_object.detonation_timer.is_zero() then 
         current_object.kill(false)
      end
   end
end

for each player do
   if not current_player.completed_lap_count < opt_lap_count then 
      game.end_round()
   end
end

if game.round_time_limit > 0 and game.round_timer.is_zero() then 
   game.end_round()
end

for each object with label "none" do -- oh. okay.
   current_object.delete()
end

do -- delete Race vehicles that have stopped moving for too long...
   alias speed         = global.number[2]
   alias minimum_speed = 50
   --
   for each object with label "race_spawned_vehicle" do
      speed = 0
      speed = current_object.get_speed()
      if speed < minimum_speed then 
         current_object.abandoned_timer.set_rate(-100%)
         if current_object.abandoned_timer.is_zero() then 
            current_object.delete()
         end
      end
   end
end

do -- postpone the deletion of stationary Race vehicles if they are near any player
   alias distance     = global.number[2]
   alias max_distance = 10
   alias unused_var   = global.object[1]
   --
   for each object with label "race_spawned_vehicle" do
      unused_var = no_object
      distance = 0
      for each player do
         distance = current_object.get_distance_to(current_player.biped)
         if distance < max_distance then 
            current_object.abandoned_timer.reset()
         end
      end
   end
end

for each player do -- if the player switches vehicles, orphan their previous vehicle
   alias player_vehicle = global.object[1]
   --
   player_vehicle = current_player.vehicle
   if player_vehicle != no_object then 
      if player_vehicle.owner != current_player then 
         current_player.vehicle = no_object
      end
      for each object with label "race_spawned_vehicle" do
         if  current_object != player_vehicle
         and current_object.owner == current_player or current_object.owner == no_player
         then 
            current_object.owner = no_player
         end
      end
   end
end

do -- delete orphaned vehicles unless someone on foot is near them, in which case grant them ownership
   --
   -- Delete unowned vehicles unless a player without a vehicle is near them, 
   -- in which case assign them to that player.
   --
   alias distance = global.number[2]
   alias max_distance = 100
   --
   distance = 0
   for each object with label "race_spawned_vehicle" do
      if current_object.owner == no_player then 
         for each player do
            if current_player.vehicle == no_object then 
               distance = current_object.get_distance_to(current_player.biped)
               if distance <= max_distance then 
                  current_object.owner   = current_player
                  current_player.vehicle = current_object
               end
            end
         end
         if current_object.owner == no_player then 
            current_object.delete()
         end
      end
   end
end

for each player do -- delete a player's vehicle when the player dies
   if current_player.killer_type_is(guardians | suicide | kill | betrayal | quit) then 
      current_player.vehicle.delete()
      current_player.vehicle = no_object
   end
end

on local: do -- maintain player speed and distance-to-checkpoint vars
   for each player do
      current_player.speed_raw = current_player.biped.get_speed()
      current_player.speed_kph = current_player.speed_raw
      current_player.speed_kph *= 109
      current_player.speed_kph /= 100 -- to KPH
      --
      alias target_checkpoint = global.object[1]
      --
      target_checkpoint = no_object
      for each object with label "race_flag" do
         if current_object.checkpoint_id == current_player.next_checkpoint_number then 
            target_checkpoint = current_object
         end
      end
      current_player.distance_to_next_checkpoint = 0
      current_player.distance_to_next_checkpoint = current_player.biped.get_distance_to(target_checkpoint)
      current_player.distance_to_next_checkpoint *= 7
      current_player.distance_to_next_checkpoint /= 23 -- to meters
   end
end

for each player do -- manage tracking who is in the lead, and give them a point, too
   if current_player == queued_award_point_to then 
      current_player.score += 1 -- taking the lead earns you a point
      last_player_to_take_lead = current_player
      queued_award_point_to    = no_player
   end
end

for each player do
   --
   -- If the player is on the first checkpoint and has not claimed any checkpoints before, 
   -- then we need this special-case to allow them to spawn.
   --
   if current_player.next_checkpoint_number == first_checkpoint.checkpoint_id then -- player is on the first checkpoint?
      for each object with label "race_flag" do
         if current_object.checkpoint_id == current_player.next_checkpoint_number then 
            current_object.set_spawn_location_permissions(mod_player, current_player, 1)
            current_player.set_primary_respawn_object(current_object)
         end
      end
   end
end

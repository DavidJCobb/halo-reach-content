
--
-- PROOF OF CONCEPT: IDENTIFYING WHAT SEAT A PLAYER IS IN
--
-- Megalo doesn't offer an API for this, but there's a hacky workaround: 
-- attach markers to a vehicle at the position of each seat, and then 
-- check which marker contains the player. We use a linked list of Hill 
-- Markers attached to vehicles that have at any point been occupied by 
-- a player.
--
-- As a proof-of-concept game variant, this does not contain the usual 
-- boilerplate code that you'd want in a game variant (e.g. loadout 
-- palette setup and round timer management), nor does it contain any 
-- scoring or other gameplay elements.
--
-- As of this writing, seat positions can be looked up in Assembly like 
-- so:
--
--  - The VEHI tag defines the seats, listing their markers.
--
--  - The HLMT tag defines the different 3D models for the vehicle. The 
--    MODE tag defines the render model. The seat markers are listed in 
--    the MODE tag as Marker Groups; each Marker Group is a child of a 
--    Node, and Nodes can be children of each other. You'll have to add 
--    translation values together as appropriate.
--
--    Multiply the translation values by 10 to get the Megalo units.
--
--  - Every spot where you can hijack a vehicle is also a "seat," but 
--    with additional data indicating which seat you end up in when you 
--    finish hijacking (when it's not something like a wraith, where you 
--    just melee or plant a grenade). In some cases, the hijack seat has 
--    an identical or near-identical position to the rider seat, but this 
--    is not always true.
--
--  - Turrets are implemented as separate vehicles which are attached to 
--    their bases. The HLMT for the base vehicle has a Variants list with 
--    an Objects list per variant. These, too, use a marker. Be sure to  
--    get the seat position for the turret itself and add that in, too.
--

-- TODO:
--
--  - Test Falcon gunners (requires Theater since turrets are first-person 
--    and you can't see your own arms)
--
--  - Need positions for Thorage vehicles; requires opening MCC maps. As of 
--    late March 2020 the format has changed; need to see if Assembly has 
--    been made compatible.
--
--  - TEST HIJACKING. REQUIRES HAVING ANOTHER PLAYER ON HAND, SINCE WHEN A 
--    RIDER-SEAT AND A HIJACKER-SEAT HAVE THE SAME POSITION, WE CAN ONLY 
--    IDENTIFY A HIJACKER BY PLAYER (NPC BIPEDS ARE NOT PLAYERS).


alias driver_traits    = script_traits[0]
alias passenger_traits = script_traits[1]
alias gunner_traits    = script_traits[2]
alias hijacker_traits  = script_traits[3]

enum seat_type
   none
   driver
   gunner
   passenger
   hijacker
end

alias temp_obj_00  = global.object[0]
alias temp_obj_01  = global.object[1]
alias temp_obj_02  = global.object[2]
alias temp_obj_03  = global.object[3]
alias temp_plr_00  = global.player[0]
alias seat_type    = object.number[0] -- a seat node's type
alias hijack_is_same_pos = object.number[1] -- this rider-seat has the same or similar position as its corresponding hijack-seat
alias seat_node    = object.object[2] -- singly-linked list of "seat nodes"
alias last_player  = object.player[1] -- last player to occupy a seat node
alias seat_type    = player.number[0] -- player's last-known seat type
alias last_vehicle = player.object[0] -- player's last-known vehicle
alias last_seat    = player.object[1] -- player's last-known seat node

-- < TEST CODE FOR HIJACKING
alias did_set_up_hijack = global.number[0]
alias hijack_setup_time = global.timer[0]
alias temp_plr_00 = global.player[0]
declare hijack_setup_time = 4
if did_set_up_hijack == 0 then
   hijack_setup_time.set_rate(-100%)
   if hijack_setup_time.is_zero() then
      for each player do
         temp_plr_00 = current_player
      end
      for each object do
         function _force()
            temp_obj_00 = current_object.place_at_me(elite, none, none, 0, 0, 0, ultra)
            temp_plr_00.set_biped(temp_obj_00)
            temp_plr_00.force_into_vehicle(current_object)
            temp_obj_01 = temp_plr_00.get_vehicle()
            if temp_obj_01 == no_object then
               temp_obj_00.delete()
            end
         end
         --
         if current_object.is_of_type(banshee)
         or current_object.is_of_type(ghost)
         then
            _force()
         end
         if current_object.is_of_type(mongoose)
         or current_object.is_of_type(revenant)
         or current_object.is_of_type(sabre)
         or current_object.is_of_type(scorpion)
         or current_object.is_of_type(wraith)
         then
            _force()
            _force()
         end
         if current_object.is_of_type(falcon)
         or current_object.is_of_type(warthog)
         then
            _force()
            _force()
            _force()
         end
      end
      --
      -- Ensure the player can spawn in a natural biped:
      --
      temp_obj_00 = temp_plr_00.biped.place_at_me(elite, none, none, 0, 0, 0, ultra)
      temp_plr_00.set_biped(temp_obj_00)
      temp_obj_00.delete()
      --
      did_set_up_hijack = 1
      game.show_message_to(all_players, none, "NPC bipeds set up for hijack tests!")
   end
end
-- > TEST CODE FOR HIJACKING

function set_up_seat_nodes()
   --
   -- Let's create the linked list of "seat nodes" for a vehicle. We want 
   -- to give the vehicle a single unnamed node at its origin position, 
   -- and attach all other seat nodes directly to that. Why? When you 
   -- attach something to a vehicle, it anchors to the nearest 3D node on 
   -- the vehicle's model -- and will animate with that node. For example, 
   -- objects attached to a Warthog will animate with the tires or even 
   -- the steering wheel. The solution is to attach an object directly to 
   -- (0, 0, 0) on the object and then attach all other nodes to that 
   -- first one.
   --
   alias vehicle = temp_obj_01 -- argument
   alias working = temp_obj_02
   alias prior   = temp_obj_03
   --
   prior = vehicle
   function _append()
      working = vehicle.place_at_me(hill_marker, none, none, 0, 0, 0, none)
      working.set_shape(sphere, 2)
      prior.seat_node = working
      prior   = working
   end
   --
   _append()
   vehicle.seat_node = working
   working.copy_rotation_from(vehicle, true)
   working.attach_to(vehicle, 0, 0, 0, relative)
   working.seat_type = seat_type.none
   if vehicle.is_of_type(banshee) then
      -- Driver seat:
      _append()
      working.attach_to(vehicle.seat_node, -1, 0, 6, relative)
      working.seat_type = seat_type.driver
      working.hijack_is_same_pos = 1
   end
   if vehicle.is_of_type(falcon) then
      -- Driver seat:
      _append()
      working.attach_to(vehicle.seat_node, 9, 0, 3, relative)
      working.seat_type = seat_type.driver
      --
      -- Left gunner:
      _append()
      working.attach_to(vehicle.seat_node, -6, 5, 2, relative) -- NEEDS CONFIRMATION
      working.seat_type = seat_type.gunner
      --
      -- Right gunner:
      _append()
      working.attach_to(vehicle.seat_node, -6, -5, 2, relative) -- NEEDS CONFIRMATION
      working.seat_type = seat_type.gunner
   end
   if vehicle.is_of_type(ghost) then
      -- Driver seat:
      _append()
      working.attach_to(vehicle.seat_node, -3, 0, 1, relative)
      working.seat_type = seat_type.driver
      working.hijack_is_same_pos = 1
   end
   if vehicle.is_of_type(mongoose) then
      -- Driver seat:
      _append()
      working.attach_to(vehicle.seat_node, -2, 0, 3, relative)
      working.seat_type = seat_type.driver
      working.hijack_is_same_pos = 1
      --
      -- Passenger seat (cannot be hijacked):
      _append()
      working.attach_to(vehicle.seat_node, -4, 0, 4, relative)
      working.seat_type = seat_type.passenger
   end
   if vehicle.is_of_type(revenant) then
      -- Driver seat:
      _append()
      working.attach_to(vehicle.seat_node, -4, 2, 3, relative)
      working.seat_type = seat_type.driver
      working.hijack_is_same_pos = 1
      --
      -- Passenger seat:
      _append()
      working.attach_to(vehicle.seat_node, -4, -2, 3, relative)
      working.seat_type = seat_type.passenger
      working.hijack_is_same_pos = 1
   end
   if vehicle.is_of_type(scorpion) then
      -- Driver seat:
      _append()
      working.attach_to(vehicle.seat_node, 0, 2, 4, relative)
      working.seat_type = seat_type.driver
      --
      -- Turret:
      _append()
      working.attach_to(vehicle.seat_node, 4, -2, 6, relative)
      working.seat_type = seat_type.gunner
      --
      -- Hijacking:
      _append()
      working.attach_to(vehicle.seat_node, -15, 0, 7, relative)
      working.seat_type = seat_type.hijacker
      _append()
      working.attach_to(vehicle.seat_node, 3, 8, 9, relative)
      working.seat_type = seat_type.hijacker
      _append()
      working.attach_to(vehicle.seat_node, 3, -8, 9, relative)
      working.seat_type = seat_type.hijacker
   end
   if vehicle.is_of_type(warthog) then
      -- Driver seat:
      _append()
      working.attach_to(vehicle.seat_node, 0, 2, 4, relative)
      working.seat_type = seat_type.driver
      --
      -- Passenger seat:
      _append()
      working.attach_to(vehicle.seat_node, -2, -2, 6, relative)
      working.seat_type = seat_type.passenger
      --
      -- Boarding driver:
      _append()
      working.attach_to(vehicle.seat_node, 0, 6, 6, relative)
      working.seat_type = seat_type.hijacker
      --
      -- Boarding passenger:
      _append()
      working.attach_to(vehicle.seat_node, 0, -6, 6, relative)
      working.seat_type = seat_type.hijacker
      --
      -- Turret:
      _append()
      working.attach_to(vehicle.seat_node, -5, 0, 7, relative)
      working.seat_type = seat_type.gunner
      --
      -- Boarding turret:
      _append()
      working.attach_to(vehicle.seat_node, -12, 0, 4, relative)
      working.seat_type = seat_type.hijacker
      
      -- Commented these out because they conflict with the turret position; 
      -- would need a way to detect if a warthog has a turret before using 
      -- these:
      
      --
      -- Troop transport back:
      --_append()
      --working.attach_to(vehicle.seat_node, -7, 0, 6, relative)
      --working.seat_type = seat_type.passenger
      --
      -- Troop transport left:
      --_append()
      --working.attach_to(vehicle.seat_node, -5, 1, 6, relative)
      --working.seat_type = seat_type.passenger
      --
      -- Troop transport right:
      --_append()
      --working.attach_to(vehicle.seat_node, -5, -1, 6, relative)
      --working.seat_type = seat_type.passenger
   end
   if vehicle.is_of_type(wraith) then
      -- Driver seat:
      _append()
      working.attach_to(vehicle.seat_node, 3, 0, 4, relative)
      working.seat_type = seat_type.driver
      --
      -- Turret:
      _append()
      working.attach_to(vehicle.seat_node, -2, 0, 10, relative)
      working.seat_type = seat_type.gunner
      --
      -- Boarding left:
      _append()
      working.attach_to(vehicle.seat_node, 5, 6, 9, relative)
      working.seat_type = seat_type.hijacker
      --
      -- Boarding right:
      _append()
      working.attach_to(vehicle.seat_node, 5, -6, 9, relative)
      working.seat_type = seat_type.hijacker
      --
      -- Boarding back:
      _append()
      working.attach_to(vehicle.seat_node, -20, 0, 5, relative)
      working.seat_type = seat_type.hijacker
   end
   --
   vehicle.seat_node.set_shape(none)
end

for each player do -- track player's current seat type
   alias vehicle = temp_obj_00
   --
   current_player.seat_type = seat_type.none
   vehicle = current_player.get_vehicle()
   if vehicle != no_object then
      if vehicle.seat_node == no_object then
         temp_obj_01 = vehicle -- argument
         set_up_seat_nodes()
      end
      --
      -- We can use a recursive function to traverse the linked list of 
      -- seat nodes:
      --
      alias current_node  = temp_obj_01
      function _handle_shape_contains()
         alias occupied_node = temp_obj_02
         if current_node.shape_contains(current_player.biped) then
            occupied_node = current_node
            current_player.seat_type = occupied_node.seat_type
            current_player.last_seat = occupied_node
            if current_node.hijack_is_same_pos == 1 then
               --
               -- We can't use positioning distinguish being in this seat from hijacking 
               -- this seat, because riding and hijacking use the same positions.
               --
               if  current_node.last_player != current_player
               and current_node.last_player != no_player
               and current_node.last_player.biped != no_object -- the other player could've quit the match and therefore not been removed from the seat
               and current_node.shape_contains(current_node.last_player.biped)
               then
                  --
                  -- This seat is already flagged as having a player, and that player has 
                  -- a biped (meaning they haven't quit or been killed). We must be hijacking.
                  --
                  current_player.seat_type = seat_type.hijacker
                  occupied_node = no_object -- clear this so we don't set state on the seat node
               end
            end
            occupied_node.last_player = current_player
         end
      end
      --
      current_node = current_player.last_seat
      if current_player.last_vehicle == vehicle and current_node != no_object then
         --
         -- First, a shortcut: players will spend more frames NOT changing vehicles than 
         -- they will spend changing vehicles, so if a player's vehicle has not changed 
         -- and we know what seat node they had last, test that node first.
         --
         _handle_shape_contains()
      end
      current_player.last_vehicle = vehicle
      if current_player.seat_type == seat_type.none then
         --
         -- Looks like the player isn't in the last seat node we had them in. 
         --
         current_node.last_player = no_object
         --
         -- We can traverse the vehicle's seat node list using a recursive function:
         --
         current_node = vehicle.seat_node
         function _iterate()
            _handle_shape_contains()
            current_node = current_node.seat_node
            if current_node != no_object then
               _iterate()
            end
         end
         _iterate()
      end
   end
end
for each player do -- cleanup for players who have stopped being in a vehicle/seat
   --
   -- This cleanup loop will only run for players who are still in the match; players 
   -- who have quit out won't be cleaned up, so the checks above need to deal with that.
   --
   if current_player.seat_type == seat_type.none then
      alias last_seat = temp_obj_00
      --
      last_seat = current_player.last_seat
      current_player.last_seat = no_object
      if last_seat.last_player == current_player then
         last_seat.last_player = no_object
      end
   end
end

for each player do -- apply traits
   if current_player.seat_type == seat_type.driver then
      current_player.apply_traits(driver_traits)
   end
   if current_player.seat_type == seat_type.gunner then
      current_player.apply_traits(gunner_traits)
   end
   if current_player.seat_type == seat_type.passenger then
      current_player.apply_traits(passenger_traits)
   end
   if current_player.seat_type == seat_type.hijacker then
      current_player.apply_traits(hijacker_traits)
   end
end
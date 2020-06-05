
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
--  - Turrets are implemented as separate vehicles which are attached to 
--    their bases. The HLMT for the base vehicle has a Variants list with 
--    an Objects list per variant. These, too, use a marker. Be sure to  
--    get the seat position for the turret itself and add that in, too.
--

-- TODO:
--
--  - Wraith Anti-Infantry Turret position is wrong
--
--  - Test Falcon gunners (requires Theater since turrets are first-person 
--    and you can't see your own arms)
--
--  - Need positions for Thorage vehicles; requires opening MCC maps. As of 
--    late March 2020 the format has changed; need to see if Assembly has 
--    been made compatible.
--
--  - Test hijacking, somehow
--
--     - Requires hijack checks for cases where the hijack "seat" is too 
--       close (or overlapping) the occupant seat. We'd need to maintain a 
--       timer on each player which counts upward, measuring how long they 
--       have occupied a given seat; if a hijack "seat" is known to overlap 
--       an occupant seat, and two players are in the same vehicle at the 
--       same seat, then the one who has been there longer is being hijacked 
--       by the other.
--
--        - Needs an "hijack_is_same_pos" object.number
--
--        - May want to add "..._hijackable" constants to the seat_type enum. 
--          We want this to be able to work with Race+; as is, we can replace 
--          that script's player.is_in_vehicle with player.seat_type, but we 
--          are otherwise out of player.number variables we can use.


alias driver_traits    = script_traits[0]
alias passenger_traits = script_traits[1]
alias gunner_traits    = script_traits[2]

alias temp_obj_00 = global.object[0]
alias temp_obj_01 = global.object[1]
alias temp_obj_02 = global.object[2]
alias temp_obj_03 = global.object[3]
alias seat_type   = object.number[0]
alias seat_node   = object.object[2]
enum seat_type
   none
   driver
   gunner
   passenger
   hijacker
end
alias seat_type = player.number[0]

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
      --
      -- The "boarding driver" seat has the same coordinates as the driver's seat, and so 
      -- cannot be meaningfully distinguished... unless the hijacker and the hijackee both 
      -- show up as sharing the vehicle, in which case the hijacker is the one of the two 
      -- who has been at that spot for the shortest amount of time. Hm...
      --
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
      --
      -- Boarding driver:
      _append()
      working.attach_to(vehicle.seat_node, -6, 0, 0, relative)
      working.seat_type = seat_type.hijacker
   end
   if vehicle.is_of_type(mongoose) then
      -- Driver seat:
      _append()
      working.attach_to(vehicle.seat_node, -2, 0, 3, relative)
      working.seat_type = seat_type.driver
      --
      -- Passenger seat:
      _append()
      working.attach_to(vehicle.seat_node, -4, 0, 4, relative)
      working.seat_type = seat_type.passenger
      --
      -- The "boarding driver" seat has the same coordinates as the driver's seat, and so 
      -- cannot be meaningfully distinguished... unless the hijacker and the hijackee both 
      -- show up as sharing the vehicle, in which case the hijacker is the one of the two 
      -- who has been at that spot for the shortest amount of time. Hm...
      --
      -- The passenger seat, apparently, cannot be hijacked at all.
      --
   end
   if vehicle.is_of_type(revenant) then
      -- Driver seat:
      _append()
      working.attach_to(vehicle.seat_node, -4, 2, 3, relative)
      working.seat_type = seat_type.driver
      --
      -- Passenger seat:
      _append()
      working.attach_to(vehicle.seat_node, -4, -2, 3, relative)
      working.seat_type = seat_type.passenger
      --
      -- The "boarding driver" seat is too close to the driver seat to be meaningfully tested. 
      -- Ditto for the passenger seat.
      --
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
      working.attach_to(vehicle.seat_node, -2, 0, 7, relative)
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
      alias current_node = temp_obj_01
      current_node = vehicle.seat_node
      function _iterate()
         if current_node.shape_contains(current_player.biped) then
            current_player.seat_type = current_node.seat_type
         end
         current_node = current_node.seat_node
         if current_node != no_object then
            _iterate()
         end
      end
      _iterate()
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
end
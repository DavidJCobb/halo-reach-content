
--
-- MINESWEEPER
--
--  - Uses a pre-rotated Hill Marker to spawn a vertical board, and pre-rotated 
--    Dice to display numbers for each cell
--
--  - Every board cell has a Fusion Coil
--
--  - Shoot a cell with a Magnum to try and reveal it, or with a DMR to plant a 
--    flag on it (game forces these weapons into the active player's hands)
--

--
-- TODO:
--
--  - Verify that numbers 5 and 6 display properly. Add code to display 
--    numbers 7 and 8.
--
--  - Add divergent behavior for Team versus FFA.
--
--     - Team: Players on the team take turns, each uncovering one cell.
--
--     - FFA: (Current script behavior.) A single player works to solve the 
--       board.
--

alias board_size         = 9
alias desired_mine_count = 10
alias cell_length        = 10 -- a Block 1x1 Flat is 1.0 Forge units on a side
alias cell_length_neg    = -10

alias opt_debugging      = script_option[0]
alias opt_points_win     = script_option[1]
alias opt_points_loss    = script_option[2]
alias opt_points_flag    = script_option[3]
alias opt_points_space   = script_option[4]
alias active_player_traits = script_traits[0]
alias spectator_traits     = script_traits[1]

alias board_center = global.object[0]
alias first_cell   = global.object[1]
alias temp_obj_00  = global.object[2]
alias temp_obj_01  = global.object[3]
alias temp_obj_02  = global.object[4]
alias temp_obj_03  = global.object[5]
alias temp_obj_04  = global.object[6]
alias temp_int_00  = global.number[0]
alias temp_int_01  = global.number[2]
alias temp_int_02  = global.number[3]

alias active_player = global.player[0] -- the player currently trying to solve the board; for team games, please use another variable

alias announced_game_start = player.number[0]
alias announce_start_timer = player.timer[0]
declare player.announce_start_timer = 5

alias set_player_weapons = player.number[1]

-- Fields for cells:
alias cell_above = object.object[0]
alias cell_left  = object.object[1]
alias cell_right = object.object[2]
alias cell_below = object.object[3] -- no more room for object.object vars!
alias adjacent_mines_count = object.number[1]
alias has_mine             = object.number[3]
alias coord_x              = object.number[4]
alias coord_y              = object.number[5]
alias has_flag             = object.number[6]
alias reveal_state         = object.number[7]
--
-- Fields for Block 1x1 Flats:
alias cell_marker  = object.object[0]
alias cell_dice    = object.object[1] -- for 7 and 8, check block.cell_dice.next_object
alias coil         = object.object[2]
alias cell_flag    = object.object[3]
alias number_drawn = object.number[0] -- bool
alias coil_invulnerability_timer = object.timer[0]
declare object.coil_invulnerability_timer = 1
--
-- General:
alias next_object       = object.object[1]
alias is_script_created = object.number[2]
--
alias cell_flags = object.number[0]
alias cell_flag_initial_coil_spawned = 1 -- 0x0001
--
alias cell_reveal_state_no        = 0
alias cell_reveal_state_yes       = 1
alias cell_reveal_state_recursing = 2

alias game_state_flags                  = global.number[1]
alias game_state_flag_board_constructed = 1 -- 0x0001
alias game_state_flag_player_failed     = 2 -- 0x0002 -- player hit a landmine
alias game_state_flag_landmine_shower   = 4 -- 0x0004
alias game_state_flag_player_killed     = 8 -- 0x0008
alias game_failure_cinematic_timer   = global.timer[0] -- kill active player and end round after this time passes
alias game_failure_timer             = global.timer[1] -- kill active player and end round after this time passes
declare game_failure_cinematic_timer = 4
declare game_failure_timer           = 8

declare active_player with network priority high
declare object.adjacent_mines_count with network priority low

alias ui_current_player = script_widget[0]
alias ui_how_to_play    = script_widget[1]

on init: do
   for each player do
      current_player.set_round_card_title("Reveal all cells in the grid while avoiding \nmines!")
      current_player.announce_start_timer.set_rate(-100%)
   end
end
for each player do -- set loadout palettes
   ui_current_player.set_text("It's %s's turn!", active_player)
   ui_how_to_play.set_text("Shoot a space with the Magnum to uncover it.\nShoot a space with the DMR to (un)flag it.")
   if current_player.announce_start_timer.is_zero() and current_player.announced_game_start != 1 then
      current_player.announced_game_start = 1
      current_player.announce_start_timer.set_rate(0%)
      send_incident(action_sack_game_start, current_player, no_player)
   end
   if current_player.is_elite() then 
      current_player.set_loadout_palette(elite_tier_1)
   else
      current_player.set_loadout_palette(spartan_tier_1)
   end
   ui_current_player.set_visibility(current_player, false)
   if current_player.biped != no_object then
      ui_current_player.set_visibility(current_player, true)
   end
end

for each object with label "minesweep_cell" do -- delete Forge-placed objects with this label
   if current_object.is_script_created == 0 then
      current_object.delete()
   end
end
for each object with label "minesweep_cell_extra" do -- delete Forge-placed objects with this label
   if current_object.is_script_created == 0 then
      current_object.delete()
   end
end

--
-- If we build the board relative to the BOARD_CENTER, which should be turned on its side to 
-- facilitate a vertical board, then we want to use relative axes.
--
-- Local X = Board Vertical   (positive = down?)
-- Local Y = Board Horizontal
-- Local Z = Board Depth      (positive = closer)
--
alias board_axis_x_offset = -10 -- world X = board-local Y
alias board_axis_y_offset =  10 -- world Y = board-local X
alias new_row_x_offset = 10
alias new_row_y_offset =  0
alias new_row_z_offset =  0
alias new_col_x_offset =  0
alias new_col_y_offset = 10
alias new_col_z_offset =  0
alias first_cell_x_offset = -45
alias first_cell_y_offset = -45
alias first_cell_z_offset =   0
function construct_board_row()
   alias base = temp_obj_00 -- caller must set this to the already-constructed first cell of this row
   alias next = temp_obj_01
   function _construct_board_row_segment()
      -- caller must set (base) to the previously-constructed cell in this row
      --
      next = base.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, cell_length, 0, 0, none) -- A
      next.attach_to(base, new_col_x_offset, new_col_y_offset, new_col_z_offset, relative)
      next.detach()
      next.copy_rotation_from(board_center, true)
      next.is_script_created = 1
      next.set_shape(box, 8, 8, 10, 10)
      next.cell_left  = base
      base.cell_right = next
      next.coord_x = base.coord_x
      next.coord_y = base.coord_y
      next.coord_x += 1
      --
      base = next.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, cell_length, 0, 0, none) -- B
      base.attach_to(next, new_col_x_offset, new_col_y_offset, new_col_z_offset, relative)
      base.detach()
      base.copy_rotation_from(board_center, true)
      base.is_script_created = 1
      base.set_shape(box, 8, 8, 10, 10)
      base.cell_left  = next
      next.cell_right = base
      base.coord_x = next.coord_x
      base.coord_y = next.coord_y
      base.coord_x += 1
      --
      -- Because (base) was set to the last-created cell, you can call this function consecutively 
      -- so long as you plan on having an odd number of cells in each row.
      --
   end
   --
   _construct_board_row_segment() -- 2 and 3
   _construct_board_row_segment() -- 4 and 5
   _construct_board_row_segment() -- 6 and 7
   _construct_board_row_segment() -- 8 and 9
end
function link_rows()
   alias row_1 = temp_obj_00 -- upper row
   alias row_2 = temp_obj_01 -- lower row
   function _link_row()
      row_1.cell_below = row_2
      row_2.cell_above = row_1
      row_1 = row_1.cell_right
      row_2 = row_2.cell_right
   end
   --
   _link_row() -- 1
   _link_row() -- 2
   _link_row() -- 3
   _link_row() -- 4
   _link_row() -- 5
   _link_row() -- 6
   _link_row() -- 7
   _link_row() -- 8
   _link_row() -- 9
end
function _construct_and_link_board_row()
   alias row_a_start = temp_obj_02 -- caller must set this to the first cell of the previously-created row
   alias row_b_start = temp_obj_03
   --
   row_b_start = row_a_start.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, 0, 0, 0, none)
   row_b_start.attach_to(row_a_start, new_row_x_offset, new_row_y_offset, new_row_z_offset, relative)
   row_b_start.detach()
   row_b_start.copy_rotation_from(board_center, true)
   row_b_start.is_script_created = 1
   row_b_start.set_shape(box, 8, 8, 10, 10)
   row_b_start.coord_y = row_a_start.coord_y
   row_b_start.coord_y += 1
   temp_obj_00 = row_b_start
   construct_board_row()
   temp_obj_00 = row_a_start
   temp_obj_01 = row_b_start
   link_rows()
   --
   row_a_start = row_b_start -- prep for next call to _construct_and_link_board_row
end
--
function recalc_adjacent_mines()
   for each object with label "minesweep_cell" do
      alias basis   = current_object
      alias working = temp_obj_00
      --
      basis.adjacent_mines_count = 0
      --
      function _add_if()
         if working.has_mine == 1 then
            basis.adjacent_mines_count += 1
         end
      end
      working = basis.cell_left
      _add_if()
      working = working.cell_above -- upper-left
      _add_if()
      working = basis.cell_right
      _add_if()
      working = working.cell_below -- lower-right
      _add_if()
      working = basis.cell_above
      _add_if()
      working = working.cell_right -- upper-right
      _add_if()
      working = basis.cell_below
      _add_if()
      working = working.cell_left -- lower-left
      _add_if()
   end
end
function randomize_mines()
   alias placed_mine_count = temp_int_01 -- caller must init this to 0
   alias attempts = temp_int_00 -- nested function needs us to init this to 0
   alias result   = temp_obj_00 -- nested function needs us to init this to no_object
   function _find_random_clear_space()
      result = get_random_object("minesweep_cell", result)
      if result.has_mine == 1 then
         attempts += 1
         if attempts >= 5 then -- give up; don't infinitely recurse
            result = no_object
         end
         if attempts < 5 then
            _find_random_clear_space()
         end
      end
   end
   --
   attempts = 0         -- set up state for next call
   result   = no_object -- set up state for next call
   _find_random_clear_space()
   if result != no_object then
      result.has_mine = 1
   end
   placed_mine_count += 1
   if placed_mine_count < desired_mine_count then
      randomize_mines()
   end
   if placed_mine_count >= desired_mine_count then -- end
      recalc_adjacent_mines()
   end
end
do -- construct board
   temp_int_00 = game_state_flags
   temp_int_00 &= game_state_flag_board_constructed
   if temp_int_00 == 0 then
      game_state_flags |= game_state_flag_board_constructed
      --
      -- Let's start by picking a board center to use.
      --
      board_center = no_object
      board_center = get_random_object("board_center", no_object)
      --
      -- Now, we need to construct the board.
      --
      alias row_a_start = temp_obj_02
      alias row_b_start = temp_obj_03
      first_cell = board_center.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, 0, 0, 0, none)
      first_cell.attach_to(board_center, first_cell_x_offset, first_cell_y_offset, first_cell_z_offset, relative)
      first_cell.detach()
      first_cell.copy_rotation_from(board_center, true)
      first_cell.is_script_created = 1
      first_cell.set_shape(box, 8, 8, 10, 10)
      temp_obj_00 = first_cell
      construct_board_row()
      --
      row_a_start = first_cell
      _construct_and_link_board_row() -- row 2
      _construct_and_link_board_row() -- row 3
      _construct_and_link_board_row() -- row 4
      _construct_and_link_board_row() -- row 5
      _construct_and_link_board_row() -- row 6
      _construct_and_link_board_row() -- row 7
      _construct_and_link_board_row() -- row 8
      _construct_and_link_board_row() -- row 9
      for each object with label "minesweep_cell" do
         alias block = temp_obj_00
         --
         block = current_object.place_at_me(block_1x1_flat, "minesweep_cell_extra", never_garbage_collect, 0, 0, 0, none)
         block.attach_to(current_object, 0, 0, 0, absolute)
         block.detach()
         block.copy_rotation_from(board_center, true)
         block.is_script_created = 1
         block.cell_marker = current_object
      end
      --
      -- We've constructed the board, so now, we need to randomly place mines.
      --
      temp_int_01 = 0 -- set up state for next call
      randomize_mines()
   end
end
do -- ensure that an active player exists and is appropriately armed
   if active_player == no_player then
      for each player randomly do
         active_player = current_player
      end
      --
      -- TODO: Code to prevent a player from playing two rounds in a row if other players 
      -- are present in the match. We can use stats to persist cross-round state for this 
      -- purpose.
      --
   end
   active_player.apply_traits(active_player_traits)
   ui_how_to_play.set_visibility(active_player, false)
   if active_player.set_player_weapons == 0 and active_player.biped != no_object then
      active_player.set_player_weapons = 1
      active_player.biped.remove_weapon(secondary, false)
      active_player.biped.remove_weapon(primary,   false)
      active_player.biped.add_weapon(dmr,    force)
      active_player.biped.add_weapon(magnum, force)
      --
      ui_how_to_play.set_visibility(active_player, true)
   end
   if active_player.killer_type_is(guardians | suicide | kill | betrayal | quit) then
      active_player.set_player_weapons = 0
   end
   --
   for each player do
      if current_player != active_player then
         current_player.apply_traits(spectator_traits)
         --
         -- TODO: FFA: All spectators should be forced into unarmed Monitor bipeds.
         --
         -- TODO: TEAM: All spectators not allied with the active player should be 
         -- forced into unarmed Monitor bipeds; spectators allied with the active 
         -- player should be stripped of their weapons.
         --
      end
   end
end

for each object with label "minesweep_cell_extra" do
   alias block = current_object
   alias cell  = temp_obj_00
   alias coil  = temp_obj_01
   alias test  = temp_int_00
   --
   cell = block.cell_marker
   if cell.has_flag == 1 and block.cell_flag == no_object then
      alias working = temp_obj_02
      --
      working = cell.place_at_me(flag, none, never_garbage_collect, 0, 0, 0, none)
      working.set_scale(80)
      working.attach_to(block, 2, 0, 5, absolute)
      working.is_script_created = 1
      working.team = team[0] -- not sure if this'll work in FFA but I want flags to be red
      block.cell_flag = working
   end
   if cell.has_flag == 0 and block.cell_flag != no_object then
      block.cell_flag.delete()
   end
   if cell.reveal_state == cell_reveal_state_yes and block.cell_dice == no_object then
      --
      -- The space is flagged as revealed, but we have not yet actually revealed it. Let's 
      -- get that taken care of.
      --
      alias working = temp_obj_02
      if cell.has_mine == 1 then
         --
         -- The space is mined. Draw the landmine.
         --
         working = cell.place_at_me(landmine, none, never_garbage_collect, 0, 0, 0, none)
         working.set_scale(134)
         working.copy_rotation_from(board_center, true)
         working.is_script_created = 1
         block.cell_dice = working
         --
         working.attach_to(block, 0, 0, 1, absolute)
         working.set_invincibility(1)
      elseif cell.adjacent_mines_count > 0 then
         alias working_adjacent = temp_int_01
         --
         working = cell.place_at_me(dice, none, never_garbage_collect, 0, 0, 0, none)
         working.set_scale(134)
         working.copy_rotation_from(board_center, true)
         working.is_script_created = 1
         block.cell_dice = working
         --
         working_adjacent = cell.adjacent_mines_count
         if working_adjacent > 6 then
            working_adjacent = 6
         end
         for each object with label "minesweep_dice" do
            if current_object.spawn_sequence == working_adjacent then
               working.copy_rotation_from(current_object, true)
            end
         end
         --
         -- The dice's origin, or pivot point, isn't actually its centerpoint; it's the center 
         -- of the "six" face. This means that different numbers will require different attach 
         -- positions. An unscaled block is 0.75 Forge units on a side (verified by extracting 
         -- the model and examining it in an editor); scaling a block to 134% would make it 
         -- ever so slightly larger than a Block 1x1, while scaling to 107% would make it 0.8 
         -- Forge units on a side.
         --
         -- Moreover, we must attach the dice after setting its rotation. If we try to modify 
         -- its rotation while it is attached, the rotation will not be changed.
         --
         if working_adjacent == 1 then
            working.attach_to(block, 0, 0, -9, relative)
         end
         if working_adjacent == 2 then
            working.attach_to(block, 5, 0, -4, relative)
         end
         if working_adjacent == 3 then
            working.attach_to(block, 5, 0, -4, relative)
         end
         if working_adjacent == 4 then
            working.attach_to(block, 5, 0, -4, relative)
         end
         if working_adjacent == 5 then
            working.attach_to(block, -5, 0, -4, relative)
         end
         if working_adjacent == 6 then
            working.attach_to(block, 0, 0, 1, relative)
         end
         --
         -- TODO: If the number of adjacent mines is 7 or 8, then we need to spawn an additional 
         -- die, scale it down, face it to 1 or 2, and merge it into the larger 6-die.
         --
      end
      --
      block.coil.delete() -- revealed cells are non-interactable
   end
   if cell.reveal_state == cell_reveal_state_no and block.coil == no_object  then -- initial fusion coil, and selection behavior
      --
      -- The space is not revealed, and its fusion coil was destroyed. That means that the 
      -- active player has chosen to interact with it in some way.
      --
      function _spawn_coil()
         coil = cell.place_at_me(fusion_coil, none, never_garbage_collect, 0, 0, 0, none)
         coil.copy_rotation_from(board_center, true)
         coil.set_scale(400) -- this MUST be done BEFORE attaching
         coil.attach_to(block, 0, 0, -17, relative)
         coil.is_script_created = 1
         block.coil = coil
      end
      --
      test  = cell.cell_flags
      test &= cell_flag_initial_coil_spawned
      if test == 0 then
         _spawn_coil()
         cell.cell_flags |= cell_flag_initial_coil_spawned
      end
      if test != 0 then
         --
         -- If we already spawned the initial coil, then this must be the destruction of a 
         -- Fusion Coil. Let's assume that the active player is responsible.
         --
         --game.show_message_to(active_player, none, "Selected space %nx%n", cell.coord_x, cell.coord_y)
         --
         -- Check what action to take based on which weapon the player had equipped.
         --
         temp_obj_02 = active_player.get_weapon(primary)
         if temp_obj_02.is_of_type(dmr) then -- toggle a flag
            cell.has_flag *= -1 -- flip the bool
            cell.has_flag +=  1 -- flip the bool
            if cell.has_flag == 0 then
               game.play_sound_for(active_player, announce_ctf_taken, false)
            end
            if cell.has_flag == 1 then
               game.play_sound_for(active_player, announce_ctf_dropped, false)
            end
         end
         if temp_obj_02.is_of_type(magnum) then -- uncover the square
            if cell.has_flag == 0 then
               cell.reveal_state = cell_reveal_state_yes
               if cell.has_mine == 1 then
                  game.show_message_to(all_players, announce_assault_armed, "Stepped on a mine!")
                  game_state_flags |= game_state_flag_player_failed
               end
               if cell.has_mine == 0 then
                  if cell.adjacent_mines_count == 0 then
                     cell.reveal_state = cell_reveal_state_recursing -- queue for recursive reveal
                  end
               end
            end
            if cell.has_flag == 1 then
               game.show_message_to(active_player, none, "To select space %nx%n, remove the flag.", cell.coord_x, cell.coord_y)
            end
         end
         if cell.reveal_state == cell_reveal_state_no then
            --
            -- Respawn the coil, to allow for further selections
            --
            _spawn_coil()
            block.coil_invulnerability_timer.reset()
            block.coil_invulnerability_timer.set_rate(-100%)
            coil.set_invincibility(1)
         end
      end
   end
   if block.coil_invulnerability_timer.is_zero() then
      block.coil_invulnerability_timer.set_rate(0%)
      block.coil_invulnerability_timer.reset()
      --
      block.coil.set_invincibility(0)
   end
end

function do_recursive_reveal()
   alias working = temp_obj_00
   alias pending = temp_int_00
   alias safety  = temp_int_01 -- set to 0 before calling
   pending = 0
   for each object with label "minesweep_cell" do
      if current_object.reveal_state == cell_reveal_state_recursing then
         current_object.reveal_state = cell_reveal_state_yes
         --
         working = current_object.cell_left
         function _process_left()
            if working.has_mine == 0 and working.reveal_state == cell_reveal_state_no then
               if working.adjacent_mines_count > 0 then
                  working.reveal_state = cell_reveal_state_yes
               else
                  working.reveal_state = cell_reveal_state_recursing
                  pending += 1
                  working = working.cell_left
                  if working != no_object then
                     _process_left()
                  end
               end
            end
         end
         _process_left()
         --
         working = current_object.cell_right
         function _process_right()
            if working.has_mine == 0 and working.reveal_state == cell_reveal_state_no then
               if working.adjacent_mines_count > 0 then
                  working.reveal_state = cell_reveal_state_yes
               else
                  working.reveal_state = cell_reveal_state_recursing
                  pending += 1
                  working = working.cell_right
                  if working != no_object then
                     _process_right()
                  end
               end
            end
         end
         _process_right()
         --
         working = current_object.cell_above
         function _process_above()
            if working.has_mine == 0 and working.reveal_state == cell_reveal_state_no then
               if working.adjacent_mines_count > 0 then
                  working.reveal_state = cell_reveal_state_yes
               else
                  working.reveal_state = cell_reveal_state_recursing
                  pending += 1
                  working = working.cell_above
                  if working != no_object then
                     _process_above()
                  end
               end
            end
         end
         _process_above()
         --
         working = current_object.cell_below
         function _process_below()
            if working.has_mine == 0 and working.reveal_state == cell_reveal_state_no then
               if working.adjacent_mines_count > 0 then
                  working.reveal_state = cell_reveal_state_yes
               else
                  working.reveal_state = cell_reveal_state_recursing
                  pending += 1
                  working = working.cell_below
                  if working != no_object then
                     _process_below()
                  end
               end
            end
         end
         _process_below()
         --
         function _process()
            if working.has_mine == 0 and working.reveal_state == cell_reveal_state_no then
               if working.adjacent_mines_count > 0 then
                  working.reveal_state = cell_reveal_state_yes
               else
                  working.reveal_state = cell_reveal_state_recursing
                  pending += 1
               end
            end
         end
         working = current_object.cell_left
         working = working.cell_above -- upper-left
         _process()
         working = current_object.cell_right
         working = working.cell_below -- lower-right
         _process()
         working = current_object.cell_above
         working = working.cell_right -- upper-right
         _process()
         working = current_object.cell_below
         working = working.cell_left -- lower-left
         _process()
      end
   end
   if pending > 0 then
      safety += 1
      if safety < 30 then
         do_recursive_reveal()
      end
   end
end
do
   do_recursive_reveal()
   if temp_int_00 == 0 then -- previous function ran successfully?
      --
      -- We want to check for victory (defined as revealing all non-mined spaces), 
      -- but first, we need to check whether we've already registered a failure. 
      -- Why? We reveal the whole board when the player fails.
      --
      temp_int_00  = game_state_flags
      temp_int_00 &= game_state_flag_player_failed
      if temp_int_00 == 0 then
         --
         -- Check for victory.
         --
         alias remaining = temp_int_00
         alias consumed  = temp_int_01
         alias mines     = temp_int_02
         remaining = 0
         consumed  = 0
         mines     = 2
         for each object with label "minesweep_cell" do
            mines += current_object.has_mine
            if current_object.has_mine == 0 then
               consumed += 1
               if current_object.reveal_state != cell_reveal_state_yes then
                  remaining += 1
               end
            end
         end
         if remaining == 0 then
            mines    *= opt_points_flag
            consumed *= opt_points_space
            active_player.score += opt_points_win
            active_player.score += mines
            active_player.score += consumed
            game.show_message_to(active_player, none, "You solved the board!")
            for each player do
               if current_player != active_player then
                  game.show_message_to(current_player, none, "%s solved the board!", active_player)
               end
            end
            game.end_round()
         end
      end
   end
end

do -- handle player failure
   temp_int_00  = game_state_flags
   temp_int_00 &= game_state_flag_player_failed
   if temp_int_00 != 0 then
      --
      -- Award the player points as appropriate for a round failure.
      --
      active_player.score += opt_points_loss
      alias correct_flags = temp_int_00
      correct_flags = 0
      for each object with label "minesweep_cell" do
         if current_object.has_mine == 0 and current_object.has_flag == 1 then
            correct_flags += 1
         end
      end
      correct_flags *= opt_points_flag
      active_player.score += correct_flags
      --
      -- Reveal the whole board.
      --
      for each object with label "minesweep_cell" do
         current_object.reveal_state = cell_reveal_state_yes
      end
      --
      -- Spawn a shower of landmines overtop the active player, and give them time to 
      -- enjoy it before killing them.
      --
      temp_int_00  = game_state_flags
      temp_int_00 &= game_state_flag_landmine_shower
      if temp_int_00 == 0 then
         game_state_flags |= game_state_flag_landmine_shower
         --
         alias counter = temp_int_01
         function _make()
            temp_obj_00 = active_player.biped
            temp_obj_01 = temp_obj_00.place_at_me(landmine, none, none, 0, 0, 20, none)
            temp_obj_01.set_invincibility(1)
            temp_obj_01.push_upward()
            temp_obj_01.push_upward()
            temp_obj_01.push_upward()
            temp_obj_01.push_upward()
            counter -= 1
            if counter > 0 then
               _make()
            end
         end
         counter = 25
         _make()
         --
         game_failure_timer.reset()
         game_failure_timer.set_rate(-100%)
         game_failure_cinematic_timer.reset()
         game_failure_cinematic_timer.set_rate(-100%)
      end
      if game_failure_cinematic_timer.is_zero() then
         game_failure_cinematic_timer.set_rate(0%)
         for each object do
            if current_object.is_of_type(landmine) then
               current_object.set_invincibility(0)
               current_object.detach()
               current_object.set_scale(200) -- big boom
               --
               current_object.kill(false)
            end
         end
         temp_int_00  = game_state_flags
         temp_int_00 &= game_state_flag_player_killed
         if temp_int_00 == 0 then
            active_player.biped.kill(false)
         else
            temp_int_00 = active_player.biped.health
            if temp_int_00 > 0 then
               active_player.biped.delete() -- ensure we only delete newly-spawned bipeds
            end
         end
         game_state_flags |= game_state_flag_player_killed
      end
      if game_failure_timer.is_zero() then
         game.end_round()
      end
   end
end

if opt_debugging == 1 then -- debug: reveal mines
   for each object with label "minesweep_cell" do
      if current_object.has_mine == 1 then
         current_object.set_waypoint_icon(bomb)
         current_object.set_waypoint_visibility(everyone)
      end
   end
end
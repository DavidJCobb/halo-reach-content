alias board_size         = 9
alias desired_mine_count = 10
alias cell_length        = 10 -- a Block 1x1 Flat is 1.0 Forge units on a side
alias cell_length_neg    = -10

alias opt_let_others_see = script_option[0] -- can players other than (active_player) see the full board state?
alias opt_debugging      = script_option[1]

alias board_center = global.object[0]
alias first_cell   = global.object[1]
alias temp_obj_00  = global.object[2]
alias temp_obj_01  = global.object[3]
alias temp_obj_02  = global.object[4]
alias temp_obj_03  = global.object[5]
alias temp_obj_04  = global.object[6]
alias temp_int_00  = global.number[0]
alias temp_int_01  = global.number[2]

alias active_player = global.player[0] -- the player currently trying to solve the board; for team games, please use another variable

-- Fields for cells:
alias cell_above = object.object[0]
alias cell_left  = object.object[1]
alias cell_right = object.object[2]
alias cell_below = object.object[3] -- no more room for object.object vars!
--
-- Fields for Block 1x1 Flats:
alias cell_marker  = object.object[0]
alias decor_number = object.object[1] -- linked list of hill markers
alias number_drawn = object.number[0] -- bool
--
-- General:
alias next_object = object.object[1]
--
alias adjacent_mines_count = object.number[1]
alias is_script_created    = object.number[2]
alias has_mine             = object.number[3]
alias cell_flags           = object.number[0]
alias cell_flag_pending_reveal = 1 -- 0x0001
alias cell_flag_revealed       = 2 -- 0x0002
alias cell_flag_is_marked      = 4 -- 0x0004 -- has the active_player placed a flag on this cell?

alias game_state_flags                  = global.number[1]
alias game_state_flag_board_constructed = 1 -- 0x0001

declare active_player with network priority high
declare object.adjacent_mines_count with network priority low

alias ui_current_player = script_widget[0]

on init: do
   for each player do
      current_player.set_round_card_title("Reveal all cells in the grid while avoiding \nmines!")
   end
end
for each player do -- set loadout palettes
   ui_current_player.set_text("It's %s's turn!", active_player)
   ui_current_player.set_visibility(current_player, true)
   if current_player.is_elite() then 
      current_player.set_loadout_palette(elite_tier_1)
   else
      current_player.set_loadout_palette(spartan_tier_1)
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

function construct_board_row()
   alias base = temp_obj_00 -- caller must set this to the already-constructed first cell of this row
   alias next = temp_obj_01
   function _construct_board_row_segment()
      -- caller must set (base) to the previously-constructed cell in this row
      --
      next = base.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, cell_length, 0, 0, none) -- A
      next.copy_rotation_from(board_center, true)
      next.is_script_created = 1
      next.set_shape(box, 8, 8, 10, 10)
      next.cell_left  = base
      base.cell_right = next
      --
      base = next.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, cell_length, 0, 0, none) -- B
      base.copy_rotation_from(board_center, true)
      base.is_script_created = 1
      base.set_shape(box, 8, 8, 10, 10)
      base.cell_left  = next
      next.cell_right = base
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
   row_b_start = row_a_start.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, 0, 0, cell_length_neg, none)
   row_b_start.copy_rotation_from(board_center, true)
   row_b_start.is_script_created = 1
   row_b_start.set_shape(box, 8, 8, 10, 10)
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
      alias basis      = current_object
      alias working    = temp_obj_00
      alias working_ex = temp_obj_01
      --
      basis.adjacent_mines_count = 0
      --
      working    = basis.cell_above
      working_ex = working.cell_left
      if working.has_mine == 1 then
         basis.adjacent_mines_count += 1
      end
      if working_ex.has_mine == 1 then
         basis.adjacent_mines_count += 1
      end
      working_ex = working.cell_right
      if working_ex.has_mine == 1 then
         basis.adjacent_mines_count += 1
      end
      --
      -- Mid row:
      --
      working    = basis.cell_left
      working_ex = basis.cell_right
      if working.has_mine == 1 then
         basis.adjacent_mines_count += 1
      end
      if working_ex.has_mine == 1 then
         basis.adjacent_mines_count += 1
      end
      --
      -- Bottom row:
      --
      working    = basis.cell_below
      working_ex = working.cell_left
      if working.has_mine == 1 then
         basis.adjacent_mines_count += 1
      end
      if working_ex.has_mine == 1 then
         basis.adjacent_mines_count += 1
      end
      working_ex = working.cell_right
      if working_ex.has_mine == 1 then
         basis.adjacent_mines_count += 1
      end
   end
end
function randomize_mines()
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
   alias placed_mine_count = temp_int_01 -- caller must init this to 0
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
do  -- construct board
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
      first_cell.attach_to(board_center, -45, -45, 0, relative) -- ensure accurate position
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
if active_player == no_player then
   --
   -- TODO: Code to prevent a player from playing two rounds in a row if other players 
   -- are present in the match. We can use stats to persist cross-round state for this 
   -- purpose.
   --
   for each player randomly do
      active_player = current_player
   end
end

for each object with label "minesweep_cell_extra" do -- create box shapes to serve as number labels
   alias cell = temp_obj_00
   --
   cell = current_object.cell_marker
   if cell.has_mine != 0 then -- don't draw numbers for cells with mines
      current_object.number_drawn = 1
   end
   if current_object.number_drawn == 0 then
      alias revealed = temp_int_00
      --
      cell      = current_object.cell_marker
      revealed  = cell.cell_flags
      revealed &= cell_flag_revealed
      if opt_debugging == 1 then
         revealed = 1
      end
      if current_object.has_mine == 1 then
         revealed = 0
      end
      if revealed != 0 then
         alias current_decor  = temp_obj_01
         alias previous_decor = temp_obj_02
         alias marker_inset   = -4
         function _make_number_shape()
            current_decor  = current_object.place_at_me(hill_marker, none, none, 0, 0, 0, none)
            previous_decor.next_object = current_decor
            previous_decor = current_decor
         end
         previous_decor = no_object
         --
         current_object.number_drawn = 1
         if cell.adjacent_mines_count == 1 then
            _make_number_shape()
            current_decor.set_shape(box, 5, 1, 9, 9) -- width, length, top, bottom
            current_decor.attach_to(current_object, marker_inset, 0, 0, absolute)
            current_object.decor_number = current_decor
         end
         if cell.adjacent_mines_count == 2 then
            --
            -- AAAAAAAAA
            --         D
            --         D
            -- BBBBBBBBB
            -- E
            -- E
            -- CCCCCCCCC
            --
            _make_number_shape()
            current_decor.set_shape(box, 5, 9, 1, 1)
            current_decor.attach_to(current_object, marker_inset, 0, 4, absolute)
            current_object.decor_number = current_decor
            _make_number_shape()
            current_decor.set_shape(box, 5, 9, 1, 1)
            current_decor.attach_to(current_object, marker_inset, 0, 0, relative)
            _make_number_shape()
            current_decor.set_shape(box, 5, 9, 1, 1)
            current_decor.attach_to(current_object, marker_inset, 0, -4, relative)
            _make_number_shape()
            current_decor.set_shape(box, 5, 1, 1, 5)
            current_decor.attach_to(current_object, marker_inset, 4, -4, relative)
            _make_number_shape()
            current_decor.set_shape(box, 5, 1, 1, 5)
            current_decor.attach_to(current_object, marker_inset, -4, 4, relative)
         end
         if cell.adjacent_mines_count == 3 then
            --
            -- BBBBBBBBA
            --         A
            --         A
            --   CCCCCCA
            --         A
            --         A
            -- DDDDDDDDA
            --
            _make_number_shape()
            current_decor.set_shape(box, 5, 1, 9, 9) -- width, length, top, bottom
            current_decor.attach_to(current_object, marker_inset, 4, 0, absolute)
            current_object.decor_number = current_decor
            _make_number_shape()
            current_decor.set_shape(box, 5, 9, 1, 1)
            current_decor.attach_to(current_object, marker_inset, 0, 4, relative)
            _make_number_shape()
            current_decor.set_shape(box, 5, 7, 1, 1)
            current_decor.attach_to(current_object, marker_inset, 2, 0, relative)
            _make_number_shape()
            current_decor.set_shape(box, 5, 9, 1, 1)
            current_decor.attach_to(current_object, marker_inset, 0, -4, relative)
         end
         if cell.adjacent_mines_count == 4 then
            --
            -- C       A
            -- C       A
            -- C       A
            -- BBBBBBBBA
            --         A
            --         A
            --         A
            --
            _make_number_shape()
            current_decor.set_shape(box, 5, 1, 9, 9) -- width, length, top, bottom
            current_decor.attach_to(current_object, marker_inset, 4, 0, absolute)
            current_object.decor_number = current_decor
            _make_number_shape()
            current_decor.set_shape(box, 5, 9, 1, 1)
            current_decor.attach_to(current_object, marker_inset, 0, 0, relative)
            _make_number_shape()
            current_decor.set_shape(box, 5, 1, 1, 4)
            current_decor.attach_to(current_object, marker_inset, -4, 2, relative)
         end
         if cell.adjacent_mines_count == 5 then
            --
            -- AAAAAAAAA
            -- D        
            -- D        
            -- BBBBBBBBB
            --         E
            --         E
            -- CCCCCCCCC
            --
            _make_number_shape()
            current_decor.set_shape(box, 5, 9, 1, 1)
            current_decor.attach_to(current_object, marker_inset, 0, 4, absolute)
            current_object.decor_number = current_decor
            _make_number_shape()
            current_decor.set_shape(box, 5, 9, 1, 1)
            current_decor.attach_to(current_object, marker_inset, 0, 0, relative)
            _make_number_shape()
            current_decor.set_shape(box, 5, 9, 1, 1)
            current_decor.attach_to(current_object, marker_inset, 0, -4, relative)
            _make_number_shape()
            current_decor.set_shape(box, 5, 1, 1, 5)
            current_decor.attach_to(current_object, marker_inset, -4, -4, relative)
            _make_number_shape()
            current_decor.set_shape(box, 5, 1, 1, 5)
            current_decor.attach_to(current_object, marker_inset, 4, 4, relative)
         end
      end
   end
end
for each object with label "minesweep_cell_extra" do -- manage number label visibility
   alias revealed = temp_int_00
   alias cell     = temp_obj_00
   --
   cell      = current_object.cell_marker
   revealed  = cell.cell_flags
   revealed &= cell_flag_revealed
   if opt_debugging == 1 then
      revealed = 1
   end
   if current_object.has_mine == 1 then
      revealed = 0
   end
   --
   if revealed != 0 and cell.has_mine == 1 then
      cell.set_waypoint_icon(bomb)
      cell.set_waypoint_visibility(everyone)
   end
   alias graphic = temp_obj_00
   function _traverse()
      graphic.set_shape_visibility(everyone)
      if revealed == 0 then
         graphic.set_shape_visibility(mod_player, active_player, 0)
      end
      graphic = graphic.next_object
      if graphic != no_object then
         _traverse()
      end
   end
   graphic = current_object.decor_number
   _traverse()
end
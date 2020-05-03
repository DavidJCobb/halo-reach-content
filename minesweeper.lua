
--
-- CURRENT TASKS:
--
-- Halo: Reach can only display 64 shapes and 18 waypoints at a time. We need a 
-- different way to indicate a board space's adjacent mine count.
--
-- Dice would be a good way to do it, except that they can only show values up 
-- to six (the theoretical maximum adjacent mines would be eight), and Megalo 
-- doesn't seem to have a way to rotate objects about the non-yaw axis. (There 
-- is an object.copy_rotation_from opcode, so if we had some object that was 
-- already on its side, we might be able to make use of it -- perhaps requiring 
-- a Forger to place pre-rotated Hill Markers with a label and an index. That's 
-- not ideal, since we can't really enforce it (object.get_orientation returns 
-- 1 for most objects and so can't be used to validate at run-time even if we 
-- were willing to put a higher burden on Forgers).
--
--  = Actually, we should test object.face_toward using its Vector3 argument to 
--    see if pitching an object is possible via that argument. Of course, that 
--    would still leave two faces of a die inaccessible to us...
--
--  - Scaled-down Capture Plates could reproduce the effect, but it'd be tricky 
--    to manage them in part because we've already used up all our object.object 
--    variables on tracking the cell grid. We could use Capture Plates to mimic 
--    the dots on a dice, or we could go the extra mile and spawn some group of 
--    items to literally draw numbers.
--
--     - If necessary, we could use two Hill Markers per cell, with one serving 
--       as an "info" marker and the other serving as a "link" marker. The link 
--       marker would function as our markers currently do; it would not hold a 
--       reference to its paired info marker. The info marker would have a one-
--       way reference to its paired link marker, along with a linked list of 
--       our number-drawing items.
--
--       How can we make a one-way reference work? Well, we're storing all of 
--       the urgent play data on the link markers. The info markers just hold 
--       extra data. Crucially, the "reveal" state for each cell (and whether 
--       the cell holds a landmine) is stored on the link markers. When the 
--       player makes a move, we're most likely going to be updating the reveal 
--       states of multiple spaces (because more spaces lack mines than have 
--       them), which means we'll be drawing several numbers at once. As such, 
--       our procedure is: when the player makes a move, we fully compute the 
--       consequences of this move, and update all link markers accordingly; 
--       then, we loop over every data marker and have it (re)draw its number 
--       as appropriate given the state of its paired link marker.
--
--       Easy. Hell, we can even have the info markers be created in the same 
--       loop as the Block 1x1 Flats... or we can USE the Block 1x1 Flats as 
--       the info markers! Yes! We don't even need a second object!!
--
--     - As for how to draw the numbers... Capture Plates won't stand out very 
--       much if we just place them on plain Block 1x1 Flats. In theory, we 
--       could overlay them (or any other dark object) on top of a box shape 
--       laid directly over the board spaces, with the shape lighting them up, 
--       but spawning such a shape would require us to find a way to have Megalo 
--       turn an object on its side (which, again, I don't think we can do).
--
--       Golf Balls are a plain white object and could work in lieu of Capture 
--       Plates. They would stick out from the board spaces pretty far, though...
--
--       Grids could work if we can scale them down far enough, but I'm not 
--       sure that a grid would be small enough even at 1% scale.
--
--        - DUDE. We could use the Grids to light up the board, and then spawn 
--          whatever want overtop them to draw real numbers on the cells! The 
--          only potential problem would be that we lose any clear spacing 
--          between the cells, but it might be possible to mitigate that if we 
--          can at least scale a Grid down smaller than a Block 1x1 Flat (i.e. 
--          if each cell has its own Grid that's just small enough, then the 
--          parts we DON'T light up serve as gridlines between cells).
--
--          Alternatively: we could have a single grid (or multiple grids that 
--          we stitch together) cover the whole board, and draw some kind of 
--          divider on top of them if we can find a non-solid one. If attaching 
--          objects doesn't consistently disable their collision, then that 
--          would be the best approach (lest we have eleventy billion overlapping 
--          grid collision objects).
--
--  - Any "physical" display will cost us the ability to let spectators see the 
--    full board state, unless we allow them to teleport to some other location 
--    and reproduce the board state there.
--
--     - That wouldn't be the worst thing in the world, would it? Imagine an 
--       inanimate Spartan being moved around the simulated board to match the 
--       active player in real time, lol.
--
--  - There are no other opcodes that can be used to alter the appearance of a 
--    physical object in any obvious fashion.
--

alias board_size         = 9
alias desired_mine_count = 10
alias cell_distance      = 10

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
--
alias active_player = global.player[0] -- the player currently trying to solve the board; for team games, please use another variable
--
-- Fields for cells:
alias cell_above = object.object[0]
alias cell_left  = object.object[1]
alias cell_right = object.object[2]
alias cell_below = object.object[3] -- no more room for object.object vars!
--
-- Fields for Block 1x1 Flats:
alias cell_marker  = object.object[0]
alias decor_base   = object.object[1]
alias decor_number = object.object[2]
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

function _construct_board_row_segment()
   alias base = temp_obj_00 -- caller must set this to the previously-constructed cell in this row
   alias next = temp_obj_01
   --
   next = base.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, cell_distance, 0, 0, none) -- A
   next.is_script_created = 1
   next.set_shape(box, 8, 8, 10, 10)
   next.cell_left  = base
   base.cell_right = next
   --
   base = next.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, cell_distance, 0, 0, none) -- B
   base.is_script_created = 1
   base.set_shape(box, 8, 8, 10, 10)
   base.cell_left  = next
   next.cell_right = base
   --
   -- Because (base) was set to the last-created cell, you can call this function consecutively 
   -- so long as you plan on having an odd number of cells in each row.
   --
end
function construct_board_row()
   alias base = temp_obj_00 -- caller must set this to the already-constructed first cell of this row
   alias next = temp_obj_01
   --
   _construct_board_row_segment() -- 2 and 3
   _construct_board_row_segment() -- 4 and 5
   _construct_board_row_segment() -- 6 and 7
   _construct_board_row_segment() -- 8 and 9
end
function _link_row()
   alias row_1 = temp_obj_00 -- upper row
   alias row_2 = temp_obj_01 -- lower row
   --
   row_1.cell_below = row_2
   row_2.cell_above = row_1
   row_1 = row_1.cell_right
   row_2 = row_2.cell_right
end
function link_rows()
   alias row_1 = temp_obj_00 -- upper row
   alias row_2 = temp_obj_01 -- lower row
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
   row_b_start = row_a_start.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, 0, cell_distance, 0, none)
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
function _find_random_clear_space()
   alias attempts = temp_int_00 -- caller must init this to 0
   alias result   = temp_obj_00 -- caller must init this to no_object
   --
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
   alias placed_mine_count = temp_int_01 -- caller must init this to 0
   --
   temp_int_00 = 0         -- set up state for next call
   temp_obj_00 = no_object -- set up state for next call
   _find_random_clear_space()
   if temp_obj_00 != no_object then
      temp_obj_00.has_mine = 1
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
      first_cell = board_center.place_at_me(hill_marker, "minesweep_cell", never_garbage_collect, -45, -45, 0, none)
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
         block.is_script_created = 1
         block.cell_marker = current_object
         --
         --alias die_1 = temp_obj_01
         --alias die_2 = temp_obj_02
         --die_1 = block.place_at_me(dice, none, never_garbage_collect, 0, 0, 0, none)
         --die_1.set_scale(95)
         --die_1.attach_to(block, 0, 0, -6, absolute)
         --block.decor_base = die_1
         --die_2 = block.place_at_me(dice, none, never_garbage_collect, 0, 0, 0, none)
         --die_2.set_scale(25)
         --die_2.attach_to(block, 0, 0, -1, absolute)
         --die_1.next_object = die_2
      end
      --
      -- We've constructed the board, so now, we need to randomly place mines.
      --
      temp_int_01 = 0 -- set up state for next call
      randomize_mines()
      --
      do -- TEMP TEST
         temp_obj_00 = board_center.place_at_me(oni_van, none, none, 0, 0, 3, none)
         temp_obj_00.set_shape_visibility(everyone)
         temp_obj_00.set_shape(box, 15, 20, 20, 40)
      end
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

function _make_number_dot()
   alias current_decor  = temp_obj_01
   alias previous_decor = temp_obj_02
   alias rotate_marker  = temp_obj_02 -- variable reuse is intentional
   --
   current_decor = current_object.place_at_me(block_1x1_flat, none, none, 0, 0, 0, none)
   current_decor.set_scale(10)
   previous_decor.next_object = current_decor
   --
   current_decor.face_toward(current_decor, 2, 2, 0)
   --
   previous_decor = current_decor
end
for each object with label "minesweep_cell_extra" do
   if current_object.number_drawn == 0 then
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
      if revealed != 0 then
         alias current_decor = temp_obj_01
         --
         current_object.number_drawn = 1
         if cell.adjacent_mines_count == 1 then
            _make_number_dot()
            current_decor.attach_to(current_object, 0, 0, 1, relative)
            current_object.decor_number = current_decor
         end
         if cell.adjacent_mines_count == 2 then
            _make_number_dot()
            current_decor.attach_to(current_object, -2, 0, 1, relative)
            current_object.decor_number = current_decor
            _make_number_dot()
            current_decor.attach_to(current_object, 2, 0, 1, relative)
         end
         if cell.adjacent_mines_count == 3 then
            _make_number_dot()
            current_decor.attach_to(current_object, -1, 2, 1, relative)
            current_object.decor_number = current_decor
            _make_number_dot()
            current_decor.attach_to(current_object, 1, -2, 1, relative)
         end
         if cell.adjacent_mines_count == 4 then
            _make_number_dot()
            current_decor.attach_to(current_object, -2, -2, 1, relative)
            current_object.decor_number = current_decor
            _make_number_dot()
            current_decor.attach_to(current_object, 2, -2, 1, relative)
            _make_number_dot()
            current_decor.attach_to(current_object, -2, 2, 1, relative)
            _make_number_dot()
            current_decor.attach_to(current_object, 2, 2, 1, relative)
         end
         if cell.adjacent_mines_count == 5 then
            _make_number_dot()
            current_decor.attach_to(current_object, -2, -2, 1, relative)
            current_object.decor_number = current_decor
            _make_number_dot()
            current_decor.attach_to(current_object, 2, -2, 1, relative)
            _make_number_dot()
            current_decor.attach_to(current_object, -2, 2, 1, relative)
            _make_number_dot()
            current_decor.attach_to(current_object, 2, 2, 1, relative)
            _make_number_dot()
            current_decor.attach_to(current_object, 0, 0, 1, relative)
         end
      end
   end
end

for each object with label "minesweep_cell" do -- manage waypoint and shape visibility for each cell
   alias revealed = temp_int_00
   --
   current_object.set_shape_visibility(no_one)
   if opt_debugging == 1 then
      --current_object.set_shape_visibility(everyone) -- NOTE: the game can only render 64 shapes at a time; we have 81 cells
   end
   current_object.set_waypoint_visibility(everyone)
   current_object.set_waypoint_priority(high)
   current_object.set_waypoint_icon(none)
   --
   revealed =  current_object.cell_flags
   revealed &= cell_flag_revealed
   for each player do
      alias visibility = temp_int_01
      --
      visibility = revealed
      if current_player != active_player and opt_let_others_see == 1 then
         visibility = 1
      end
      if opt_debugging == 1 then
         visibility = 1
      end
      --
      if visibility == 0 then
         current_object.set_waypoint_visibility(mod_player, current_player, 0)
      end
   end
   --
   temp_int_00 =  current_object.cell_flags
   temp_int_00 &= cell_flag_is_marked
   if temp_int_00 != 0 then
      current_object.set_waypoint_icon(flag)
      --
      -- TODO: Recolor the current object's shape boundary as well.
      --
   end
   current_object.set_waypoint_icon(territory_a, current_object.adjacent_mines_count)
   if current_object.has_mine == 1 then
      current_object.set_waypoint_icon(bomb)
   end
   if revealed == 0 then
      current_object.set_waypoint_text("Locked") -- let spectators see which cells the active player has(n't) revealed
   end
end

--
-- TODO:
--
--  - Idea: a custom game option which controls whether numbers are rendered as numbers 
--    or as dots. Bonus points if, if we go with dark objects on a grid, we can use 
--    45-degree-rotated scaled-down Block 1x1 Flats as the dots, for a futuristic and 
--    sorta 343i-style-Forerunner look.
--
--  - Spawn a flag and a bomb, and let the player select a space with either
--
--  - Dropping a flag in a space marks it with a flag (attach the flag to the cell; set 
--    that_cell.cell_flags |= cell_flag_is_marked.
--
--  - Dropping a bomb in a space is akin to a normal left-click: if the space has no 
--    mine, then reveal it and recursively reveal all adjacent spaces with no mine; if 
--    it did have a mine, then kaboom
--
--  - Add scoring options:
--
--     - Cell Reveal Points: Points received for revealing a cell
--
--     - Correct Flag Points: Points received at the end of a losing round for each 
--       correctly-placed flag, or at the end of a winning round for each mine.
--
--     - Wrong Flag Points: Points received at the end of a losing round for each 
--       incorrectly-placed flag.
--
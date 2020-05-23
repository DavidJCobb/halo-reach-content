

--
-- HALO CHESS IMPLEMENTATION IDEAS
--
-- GOAL: Reimplement Halo Chess using user-defined functions, in order to allow 
-- for checkmate functionality -- removing the need to determine the winner by 
-- honor rules.
--

--
-- BUG: Host migration basically breaks the game; the board becomes littered 
--      with dropped biped weapons, and possessing a biped causes a loud 
--      vibration and a near-black screen (with a very, very faint afterimage 
--      of the board). User is stuck on that black screen until the turn clock 
--      runs out.
--
--       - Yep, vanilla Halo Chess nukes bipeds on host migration.
--
--       - Not resolved by looping over "board_space_extra"; try brute-forcing 
--         it: loop over every object and delete every Spartan and Elite.
--
--       - It seems that on host migration, every scripted biped is deleted, 
--         with one of each pair being dead. I suspect that the possession 
--         problem may be the result of possessing a dead body -- something 
--         I've been meaning to test...
--
-- TODO: Delete dropped weapons. Harder than it sounds since we can't get the 
--       weapons held by a non-player biped, and we can't check if a weapon is 
--       being held by a non-player biped. Only real way to do it is to have a 
--       shape volume that covers the board, rising one unit off of the floor; 
--       a weapon in this shape volume must be dropped (DOUBLE-CHECK THAT IT 
--       ISN'T BEING HELD BY A PLAYER, AT LEAST) and should be deleted.
--
--        - Let's include dropped flags in this.
--
-- TODO: consider adding a script option which controls whether you're allowed 
--       to put yourself in check.
--
-- TODO: Spawn a "tray" of pieces behind each team. Halo Chess doesn't give you 
--       waypoints on each individual enemy piece; rather, the tray contains one 
--       rook, one knight, one bishop, and one queen, and you get waypoints on 
--       the pieces in the enemy tray.
--
-- TODO: spawning the player into a Monitor after a move: i think official halo 
--       chess uses an offset of (-15, 0, 15); try that and see if it's consistent 
--       with gameplay videos. (currently we do (0, 0, 6).)
--
-- DONE:
--
--  - Piece selection (and the ability to re-select)
--
--     - You are blocked from making moves that would leave your king in check
--
--  - Target square selection
--
--  - Pawn promotion
--
--  - Check and checkmate
--
--  - Victory conditions: checkmate; killing king
--
--  - Draw conditions: stalemate; 75-turn rule; insufficient materials
--
--  - Edge-case: turn clock runs out after you've selected a piece and gained 
--    control
--

alias MAX_INT = 32767

alias species_human = 0
alias species_elite = 1
alias opt_turn_clock = script_option[0]
alias species_black  = script_option[1]
alias species_white  = script_option[2]
alias opt_draw_rule  = script_option[3]
alias opt_dim_immovable_piece_waypoints = script_option[4]

alias faction_none  = 0
alias faction_black = 2 -- north
alias faction_white = 1 -- south
alias team_black  = global.team[0]
alias team_white  = global.team[1]
alias active_team = global.team[2]

alias piece_type_none   = 0
alias piece_type_pawn   = 1
alias piece_type_knight = 2
alias piece_type_bishop = 3
alias piece_type_rook   = 4
alias piece_type_queen  = 5
alias piece_type_king   = 6
alias piece_type_dummy  = -1

alias time_limit_for_finishing_off_losing_king = 30

-- General state:
alias is_script_created = object.number[5]

-- Piece data is stored on the board square that the piece is standing on, not 
-- the piece biped itself. As with my Minesweeper design, all object.object 
-- variables are expended on linking pieces with their neighbors, so in order 
-- to track additional information (e.g. linking board spaces to their bipeds) 
-- we will need to create an "extra data" object for each space, which will 
-- have a one-way link to its space.
--
-- Cell-marker data:
alias coord_x       = object.number[0]
alias coord_y       = object.number[1]
alias piece_type    = object.number[2]
alias is_valid_move = object.number[3]
alias owner         = object.number[4]
alias threatened_by = object.number[5] -- for check(mate) processing
alias en_passant_vulnerable = object.number[6] -- pawns only; must be set on the turn the pawn double-moves, and cleared on its owner's next turn
alias space_flags   = object.number[7]
alias space_flag_moving_would_self_check = 0x0001 -- moving this piece would put you in check
alias space_flag_is_threatened_by_enemy  = 0x0002 -- you cannot move your king here; this space is under threat by an enemy
alias space_flag_has_no_valid_moves      = 0x0004
alias space_flag_has_no_valid_moves_clear = 0x7FFB
alias space_flag_mask_cannot_move        = 0x0005 -- space_flag_moving_would_self_check | space_flag_has_no_valid_moves
alias space_left    = object.object[0]
alias space_right   = object.object[1]
alias space_above   = object.object[2]
alias space_below   = object.object[3]
declare object.piece_type    = piece_type_none
declare object.is_valid_move with network priority low = 0
declare object.threatened_by with network priority low = 0
declare object.owner         = faction_none
declare object.space_flags   = 0
--
-- Cell-extra data:
alias marker = object.object[0]
alias biped  = object.object[1] -- link extra to biped
alias extra  = object.object[1] -- link biped to extra
--
-- Board center data:
alias piece_deselect_boundary = object.object[0]
--
-- State for the kings' flags:
alias flag_was_processed = object.is_script_created

-- Global state
alias temp_int_00     = global.number[0]
alias temp_int_01     = global.number[1]
alias temp_int_02     = global.number[2]
alias board_created   = global.number[3]
alias active_faction  = global.number[4] -- faction currently making a move
declare active_faction = faction_none
alias turn_flags      = global.number[5]
alias temp_int_03     = global.number[6]
alias winning_faction = global.number[7]
declare winning_faction with network priority low = faction_none
alias draw_turn_count = global.number[8]
declare draw_turn_count with network priority low = 0
alias temp_int_04     = global.number[9]
--
alias turn_flag_in_check = 0x0001
--
alias temp_obj_00     = global.object[0]
alias temp_obj_01     = global.object[1]
alias temp_obj_02     = global.object[2]
alias temp_obj_03     = global.object[3]
alias selected_piece  = global.object[4] -- piece that the player is (about to be) controlling
alias board_center    = global.object[5]
alias temp_obj_04     = global.object[6]
alias temp_obj_05     = global.object[7]
alias active_player   = global.player[0] -- player currently making a move
declare active_player with network priority high -- we use it in the UI
alias temp_plr_00     = global.player[1]
alias temp_plr_01     = global.player[2]
alias temp_tem_00     = global.team[3]
alias turn_clock      = global.timer[0]
declare turn_clock = opt_turn_clock
--
declare temp_int_00 with network priority low
declare temp_int_01 with network priority low
declare temp_int_02 with network priority low
declare temp_int_03 with network priority low
declare temp_int_04 with network priority low
declare temp_obj_00 with network priority low
declare temp_obj_01 with network priority low
declare temp_obj_02 with network priority low
declare temp_obj_03 with network priority low
declare temp_obj_04 with network priority low
declare temp_obj_05 with network priority low
declare temp_plr_00 with network priority low
declare temp_plr_01 with network priority low
declare temp_tem_00 with network priority low

alias announced_game_start = player.number[0]
alias ui_would_self_check  = player.number[1]
declare player.ui_would_self_check = piece_type_none
alias turn_order           = player.number[2]
declare player.turn_order = -1
alias target_space         = player.object[0] -- piece the player is about to select (pending their timer)
alias selection_timer = player.timer[0]
declare player.selection_timer = 2
alias announce_start_timer = player.timer[1]
declare player.announce_start_timer = 5

alias faction    = team.number[0]
declare team.faction with network priority low = faction_none
alias turn_order = team.number[1]
declare team.turn_order = -1
alias enemy      = team.team[0]
declare team.enemy with network priority low = no_team

alias ui_your_turn  = script_widget[0]
alias ui_in_check   = script_widget[1]
alias ui_bad_move   = script_widget[2]
alias ui_turn_clock = script_widget[3]
alias ui_endgame    = script_widget[3] -- multi-purpose widget

alias all_flags = 2 -- forge label

alias monitor_traits  = script_traits[1]
alias piece_traits    = script_traits[2]
alias override_traits = script_traits[0]

--
-- SCRIPT FLOW:
--
--  - Generate board
--     - Generate initial piece arrangement
--  - Generate bipeds for spaces that are missing them
--     - If a biped is displaced from its space and not under player control, reset it
--  - Force players into Monitor bipeds
--     - ...but only if they've already spawned
--     - Remove their weapons and grenades
--  - Update UI during gameplay
--  - Handle picking a piece or picking a move
--     = Skip this processing if we are in the victory process.
--     - If there is no active faction, pick one
--     - If there is no active player (or they quit), pick one
--     - Handle moving a piece to an unoccupied space
--        - If the player is double-moving a pawn: flag as vulnerable to capturing en passant
--        - If the player is killing a king: begin victory process
--        - End turn
--           = Skip this processing if we are in the victory process.
--           - Switch to next faction and player
--           - Clear en passant vulnerability from new player's pawns
--           - Check whether new player is in check or checkmate
--              - If checkmate, begin the victory process.
--                 - Award point to winner
--                 - Reset (is_valid_move) and friends for all spaces
--                 - If loser has no king, end round
--              - If not checkmate, pre-validate moves:
--                 - Identify spaces the king cannot safely move to
--                 - Identify pieces that can't be moved because they're blocking the king from being in check
--           - Manage 75-turn draw rule
--     = Same containing trigger also ends the turn if the turn clock runs out
--  - Handle piece death, if it occurs
--     - Handle moving a piece to an enemy-occupied space
--        - If the player is double-moving a pawn: flag as vulnerable to capturing en passant
--        - If the player is killing a king: begin victory process
--        - End turn
--           = Skip this processing if we are in the victory process.
--           - Switch to next faction and player
--           - Clear en passant vulnerability from new player's pawns
--           - Check whether new player is in check or checkmate
--              - If checkmate, begin the victory process.
--                 - Award point to winner
--                 - Reset (is_valid_move) and friends for all spaces
--                 - If loser has no king, end round
--              - If not checkmate, pre-validate moves:
--                 - Identify spaces the king cannot safely move to
--                 - Identify pieces that can't be moved because they're blocking the king from being in check
--           - Manage 75-turn draw rule
--     - If victory process is active, handle death of the loser's king
--  - Victory process, if active
--     - Reset board space shape visibility
--     - Failsafe: end the round if the active player disappears
--     - Manage piece (in)vulnerability
--     - Manage UI
--  - Draw checks
--     - 75-turn rule (number of turns configurable via script option)
--     - Insufficient materials 1
--     - Insufficient materials 2
--

on init: do
   team_black = team[0]
   team_white = team[1]
   team_black.enemy   = team_white
   team_white.enemy   = team_black
   team_black.faction = faction_black
   team_white.faction = faction_white
end

on host migration: do
   for each object with label "board_space_extra" do
      temp_obj_00 = current_object.biped
      temp_obj_00.delete()
   end
   --
   -- Deleting a controlled biped requires additional changes to game state, 
   -- as well as accommodations for wasting the player's turn time:
   --
   turn_clock.reset()
   selected_piece = no_object
end

for each player do -- announce game start
   current_player.announce_start_timer.set_rate(-100%)
   current_player.set_round_card_title("Control chess pieces to move.\nAchieve checkmate to win!")
   if current_player.announced_game_start == 0 and current_player.announce_start_timer.is_zero() then 
      send_incident(action_sack_game_start, current_player, no_player)
      game.show_message_to(current_player, none, "Halo Chess+ v1.0.0 by Cobb!")
      current_player.announced_game_start = 1
   end
end

if board_created == 0 then -- generate board
   board_created = 1
   --
   alias board_axis_x_offset = -10
   alias board_axis_y_offset =  10
   alias new_row_x_offset = 10
   alias new_row_y_offset =  0
   alias new_row_z_offset =  0
   alias new_col_x_offset =  0
   alias new_col_y_offset = 10
   alias new_col_z_offset =  0
   alias first_cell_x_offset = -40
   alias first_cell_y_offset = -40
   alias first_cell_z_offset =   0
   alias current = temp_obj_00 -- last-spawned cell
   alias working = temp_obj_01
   alias matched = temp_obj_02
   alias first   = temp_obj_03 -- first column in current row
   function new_column()
      working = current.place_at_me(block_1x1_flat, "board_space", never_garbage_collect, 0, 0, 0, none)
      working.attach_to(current, new_col_x_offset, new_col_y_offset, new_col_z_offset, relative)
      working.detach()
      working.copy_rotation_from(board_center, true)
      working.set_shape(box, 8, 8, 10, 10)
      working.coord_x = current.coord_x
      working.coord_y = current.coord_y
      working.coord_x += 1
      working.is_script_created = 1
      working.space_left  = current
      current.space_right = working
      matched = current.space_above
      matched = matched.space_right
      working.space_above = matched
      matched.space_below = working
      current = working
   end
   function start_new_row()
      working = first.place_at_me(block_1x1_flat, "board_space", never_garbage_collect, 0, 0, 0, none)
      working.attach_to(first, new_row_x_offset, new_row_y_offset, new_row_z_offset, relative)
      working.detach()
      working.copy_rotation_from(board_center, true)
      working.set_shape(box, 8, 8, 10, 10)
      working.coord_x = first.coord_x
      working.coord_y = first.coord_y
      working.coord_y += 1
      working.is_script_created = 1
      working.space_above = first
      first.space_below   = working
      first   = working
      current = working
   end
   function finish_row()
      new_column()
      new_column()
      new_column()
      new_column()
      new_column()
      new_column()
      new_column()
   end
   function construct_and_link_row()
      start_new_row()
      finish_row()
   end
   --
   board_center = no_object
   board_center = get_random_object("board_center", no_object)
   --
   working = board_center.place_at_me(hill_marker, none, never_garbage_collect, 0, 0, 0, none)
   working.attach_to(board_center, 0, 0, 0, relative)
   working.detach()
   working.copy_rotation_from(board_center, true)
   working.set_shape(box, 140, 140, 40, 20)
   board_center.piece_deselect_boundary = working
   --
   current = board_center.place_at_me(block_1x1_flat, "board_space", never_garbage_collect, 0, 0, 0, none)
   current.attach_to(board_center, first_cell_x_offset, first_cell_y_offset, first_cell_z_offset, relative)
   current.detach()
   current.copy_rotation_from(board_center, true)
   current.set_shape(box, 8, 8, 10, 10)
   current.is_script_created = 1
   first = current
   --
   finish_row()
   construct_and_link_row()
   construct_and_link_row()
   construct_and_link_row()
   construct_and_link_row()
   construct_and_link_row()
   construct_and_link_row()
   construct_and_link_row()
   --
   working = board_center.place_at_me(soft_safe_boundary, none, never_garbage_collect | absolute_orientation, 0, 0, 0, none)
   working.attach_to(board_center, 0, 0, 0, absolute)
   working.set_shape(box, 310, 310, 200, 50)
   working.set_shape_visibility(no_one)
   --
   for each object with label "board_space" do -- create "extra" markers
      working = current_object.place_at_me(hill_marker, "board_space_extra", never_garbage_collect, 0, 0, 0, none)
      working.attach_to(current_object, 0, 0, 0, relative)
      working.detach()
      working.copy_rotation_from(board_center, true)
      working.is_script_created = 1
      working.marker = current_object
   end
   --
   -- Initialize the pieces:
   --
   for each object with label "board_space" do
      current_object.owner = faction_none
      if current_object.coord_y == 1 or current_object.coord_y == 6 then
         current_object.piece_type = piece_type_pawn
      end
      if current_object.coord_y == 0 or current_object.coord_y == 7 then
         if current_object.coord_x == 0 or current_object.coord_x == 7 then
            current_object.piece_type = piece_type_rook
         end
         if current_object.coord_x == 1 or current_object.coord_x == 6 then
            current_object.piece_type = piece_type_knight
         end
         if current_object.coord_x == 2 or current_object.coord_x == 5 then
            current_object.piece_type = piece_type_bishop
         end
         if current_object.coord_x == 3 then
            current_object.piece_type = piece_type_queen
         end
         if current_object.coord_x == 4 then
            current_object.piece_type = piece_type_king
         end
      end
      --
      if current_object.piece_type != piece_type_none then
         if current_object.coord_y <= 1 then
            current_object.owner = faction_black
         end
         if current_object.coord_y >= 6 then
            current_object.owner = faction_white
         end
      end
   end
end

for each object with label "board_space_extra" do -- generate missing bipeds
   alias cell  = temp_obj_00
   alias extra = current_object
   --
   cell = extra.marker
   if winning_faction == faction_none or winning_faction == cell.owner then
      alias biped = temp_obj_01
      alias face  = temp_obj_02
      --
      if winning_faction == faction_none and extra.biped != no_object and cell != selected_piece and not cell.shape_contains(extra.biped) then
         extra.biped.attach_to(cell, 0, 0, 1, relative)
         extra.biped.detach()
      end
      if extra.biped == no_object then
         if cell.piece_type != piece_type_none then
            alias species = temp_int_00
            alias ownteam = temp_tem_00
            --
            ownteam = team_black
            species = species_black
            if cell.owner == faction_white then
               ownteam = team_white
               species = species_white
            end
            --
            biped = no_object
            function setup_biped()
               biped.is_script_created = 1
               biped.team = ownteam
               biped.remove_weapon(secondary, true)
               biped.remove_weapon(primary,   true)
               biped.copy_rotation_from(board_center, false)
               if cell.owner == faction_white then
                  face = biped.place_at_me(hill_marker, none, none, 0, 0, 0, none)
                  face.attach_to(biped, -20, 0, 0, relative)
                  face.detach()
                  biped.face_toward(face, 0, 0, 0)
                  face.delete()
               end
            end
            if cell.piece_type == piece_type_pawn then
               if species == species_human then
                  biped = cell.place_at_me(spartan, none, none, 0, 0, 1, male)
               else
                  biped = cell.place_at_me(elite, none, none, 0, 0, 1, minor)
               end
               setup_biped()
               biped.set_waypoint_icon(skull)
               biped.set_waypoint_text("Pawn")
               if biped.is_of_type(spartan) then
                  biped.add_weapon(assault_rifle, primary)
               else
                  biped.add_weapon(plasma_repeater, primary)
               end
            end
            if cell.piece_type == piece_type_knight then
               if species == species_human then
                  biped = cell.place_at_me(spartan, none, none, 0, 0, 1, emile)
               else
                  biped = cell.place_at_me(elite, none, none, 0, 0, 1, spec_ops)
               end
               setup_biped()
               biped.set_waypoint_icon(vip)
               biped.set_waypoint_text("Knight")
               if biped.is_of_type(spartan) then
                  biped.add_weapon(shotgun, primary)
               else
                  biped.add_weapon(energy_sword, primary)
               end
            end
            if cell.piece_type == piece_type_bishop then
               if species == species_human then
                  biped = cell.place_at_me(spartan, none, none, 0, 0, 1, female)
               else
                  biped = cell.place_at_me(elite, none, none, 0, 0, 1, zealot)
               end
               setup_biped()
               biped.set_waypoint_icon(bullseye)
               biped.set_waypoint_text("Bishop")
               if biped.is_of_type(spartan) then
                  biped.add_weapon(grenade_launcher, primary)
               else
                  biped.add_weapon(concussion_rifle, primary)
               end
            end
            if cell.piece_type == piece_type_rook then
               if species == species_human then
                  biped = cell.place_at_me(spartan, none, none, 0, 0, 1, jun)
               else
                  biped = cell.place_at_me(elite, none, none, 0, 0, 1, space)
               end
               setup_biped()
               biped.set_waypoint_icon(bomb)
               biped.set_waypoint_text("Rook")
               if biped.is_of_type(spartan) then
                  biped.add_weapon(sniper_rifle, primary)
               else
                  biped.add_weapon(beam_rifle, primary)
               end
            end
            if cell.piece_type == piece_type_queen then
               if species == species_human then
                  biped = cell.place_at_me(spartan, none, none, 0, 0, 1, kat)
               else
                  biped = cell.place_at_me(elite, none, none, 0, 0, 1, ultra)
               end
               setup_biped()
               biped.set_waypoint_icon(crown)
               biped.set_waypoint_text("Queen")
               if biped.is_of_type(spartan) then
                  biped.add_weapon(rocket_launcher, primary)
               else
                  biped.add_weapon(plasma_launcher, primary)
               end
            end
            if cell.piece_type == piece_type_king then
               if species == species_human then
                  biped = cell.place_at_me(spartan, none, none, 0, 0, 1, carter)
               else
                  biped = cell.place_at_me(elite, none, none, 0, 0, 1, general)
               end
               setup_biped()
               biped.set_waypoint_icon(crown)
               biped.set_waypoint_text("King")
               biped.add_weapon(flag, primary)
               --
               for each object with label all_flags do -- set flag color by assigning its team
                  --
                  -- The object.get_carrier opcode can only return a player, so we have to do 
                  -- it this way:
                  --
                  if current_object.flag_was_processed == 0 then
                     current_object.flag_was_processed = 1
                     current_object.team = neutral_team -- best fallback we can do for single-player matches where the other team is absent
                     current_object.team = biped.team
                  end
               end
            end
            --
            biped.attach_to(cell, 0, 0, 1, relative) -- enforce position (TODO: should we leave it attached?)
            biped.detach()
            extra.biped  = biped
            biped.extra  = extra
            biped.marker = cell
         end
      end
   end
end
for each object with label "board_space_extra" do -- manage piece waypoint visibility
   alias extra = current_object
   if extra.biped != no_object then
      extra.biped.set_waypoint_visibility(allies)
      extra.biped.set_waypoint_priority(normal)
      --
      if winning_faction == faction_none and opt_dim_immovable_piece_waypoints == 1 then
         --
         -- During a player's turn, fade the waypoints on allied pieces that cannot 
         -- be moved.
         --
         alias cell = temp_obj_00
         cell = extra.marker
         if active_faction == cell.owner then
            temp_int_00  = cell.space_flags
            temp_int_00 &= space_flag_mask_cannot_move
            if temp_int_00 != 0 then
               extra.biped.set_waypoint_priority(low)
            end
         end
      end
   end
end

for each player do -- force players into Monitor bipeds
   alias biped   = temp_obj_00
   alias created = temp_obj_01
   biped = current_player.biped
   if current_player.biped != no_object and not current_player.biped.is_of_type(monitor) then
      biped = current_player.biped
      if biped.is_script_created == 0 then
         created = board_center.place_at_me(monitor, none, none, 0, 0, 0, none)
         created.attach_to(board_center, 0, 0, 20, relative)
         created.detach()
         if biped != no_object and not biped.is_out_of_bounds() then
            created.attach_to(biped, 0, 0, 6, relative)
            created.detach()
            created.copy_rotation_from(biped, true)
         end
         current_player.set_biped(created)
         biped.delete()
      end
   end
   if current_player.biped.is_of_type(monitor) then -- do what we can to stop Monitors from picking stuff up
      current_player.biped.remove_weapon(secondary, true)
      current_player.biped.remove_weapon(primary,   true)
      current_player.frag_grenades   = 0
      current_player.plasma_grenades = 0
   end
end
for each player do -- player traits
   temp_obj_00 = current_player.biped
   if temp_obj_00.is_of_type(monitor) then 
      current_player.apply_traits(monitor_traits)
   end
   if temp_obj_00.is_script_created == 1 then
      current_player.apply_traits(piece_traits)
   end
   current_player.apply_traits(override_traits)
end
do -- UI
   if winning_faction == faction_none then
      ui_your_turn.set_text("Your Turn!")
      ui_in_check.set_text("Check!")
      ui_bad_move.set_text("Invalid move, try another!")
      ui_bad_move.set_icon(castle_defense)
      ui_turn_clock.set_text("Turn Clock: %s", turn_clock)
      --
      temp_int_00  = turn_flags
      temp_int_00 &= turn_flag_in_check
      for each player do
         ui_turn_clock.set_visibility(current_player, false)
         if opt_turn_clock > 0 then
            ui_turn_clock.set_visibility(current_player, true)
         end
         --
         ui_your_turn.set_visibility(current_player, false)
         ui_in_check.set_visibility(current_player, false)
         ui_bad_move.set_visibility(current_player, false)
         if temp_int_00 != 0 and current_player.team == active_team then
            ui_in_check.set_visibility(current_player, true)
         end
      end
      --
      ui_your_turn.set_visibility(active_player, true)
      for each player do
         if current_player != active_player then
            ui_your_turn.set_visibility(current_player, false)
            if current_player.team == active_player.team then
               ui_your_turn.set_visibility(current_player, true)
               ui_your_turn.set_text("It's %s's turn!", active_player)
            end
         end
      end
      --
      if active_player.ui_would_self_check != 0 then
         ui_bad_move.set_visibility(active_player, true)
         if active_player.ui_would_self_check == piece_type_pawn then
            ui_bad_move.set_text("You cannot move this Pawn. Doing so would place your King in check. Try another piece.")
         end
         if active_player.ui_would_self_check == piece_type_rook then
            ui_bad_move.set_text("You cannot move this Rook. Doing so would place your King in check. Try another piece.")
         end
         if active_player.ui_would_self_check == piece_type_knight then
            ui_bad_move.set_text("You cannot move this Knight. Doing so would place your King in check. Try another piece.")
         end
         if active_player.ui_would_self_check == piece_type_queen then
            ui_bad_move.set_text("You cannot move this Queen. Doing so would place your King in check. Try another piece.")
         end
         if active_player.ui_would_self_check == piece_type_bishop then
            ui_bad_move.set_text("You cannot move this Bishop. Doing so would place your King in check. Try another piece.")
         end
      end
   end
end

function do_endgame_ui_visibility()
   for each player do
      ui_your_turn.set_visibility(current_player, false)
      ui_in_check.set_visibility(current_player, false)
      ui_bad_move.set_visibility(current_player, false)
      -- ui_turn_clock and ui_endgame are the same widget
      ui_endgame.set_visibility(current_player, true)
   end
end

function check_valid_move()
   --
   -- This function can be used both for determining what squares the player is 
   -- allowed to move their current piece to, and determining whether a check or 
   -- checkmate is in progress. In the former case, you'd want to run a for loop 
   -- to reset object.is_valid_move to 0 for all chess squares BEFORE calling 
   -- this function. In the latter case, you'd run that loop once, and then call 
   -- this function on all of the attacker's pieces; then, check whether the 
   -- defender's king can move to any square for which that variable is still 0.
   --
   -- Note, when establishing a player's legal moves, that if a player has no 
   -- legal moves but is not in check, then the game ends in a draw; if they 
   -- have no legal moves and are in check, then they lose. Note also that if 
   -- the player is in check, then they are only allowed to move their king. 
   -- Finally, note that this function does not check whether a target space 
   -- would put a king in check; you will have to let the player move their 
   -- king, then test whether their move has put their own king in check, and 
   -- if so, revert the move.
   --
   alias current_piece = temp_obj_00
   alias target_space  = temp_obj_01
   alias temporary_obj = temp_obj_02
   alias temporary_ob2 = temp_obj_03
   alias x_diff        = temp_int_00
   alias y_diff        = temp_int_01
   --
   if current_piece.piece_type == piece_type_bishop
   or current_piece.piece_type == piece_type_queen
   then
      target_space = current_piece
      function upperleft()
         target_space = target_space.space_left
         target_space = target_space.space_above
         if target_space != no_object then
            target_space.threatened_by += 1
            if target_space.piece_type == piece_type_none or target_space.owner != current_piece.owner then
               target_space.is_valid_move = 1
               if target_space.piece_type == piece_type_none then
                  upperleft()
               end
            end
         end
      end
      upperleft()
      --
      target_space = current_piece
      function upperright()
         target_space = target_space.space_right
         target_space = target_space.space_above
         if target_space != no_object then
            target_space.threatened_by += 1
            if target_space.piece_type == piece_type_none or target_space.owner != current_piece.owner then
               target_space.is_valid_move = 1
               if target_space.piece_type == piece_type_none then
                  upperright()
               end
            end
         end
      end
      upperright()
      --
      target_space = current_piece
      function lowerleft()
         target_space = target_space.space_left
         target_space = target_space.space_below
         if target_space != no_object then
            target_space.threatened_by += 1
            if target_space.piece_type == piece_type_none or target_space.owner != current_piece.owner then
               target_space.is_valid_move = 1
               if target_space.piece_type == piece_type_none then
                  lowerleft()
               end
            end
         end
      end
      lowerleft()
      --
      target_space = current_piece
      function lowerright()
         target_space = target_space.space_right
         target_space = target_space.space_below
         if target_space != no_object then
            target_space.threatened_by += 1
            if target_space.piece_type == piece_type_none or target_space.owner != current_piece.owner then
               target_space.is_valid_move = 1
               if target_space.piece_type == piece_type_none then
                  lowerright()
               end
            end
         end
      end
      lowerright()
   end
   if current_piece.piece_type == piece_type_rook
   or current_piece.piece_type == piece_type_queen
   then
      target_space = current_piece
      function left()
         target_space = target_space.space_left
         if target_space != no_object then
            target_space.threatened_by += 1
            if target_space.piece_type == piece_type_none or target_space.owner != current_piece.owner then
               target_space.is_valid_move = 1
               if target_space.piece_type == piece_type_none then
                  left()
               end
            end
         end
      end
      left()
      --
      target_space = current_piece
      function right()
         target_space = target_space.space_right
         if target_space != no_object then
            target_space.threatened_by += 1
            if target_space.piece_type == piece_type_none or target_space.owner != current_piece.owner then
               target_space.is_valid_move = 1
               if target_space.piece_type == piece_type_none then
                  right()
               end
            end
         end
      end
      right()
      --
      target_space = current_piece
      function up()
         target_space = target_space.space_above
         if target_space != no_object then
            target_space.threatened_by += 1
            if target_space.piece_type == piece_type_none or target_space.owner != current_piece.owner then
               target_space.is_valid_move = 1
               if target_space.piece_type == piece_type_none then
                  up()
               end
            end
         end
      end
      up()
      --
      target_space = current_piece
      function down()
         target_space = target_space.space_below
         if target_space != no_object then
            target_space.threatened_by += 1
            if target_space.piece_type == piece_type_none or target_space.owner != current_piece.owner then
               target_space.is_valid_move = 1
               if target_space.piece_type == piece_type_none then
                  down()
               end
            end
         end
      end
      down()
   end
   if current_piece.piece_type == piece_type_knight then
      for each object with label "board_space" do
         x_diff  = current_piece.coord_x
         x_diff -= current_object.coord_x
         y_diff  = current_piece.coord_y
         y_diff -= current_object.coord_y
         x_diff *= y_diff
         if x_diff == 2 or x_diff == -2 then -- (2 * 1) or (-2 * 1) or (2 * -1) or (-2 * -1)
            current_object.threatened_by += 1
            if current_object.piece_type == piece_type_none or current_object.owner != current_piece.owner then
               current_object.is_valid_move = 1
            end
         end
      end
   end
   if current_piece.piece_type == piece_type_king then
      function _set_if() -- if we inlined this, each copy would be a separate trigger. since they're all identical, let's just make it a function so we're not compiling tons of duplicate data
         target_space.threatened_by = 1
         if target_space.piece_type == piece_type_none or target_space.owner != current_piece.owner then
            target_space.is_valid_move = 1
         end
      end
      target_space = current_piece.space_left
      _set_if()
      target_space = target_space.space_above -- upper-left
      _set_if()
      target_space = current_piece.space_right
      _set_if()
      target_space = target_space.space_below -- lower-right
      _set_if()
      target_space = current_piece.space_above
      _set_if()
      target_space = target_space.space_right -- upper-right
      _set_if()
      target_space = current_piece.space_below
      _set_if()
      target_space = target_space.space_left -- lower-left
      _set_if()
   end
   if current_piece.piece_type == piece_type_pawn then
      alias single_move = target_space
      alias double_move = temporary_obj
      alias double_from = y_diff
      --
      single_move = current_piece.space_above
      double_move = single_move.space_above
      double_from = 6
      if current_piece.owner == faction_black then
         single_move = current_piece.space_below
         double_move = single_move.space_below
         double_from = 1
      end
      if single_move.piece_type == piece_type_none then
         single_move.is_valid_move = 1
         if current_piece.coord_y == double_from and double_move.piece_type == piece_type_none then
            double_move.is_valid_move = 1
         end
      end
      --
      -- Check for diagonal capture possibilities, including capturing en passant:
      --
      alias diagonal = temporary_obj
      alias passant  = temporary_ob2
      function _check_diagonal()
         diagonal.threatened_by += 1
         --
         passant = diagonal.space_below
         if current_piece.owner == faction_black then
            passant = diagonal.space_above
         end
         --
         if diagonal.piece_type != piece_type_none and diagonal.owner != current_piece.owner then
            diagonal.is_valid_move = 1
         end
         if  diagonal.piece_type == piece_type_none
         and passant.piece_type == piece_type_pawn
         and passant.owner != current_piece.owner
         then
            diagonal.is_valid_move = 1
         end
      end
      diagonal = single_move.space_left
      _check_diagonal()
      diagonal = single_move.space_right
      _check_diagonal()
   end
end

function _reset_board_for_move_checks()
   for each object with label "board_space" do
      current_object.is_valid_move = 0
      current_object.threatened_by = 0
   end
end
function is_king_in_check()
   alias king        = temp_obj_04 -- which king to check; must be set by the caller
   alias king_threat = temp_obj_05
   alias king_in_checkmate = temp_int_03 -- out
   alias king_in_check     = temp_int_04 -- out
   --
   king_in_checkmate = 0
   king_in_check     = 0
   if king != no_object then
      _reset_board_for_move_checks()
      king_threat = no_object
      for each object with label "board_space" do
         if current_object.piece_type != piece_type_none and current_object.owner != king.owner then
            temp_obj_00 = current_object -- parameter for next function call
            check_valid_move()
            if king.is_valid_move == 1 then
               king.is_valid_move = 0
               king_threat = current_object
            end
         end
      end
      --
      if king.threatened_by > 0 then
         king_in_check = 1
         --
         alias safe_space   = temp_obj_00
         alias target_space = temp_obj_01
         function _set_if()
            if target_space.threatened_by == 0 then
               if target_space.piece_type == piece_type_none or target_space.owner != king.owner then
                  safe_space = target_space
               end
            end
         end
         target_space = king.space_left
         _set_if()
         target_space = target_space.space_above -- upper-left
         _set_if()
         target_space = king.space_right
         _set_if()
         target_space = target_space.space_below -- lower-right
         _set_if()
         target_space = king.space_above
         _set_if()
         target_space = target_space.space_right -- upper-right
         _set_if()
         target_space = king.space_below
         _set_if()
         target_space = target_space.space_left -- lower-left
         _set_if()
         if safe_space == no_object then
            --
            -- The king cannot move to an unoccupied space or kill an enemy without 
            -- ending up under threat from another enemy.
            --
            if king.threatened_by > 1 then
               --
               -- The king is under threat by multiple enemies. His team can kill 
               -- only one of them in a single turn; thus he is in checkmate.
               --
               king_in_checkmate = 1
            end
            if king.threatened_by == 1 then
               alias can_escape = temp_int_02
               can_escape = 0
               if king_threat.en_passant_vulnerable == 1 then
                  --
                  -- The king is under threat by a pawn. Can one of his allies 
                  -- capture it en passant?
                  --
                  alias side = temp_obj_00
                  side = king_threat.space_above
                  if king_threat.owner == faction_white then
                     side = king_threat.space_below
                  end
                  if side.owner == king_threat.owner or side.piece_type == piece_type_none then
                     side = king_threat.space_left
                     if side.owner == king.owner and side.piece_type == piece_type_pawn then
                        can_escape = 1
                     end
                     side = king_threat.space_right
                     if side.owner == king.owner and side.piece_type == piece_type_pawn then
                        can_escape = 1
                     end
                  end
               end
               if can_escape == 0 then
                  --
                  -- If the piece threatening the king can be killed by one of the 
                  -- king's allies, then this is not checkmate.
                  --
                  _reset_board_for_move_checks()
                  for each object with label "board_space" do
                     if  current_object.piece_type != piece_type_none
                     and current_object.piece_type != piece_type_king
                     and current_object.owner == king.owner
                     then
                        temp_obj_00 = current_object -- parameter for next function call
                        check_valid_move()
                     end
                  end
                  if king_threat.is_valid_move == 0 then
                     --
                     -- A kill is not possible. Can we move a piece between it and the king 
                     -- instead?
                     --
                     if king_threat.piece_type == piece_type_knight then
                        --
                        -- You can't physically block a knight.
                        --
                        king_in_checkmate = 1
                     else
                        --
                        -- We've already identified every space that the king's allies can 
                        -- move to. Let's take the unoccupied spaces and temporarily change 
                        -- their piece type to a dummy value. Then, we'll re-check what 
                        -- spaces the (king_threat) can move to: the dummy value will cause 
                        -- it to treat those spaces as being occupied (i.e. blocked), and if 
                        -- because of that it can't reach the king, then physically blocking 
                        -- it from the king is indeed posible.
                        --
                        for each object with label "board_space" do
                           current_object.threatened_by = 0
                           if current_object.is_valid_move == 1 then
                              current_object.is_valid_move = 0
                              if current_object.piece_type == piece_type_none then
                                 current_object.piece_type = piece_type_dummy
                              end
                           end
                        end
                        temp_obj_00 = king_threat -- parameter for next function call
                        check_valid_move()
                        for each object with label "board_space" do
                           if current_object.piece_type == piece_type_dummy then
                              current_object.piece_type = piece_type_none
                           end
                        end
                        if king.is_valid_move == 1 then
                           --
                           -- The king's allies can't block this enemy from threatening the 
                           -- king.
                           --
                           king_in_checkmate = 1
                        end
                     end
                  end
               end
            end
         end
      end
      --
   end
end

function begin_victory()
   --
   -- This subroutine triggers the beginning of a victory sequence, in which the 
   -- winning team is awarded a point and given a brief opportunity to kill the 
   -- enemy king.
   --
   -- Note that the enemy king may already be dead. There are two ways to win:
   -- 
   --  - You placed the enemy in checkmate.
   --
   --  - You placed the enemy in check, and they did not make a move before the 
   --    turn clock ran out, allowing you to kill their king the next turn.
   --
   if winning_faction == faction_none then
      alias faction_to_win = temp_int_00 -- argument
      alias team_to_win    = temp_tem_00
      --
      team_to_win = team_black
      if faction_to_win == faction_white then
         team_to_win = team_white
      end
      winning_faction = faction_to_win
      team_to_win.score += 1
      --
      alias losing_king_alive = temp_int_00
      losing_king_alive = 0
      for each object with label "board_space" do
         current_object.is_valid_move = 0
         current_object.threatened_by = 0
         current_object.en_passant_vulnerable = 0
         --
         if current_object.piece_type == piece_type_king and current_object.owner != winning_faction then
            losing_king_alive = 1
            game.round_timer = time_limit_for_finishing_off_losing_king
         end
      end
      if losing_king_alive == 0 then
         game.end_round()
      end
   end
end

function prep_for_avoiding_self_check()
   --
   -- Prepare piece state to prevent the active player from putting 
   -- themselves in check.
   --
   for each object with label "board_space" do -- clear piece/space movement flags
      current_object.space_flags   = 0
      current_object.is_valid_move = 0
      current_object.threatened_by = 0
   end
   for each object with label "board_space" do -- identify all enemy moves
      if current_object.piece_type != piece_type_none and current_object.owner != active_faction then
         temp_obj_00 = current_object -- argument
         check_valid_move()
      end
   end
   --
   alias king = temp_obj_00
   king = no_object
   for each object with label "board_space" do
      if current_object.piece_type == piece_type_king and current_object.owner == active_faction then
         king = current_object
      end
   end
   if king != no_object then
      --
      -- We need to convert all spaces' (threatened_by) to the special flag 
      -- that we'll use to indicate that the player can't move their king 
      -- there: (space_flag_is_threatened_by_enemy). The reason we want to use 
      -- (threatened_by) and not (is_valid_move) is so that we prevent you 
      -- from putting yourself in check by using your king to kill an enemy 
      -- that can be avenged by another enemy (checkmate logic also takes this 
      -- into consideration).
      --
      -- We also need to detect allied pieces that are blocking an enemy from 
      -- reaching the king. A piece meets this description if the following 
      -- criteria are met:
      --
      --  - The allied piece is aligned with the king on a diagonal or cardinal 
      --    direction.
      --
      --  - There are no other pieces between the allied piece and the king.
      --
      --  - The allied piece is between the king and one or more enemy pieces.
      --
      --  - The nearest enemy piece is capable of moving toward the king (i.e. 
      --    it is a queen, or: it is a rook and the pieces are aligned on a 
      --    cardinal direction; or: it is a bishop and the pieces are aligned 
      --    on a diagonal direction).
      --
      -- We want to set the flag (space_flag_moving_would_self_check) on all 
      -- allied pieces that meet those conditions.
      --
      -- As a nice shortcut, if these conditions are met, then the allied piece 
      -- will also be under threat from the nearest enemy, i.e. (is_valid_move) 
      -- will be true and (threatened_by) will be non-zero. This means we can 
      -- use those variables as a filter and only run our checks where they're 
      -- actually needed.
      --
      -- We can ignore knights and pawns, since the former cannot be blocked 
      -- and the latter can only capture a king while adjacent to that king 
      -- (i.e. there are no spaces between it and the king, and so it cannot 
      -- be blocked).
      --
      for each object with label "board_space" do
         if current_object.threatened_by > 0 then
            current_object.space_flags |= space_flag_is_threatened_by_enemy -- is_valid_move -> flag
            --
            if  current_object.piece_type != piece_type_none
            and current_object.piece_type != piece_type_king
            and current_object.owner == active_faction then
               --
               -- This piece belongs to the active faction. Check if it is blocking 
               -- an enemy from reaching the king.
               --
               alias has_path_to_king = temp_int_00 -- there are no pieces between this one and its allied king
               alias current_ally     = temp_obj_01
               alias nearest_enemy    = temp_obj_02
               has_path_to_king = 1
               current_ally  = current_object
               nearest_enemy = no_object
               --
               function _to_sign()
                  alias diff_sign = temp_int_01
                  if diff_sign != 0 then
                     if diff_sign > 0 then
                        diff_sign = 1
                     end
                     if diff_sign < 0 then
                        diff_sign = -1
                     end
                  end
               end
               --
               if current_ally.coord_y == king.coord_y then -- left or right
                  alias diff_sign = temp_int_01
                  diff_sign  = current_ally.coord_x
                  diff_sign -= king.coord_x
                  _to_sign()
                  --
                  alias nearest_opposite = temp_int_02
                  nearest_opposite = 99
                  for each object with label "board_space" do
                     if  current_object != current_ally
                     and current_object != king
                     and current_object.coord_y == current_ally.coord_y
                     and current_object.piece_type != piece_type_none
                     then
                        alias distance = temp_int_03
                        alias working  = temp_int_04
                        distance  = current_object.coord_x
                        distance -= king.coord_x
                        working  = distance
                        working *= diff_sign
                        if working > 0 then -- (current_object) is on the same side of (king) as (current_ally)
                           distance  = current_ally.coord_y
                           distance -= king.coord_y
                           distance *= diff_sign
                           if working < distance then
                              has_path_to_king = 0
                           end
                           if working > distance and working < nearest_opposite then
                              nearest_opposite = working
                              nearest_enemy    = no_object
                              if  current_object.piece_type == piece_type_queen
                              or  current_object.piece_type == piece_type_rook
                              and current_object.owner != king.owner
                              then
                                 nearest_enemy = current_object
                              end
                           end
                        end
                     end
                  end
               end
               if current_ally.coord_x == king.coord_x then -- above or below
                  alias diff_sign = temp_int_01
                  diff_sign  = current_ally.coord_y
                  diff_sign -= king.coord_y
                  _to_sign()
                  --
                  alias nearest_opposite = temp_int_02
                  nearest_opposite = 99
                  for each object with label "board_space" do
                     if  current_object != current_ally
                     and current_object != king
                     and current_object.coord_x == current_ally.coord_x
                     and current_object.piece_type != piece_type_none
                     then
                        alias distance = temp_int_03
                        alias working  = temp_int_04
                        distance  = current_object.coord_y
                        distance -= king.coord_y
                        working  = distance
                        working *= diff_sign
                        if working > 0 then -- (current_object) is on the same side of (king) as (current_ally)
                           distance  = current_ally.coord_y
                           distance -= king.coord_y
                           distance *= diff_sign
                           if working < distance then
                              has_path_to_king = 0
                           end
                           if working > distance and working < nearest_opposite then
                              nearest_opposite = working
                              nearest_enemy    = no_object
                              if  current_object.piece_type == piece_type_queen
                              or  current_object.piece_type == piece_type_rook
                              and current_object.owner != king.owner
                              then
                                 nearest_enemy = current_object
                              end
                           end
                        end
                     end
                  end
               end
               --
               if current_ally.coord_x != king.coord_x and current_ally.coord_y != king.coord_y then
                  alias diff_x = temp_int_01
                  alias nearest_opposite = temp_int_02
                  alias diff_y = temp_int_03
                  diff_x  = current_ally.coord_x
                  diff_x -= king.coord_x
                  diff_y  = current_ally.coord_y
                  diff_y -= king.coord_y
                  if diff_y != diff_x then
                     diff_y *= -1
                  end
                  if diff_y == diff_x then
                     --
                     -- The current_ally is on a diagonal with the king.
                     --
                     alias diff_sign = temp_int_01
                     diff_sign  = current_ally.coord_x
                     diff_sign -= king.coord_x
                     _to_sign()
                     --
                     nearest_opposite = 99
                     for each object with label "board_space" do
                        if  current_object != current_ally
                        and current_object != king
                        and current_object.piece_type != piece_type_none
                        then
                           alias temp_x = diff_y
                           alias temp_y = temp_int_04
                           temp_x  = current_object.coord_x
                           temp_x -= king.coord_x
                           temp_y  = current_object.coord_y
                           temp_y -= king.coord_y
                           if temp_y != temp_x then
                              temp_y *= -1
                           end
                           if temp_y == temp_x then
                              --
                              -- The current_object is on a diagonal with the king; however, it 
                              -- may not be the same diagonal as current_ally. If we were to 
                              -- stop our checks here, we'd false-positive in the following case:
                              --
                              -- ░▓░▓░▓░▓ Uppercase: enemy; lowercase: ally
                              -- ▓░▓░▓R▓░
                              -- ░▓░▓░▓░▓
                              -- ▓░▓k▓░▓░ Allied king shares NE/SW diagonal with enemy rook
                              -- ░▓░▓░▓░▓
                              -- ▓░▓░▓░▓░
                              -- ░▓░▓░▓p▓ Allied pawn shares NW/SE diagonal with allied king
                              -- ▓░▓░▓░▓░
                              --
                              temp_x  = current_object.coord_x
                              temp_x -= current_ally.coord_x
                              temp_y  = current_object.coord_y
                              temp_y -= current_ally.coord_y
                              if temp_y != temp_x then
                                 temp_y *= -1
                              end
                              if temp_y == temp_x then
                                 --
                                 -- The current_object is on a diagonal with both the king and 
                                 -- the current_ally. This means that they must be on the same 
                                 -- diagonal: one piece must be physically between the others 
                                 -- along that diagonal.
                                 --
                                 -- From this point, we only need to check one axis, so we can 
                                 -- treat this the same as we would pieces on a cardinal axis. 
                                 -- The only difference is that we need to check for an enemy 
                                 -- bishop instead of an enemy rook. Let's copy the code for 
                                 -- pieces that share a row.
                                 --
                                 alias distance = temp_int_03
                                 alias working  = temp_int_04
                                 distance  = current_object.coord_x
                                 distance -= king.coord_x
                                 working  = distance
                                 working *= diff_sign
                                 if working > 0 then -- (current_object) is on the same side of (king) as (current_ally)
                                    distance  = current_ally.coord_y
                                    distance -= king.coord_y
                                    distance *= diff_sign
                                    if working < distance then
                                       has_path_to_king = 0
                                    end
                                    if working > distance and working < nearest_opposite then
                                       nearest_opposite = working
                                       nearest_enemy    = no_object
                                       if  current_object.piece_type == piece_type_queen
                                       or  current_object.piece_type == piece_type_bishop
                                       and current_object.owner != king.owner
                                       then
                                          nearest_enemy = current_object
                                       end
                                    end
                                 end
                              end
                           end
                        end
                     end
                  end
               end
               --
               -- All tests done for current_ally.
               --
               if has_path_to_king == 1 and nearest_enemy != no_object then
                  current_ally.space_flags |= space_flag_moving_would_self_check
               end
            end
         end
      end
   end
end

function quick_force_active_player_to_monitor()
   alias working = temp_obj_00
   alias ctrlbip = temp_obj_01
   ctrlbip = active_player.biped
   working = ctrlbip.place_at_me(monitor, none, none, 0, 0, 0, none)
   working.copy_rotation_from(ctrlbip, true)
   working.attach_to(ctrlbip, 0, 0, 6, relative)
   working.detach()
   active_player.set_biped(working)
   ctrlbip.delete()
   --if working.is_out_of_bounds() then
   --   working.copy_rotation_from(board_center, true)
   --   working.attach_to(board_center, 0, 0, 20, relative)
   --   working.detach()
   --end
end
function end_turn()
   if winning_faction == faction_none then
      alias previous_faction = temp_int_00
      alias previous_player  = temp_plr_00
      --
      previous_faction = active_faction
      previous_player  = active_player
      active_faction   = faction_white
      active_team      = team_white
      if previous_faction == faction_white then
         active_faction = faction_black
         active_team    = team_black
      end
      temp_obj_00 = active_player.biped
      if temp_obj_00.is_script_created != 0 then -- turn clock ran out while the active player had control of a biped
         temp_obj_00.delete()
      end
      active_player.target_space = no_object
      active_player  = no_player
      selected_piece = no_object
      --
      alias active_king = temp_obj_04
      turn_clock.reset()
      turn_flags  = 0
      active_king = no_object
      for each object with label "board_space" do
         if current_object.owner == active_faction then
            if current_object.en_passant_vulnerable == 1 then
               --
               -- When a faction begins a new turn, clear this flag on any of their pawns that 
               -- had it set from a previous turn.
               --
               current_object.en_passant_vulnerable = 0
            end
            if current_object.piece_type == piece_type_king then
               active_king = current_object
            end
         end
      end
      is_king_in_check() -- check if the previously-made move has put this player in check
      if temp_int_04 != 0 then -- active faction is in check!
         turn_flags |= turn_flag_in_check
         if temp_int_03 != 0 then -- active faction is in checkmate!
            --
            -- Revert active faction and player back to previous; then, trigger victory 
            -- endgame.
            --
            temp_int_00 = faction_white
            if active_faction == faction_white then
               active_faction = faction_black
            end
            active_player = previous_player
            begin_victory() -- victory condition: checkmate
            for each player do
               temp_tem_00 = current_player.team
               if temp_tem_00.faction == winning_faction then
                  game.show_message_to(current_player, none, "Checkmate! Your team won!")
               end
               if temp_tem_00.faction != winning_faction and temp_tem_00.faction != faction_none then
                  game.show_message_to(current_player, none, "Checkmate! Your team lost.")
               end
            end
         end
      end
      if winning_faction == faction_none then -- not in checkmate
         prep_for_avoiding_self_check()
         --
         -- Check whether the player has any valid moves.
         --
         alias has_movable_pieces = temp_int_02
         alias is_king            = temp_int_03
         has_movable_pieces = 0
         for each object with label "board_space" do
            current_object.space_flags &= space_flag_has_no_valid_moves_clear
            if current_object.piece_type != piece_type_none and current_object.owner == active_faction then
               temp_int_00  = current_object.space_flags
               temp_int_00 &= space_flag_moving_would_self_check
               if temp_int_00 == 0 then
                  temp_obj_00 = current_object -- argument
                  for each object with label "board_space" do
                     current_object.is_valid_move = 0
                     current_object.threatened_by = 0
                  end
                  check_valid_move()
                  --
                  alias piece_can_move = temp_int_00
                  piece_can_move = 0
                  is_king        = 0
                  if current_object.piece_type == piece_type_king then
                     is_king = 1
                  end
                  for each object with label "board_space" do
                     if current_object.is_valid_move == 1 then
                        temp_int_01  = current_object.space_flags
                        temp_int_01 &= space_flag_is_threatened_by_enemy
                        if is_king == 0 or temp_int_01 == 0 then
                           piece_can_move = 1
                        end
                     end
                  end
                  has_movable_pieces += piece_can_move
                  if piece_can_move == 0 then
                     current_object.space_flags |= space_flag_has_no_valid_moves
                  end
               end
            end
         end
         if has_movable_pieces == 0 then
            temp_int_00  = turn_flags
            temp_int_00 &= turn_flag_in_check
            if temp_int_00 == 0 then
               --
               -- End the match in a draw.
               --
               ui_endgame.set_text("Draw! (White Team has no moves left.)")
               if active_faction == faction_black then
                  ui_endgame.set_text("Draw! (Black Team has no moves left.)")
               end
               do_endgame_ui_visibility()
               game.end_round()
            end
         end
      end
      --
      alias pawn_count = temp_int_00
      pawn_count = 0
      for each object with label "board_space" do
         if current_object.piece_type == piece_type_pawn then
            pawn_count += 1
            --
            -- Let's handle pawn promotion too, while we're at it:
            --
            if winning_faction == faction_none then
               if current_object.coord_y == 0 or current_object.coord_y == 7 then -- pawns can't go backwards so we can do this shortcut
                  temp_obj_00 = current_object
                  temp_obj_00.piece_type = piece_type_queen
                  for each object with label "board_space_extra" do
                     if current_object.marker == temp_obj_00 then
                        current_object.biped.delete()
                     end
                  end
                  if temp_obj_00.owner == faction_white then
                     game.show_message_to(all_players, none, "White Team promoted a Pawn to Queen!")
                  end
                  if temp_obj_00.owner == faction_black then
                     game.show_message_to(all_players, none, "Black Team promoted a Pawn to Queen!")
                  end
               end
            end
         end
      end
      if pawn_count == 0 then
         draw_turn_count += 1
      end
   end
end
function commit_move()
   alias target_space = temp_obj_00 -- argument
   alias target_biped = temp_obj_01 -- argument
   --
   if selected_piece.piece_type == piece_type_pawn then -- handle en-passant vulnerability state
      alias y_diff = temp_int_00
      y_diff  = selected_piece.coord_y
      y_diff -= target_space.coord_y
      if y_diff == 2 or y_diff == -2 then
         target_space.en_passant_vulnerable = 1
      end
   end
   alias slayer_owner        = temp_int_00
   alias slain_enemy_is_king = temp_int_01
   slayer_owner        = selected_piece.owner
   slain_enemy_is_king = 0
   if target_space.piece_type == piece_type_king then -- king was killed
      slain_enemy_is_king = 1
   end
   --
   target_space.piece_type = selected_piece.piece_type
   target_space.owner      = selected_piece.owner
   selected_piece.piece_type = piece_type_none
   selected_piece.owner      = faction_none
   selected_piece.en_passant_vulnerable = 0
   target_biped.delete()
   if slain_enemy_is_king == 1 then
      temp_int_00 = slayer_owner -- argument: faction to win
      begin_victory() -- victory condition: killed king
   end
   --
   end_turn()
end

if winning_faction == faction_none then -- handle picking a piece and handle making a move
   turn_clock.set_rate(-100%)
   if active_faction == faction_none then
      --
      -- We want White Team to move first, but there's a lot of state that we only 
      -- set up at the end of a turn... so tell the game it's Black Team's turn and 
      -- then immediately end the turn.
      --
      -- (Also, we want to alternate who gets to go first every round, but bear in 
      -- mind that game.current_round starts from 1, not 0.)
      --
      active_faction = faction_white
      active_team    = team_white
      temp_int_00  = game.current_round
      temp_int_00 %= 2
      if temp_int_00 == 0 then -- every round we should alternate who gets to move first
         active_faction = faction_black
         active_team    = team_black
      end
      end_turn()
   end
   if active_player != no_player and active_player.killer_type_is(quit) and active_player.team.has_any_players() then -- handle active player quitting
      turn_clock.reset()
      active_player = no_player
   end
   if active_player == no_player then
      --
      -- Ensure that all players have a turn order, and select an active player.
      --
      if active_team != no_team and active_team.has_any_players() then
         --
         -- Let's start by identifying the highest turn-order value, the lowest 
         -- turn-order value, and the player with the lowest value.
         --
         alias t_o_min    = temp_int_00
         alias t_o_max    = temp_int_01
         alias min_player = temp_plr_01
         t_o_min = MAX_INT
         t_o_max = -1
         temp_plr_01 = no_player
         for each player do
            if current_player.turn_order > -1 and current_player.team == active_team then
               if current_player.turn_order < t_o_min then
                  t_o_min    = current_player.turn_order
                  min_player = current_player
               end
               if current_player.turn_order > t_o_max then
                  t_o_max = current_player.turn_order
               end
            end
         end
         --
         -- Next, let's try to advance the team's turn-order value to the next 
         -- player, while also giving turn-order values to any players who are 
         -- missing one.
         --
         alias t_o_next    = temp_int_02
         alias next_player = temp_plr_00
         t_o_next    = MAX_INT
         next_player = no_player
         for each player do
            if current_player.turn_order < 0 then
               --
               -- This player doesn't have a turn-order value. Let's give them 
               -- one.
               --
               t_o_max += 1
               current_player.turn_order = t_o_max
               if min_player == no_player then
                  --
                  -- If no players had turn-order values in the earlier loop, 
                  -- then there won't be a min_player. We need to have one.
                  --
                  min_player = current_player
               end
            end
            if  current_player.turn_order > active_team.turn_order 
            and current_player.turn_order < t_o_next
            then
               t_o_next    = current_player.turn_order
               next_player = current_player
            end
         end
         if next_player == no_player then
            --
            -- There aren't any players after the new turn order, so we need to loop 
            -- back around to the start.
            --
            next_player = min_player
         end
         if next_player != no_player then
            active_player = next_player
            active_team.turn_order = active_player.turn_order -- advance the team's current turn-order value
         end
      end
   end
   if active_player == no_player and opt_turn_clock <= 0 then -- team is empty and no turn clock; skip its turn
      end_turn()
   end
   --
   active_player.ui_would_self_check = 0
   if selected_piece == no_object then -- the player is not in control of a piece
      --
      -- Code to select a piece to control.
      --
      for each object with label "board_space_extra" do
         current_object.biped.set_invincibility(1)
      end
      alias prior_space = temp_obj_00
      prior_space = active_player.target_space
      active_player.target_space = no_object
      --
      active_player.ui_would_self_check = 0
      for each object with label "board_space" do
         current_object.set_shape_visibility(no_one)
         if current_object.owner == active_faction and current_object.shape_contains(active_player.biped) then
            alias cannot_move = temp_int_00
            alias flag_check  = temp_int_01
            cannot_move  = current_object.space_flags
            cannot_move &= space_flag_mask_cannot_move
            flag_check   = current_object.space_flags
            flag_check  &= space_flag_moving_would_self_check
            if flag_check != 0 then
               active_player.ui_would_self_check = current_object.piece_type
            end
            if cannot_move == 0 then
               current_object.set_shape_visibility(everyone)
               active_player.target_space = current_object
               if prior_space != current_object then
                  active_player.selection_timer.reset()
               end
            end
         end
      end
      if active_player.target_space == no_object then
         active_player.selection_timer.set_rate(0%)
      end
      if active_player.target_space != no_object then
         active_player.selection_timer.set_rate(-100%)
         if active_player.selection_timer.is_zero() then
            active_player.selection_timer.reset()
            selected_piece = active_player.target_space
            active_player.target_space = no_object
            --
            -- Identify valid moves:
            --
            for each object with label "board_space" do
               current_object.is_valid_move = 0
               current_object.threatened_by = 0
            end
            temp_obj_00 = selected_piece -- argument
            check_valid_move()
         end
      end
   end
   if selected_piece != no_object then -- the player is in control of a piece
      --
      -- Code to select a board space.
      --
      alias extra = temp_obj_01
      extra = no_object
      for each object with label "board_space_extra" do
         alias cell = temp_obj_00
         alias temp = temp_int_00
         --
         cell  = current_object.marker
         temp  = cell.is_valid_move
         temp *= -1
         temp +=  1
         current_object.biped.set_invincibility(temp)
         if current_object.marker == selected_piece then
            extra = current_object
         end
      end
      if active_player.biped.is_of_type(monitor) and extra.biped != no_object then
         temp_obj_00 = active_player.biped
         active_player.set_biped(extra.biped)
         temp_obj_00.delete()
      end
      --
      -- The player can capture an empty space by standing in it. For an occupied space, 
      -- they must kill the piece on that space. The code here handles empty spaces.
      --
      for each object with label "board_space" do
         current_object.set_shape_visibility(no_one)
         if current_object.is_valid_move == 1 then
            temp_int_00 = 0
            if selected_piece.piece_type == piece_type_king then
               temp_int_00  = current_object.space_flags
               temp_int_00 &= space_flag_is_threatened_by_enemy
            end
            if temp_int_00 == 0 then
               current_object.set_shape_visibility(everyone)
               if  current_object.piece_type == piece_type_none
               and active_player.target_space != current_object
               and current_object.shape_contains(active_player.biped)
               then
                  active_player.target_space = current_object
                  active_player.selection_timer.reset()
               end
            end
         end
      end
      if active_player.target_space == no_object then
         active_player.selection_timer.set_rate(0%)
      end
      if active_player.target_space != no_object then
         active_player.selection_timer.set_rate(-100%)
         if active_player.selection_timer.is_zero() then
            alias cell = temp_obj_00
            --
            quick_force_active_player_to_monitor()
            temp_obj_00 = active_player.target_space
            temp_obj_01 = no_object
            commit_move()
         end
      end
      if not board_center.piece_deselect_boundary.shape_contains(active_player.biped) then
         --
         -- If the current player runs their piece-biped far outside of the board, deselect 
         -- the piece so they can change their choice.
         --
         selected_piece = no_object
         quick_force_active_player_to_monitor()
      end
   end
   if turn_clock.is_zero() and opt_turn_clock > 0 then
      end_turn()
   end
end
on object death: do
   if  killed_object.is_script_created == 1
   and killed_object.marker != no_object
   then
      alias cell  = temp_obj_00
      alias extra = temp_obj_01
      cell  = killed_object.marker
      extra = killed_object.extra
      killed_object.delete()
      --
      if winning_faction != faction_none and cell.piece_type == piece_type_king then -- end-of-match victory
         if cell.owner != winning_faction then
            game.end_round()
         end
      end
      --
      if killer_object.is_script_created == 1 and selected_piece != no_object then -- active player tried to capture this square
         --
         -- The active player tried to capture this space.
         --
         if cell.owner != selected_piece.owner and cell.is_valid_move == 1 then
            --
            -- The active player is allowed to capture this square.
            --
            temp_obj_02 = cell -- temp_obj_00 is used by next call
            quick_force_active_player_to_monitor()
            killer_object.delete()
            if winning_faction == faction_none then
               temp_obj_00 = temp_obj_02
               temp_obj_01 = no_object
               commit_move()
               draw_turn_count = 0 -- reset the 75-rule counter if a piece was killed
            end
         end
      end
   end
end


if winning_faction != faction_none then
   alias cell = temp_obj_00
   --
   if active_player == no_player or active_player.killer_type_is(quit) then
      game.end_round()
   end
   for each object with label "board_space_extra" do
      current_object.biped.set_invincibility(0)
      cell = current_object.marker
      cell.set_shape_visibility(no_one)
      if current_object.biped != no_object and cell.owner == winning_faction then
         if not current_object.biped.is_out_of_bounds() then
            current_object.biped.set_invincibility(1)
         end
         if cell.piece_type == piece_type_king then
            if active_player.biped.is_of_type(monitor) then
               active_player.biped.delete()
            end
            active_player.set_biped(current_object.biped)
         end
      end
   end
   ui_your_turn.set_text("Finish off the enemy King!")
   ui_endgame.set_text("Black Team won!")
   if winning_faction == faction_white then
      ui_endgame.set_text("White Team won!")
   end
   do_endgame_ui_visibility()
   ui_your_turn.set_visibility(active_player, true)
end

if winning_faction == faction_none then -- check for draw conditions
   if opt_draw_rule > 0 and draw_turn_count >= opt_draw_rule then
      --
      -- If 75 moves (by default) pass without there being pawns on the board, and 
      -- without either player capturing an enemy piece, then the game will end in 
      -- a draw automatically.
      --
      ui_endgame.set_text("Draw! (%n turns passed with no pawns and no captures.)", draw_turn_count)
      do_endgame_ui_visibility()
      game.end_round()
   end
   --
   -- Check for insufficient material condition 1: one side only has a king, and 
   -- the other side only has a king and one knight OR a king and one bishop.
   --
   alias knights_and_bishops = temp_int_00
   alias any_other_pieces    = temp_int_01
   knights_and_bishops = 0
   any_other_pieces    = 0
   for each object with label "board_space" do
      if current_object.piece_type == piece_type_knight
      or current_object.piece_type == piece_type_bishop
      then
         knights_and_bishops += 1
      end
      if  current_object.piece_type != piece_type_king
      and current_object.piece_type != piece_type_knight
      and current_object.piece_type != piece_type_bishop
      then
         any_other_pieces = 1
      end
   end
   if any_other_pieces == 0 then
      if knights_and_bishops == 1 then
         ui_endgame.set_text("Draw! (Insufficient material.)")
         do_endgame_ui_visibility()
         game.end_round()
      end
      --
      -- Check for insufficient material condition 2: each side has one king and 
      -- one bishop, and the bishops are both on the same color. We've already 
      -- confirmed the only pieces in play are kings, knights, and bishops.
      --
      alias bishops_black = temp_int_00
      alias bishops_white = temp_int_01
      alias b_align_black = temp_int_02
      alias b_align_white = temp_int_03
      bishops_black = 0
      bishops_white = 0
      b_align_black = 0
      b_align_white = 0
      for each object with label "board_space" do
         if current_object.piece_type == piece_type_bishop then
            if current_object.owner == faction_black then
               bishops_black += 1
               b_align_black  = current_object.coord_x
               b_align_black += current_object.coord_y
               b_align_black %= 2
            end
            if current_object.owner == faction_white then
               bishops_white += 1
               b_align_white  = current_object.coord_x
               b_align_white += current_object.coord_y
               b_align_white %= 2
            end
         end
      end
      if bishops_black == 1 and bishops_white == 1 and b_align_black == b_align_white then
         ui_endgame.set_text("Draw! (Insufficient material.)")
         do_endgame_ui_visibility()
         game.end_round()
      end
   end
end

if game.round_time_limit > 0 or winning_faction != faction_none and game.round_timer.is_zero() then
   game.end_round()
end
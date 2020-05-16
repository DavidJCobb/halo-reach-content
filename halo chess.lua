

--
-- HALO CHESS IMPLEMENTATION IDEAS
--
-- GOAL: Reimplement Halo Chess using user-defined functions, in order to allow 
-- for checkmate functionality -- removing the need to determine the winner by 
-- honor rules.
--

--
-- TODO: if a player's move would put their king in check, revert the move and 
--       force them to try another. (we can't disallow these moves in advance 
--       because we'd have to detect cases like if the player has a piece in 
--       between the king and an enemy rook, and they move that piece, exposing 
--       their own king -- just lots of things that are indirect and harder to 
--       test for than their complimentary cases in the checkmate logic.)
--
--        - if the player has no permitted moves, and there is no time limit on 
--          turns, then this will softlock. how do we deal with that?
--
--        - hm... it might be possible to forbid moves that would put a player's 
--          own king in check, but it'd be really tricky. we would have to...
--
--           - identify all spaces threatened by an enemy piece, and disallow 
--             moving the king there. simple.
--
--           - to prevent the player from moving a piece that is blocking their 
--             king from being in check: when setting up a piece's valid moves, 
--             check if its allied king is off in any cardinal or diagonal 
--             direction (with no other allied pieces between the current piece 
--             and the king). if so, check the opposite direction for either an 
--             enemy queen or (depending on whether it's cardinal or diagonal) 
--             an enemy rookor bishop. if a matching enemy is found, then the 
--             current piece cannot be moved without putting the king in check.
--
--              - pawns can only capture kings diagonally, from adjacent spaces, 
--                and so cannot be blocked. we can ignore enemy pawns.
--
--              - enemy knights can leap over pieces and so can be ignored here 
--                (what we're trying to prevent is moving a king-allied piece 
--                that is blocking the king from being in check; you cannot 
--                block a knight). the enemy king can be ignored as well, since 
--                kings can't traverse across multiple spaces: they must be 
--                adjacent to each other to threaten each other and so cannot 
--                be blocked.
--
--              = this could lead to ugly UX, where we indicate that a piece 
--                can be controlled only to punt the user out and tell them that 
--                they can't safely move it. if we make this code a function, we 
--                can call it on all of the player's pieces and disallow the 
--                player from even taking control of pieces that can't be safely 
--                moved. of course, we'd need to indicate WHY we're doing this, 
--                and i'm not sure we have the UI widgets to spare; we'll need 
--                to make some changes...
--          
--          there is an uglier alternative approach, which would require taking 
--          our current "valid move" logic and splitting it (current code would 
--          be check(mate) only, with a new approach for setting up a player's 
--          available moves). the new logic would be:
--
--           - identify all spaces threatened by an enemy piece, and disallow 
--             moving the king there. simple.
--
--           - for each piece with a contiguous direction of movement (i.e. all 
--             enemy rooks, bishops, and queens): if only one king-allied piece 
--             blocks any of these enemy pieces from the king, then flag that 
--             king-allied piece and not being movable. (essentially, this 
--             requires a modified variant on valid-move logic: for each of the 
--             enemy's directions of movement, instead of stopping iteration at 
--             the first blocker, we remember the first blocker found, the 
--             number of blockers up to the enemy king, and whether the king is 
--             even in that direction relative to the enemy piece. if there is 
--             only one blocker and it is indeed interposed between the enemy 
--             and the king, then we flag that blocker as not being safely 
--             movable.)
--          
--          probably would consume too much space.
--
-- TODO: draw if a player has no legal moves but is not in check
--
-- TODO: pawn promotion
--
-- TODO: if a team has no players, skip its turn, optionally with a short delay 
--       and a UI message (clearly indicate the code; we only want this for 
--       testing, and we may try to replace it with letting a single player 
--       control both sides of the board)
--
-- TODO: short delay between checkmate and victory
--
--        - WROTE A FIX BUT HAVEN'T TESTED IT YET. Hopefully the round won't end 
--          immediately upon checkmate anymore.
--
--        - If the fix works, we still need to set a time limit on the winners 
--          killing the enemy king.
--
-- TODO: Write code to end the round when the round timer runs out. If a checkmate  
--       occurs and we're waiting on the winner to kill the king, force the round 
--       timer to match the time limit on killing the king. (We award points as 
--       soon as the checkmate/victory is detected, so after that it's just a 
--       matter of deciding when to end the round.)
--
-- TODO: Spawn a "tray" of pieces behind each team. Halo Chess doesn't give you 
--       waypoints on each individual enemy piece; rather, the tray contains one 
--       rook, one knight, one bishop, and one queen, and you get waypoints on 
--       the pieces in the enemy tray.
--
-- TODO: if multiple players are on a team, they should take turns making moves 
--       for that team; turn order for players should be consistent
--
-- TODO: spawning the player into a Monitor after a move: i think official halo 
--       chess uses an offset of (-15, 0, 15); try that and see if it's consistent 
--       with gameplay videos. (currently we do (0, 0, 6); i've been meaning to 
--       try out (-4, 0, 5) and see if that looks a bit better.)
--
-- TODO: sometimes there is a constant alarm sound which begins immediately at the 
--       start of the match and may play indefinitely; I think it may result from 
--       forcibly reassigning the player's biped but I don't know exactly why. 
--       it's obnoxious -- easily qualifying as making chess unplayable.
--
--       UPDATE: it's sound\weapons\missile_launcher\tracking_locking\locking\loop
--
--               why? "missile_launcher" is leftover sounds for the H3 missile pod.
--               i can't find any references to the tag, but then the usual tools 
--               don't let you search for that.
--
--       this happened to me in another test, when i was checking whether i could 
--       force players into a biped before the initial loadout camera, though in 
--       that case it stopped when that biped died. try modifying the script so 
--       that players aren't forced into a Monitor until they've spawned for the 
--       first time (and then be sure to test respawning)
--
--        - halo chess official only removes the monitor's weapons on spawn. check 
--          if constantly removing them is aggravating this weird problem
--
-- DONE:
--
--  - Piece selection (and the ability to re-select)
--
--  - Target square selection
--
--  - Check and checkmate
--
--  - Victory conditions: checkmate; killing king
--
--  - Edge-case: turn clock runs out after you've selected a piece and gained 
--    control
--

alias species_human = 0
alias species_elite = 1
alias opt_turn_clock = script_option[0]
alias species_black  = script_option[1]
alias species_white  = script_option[2]
alias opt_draw_rule  = script_option[3]

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
alias space_left    = object.object[0]
alias space_right   = object.object[1]
alias space_above   = object.object[2]
alias space_below   = object.object[3]
declare object.piece_type    = piece_type_none
declare object.is_valid_move = 0
declare object.threatened_by = 0
declare object.owner         = faction_none
--
-- Cell-extra data:
alias marker = object.object[0]
alias biped  = object.object[1] -- link extra to biped
alias extra  = object.object[1] -- link biped to extra
--
-- Board center data:
alias piece_deselect_boundary = object.object[0]

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
alias temp_plr_00     = global.player[1]
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
declare temp_tem_00 with network priority low

alias announced_game_start = player.number[0]
alias target_space         = player.object[0] -- piece the player is about to select (pending their timer)
alias selection_timer = player.timer[0]
declare player.selection_timer = 2
alias announce_start_timer = player.timer[1]
declare player.announce_start_timer = 5

alias faction = team.number[0]
alias enemy   = team.team[0]

alias ui_your_turn  = script_widget[0]
alias ui_in_check   = script_widget[1]
alias ui_bad_move   = script_widget[2]
alias ui_turn_clock = script_widget[3]
alias ui_endgame    = script_widget[3] -- multi-purpose widget

--
-- SCRIPT FLOW:
--
--  - Generate board
--  - Generate bipeds for spaces that are missing them
--  - Force players into Monitor bipeds
--  - Update UI during gameplay
--  - Handle picking a piece or picking a move
--     - Handle moving a piece to an unoccupied space
--        - If the player is double-moving a pawn: flag as vulnerable to capturing en passant
--        - If the player is killing a king: begin victory process
--        - End turn
--           = Skip this processing if we are in the victory process.
--           - Switch to next player
--           - Clear en passant vulnerability from new player's pawns
--           - Check whether new player is in check or checkmate
--              - If checkmate, begin the victory process.
--           - Manage 75-turn draw rule
--  - Handle piece death, if it occurs
--     - Handle moving a piece to an enemy-occupied space
--        - If the player is double-moving a pawn: flag as vulnerable to capturing en passant
--        - If the player is killing a king: begin victory process
--        - End turn
--           = Skip this processing if we are in the victory process.
--           - Switch to next player
--           - Clear en passant vulnerability from new player's pawns
--           - Check whether new player is in check or checkmate
--              - If checkmate, begin the victory process.
--           - Manage 75-turn draw rule
--     - If victory process is active, handle death of the loser's king
--  - Victory process, if active
--     - Manage piece (in)vulnerability
--     - Manage UI
--  - Draw checks
--     - 75-turn rule
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

for each player do -- announce game start
   current_player.announce_start_timer.set_rate(-100%)
   current_player.set_round_card_title("Control chess pieces to move.\nAchieve checkmate to win!")
   if current_player.announced_game_start == 0 and current_player.announce_start_timer.is_zero() then 
      send_incident(action_sack_game_start, current_player, no_player)
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
   extra.biped.set_waypoint_visibility(allies)
   --if cell.piece_type == piece_type_queen
   --or cell.piece_type == piece_type_king
   --then
   --   extra.biped.set_waypoint_visibility(everyone)
   --end
   --
   if winning_faction == faction_none then
      alias biped = temp_obj_01
      alias face  = temp_obj_02
      --
      if extra.biped != no_object and cell != selected_piece and not cell.shape_contains(extra.biped) then
         extra.biped.delete()
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
               -- TODO: set flag color by assigning its team
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

for each player do -- force players into Monitor bipeds
   alias biped   = temp_obj_00
   alias created = temp_obj_01
   if not current_player.biped.is_of_type(monitor) then
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
         ui_turn_clock.set_visibility(current_player, true)
         --
         ui_your_turn.set_visibility(current_player, false)
         ui_in_check.set_visibility(current_player, false)
         ui_bad_move.set_visibility(current_player, false)
         if temp_int_00 != 0 and current_player.team == active_team then
            ui_in_check.set_visibility(current_player, true)
         end
      end
      ui_your_turn.set_visibility(active_player, true)
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
for each player do game.show_message_to(active_player, none, "DEBUG: Beginning victory process for %s.", team_to_win) end
      --
      alias losing_king_alive = temp_int_00
      losing_king_alive = 0
      for each object with label "board_space" do
         if current_object.piece_type == piece_type_king and current_object.owner != winning_faction then
            losing_king_alive = 1
         end
      end
      if losing_king_alive == 0 then
for each player do game.show_message_to(current_player, none, "DEBUG: Losing king is dead; victory process is ending round.") end
         game.end_round()
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
      --
      previous_faction = active_faction
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
            for each player do
               game.show_message_to(current_player, none, "Checkmate! %s wins!", active_team.enemy)
            end
            temp_int_00 = faction_white
            if active_faction == faction_white then
               active_faction = faction_black
            end
            begin_victory() -- victory condition: checkmate
         end
      end
      --
      alias pawn_count = temp_int_00
      pawn_count = 0
      for each object with label "board_space" do
         if current_object.piece_type == piece_type_pawn then
            pawn_count += 1
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
   if target_space.piece_type == piece_type_king then -- king was killed
      temp_int_00 = selected_piece.owner
      begin_victory() -- victory condition: killed king
   end
   --
   target_space.piece_type = selected_piece.piece_type
   target_space.owner      = selected_piece.owner
   selected_piece.piece_type = piece_type_none
   selected_piece.owner      = faction_none
   selected_piece.en_passant_vulnerable = 0
   target_biped.delete()
   --
   end_turn()
end

if winning_faction == faction_none then -- handle picking a piece and handle making a move
   turn_clock.set_rate(-100%)
   if active_faction == faction_none then
      active_faction = faction_white
      active_team    = team_white
   end
   if active_player == no_player then
      for each player do
         if current_player.team == active_team then
            active_player = current_player
         end
      end
   end
   --
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
      for each object with label "board_space" do
         current_object.set_shape_visibility(no_one)
         if current_object.owner == active_faction and current_object.shape_contains(active_player.biped) then
            current_object.set_shape_visibility(everyone)
            active_player.target_space = current_object
            if prior_space != current_object then
               active_player.selection_timer.reset()
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
            global.object[0] = selected_piece
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
for each player do game.show_message_to(current_player, none, "DEBUG: Victory process: king biped killed. Ending round.") end
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

function do_endgame_ui_visibility()
   for each player do
      ui_your_turn.set_visibility(current_player, false)
      ui_in_check.set_visibility(current_player, false)
      ui_bad_move.set_visibility(current_player, false)
      -- ui_turn_clock and ui_endgame are the same widget
      ui_endgame.set_visibility(current_player, true)
   end
end

if winning_faction != faction_none then
   alias winning_biped_count = temp_int_00
   alias cell = temp_obj_00
   --
   winning_biped_count = 0
   for each object with label "board_space_extra" do
      current_object.biped.set_invincibility(0)
      cell = current_object.marker
      if current_object.biped != no_object and cell.owner == winning_faction then
         winning_biped_count += 1
         if not current_object.biped.is_out_of_bounds() then
            current_object.biped.set_invincibility(1)
         end
      end
   end
   if winning_biped_count == 0 then -- the winners lost all bipeds and can't kill the king
for each player do game.show_message_to(current_player, none, "DEBUG: No winning bipeds. Winner: %n", winning_faction) end
      game.end_round()
   end
   ui_endgame.set_text("%s won!", team_black)
   if winning_faction == faction_white then
      ui_endgame.set_text("%s won!", team_white)
   end
   do_endgame_ui_visibility()
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
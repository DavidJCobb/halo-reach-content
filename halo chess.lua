

--
-- HALO CHESS IMPLEMENTATION IDEAS
--
-- GOAL: Reimplement Halo Chess using user-defined functions, in order to allow 
-- for checkmate functionality -- removing the need to determine the winner by 
-- honor rules.
--

--
-- TODO: change label "board_space" to "_chess_space"
--
-- TODO: change label "board_space_extra" to "_chess_space_extra"
--
-- TODO: our handling for the king being in "check" is totally wrong. for one, 
--       you can resolve check by moving pieces other than the king: if the king 
--       is only under threat from one piece, then you can kill that piece; we 
--       don't allow you to move a non-king piece when you're in check, and that 
--       is wrong. for two: you can resolve checkmate in the same way, which 
--       means that our "checkmate" check REQUIRES us to not only check whether 
--       the king himself has no available moves, but also whether the enemy 
--       pieces that threaten the king are all themselves threatened by a piece 
--       allied to the king. (for an especially devilish example of both issues, 
--       see wikipedia's "en passant" article, "unusual examples" section; the 
--       first example is a good case.)
--
--       this isn't impossible to fix.
--
--       first: the check(mate) testing needs to set up the following information:
--
--        - Is the king currently under threat?
--
--        - Can the king move to any spaces that are not currently under threat? 
--          (A space is considered "under threat" if an enemy piece can move to 
--          it. If an enemy is standing on the space, but another enemy would be 
--          able to move there were that not the case, then the king cannot 
--          escape check by killing the former enemy and capturing its space, so 
--          the space is still "under threat.")
--
--           - We already flag all spaces in range of the king as (is_king_move) 
--             before testing the king's enemies, so we can handle that caveat 
--             without substantial changes to the piece move logic: for any 
--             piece: if a space you ordinarily would be able to move to is 
--             occupied by an ally (i.e. king's enemy), then:
--
--              - If the space is not flagged as a king move, then don't flag 
--                it as a valid move.
--
--              - For contiguous pieces (i.e. not knights), stop testing this 
--                direction either way.
--
--             So given R = Rook, K = king, P = pawn, lowercase = white, upper-
--             case = black:
--
--                |R    Rk  | Pieces
--                | XXXX X  | Valid black moves
--                | XXXXXX  | Spaces under threat by black
--
--        - Which enemy pieces are currently threatening the player?
--
--           - Probably best stored as part of a "checkmate_flags" member:
--
--             0x0001 = This piece is threatening the enemy king
--             0x0002 = Enemy king can't escape check by killing this piece
--
--       Once we have that information: if the king's owner is in check, then 
--       we need to identify all valid moves for all of their pieces, and then 
--       determine:
--
--        - If the king is under threat by only one enemy, can the player kill 
--          that enemy? (This includes killing the enemy with the king, but only 
--          if the enemy's own space is not accessible to another enemy -- thus 
--          the caveat to "spaces not currently under threat" above.)
--
--           - So: only allow the player to kill that enemy with the king if the 
--             space isn't flagged as a valid move for enemies. You can't move a 
--             piece to a space occupied by another of your pieces, so if the 
--             king is under threat by an enemy space that is also flagged as 
--             enemy-accessible, then it's because having the king capture that 
--             enemy space would leave the king in check by yet another enemy.
--
--        - If the king is under threat by only one enemy, can the player block 
--          that enemy from reaching the king (i.e. can the player interpose a 
--          piece between the enemy and the king, if the enemy is not a knight)?
--
--       If the king is under threat, neither of those conditions are met, and 
--       earlier testing determined that the king cannot be moved out of danger, 
--       then we have a checkmate.
--
--       In all honesty I should probably prototype this in JavaScript before 
--       trying to implement it in Megalo. Easier to test that way.
--
--       As for handling a non-check checkmate? Just brute-force it. When the 
--       player attempts a move, re-run the full checkmate test. if it fails, 
--       then reject the move.
--
-- TODO: pawn initial double-move
--
-- TODO: pawn capture en passant
--
-- TODO: pawn promotion
--
-- TODO: if a team has no players, skip its turn, optionally with a short delay 
--       and a UI message
--
-- TODO: short delay between checkmate and victory
--
-- TODO: when forcing players into a Monitor, check if they have a biped and if 
--       so, place the Monitor as close to that biped's position as possible 
--       before deleting it (unless the biped is out of bounds)
--
-- TODO: walking too far off the board while in control of a piece should abandon 
--       control of the piece, allowing you to pick a different one
--
-- TODO: anchor pieces to their squares when they are not under player control 
--       and when is_valid_move == 0
--
-- TODO: pieces that are out of bounds should be rendered non-invincible, both so 
--       that pieces under player control can get softkilled and in case a piece 
--       is somehow moved
--
-- TODO: properly manage waypoint visibility for pieces
--
-- TODO: if multiple players are on a team, they should take turns making moves 
--       for that team; turn order for players should be consistent
--
-- DONE:
--
--  - Piece selection
--
--  - Target square selection
--
--  - Check and checkmate
--
--  - Edge-case: turn clock runs out after you've selected a piece and gained 
--    control
--

alias species_black = script_option[1]
alias species_white = script_option[2]
alias species_human = 0
alias species_elite = 1
alias opt_turn_clock = script_option[0]

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
alias is_king_move  = object.number[4] -- used to check whether a king is checkmated by a pawn
alias owner         = object.number[5]
alias space_left    = object.object[0]
alias space_right   = object.object[1]
alias space_above   = object.object[2]
alias space_below   = object.object[3]
declare object.piece_type    = piece_type_none
declare object.is_valid_move = 0
declare object.is_king_move  = 0
declare object.owner         = faction_none
--
-- Cell-extra data:
alias marker = object.object[0]
alias biped  = object.object[1] -- link extra to biped
alias extra  = object.object[1] -- link biped to extra

-- Global state
alias temp_int_00     = global.number[0]
alias temp_int_01     = global.number[1]
alias temp_int_02     = global.number[2]
alias board_created   = global.number[3]
alias active_faction  = global.number[4] -- faction currently making a move
declare active_faction = faction_none
alias turn_flags      = global.number[5]
alias temp_int_03     = global.number[6]
--
alias turn_flag_in_check = 0x0001
--
alias temp_obj_00     = global.object[0]
alias temp_obj_01     = global.object[1]
alias temp_obj_02     = global.object[2]
alias temp_obj_03     = global.object[3]
alias selected_piece  = global.object[4] -- piece that the player is (about to be) controlling
alias board_center    = global.object[5]
alias active_player   = global.player[0] -- player currently making a move
alias temp_plr_00     = global.player[1]
alias temp_tem_00     = global.team[3]
alias turn_clock      = global.timer[0]
declare turn_clock = opt_turn_clock

alias announced_game_start = player.number[0]
alias target_space    = player.object[0] -- piece the player is about to select (pending their timer)
alias selection_timer = player.timer[0]
declare player.selection_timer = 2
alias announce_start_timer = player.timer[1]
declare player.announce_start_timer = 5

alias enemy = team.team[0]

alias ui_your_turn  = script_widget[0]
alias ui_in_check   = script_widget[1]
alias ui_bad_move   = script_widget[2]
alias ui_turn_clock = script_widget[3]

on init: do
   team_black = team[0]
   team_white = team[1]
   team_black.enemy = team_white
   team_white.enemy = team_black
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
   alias biped = temp_obj_01
   alias face  = temp_obj_02
   --
   if extra.biped == no_object then
      cell = extra.marker
      if cell.piece_type != piece_type_none then
         alias species = temp_int_00
         --
         species = species_black
         if cell.owner == faction_white then
            species = species_white
         end
         --
         biped = no_object
         function setup_biped()
            biped.is_script_created = 1
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

for each player do -- force players into Monitor bipeds
   alias biped   = temp_obj_00
   alias created = temp_obj_01
   if not current_player.biped.is_of_type(monitor) then
      biped = current_player.biped
      if biped.is_script_created == 0 then
         created = board_center.place_at_me(monitor, none, none, 0, 0, 0, none)
         created.attach_to(board_center, 0, 0, 20, relative)
         created.detach()
         created.remove_weapon(secondary, true)
         created.remove_weapon(primary,   true)
         created.copy_rotation_from(biped, true)
         current_player.set_biped(created)
         biped.delete()
      end
   end
end
do -- UI
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
   -- In order to check whether the king is checkmated by a pawn, you will need 
   -- to set (object.is_king_move) on all of the spaces that the king can move 
   -- to before calling this function. If you are running checks for any other 
   -- reason (e.g. "is the king currently in check" or "can the player move 
   -- their piece here"), then you must set that variable to 0.
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
   alias x_diff        = temp_int_00
   alias y_diff        = temp_int_01
   --
   function bishop_check()
      target_space = current_piece
      function upperleft()
         target_space = target_space.space_left
         target_space = target_space.space_above
         if target_space != no_object and target_space.piece_type == piece_type_none then
            target_space.is_valid_move = 1
            upperleft()
         end
      end
      upperleft()
      --
      target_space = current_piece
      function upperright()
         target_space = target_space.space_right
         target_space = target_space.space_above
         if target_space != no_object and target_space.piece_type == piece_type_none then
            target_space.is_valid_move = 1
            upperright()
         end
      end
      upperright()
      --
      target_space = current_piece
      function lowerleft()
         target_space = target_space.space_left
         target_space = target_space.space_below
         if target_space != no_object and target_space.piece_type == piece_type_none then
            target_space.is_valid_move = 1
            lowerleft()
         end
      end
      lowerleft()
      --
      target_space = current_piece
      function lowerright()
         target_space = target_space.space_right
         target_space = target_space.space_below
         if target_space != no_object and target_space.piece_type == piece_type_none then
            target_space.is_valid_move = 1
            lowerright()
         end
      end
      lowerright()
   end
   function rook_check()
      target_space = current_piece
      function left()
         target_space = target_space.space_left
         if target_space != no_object and target_space.piece_type == piece_type_none then
            target_space.is_valid_move = 1
            left()
         end
      end
      left()
      --
      target_space = current_piece
      function right()
         target_space = target_space.space_right
         if target_space != no_object and target_space.piece_type == piece_type_none then
            target_space.is_valid_move = 1
            right()
         end
      end
      right()
      --
      target_space = current_piece
      function up()
         target_space = target_space.space_above
         if target_space != no_object and target_space.piece_type == piece_type_none then
            target_space.is_valid_move = 1
            up()
         end
      end
      up()
      --
      target_space = current_piece
      function down()
         target_space = target_space.space_below
         if target_space != no_object and target_space.piece_type == piece_type_none then
            target_space.is_valid_move = 1
            down()
         end
      end
      down()
   end
   if current_piece.piece_type == piece_type_bishop
   or current_piece.piece_type == piece_type_queen
   then
      bishop_check()
   end
   if current_piece.piece_type == piece_type_knight then
      for each object with label "board_space" do
         x_diff  = current_piece.coord_x
         x_diff -= current_object.coord_x
         y_diff  = current_piece.coord_y
         y_diff -= current_object.coord_y
         x_diff *= y_diff
         if x_diff == 2 or x_diff == -2 then -- (2 * 1) or (-2 * 1) or (2 * -1) or (-2 * -1)
            current_object.is_valid_move = 1
         end
      end
   end
   if current_piece.piece_type == piece_type_rook
   or current_piece.piece_type == piece_type_queen
   then
      rook_check()
   end
   if current_piece.piece_type == piece_type_king then
      function _set_if() -- if we inlined this, each copy would be a separate trigger. since they're all identical, let's just make it a function so we're not compiling tons of duplicate data
         if target_space.piece_type == piece_type_none then
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
      target_space  = current_piece.space_above
      temporary_obj = current_piece.space_above
      if current_piece.owner == faction_black then -- black starts north and moves south
         target_space  = current_piece.space_below
         temporary_obj = target_space.space_below
      end
      if target_space.piece_type == piece_type_none then
         target_space.is_valid_move = 1
      end
      --
      -- TODO: Check whether double-forward movement to space (temporary_obj) 
      -- is possible.
      --
      
      --
      -- Check whether diagonal capture is possible.
      --
      function _check_diagonal() -- if we inlined this, each copy would be a separate trigger. since they're all identical, let's just make it a function so we're not compiling tons of duplicate data
         temporary_obj.is_valid_move |= temporary_obj.is_king_move
         if  temporary_obj.piece_type != piece_type_none
         and temporary_obj.owner != current_piece.owner
         then
            temporary_obj.is_valid_move = 1
         end
      end
      temporary_obj = target_space.space_left
      _check_diagonal()
      temporary_obj = target_space.space_right
      _check_diagonal()
      --
      -- TODO: If the player actually moves their pawn diagonally, then we need 
      -- to check for a capture en passant. If an enemy pawn uses its initial 
      -- move to travel two spaces forward and lands next to your pawn, then 
      -- you can (on the very next turn only) move your pawn diagonally behind 
      -- the enemy pawn *and* capture that enemy pawn. This is called "capturing 
      -- en passant," or "in passing."
      --
      -- We'll also have to handle pawn promotion at the time that a pawn is 
      -- moved to the end of the board. The ONLY limitation on pawn promotion 
      -- is that a pawn cannot be promoted to a king or to a pawn (i.e. you MUST 
      -- promote the pawn; you cannot leave it unpromoted and immobilized).
      --
   end
end

function is_king_in_check()
   alias king = temp_obj_03 -- which king to check; must be set by the caller
   alias king_in_checkmate = temp_int_00 -- out
   alias king_in_check     = temp_int_01 -- out
   --
   king_in_checkmate = 0
   king_in_check     = 0
   if king != no_object then
      for each object with label "board_space" do
         current_object.is_valid_move = 0
         current_object.is_king_move  = 0
      end
      --
      -- Flag every space within reach of the king as a "king move space," so that 
      -- enemy pawn movement checks treat these spaces the same way they would an 
      -- occupied space (i.e. the pawn tests as being able to diagonally capture 
      -- onto these spaces). Don't bother checking whether the king can actually 
      -- move to these spaces (i.e. whether they are unoccupied). Nothing else 
      -- needs us to check that from here.
      --
      alias temporary_obj = temp_obj_01
      temporary_obj = king.space_left
      temporary_obj.is_king_move = 1
      temporary_obj = temporary_obj.space_above -- upper-left
      temporary_obj.is_king_move = 1
      temporary_obj = king.space_right
      temporary_obj.is_king_move = 1
      temporary_obj = temporary_obj.space_below -- lower-right
      temporary_obj.is_king_move = 1
      temporary_obj = king.space_above
      temporary_obj.is_king_move = 1
      temporary_obj = temporary_obj.space_right -- upper-right
      temporary_obj.is_king_move = 1
      temporary_obj = king.space_below
      temporary_obj.is_king_move = 1
      temporary_obj = temporary_obj.space_left -- lower-left
      temporary_obj.is_king_move = 1
      --
      for each object with label "board_space" do
         if current_object.piece_type != piece_type_none and current_object.owner != king.owner then
            global.object[0] = current_object -- parameter for next function call
            check_valid_move()
         end
      end
      --
      -- Now that all of the data we need is set up, we can check whether the king 
      -- is in check, and whether they're in checkmate. We'll consider them to be 
      -- in checkmate by default, and free them from checkmate if the king has any 
      -- legal moves that are not vulnerable to enemy pieces. In addition to being 
      -- more efficient, this approach also means that if the king has no legal 
      -- moves (e.g. they are totally boxed in by adjacent pieces), we'll properly 
      -- flag them as being in checkmate.
      --
      king_in_check     = king.is_valid_move -- can the enemy move to where the king is?
      king_in_checkmate = king_in_check
      for each object with label "board_space" do
         if  current_object.is_king_move  == 1 -- this space is within reach of the king we're testing
         and current_object.is_valid_move == 0 -- no enemy can move here
         and current_object.piece_type == piece_type_none -- no one is standing here
         then
            king_in_checkmate = 0
         end
      end
   end
end

function on_move_made()
   alias previous_faction = temp_int_00
   --
   previous_faction = active_faction
   active_faction  = faction_white
   active_team     = team_white
   if previous_faction == faction_white then
      active_faction = faction_black
      active_team    = team_black
   end
   temp_obj_00 = active_player.biped
   if temp_obj_00.is_script_created != 0 then -- turn clock ran out while the active player had control of a biped
      temp_obj_00.delete()
   end
   active_player.target_space = no_object
   active_player = no_player
   --
   selected_piece = no_object
   turn_clock.reset()
   turn_flags = 0
   temp_obj_03 = no_object
   for each object with label "board_space" do
      if current_object.piece_type == piece_type_king and current_object.owner == active_faction then
         temp_obj_03 = current_object
      end
   end
   is_king_in_check() -- check if the previously-made move has put this player in check
   if temp_int_01 != 0 then -- active faction is in check!
      turn_flags |= turn_flag_in_check
      if temp_int_00 != 0 then -- active faction is in checkmate!
         active_team.enemy.score += 1
         game.end_round()
      end
   end
end

do
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
      temp_int_00  = turn_flags
      temp_int_00 &= turn_flag_in_check
      if temp_int_00 == 0 then
         --
         -- The player is not in check. Allow them to select any piece that they control.
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
      else
         --
         -- The player is in check. Only allow them to select their king.
         --
         for each object with label "board_space" do
            current_object.set_shape_visibility(no_one)
            if  current_object.owner == active_faction
            and current_object.piece_type == piece_type_king
            then
               current_object.set_shape_visibility(everyone)
               active_player.target_space = current_object
               if current_object.shape_contains(active_player.biped) and prior_space != current_object then
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
               current_object.is_king_move  = 0
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
            cell = active_player.target_space
            cell.piece_type = selected_piece.piece_type
            cell.owner      = selected_piece.owner
            selected_piece.piece_type = piece_type_none
            selected_piece.owner      = faction_none
            --
            extra.biped.delete()
            on_move_made()
         end
      end
      --
      -- TODO: If the current player runs their piece-biped out of the board, deselect the 
      -- piece so they can change their choice.
      --
   end
   if turn_clock.is_zero() and opt_turn_clock > 0 then
      on_move_made()
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
      if  killer_object.is_script_created == 1
      and killer_object.marker != no_object
      and selected_piece != no_object
      then -- active player tried to capture this square
         if  killed_object.owner != selected_piece.owner
         and cell.is_valid_move == 1
         then -- active player is allowed to capture this square
            cell.piece_type = selected_piece.piece_type
            cell.owner      = selected_piece.owner
            selected_piece.piece_type = piece_type_none
            selected_piece.owner      = faction_none
            --
            killer_object.delete()
            on_move_made()
         end
      end
   end
end

do -- check for draw conditions
   --
   -- TODO: Check for the 75-move rule: if 75 moves pass without there being pawns on 
   -- the board, and without either player capturing an enemy piece, then the game will 
   -- automatically end in a draw. Some places allow players to manually request a draw 
   -- at every 50-move threshold; I don't want to code in a mechanism for requesting a 
   -- draw, but we can make the move threshold for an automatic draw a script_option.
   --
   
   --
   -- Check for insufficient material condition 1: one side only has a king, and 
   -- the other side only has a king and one knight OR a king and one bishop.
   --
   alias knights_and_bishops = global.number[0]
   alias any_other_pieces    = global.number[1]
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
         --
         -- TODO: The insufficient material condition has been met. It is impossible 
         -- for either team to checkmate the other, so the game should end on a draw.
         --
         game.end_round()
      end
      --
      -- TODO: Check for insufficient material condition 2: each side has one king and one 
      -- bishop, and the bishops are both on the same color. We've already confirmed that 
      -- the only pieces in play are kings, knights, and bishops.
      --
   end
end
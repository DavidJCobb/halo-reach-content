# halo-reach-content
 Repo for map and game variants I've modded

## Table of contents
* [Minesweeper](#minesweeper)
* [Race+](#race-plus)
* [Halo Chess+](#halo-chess-plus)

## Gametypes

### Minesweeper <a name="minesweeper"/>
[In-development footage](https://www.youtube.com/watch?v=-sP8ElrIdek)

Spawns a board with one scaled-up Fusion Coil per board cell. Shoot a coil to interact with the cell. The action taken depends on your weapon; Magnums uncover spaces while DMRs toggle flags. Minesweeper rules are fully implemented with the exception of guaranteeing that the first selected space is not a mine. All mines are randomly placed. Scoring options allow players to configure rewards or penalties for winning, losing, for each correctly-placed flag, and for each uncovered board cell.

Setup requires the placement of seven objects in Forge. The first should be a Hill Marker with the Forge label `BOARD_CENTER`. The other six should be Dice with the Forge label `MINESWEEP_DICE` and Spawn Sequences 1 through 6. Each dice needs to be rotated as described below. (The dice are needed because Megalo cannot easily rotate objects, but it can copy one object's rotation onto another.)

The 3D model for a Hill Marker resembles a Respawn Point that has been scaled down, with an inward-pointing arrow overtop of it. Respawn Points and Hill Markers both have a "forward" direction indicated by the pointed tip of their base, while a Hill Marker's larger arrow indicates the "down" direction. For a vertical board, your `BOARD_CENTER` Hill Marker should have its "forward" direction pointing down, and its "up" direction pointing toward the player. (The board's rotation doesn't technically matter &mdash; an upside-down board won't break the game &mdash; but board cells are numbered starting from the top-left, and cell numbers are displayed in the kill feed if the player tries to uncover a cell that they have flagged.)

The six dice need to be rotated such that specific numbers face out toward specific board-relative(!) directions as listed in the table below. A PNG file is included in this repo, showing the rotations needed for a vertical board.

| Spawn sequence | Upward face | Backward face |
| - | - | - |
| 1 | 1 | 5 |
| 2 | 2 | 1 |
| 3 | 3 | 1 |
| 4 | 4 | 1 |
| 5 | 5 | 1 |
| 6 | 6 | 3 |

Forgers should be careful not to design maps in such a way that the board's Fusion Coils can be destroyed by any means other than the active player firing a bullet; Megalo does not make it possible to identify who or what killed a Fusion Coil, so the gametype assumes that any Fusion Coil's destruction is a deliberate action taken by the active player.

Technical considerations for the gametype script include:

* There is no way to detect who is responsible for a Fusion Coil's destruction. Fusion Coils do not fire the "on object death" even when destroyed; we can only check for the cessation of a coil's existence.

* A Fusion Coil's base is 0.25 x 0.25 Forge units, so a Fusion Coil must be scaled up 400% to fill a full board space. Scaling affects bullet and projectile impacts (including sticky grenades), but not splash damage, and by happy coincidence the Fusion Coils are each far enough away from each other to be totally unaffected by each other's explosions. If the mechanics behind object scaling ever change, this gametype will no longer function.

* The only way to display a board cell's number of adjacent mines is by using dice. Waypoints are not viable because the game can only display up to 18 of them at a time. Shape boundaries cannot be used to draw numbers upon the board because the game can only display up to 64 shape boundaries at a time. Spawning objects to physically draw numbers is not viable because the game's lighting malfunctions dramatically when 640 objects are in the field of view at a time (even if the player's vision of them is obstructed); there are 81 board spaces and 10 mines, so a perfect arrangement of mines would leave 80 tiles in need of drawn numbers; given the number of objects needed just to set up the board, any plan which could require more than five additional objects per board cell would easily blow past the lighting limit.

As of this writing, this variant is not available for download. I want to try to add team support to the script or, failing that, hide the "Teams Enabled" option from the in-game menus. I'd also like to design the gametype so that in an FFA game, all players get an equal number of turns on the board (provided the round limit is high enough for everyone to play).

### Race+ <a name="race-plus"/>
One of a set of "vanilla plus" gametypes I wish to make. Race+ adds the following options:

* New vehicle options: Sabre, Civilian, or None. The "Civilian" option selects a random civilian vehicle for each round from the following set: electric cart; forklift; ONI van; pickup truck; semi truck. Most of these vehicles are quite slow and not actually enjoyable to race with, but the novelty factor should earn a chuckle or two.

* New script options to control landmine behavior. In the vanilla Race variant, driving within 10 meters of a landmine will arm it, and it will detonate on its own after a delay even if it isn't touched. Race+ allows you to control the distance (or disable the behavior entirely) and the delay.

As of this writing, this variant is not available for download. There are issues I want to fix, namely surrounding checkpoints and landmines.

When the game checks whether an object is inside of a shape boundary, it only checks the object's origin (also called a "pivot point" in some game engines), which usually lies at the object's center of gravity or center of mass. You can test this yourself: load up a Race variant, slowly edge a Warthog into a checkpoint, and take note of exactly when you register as entering the checkpoint. The Sabre and most civilian vehicles have origins that are too far off the ground for the vehicles to register as entering relatively small checkpoints; Hemorrhage, for example, is unplayable for these vehicles.

The fix for this would be for the gametype to spawn invisible Hill Markers (hereafter: "nodes") and attach them to the vehicles at different points, e.g. one on each corner of a Warthog's "footprint." Checkpoint and landmine tests would check not only the vehicle itself, but also all of the vehicle's nodes. This would allow large vehicles (and *huge* ones, like Sabres) to properly test against checkpoints.

### Halo Chess+ <a name="halo-chess-plus"/>
Planned. A small amount of code has been written, but not tested.

Bungie's original Halo Chess is not Matchmaking-suitable in part because it relies on honor rules. The gametype pushes the game variant file format to the limit; the file uses almost all of the available space for script code, and likely doesn't have enough room for a checkmate implementation. However, it's worth noting the limitations that Halo Chess was built under.

"Megalo" can refer to three things: the scripting *engine* that Bungie designed for Halo: Reach; the scripting *[bytecode](https://en.wikipedia.org/wiki/Bytecode)* that Bungie designed the engine to interpret; and the scripting *language* that Bungie designed to compile to that bytecode. The difference between these three things is important because the bytecode is actually capable of more than the language itself is capable of.

The Megalo bytecode is known thanks to reverse-engineering efforts by kornman00, but nobody outside of Bungie and 343 Industries has ever seen the Megalo language itself. This means that in order to write Megalo scripts, we either have to hand-write data that corresponds 1:1 with the bytecode (the approach required by kornman00's KSoft.Tool), or design our own scripting language that compiles to that same bytecode &mdash; and crucially, if the bytecode itself doesn't have the same limitations as Bungie's language, then our designed language doesn't need to adhere to those limitations either.

Many years ago, Bungie held a Megalo Q&A. The original has been lost, but pieces of it have been archived elsewhere. Per Bungie, the official Megalo language allows one to write a single program which is executed in its entirety; there are no function calls, gotos, or similar constructs. However, the Megalo bytecode allows for function calls via the same mechanism as nested blocks of code; every nested block of code is, in effect, an independent unit that is called, and you can compile such a unit to be called from multiple places. This allows for user-defined functions and recursion and, with those, a radically different approach to control flow.

Bungie's original Halo Chess code is hard to decipher even when put into the Megalo language that I personally designed. It's a very complicated script, and admittedly I've only looked at it whenever I needed specific ideas from it. From what little I've been able to grasp when glancing at the code, the author set a single globally-scoped number to serve as a control flow enum; "functions" are implemented as if-statements which check the value of that number, with a task that requires multiple function calls essentially being performed over multiple executions of the full script. Repeating a task requires either multiple full executions of the script (with the variables and other baggage needed to track state) or multiple repetitions of the code for that task.

With function calls and especially with recursion, things become easier and simpler: a task can be repeated an arbitrary number of times within a single execution of the script, with minimal boilerplate and no need to persist (across multiple executions of the script) any state related to the task itself. Moreover, recursion enables some simpler approaches to tracking which spaces a piece can move to. For example: if we link each board space to its cardinal neighbors (up, down, left, right) via the four available object.object variables, then we can check which spaces a Rook can move to using four recursive functions &mdash; one for each direction. If we wrap those four recursive functions in a larger function, then we can use that larger function for both Rooks and Queens. The same approach, with slightly different code, can be taken for Bishops and Queens. Moreover, the *entire process* of tracking what spaces a piece can be moved to can be placed inside of a function, and that function can then be used to handle: allowing a player to move their piece; checking whether a king is in check; and checking whether a king is in checkmate:

* We give every board space a number variable indicating whether it is a "valid move." We make sure that our function to check the available moves for a piece will only set that variable to 1, and never reset it to 0.

* When a player picks a piece to move, we reset that variable on all board spaces. Then, we call our function to check the available moves for the current piece; that function will set the "valid move" variable to 1 on every space that the player can move their piece to.

* When we want to detect whether a king is in check, or in checkmate, we reset the "valid move" variable on all board spaces. We can then take our function to check a piece's available moves, and call that on *every* enemy piece. We can then check whether the king's current space is a "valid move" (check), and whether all of the spaces that a king can move to are "valid moves" (checkmate). (Some extra measures are needed to check for pawns checkmating a king, but these are trivial. It's also more efficient to check whether there exist any spaces that the king can move to and that are not "valid moves," and as a bonus that lets us properly handle a king that has been immobilized by adjacent pieces.)

Which brings me to my point: I might &mdash; I *might* &mdash; be able to build a Matchmaking-suitable, non-honor-rule Halo Chess+.
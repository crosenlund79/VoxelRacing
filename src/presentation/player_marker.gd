class_name PlayerMarker
extends Node
## P1 readability: which cars are controlled on this computer, and in which
## player colour (gold for Player 1 / you, blue for Player 2). VoxelStage
## floats a little glowing voxel chevron above each of them, so a player finds
## their own car in a pack or after a respawn. Read-only.

## racer id -> colour; only these cars are marked.
var marked: Dictionary = {}


func setup(_cars: Array[Car]) -> void:
	pass


func set_marked(colors: Dictionary) -> void:
	marked = colors

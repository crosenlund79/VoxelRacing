class_name PlayerMarker
extends Node2D
## P1 readability: a small chevron floating above each locally controlled car
## (gold for Player 1 / you, blue for Player 2), so a player finds their own
## car in a pack or after a respawn. Drawn procedurally (no sprite asset).
## Read-only: it follows the cars and never changes the race.

const OFFSET := Vector2(0, -34)
const SIZE := 8.0
const OUTLINE := Color("2a2220")

## racer id -> colour; only these cars are marked.
var marked: Dictionary = {}
var _cars: Array[Car] = []


func setup(cars: Array[Car]) -> void:
	_cars = cars
	z_index = 10  # above both road levels (J2), so you find your car under a bridge too


func set_marked(colors: Dictionary) -> void:
	marked = colors
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	for id in marked:
		if id < 0 or id >= _cars.size():
			continue
		var c := _cars[id]
		if not c.visible:
			continue
		var tip := c.global_position + OFFSET
		var pts := PackedVector2Array([tip, tip + Vector2(-SIZE, -SIZE * 1.1), tip + Vector2(SIZE, -SIZE * 1.1)])
		draw_colored_polygon(pts, Color(marked[id], 0.92))
		pts.append(tip)
		draw_polyline(pts, Color(OUTLINE, 0.85), 2.0, true)

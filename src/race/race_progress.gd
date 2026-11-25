class_name RaceProgress
extends RefCounted
## Converts a car's world position into continuous distance along the track
## (unwrapped across laps), used for live race positions and the AI.

var path: ClosedPath
var distance := 0.0
var lateral := 0.0
var index := -1
var _last_s := 0.0


func _init(p_path: ClosedPath) -> void:
	path = p_path


## Starts tracking from a grid position. Cars behind the start/finish line
## (the second half of the lap) start with negative distance.
func reset(pos: Vector2) -> void:
	var p := path.project(pos)
	index = p.index
	lateral = p.lateral
	_last_s = p.distance
	distance = _last_s - path.length if _last_s > path.length * 0.5 else _last_s


func update(pos: Vector2) -> void:
	var p := path.project(pos, index)
	index = p.index
	lateral = p.lateral
	var delta := wrapf(p.distance - _last_s, -path.length * 0.5, path.length * 0.5)
	_last_s = p.distance
	distance += delta

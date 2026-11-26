class_name JumpView
extends Node2D
## J3 jump sounds: the thud of a landing and the crash of a fall into the gap.
## The flight itself is real height in the voxel world (VoxelStage), the
## dust and smoke are voxel puffs (VoxelRaceFx). Reads JumpWorld state and
## never changes the race.

## Tint of a car that fell into the gap (VoxelStage darkens its model).
const FALLEN_TINT := Color(0.3, 0.27, 0.27)

var enabled := true
var _jumps: JumpWorld
var _cars: Array[Car] = []
var _audio: RaceAudio
var _was_air := PackedByteArray()
var _was_down := PackedByteArray()


func setup(jumps: JumpWorld, cars: Array[Car], _resolver: AssetResolver, audio: RaceAudio) -> void:
	_jumps = jumps
	_cars = cars
	_audio = audio
	_was_air.resize(cars.size())
	_was_down.resize(cars.size())


func _process__perf(_delta: float) -> void:
	for i in _cars.size():
		var c := _cars[i]
		var air := _jumps.is_airborne(i)
		var down := _jumps.is_down(i)
		if _audio != null and enabled:
			if not air and _was_air[i] == 1 and not down:
				_audio.play_at("vehicles/impact_wall", c.global_position)
			if down and _was_down[i] == 0:
				_audio.play_at("weapons/explosion", c.global_position)
		_was_air[i] = 1 if air else 0
		_was_down[i] = 1 if down else 0


## DIAGNOSTIC probe (Performance Investigation 001)
func _process(_delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process__perf(_delta)
	PerfProbe.add(&"legacy2d.jump_view", __t)

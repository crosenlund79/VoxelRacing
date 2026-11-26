class_name DamageView
extends Node2D
## Vehicle condition sounds: the crash when a car is retired by damage (DNF).
## What damage looks like (bodywork breaking off voxel by voxel, smoke, the
## explosion and the burnt hull) is VoxelRaceFx. Reads DamageWorld; never
## changes the race.

var enabled := true
var _damage: DamageWorld
var _cars: Array[Car] = []
var _audio: RaceAudio
var _was_retired := PackedByteArray()


func setup(damage: DamageWorld, cars: Array[Car], _resolver: AssetResolver, audio: RaceAudio) -> void:
	_damage = damage
	_cars = cars
	_audio = audio
	_was_retired.resize(cars.size())


func _process__perf(_delta: float) -> void:
	for i in _cars.size():
		var retired := _damage.is_retired(i)
		if retired and _was_retired[i] == 0 and _cars[i].visible and enabled and _audio != null:
			_audio.play_at("weapons/explosion", _cars[i].global_position)
		_was_retired[i] = 1 if retired else 0


## DIAGNOSTIC probe (Performance Investigation 001)
func _process(_delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process__perf(_delta)
	PerfProbe.add(&"legacy2d.damage_view", __t)

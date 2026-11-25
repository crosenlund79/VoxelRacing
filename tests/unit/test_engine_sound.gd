extends GutTest
## P2 Stage 1: engine sound model (presentation only). Pitch stays in a narrow,
## deep range and flattens near top speed instead of droning at 2.6x; load
## and braking colour it; the load layer is silent when cruising.

var _p: EngineSoundParams


func before_each() -> void:
	_p = load("res://src/audio/default_engine_sound.tres")


func _pitch(ratio: float, load := 0.0, brake := 0.0) -> float:
	return RaceAudio.engine_targets(_p, ratio, load, brake, 0.0).pitch


func test_pitch_range_is_deep_and_bounded() -> void:
	assert_almost_eq(_pitch(0.0), _p.pitch_idle, 0.001)
	assert_almost_eq(_pitch(1.0), _p.pitch_top, 0.001)
	assert_lt(_pitch(1.2, 1.0), 1.5, "never climbs towards the old 2.6x drone, even over top speed under load")
	for t in [0.0, 1.3, 2.9, 7.7]:
		var p: float = RaceAudio.engine_targets(_p, 1.0, 0.0, 0.0, t).pitch
		assert_almost_eq(p, _p.pitch_top, _p.pitch_top * _p.drift_amount + 0.0001, "cruise drift stays tiny")


func test_pitch_rises_with_speed_and_flattens_near_the_top() -> void:
	var last := 0.0
	for k in 11:
		var p := _pitch(k / 10.0)
		assert_gt(p, last, "monotonic")
		last = p
	assert_lt(_pitch(1.0) - _pitch(0.8), _pitch(0.2) - _pitch(0.0), "flatter near top speed")


func test_load_and_braking_colour_the_pitch_and_layer() -> void:
	assert_gt(_pitch(0.5, 1.0), _pitch(0.5), "working engine a little higher")
	assert_lt(_pitch(0.5, 0.0, 1.0), _pitch(0.5), "dips when braking")
	var cruise: Dictionary = RaceAudio.engine_targets(_p, 1.0, 0.0, 0.0, 0.0)
	var working: Dictionary = RaceAudio.engine_targets(_p, 0.5, 1.0, 0.0, 0.0)
	assert_almost_eq(working.load_db, _p.load_volume_db, 0.01)
	assert_lt(cruise.load_db, -50.0, "load layer silent when cruising")
	assert_gt(cruise.base_db, RaceAudio.engine_targets(_p, 0.0, 0.0, 0.0, 0.0).base_db, "foundation fuller at speed")

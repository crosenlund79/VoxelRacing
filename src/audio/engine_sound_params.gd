class_name EngineSoundParams
extends Resource
## Engine sound tuning (P2): a deep foundation loop plus a responsive load
## layer, per audible car. Presentation only: read from car motion, never
## written back. Defaults in default_engine_sound.tres; all values are taste.

@export_group("Foundation pitch")
## Foundation pitch at standstill / at top speed (1.0 = the loop as recorded).
## The old engine climbed to 2.6x and droned there at cruising speed.
@export var pitch_idle := 0.78
@export var pitch_top := 1.3
## < 1: pitch rises early in the speed range and flattens near top speed.
@export var pitch_curve := 0.75
## Extra pitch while the engine is working (accelerating), dip while braking.
@export var load_pitch := 0.06
@export var brake_pitch := -0.07
## Very slow, tiny pitch drift so long cruising is not a fixed tone.
@export var drift_amount := 0.007
@export var drift_hz := 0.27

@export_group("Volumes (dB, before the Engine bus)")
@export var volume_idle_db := -6.0
@export var volume_top_db := -1.0
## Load layer at full acceleration; it falls silent when cruising.
@export var load_volume_db := -3.0
## Rivals a little quieter than the car(s) you drive.
@export var rival_offset_db := -3.0

@export_group("Response")
## Smoothing time constants (seconds) for pitch, volumes and the load estimate.
@export var pitch_smoothing := 0.12
@export var volume_smoothing := 0.15
@export var load_smoothing := 0.18
## Acceleration below this share of full acceleration does not count as load
## (small speed recoveries after each turn at top speed stay calm).
@export var load_deadzone := 0.2
## Share of the load layer kept within the last 10 % of top speed.
@export var cruise_load := 0.3

@export_group("Voices")
## Rival engines heard at once (the nearest); your own car(s) always play.
@export var max_rival_voices := 3
## Fade time (seconds) when a rival engine enters / leaves the nearest set.
@export var voice_fade := 0.35

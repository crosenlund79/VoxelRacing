class_name VoiceParams
extends Resource
## Tunables for the Voice Director (default_voice_params.tres). Presentation
## only: nothing here can change a race.

## Playback speed (1.0 = as recorded). The recordings are a little slow for
## racing; the speed-up keeps the natural pitch when preserve_pitch is on.
@export var rival_speed := 1.10
@export var announcer_speed := 1.0
## Per-line speed overrides, e.g. {"rocco_laughing": 1.05}.
@export var line_speed: Dictionary = {}
## Keep the voice's pitch when speeding up (pitch-shift effect on the Voice
## bus); off = plain faster playback (slightly higher voice).
@export var preserve_pitch := true

## Seconds of quiet after any line before the next can start.
@export var min_gap := 3.5
## The same speaker again within this many seconds is much less likely.
@export var speaker_cooldown := 18.0
@export var speaker_cooldown_factor := 0.12
## The same interaction (event + speaker) again within this window is less likely.
@export var repeat_window := 40.0
@export var repeat_factor := 0.25
## The line that played last is less likely to play again straight away.
@export var same_line_factor := 0.35
## Weight of saying nothing, per event (higher = quieter).
@export var silence_destroyed := 0.35
@export var silence_overtake := 0.55
@export var silence_wall := 2.2
## A pit-lane collision ticket: usually announced (it is rare).
@export var silence_pit_violation := 0.2
## Each line already spoken in the last minute adds this much silence weight.
@export var chatter_silence := 0.25
## How much a rival's own line is preferred over announcer commentary on the
## same event (when both exist).
@export var rival_preference := 1.6

## Barrier impacts (px/s into the barrier) below this are never commented on.
@export var wall_min_speed := 210.0
## Overtakes: the rival must lead the player by this much (px of race
## distance) for confirm_time seconds, after having trailed by as much.
@export var overtake_margin := 24.0
@export var overtake_confirm := 0.6
## No overtake comments in the first seconds of a race (the grid sorting out).
@export var start_quiet := 3.0
## Music and engines are lowered by this much (dB) while someone speaks,
## fading over duck_fade seconds.
@export var duck_db := -5.0
@export var duck_fade := 0.25

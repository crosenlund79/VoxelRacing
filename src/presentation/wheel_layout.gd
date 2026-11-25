class_name WheelLayout
extends Resource
## Where the four shared wheels sit on a car and how they move (P2).
## Positions are display pixels relative to the car centre, car facing +X
## (the 64x36 car display size), so they do not depend on the resolution of
## a body image. Defaults fit the template bodies (default_wheel_layout.tres).

## Wheel centres: front / rear axle along the car (+ = forward), and the
## distance of each wheel from the centre line.
@export var front_x := 16.5
@export var rear_x := -16.5
## 10.5 (2026-11-22, was 12): the wheels sit mostly under the body
## silhouette (the template bodies are 24 px wide at the axles), about 2 px
## of tyre showing on each side.
@export var half_track := 10.5
## Per-car positions for differently shaped bodies:
## body logical name ("cars/body_ai_3") -> Vector3(front_x, rear_x, half_track).
@export var per_car: Dictionary = {}

@export_group("Motion (visual only)")
## Front wheels: angle at full steering, and smoothing time (s).
## 30 degrees (2026-11-22, was 26): steering reads clearly at race zoom.
@export var max_steer_degrees := 30.0
@export var steer_smoothing := 0.07
## Rear wheels: sideways shift at the hardest cornering (display px), and
## smoothing time (s).
@export var rear_shift_px := 1.5
@export var rear_smoothing := 0.15
## Rolling tread (2026-11-22): the wheel image's colours scroll inside its own
## outline by the distance driven (one full scroll per roll_px display px),
## so any wheel drawing looks like it rolls without extra frames. Capped per
## frame so fast cars never strobe backwards. Off: the wheels never scroll.
@export var roll_animation := true
@export var roll_px := 20.0
@export var max_roll_per_frame := 0.22


## Vector3(front_x, rear_x, half_track) for a body.
func positions(body_logical: String) -> Vector3:
	if per_car.has(body_logical):
		return per_car[body_logical]
	return Vector3(front_x, rear_x, half_track)

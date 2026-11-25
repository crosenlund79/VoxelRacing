class_name PitRules
extends Resource
## Pit lanes: service, the pit limiter and pit-area collision tickets.
## Provisional numbers for human balancing (docs/PIT_LANES.md).

## Service: condition points restored (never above 100 %), seconds stationary
## in a service bay, and the speed (px/s) below which a car counts as stopped.
@export var repair_points := 30.0
@export var service_time := 6.0
@export var stopped_speed := 12.0
## The pit limiter: share of the car's top speed allowed in the pit lane.
## Overriding it (double tap) is allowed and never punished.
@export_range(0.1, 1.0) var limiter_share := 0.5
## Override: two separate accelerator presses within this many seconds.
@export var double_tap_window := 0.35
## Collision ticket: a meaningful impact in the pit area (above the damage
## model's own thresholds: DamageRules.wall_threshold / car_threshold) by the
## responsible car. Fine in $ (paid by the human in garage races, never below
## $0; a statistic everywhere else).
@export var collision_fine := 100
## One incident: impacts closer together than this (s) count once.
@export var incident_gap := 1.0

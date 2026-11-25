class_name TrackTheme
extends Resource
## One environment (theme variant) of a circuit (Variant 1, 2, 3 ...): artwork, a
## few colour tints, weather, the night mood, and (2026-11) modest handling
## differences for every car alike (grip, response, braking). The layout,
## collision and race rules are identical for every variant. Internal names stay generic ("variant_N"); only display_name is
## thematic, so artwork can be replaced without renaming code or folders.
##
## Assets: a variant looks up "variant_N/<logical name>" first (when the asset
## catalogue defines it) and otherwise falls back to the shared asset, so a
## variant only provides what it changes. Variant 1 is the baseline and uses
## the shared assets directly.

const VARIANT_COUNT := 5
const PATH := "res://src/track/themes/variant_%d.tres"

@export_range(1, 9) var variant := 1
## Name shown in menus (thematic; never used as an identifier).
@export var display_name := "Variant 1"
## Trackside props: shared logical asset names (resolved per variant), their
## relative frequency and whether they sway (tall props). Same placement
## algorithm and seed for every variant.
@export var scenery: Array[String] = []
@export var scenery_weights: Array[float] = []
@export var scenery_sway: Array[bool] = []
## Colour of the dust a car throws up when it runs off the road.
@export var dust_color := Color(0.75, 0.66, 0.5, 0.7)
## Handling for every car, human and AI alike (multipliers on DrivingParams;
## 1 = the approved baseline). Modest by design.
@export var grip_scale := 1.0
@export var acceleration_scale := 1.0
@export var turn_scale := 1.0
@export var brake_scale := 1.0
## Top speed for every car (2026-11, The Raceway): 1 = the approved baseline.
@export var max_speed_scale := 1.0
## How many scattered props (scenery); landmarks: extra environment-only props
## (variant logical names such as "scenery/pencil"), how many of each, and
## whether each one faces the track (advertising boards) or lies at any angle.
## Every prop keeps its whole display size clear of the road.
@export var scenery_count := 140
@export var landmarks: Array[String] = []
@export var landmark_counts: Array[int] = []
@export var landmark_facing: Array[bool] = []
## Red / white kerbs on the corners and a pit building on the main straight.
@export var kerbs := false
@export var pit_building := false
## Grandstands with crowds along the main straight.
@export var grandstands := true
## Night: how many trackside lamps (floodlights on The Raceway).
@export var lamp_count := 10
## Look: tints over the ground and road artwork (white = unchanged), weather
## ("", "rain" or "snow"), and the night mood (ambient tint, lamp colour and
## strength, headlight strength).
@export var ground_tint := Color.WHITE
@export var road_tint := Color.WHITE
@export var weather := ""
@export var night_ambient := Color(0.42, 0.44, 0.58)
@export var lamp_color := Color(1.0, 0.86, 0.6)
@export var lamp_energy := 1.15
@export var headlight_energy := 0.95


## The asset this variant uses for a shared logical name.
func asset(logical: String) -> String:
	return AssetCatalog.themed(logical, variant)


## The driving parameters in this environment (the same object when nothing changes).
func driving(base: DrivingParams) -> DrivingParams:
	if grip_scale == 1.0 and acceleration_scale == 1.0 and turn_scale == 1.0 and brake_scale == 1.0 and max_speed_scale == 1.0:
		return base
	var p := base.duplicate() as DrivingParams
	p.max_speed = base.max_speed * max_speed_scale
	p.grip = base.grip * grip_scale
	p.acceleration = base.acceleration * acceleration_scale
	p.turn_rate_degrees = base.turn_rate_degrees * turn_scale
	p.brake_deceleration = base.brake_deceleration * brake_scale
	p.release_deceleration = base.release_deceleration * brake_scale
	return p


static func load_variant(n: int) -> TrackTheme:
	return load(PATH % clampi(n, 1, VARIANT_COUNT))

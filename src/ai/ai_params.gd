class_name AiParams
extends Resource
## Tunables for computer drivers. These shape decisions only: AI cars use the
## same DrivingParams, CarModel and inputs (digital left/right + fire) as the
## player, with no speed, grip or catch-up advantages.
## All values PROVISIONAL: the original AI behaviour is undocumented.

## Distance kept between the racing line and the barrier faces (px).
@export var line_margin := 34.0
## Smoothing passes used to straighten the racing line through corners.
@export var line_iterations := 300
## Fraction of the steering-limited speed (turn rate x radius) used as corner speed.
@export var corner_speed_factor := 0.85
## Fraction of release_deceleration assumed when planning braking.
@export var brake_planning_factor := 0.8
## Steering look-ahead: base distance (px) plus distance per px/s of speed.
@export var lookahead_base := 60.0
@export var lookahead_per_speed := 0.22
## Heading error below which the driver does not steer (degrees).
@export var steer_deadband_degrees := 4.0
## Cars closer than this ahead (px along the track) are treated as traffic.
@export var traffic_distance := 150.0
## Pass only cars at least this much slower (px/s); otherwise follow.
@export var pass_speed_margin := 4.0
## Gap (px) below which a driver eases off rather than run into the car ahead.
@export var follow_gap := 85.0
## Lateral gap (px) below which a car ahead is in our path.
@export var car_clearance := 42.0
## Lateral position (px from the other car) used when moving out to pass.
@export var pass_offset := 50.0
## Minimum distance between a passing car's centre and the barrier face (px).
@export var pass_margin := 24.0
## Rate the driver moves sideways when changing line (px/s), and returns to the racing line.
@export var lane_change_rate := 110.0
@export var lane_return_rate := 45.0

## --- Personality (decision traits). Defaults are neutral and reproduce the M2 driver.
## How far ahead (seconds at current speed) the driver reads the target speed;
## smaller = brakes later.
@export var brake_anticipation := 0.1
## Target-speed scale inside braking/corner zones (>1 = pushes harder than the plan).
@export var corner_commitment := 1.0
## Random +- variation of corner_commitment, rolled per corner (consistency).
@export var commitment_variation := 0.0
## Chance per corner of over-committing, and the extra commitment when it happens.
@export var overcommit_chance := 0.0
@export var overcommit_extra := 0.0
## Extra commitment when chasing a car within traffic_distance.
@export var chase_aggression := 0.0
## Only start a pass when the line ahead is a straight (no braking zone within pass_lookahead).
@export var pass_on_straights_only := false
@export var pass_lookahead := 300.0
## Pressure: a car within pressure_distance behind or alongside. 0 disables.
@export var pressure_distance := 0.0
## Chance per second under pressure of becoming flustered, and how long it lasts (s).
@export var fluster_chance_per_second := 0.0
@export var fluster_duration := 1.0
## While flustered: chance per tick of lifting off (hesitation) ...
@export var fluster_lift_chance := 0.0
## ... and over-correction: look-ahead shrinks by this fraction and the steering deadband vanishes.
@export var fluster_overcorrection := 0.0

## --- M2.3 traits (neutral defaults: no effect).
## Defending: when a closing car is within defend_distance behind, move towards
## its line by defend_strength (0..1) and scale corner commitment by
## defend_commitment (gives up speed to keep the position). 0 disables.
@export var defend_distance := 0.0
@export var defend_strength := 0.0
@export var defend_commitment := 1.0
## Only pass into a lane with no other car nearby (no forcing).
@export var pass_check_clearance := false
## Passing side: 0 = nearest side, 1 = outside of the coming corner, 2 = random per attempt.
@export_range(0, 2) var pass_side := 0
## Disrupted line: when pushed more than disrupted_threshold px off the planned
## line, corner commitment is scaled by disrupted_commitment for disrupted_recovery s. 0 disables.
@export var disrupted_threshold := 0.0
@export var disrupted_commitment := 1.0
@export var disrupted_recovery := 0.0
## Chance per second of attempting a pass even without a speed advantage (impulse).
@export var pass_impulse_chance := 0.0

## --- M3 combat decisions (same weapons and rules for everyone; these only shape
## when a driver chooses to fire). Defaults: a competent, neutral shooter.
## Minimum shot quality (0..1: predicted miss distance vs hit radius) for a front shot.
@export_range(0.0, 1.0) var attack_min_confidence := 0.6
## How eagerly a valid shot is taken (attempts per second).
@export var attack_rate := 2.0
## Longest front shot considered (px).
@export var attack_range := 600.0
## A soft reserve (2026-11-23): with this many front rounds or fewer left,
## shots must be clearly better until the closing stage of the race (never an
## absolute hold).
@export var ammo_reserve := 0
## Methodical pacing: the driver keeps closer to its spending schedule, both
## ways (half the usual tolerance).
@export var ammo_pacing := false
## Chance per second of firing without a decent shot (wasted rounds).
@export var waste_chance := 0.0
## Only attack slow, recovering or very close targets.
@export var opportunist := false
## Random +- change of the confidence threshold per decision.
@export var confidence_variation := 0.0
## Under pressure (see pressure_distance) the threshold drops by this much (hasty shots).
@export var pressure_attack_drop := 0.0
## Minimum quality for dropping a mine (0..1: how well a follower's arrival matches the fuse).
@export_range(0.0, 1.0) var mine_min_quality := 0.5
## How eagerly a good mine drop is taken (attempts per second).
@export var mine_rate := 1.5
## After being destroyed: for retaliation_time s, rates are multiplied by
## retaliation_boost and the thresholds lowered by 0.15. 0 disables.
@export var retaliation_time := 0.0
@export var retaliation_boost := 1.0

## --- M3.5 Tactical combat decisions (used only in Tactical style; Classic keeps
## the M3 decisions above unchanged). Neutral defaults.
## Patience: seconds a firing solution must hold before the shot is taken
## (0 = shoots the moment it looks good). Ignored under pressure.
@export var tactical_aim_time := 0.0
## Rear-slot eagerness: multiplies the rear attempt rate and lowers its
## threshold by 0.1 per unit above 1 (defensive drivers watch their mirrors).
@export var rear_eagerness := 1.0
## Super missile: cars that must be close before it is worth launching.
@export_range(1, 4) var super_min_targets := 1
## "Occasionally brilliant": attempts per second to take a near-perfect shot
## (quality >= 0.9) at once, whatever the mood or the aim time. 0 disables.
@export var brilliance_rate := 0.0

## --- Racecraft (2026-11): ammunition over a whole race, grudges, wrecks ahead
## and each driver's own way of using the road. Decisions only.
## How strictly a driver spends ammunition in step with the race (0 = fires
## whenever it likes, 1 = never ahead of schedule): when more of the starting
## rounds are gone than the race is done, shots need to be that much better.
@export_range(0.0, 1.0) var ammo_discipline := 0.6
## Spending schedule (2026-11-23): by race progress p (0..1) the driver means
## to have used ammo_spend_target * p ^ ammo_spend_curve of its starting
## rounds. Curve < 1 spends early (aggressive), > 1 saves for later (patient).
@export var ammo_spend_curve := 1.0
@export_range(0.0, 1.0) var ammo_spend_target := 0.95
## Impulsive bursts: chance per second of a trigger-happy spell lasting
## impulse_time s, in which shots need impulse_drop less quality. 0 = never.
@export var ammo_impulse := 0.0
@export var impulse_time := 3.0
@export var impulse_drop := 0.15
## Micro Nemesis: after being destroyed by a driver, shots at that driver look
## up to grudge_bonus better (0..1 quality), fading over grudge_time s.
@export var grudge_bonus := 0.12
@export var grudge_time := 20.0
## Wrecks ahead: how far ahead the driver reads the road for a wrecked car
## (seconds at the current speed, at least traffic_distance), and how long it
## takes to react once one is in view (s).
@export var hazard_lookahead := 0.7
@export var hazard_reaction := 0.25
## Own line: a preferred offset from the shared racing line (px, + = right)
## and a slow wander around it (amplitude px, period s).
@export var line_offset := 0.0
@export var line_wander := 0.0
@export var line_wander_period := 6.0

## Track branches and pit stops (2026-11-17; neutral defaults, see personalities):
## route choice at a split: noise in seconds, and seconds a car in a lane counts as.
@export var route_whim := 0.15
@export var route_traffic_weight := 0.25
## Pit strategy: pits below this condition (share) with laps to go; chance of
## staying out one more lap anyway; chance of deliberately overriding the pit
## limiter on a stop (more when chasing or fighting for the podium late on).
@export var pit_threshold := 0.35
@export var pit_stay_out_chance := 0.0
@export var pit_speeding := 0.02
## Seconds a driver waits before the bays when all are taken, before giving up
## the stop and driving on (0 = never waits).
@export var pit_patience := 2.0


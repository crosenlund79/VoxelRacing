class_name HumanDriverInput
extends DriverInput
## A human driver on this machine. Reads one set of input actions: the default
## single-player actions (prefix "") or a player's own device-bound actions
## (e.g. "p2_", see PlayerControls.ensure_player_actions).

var prefix := ""
## Steering builds up briefly so taps make small corrections (SteerShaper).
var shaper := SteerShaper.new()
## Double-tap the accelerator in the pit lane: override the pit limiter.
var pit_taps := PitTapDetector.new()


func _init(p_racer_id: int, p_prefix: String = "") -> void:
	racer_id = p_racer_id
	prefix = p_prefix


func is_human() -> bool:
	return true


## While racing: the player's joystick. After this driver's flag the player has
## no control and the car brakes to a stop.
func drive(race: Node, step: float) -> Dictionary:
	var car: Car = race.cars[racer_id]
	if race.session.racers[racer_id].is_finished() or race.menu_open:  # menu open: brake, no steering
		shaper.reset()
		return {"steer": 0.0, "fire": car.model.control_mode == CarModel.ControlMode.FIRE_TO_BRAKE}
	var share := car.model.velocity.length() / maxf(car.model.params.max_speed, 1.0)
	var fire := PlayerControls.fire_held(prefix)
	var override := false
	if race.get("pits") != null:  # (the Battle Royale arena has no pit lane)
		override = pit_taps.step(fire, race.pits.in_lane[racer_id] == 1, step, race.pit_rules.double_tap_window)
	return {"steer": shaper.step(PlayerControls.steer(prefix), share, step), "fire": fire, "pit_override": override}


## Joystick Forward / Backwards presses, only while racing and not wrecked.
func weapons(race: Node, _step: float, _states: Array) -> Dictionary:
	var out := {"front": false, "rear": false}
	if race.session.state != RaceSession.State.RACING or race.combat.is_wrecked(racer_id) \
			or race.session.racers[racer_id].is_finished() or race.menu_open:
		return out
	out.front = Input.is_action_just_pressed(prefix + PlayerControls.FIRE_FRONT)
	out.rear = Input.is_action_just_pressed(prefix + PlayerControls.FIRE_REAR)
	if Input.is_action_just_pressed(prefix + PlayerControls.CYCLE_FRONT):  # (only when pressed: the command is unchanged otherwise)
		out.cycle_front = true
	if Input.is_action_just_pressed(prefix + PlayerControls.CYCLE_REAR):
		out.cycle_rear = true
	return out

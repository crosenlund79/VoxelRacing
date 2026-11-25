class_name DrivingParams
extends Resource
## Tunable driving parameters for fidelity calibration.
##
## ALL VALUES ARE PROVISIONAL - chosen for playability, NOT verified against
## the 1991 Amiga Super Cars II. Units: world pixels and seconds.
## Behaviour (from the manual, as confirmed by the user):
##   Fire to Accelerate: fire held = accelerate; fire released = brake automatically.
##   Fire to Brake: accelerates automatically; fire held = stronger braking.

## Top forward speed (px/s). PROVISIONAL.
@export var max_speed: float = 420.0
## Forward acceleration while accelerating (px/s^2). PROVISIONAL.
@export var acceleration: float = 260.0
## Fire to Accelerate mode: deceleration while fire is released (px/s^2). PROVISIONAL.
@export var release_deceleration: float = 200.0
## Fire to Brake mode: deceleration while fire is held; must exceed release_deceleration (px/s^2). PROVISIONAL.
@export var brake_deceleration: float = 520.0
## Rotation speed while steering (degrees/s). PROVISIONAL; original rotation steps unknown.
@export var turn_rate_degrees: float = 210.0
## Speed below which turning is scaled down linearly; 0 = full turning at any speed. PROVISIONAL.
@export var full_steer_speed: float = 0.0
## How fast sideways (sliding) velocity decays, per second. Lower = more slide. PROVISIONAL.
@export var grip: float = 4.5
## Fraction of the into-wall speed bounced back on impact (0..1). PROVISIONAL.
@export_range(0.0, 1.0) var wall_restitution: float = 0.3
## Fraction of the along-wall speed kept on impact (0..1). PROVISIONAL.
@export_range(0.0, 1.0) var wall_tangent_retention: float = 0.75
## Car-to-car contact: fraction of the closing speed bounced apart (0..1). Equal masses,
## symmetric for every car. Added in M2; PROVISIONAL.
@export_range(0.0, 1.0) var car_restitution: float = 0.4

## Aggressive contact (car-to-car only; walls, steering, throttle, brakes and
## grip are unchanged). A contact also gives each car a brief yaw disturbance
## from where it was struck: the angular impulse (contact offset x impulse,
## per car_half_length^2) times contact_yaw_factor. Struck behind its centre
## a car gets the full effect (the rear quarter is easy to rotate); struck
## ahead of its centre only contact_front_factor of it. The extra rotation is
## capped at contact_yaw_max (rad/s) and fades with contact_yaw_damping (1/s),
## so a hard rear-quarter hit turns a car by roughly 15-25 degrees, which the
## driver can correct: never a scripted spin. PROVISIONAL (not in the manual).
## contact_yaw_factor = 0 switches it off. All cars are equal: same mass.
@export var contact_yaw_factor := 0.9
@export var contact_front_factor := 0.3
@export var contact_yaw_max := 1.6
@export var contact_yaw_damping := 4.0
## Half the car's length (px) used for the lever arm (template car 64 px long).
@export var car_half_length := 32.0

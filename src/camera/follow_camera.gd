class_name FollowCamera
extends Camera2D
## Overhead scrolling camera: keeps the target centred, never rotates.
## Rigid follow (no smoothing or look-ahead): the original's camera lag/lead is unverified.

@export var target: Node2D


func _ready() -> void:
	ignore_rotation = true
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	position_smoothing_enabled = false
	snap_to_target()


func _physics_process(_delta: float) -> void:
	snap_to_target()


func snap_to_target() -> void:
	if target != null:
		global_position = target.global_position

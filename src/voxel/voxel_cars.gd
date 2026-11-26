class_name VoxelCars
extends RefCounted
## The racing cars' voxel models. Since Prototype 006 every car is its
## driver's own layered vehicle design (VoxelVehicle: crash cell, internals
## and detachable body components, at a finer vehicle voxel); this class is
## the shared entry point the race, menus, garage, podium and icons use.
## The user's own body drawings get a design and their main paint from the
## drawing. Meshes are cached per design.

const MODEL_SHADER := preload("res://src/voxel/shaders/voxel_model.gdshader")
const DISPLAY := Vector2(64.0, 36.0)
## The old car voxel (2 px) stays the size of small voxel effects (weapons,
## flair, debris); wheels: centre height WHEEL_R * Vox.CAR_VOXEL_PX = 6 px.
const WHEEL_R := 3

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = MODEL_SHADER
	return _material


static func voxel_size() -> float:
	return Vox.CAR_VOXEL_PX * Vox.PX


## The whole, undamaged vehicle for a car drawing (nose +X, the car's right
## +Z, centred, standing on y = 0). Shared: damage is shown per instance
## (VoxelCarDamage sets the component masks).
static func body_mesh(tex: Texture2D, _layout: WheelLayout = null, body_logical: String = "") -> ArrayMesh:
	return model(tex, body_logical).mesh


## The vehicle (components, lamps, wheels) for a car drawing.
static func model(tex: Texture2D, body_logical: String = "") -> VoxelVehicle.Model:
	return VoxelVehicle.model_for(tex, body_logical)


## The vehicle's voxels (shared; do not change).
static func body_grid(tex: Texture2D, _layout: WheelLayout = null, body_logical: String = "") -> VoxelGrid:
	return model(tex, body_logical).grid


## Wheel centres of a body in display px: Vector3(front x, rear x, half track).
static func wheels_of(layout: WheelLayout, tex: Texture2D, body_logical: String) -> Vector3:
	return VoxelVehicle.wheels_for(layout, tex, body_logical)


## Moves four wheel nodes (front left, front right, rear left, rear right,
## as the cars build them) to a body's wheel positions and tyre widths.
static func place_wheels(wheels: Array, layout: WheelLayout, tex: Texture2D, body_logical: String) -> void:
	if wheels.size() < 4:
		return
	var at := wheels_of(layout, tex, body_logical)
	var m := model(tex, body_logical)
	var k := 0
	for ax in [at.x, at.y]:
		for az in [-at.z, at.z]:
			var w := wheels[k] as Node3D
			w.position = Vector3(ax, WHEEL_R * Vox.CAR_VOXEL_PX, az) * Vox.PX
			w.scale.z = m.tyre.x if k < 2 else m.tyre.y
			k += 1


## Model-space offset of a body grid (centred on the car, standing on y = 0).
static func pivot() -> Vector3:
	return VoxelVehicle.pivot()


## Cache key of a drawing: its file (packaged art), else the texture itself
## (the user's custom art is loaded as plain image textures).
static func _tex_key(tex: Texture2D) -> String:
	if tex == null:
		return "none"
	if not tex.resource_path.is_empty():
		return tex.resource_path
	return str(tex.get_instance_id())


## One voxel wheel (axle along Z, centred), at the vehicle voxel size.
static func wheel_mesh() -> ArrayMesh:
	return VoxelVehicle.wheel_mesh()

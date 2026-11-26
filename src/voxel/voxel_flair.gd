class_name VoxelFlair
extends RefCounted
## VoxelRacing (P004): little touches that make each car its driver's own -
## exhaust pipes (they puff and pop) and rims in the driver's colour.
## (P006: the racing numbers and their plates are gone; the vehicles carry
## their own exhausts. Cartoon Motorsport: the novelty gadgets - roof
## spikes, mortarboard, pennant, playing card and the rest - are gone.) Small voxel
## models in the cars' fine voxel size, added on top of the car's own model
## (its livery and shape stay as drawn). Presentation only.

## Rim tints by racer id (multiplies the shared wheel's colours).
const RIMS := [Color(1.25, 1.05, 0.55), Color(0.9, 0.95, 1.15), Color(1.3, 0.6, 0.5), Color(0.8, 1.05, 1.3), Color(0.8, 1.1, 0.7),
	Color(1.15, 1.15, 1.2), Color(1.4, 1.15, 0.45), Color(0.85, 0.85, 0.9), Color(1.1, 0.7, 1.2), Color(1.3, 0.6, 0.85)]

static var _cache: Dictionary = {}


static func _vs() -> float:
	return VoxelCars.voxel_size()


static func _done(g: VoxelGrid, pivot: Vector3) -> ArrayMesh:
	return VoxelMesher.build_mesh(g, VoxelCars.material(), pivot * _vs(), 0.02)


static func exhaust() -> ArrayMesh:
	if _cache.has("exhaust"):
		return _cache["exhaust"]
	var g := VoxelGrid.new(Vector3i(3, 2, 2), _vs(), Vector3.ZERO)
	g.box(Vector3i(0, 0, 0), Vector3i(2, 1, 1), Vox.METAL, Color(0.42, 0.43, 0.46))
	g.set_v(0, 0, 0, Vox.SOLID, Color(0.08, 0.08, 0.08))
	g.set_v(0, 1, 1, Vox.SOLID, Color(0.08, 0.08, 0.08))
	var mesh := _done(g, Vector3(1.0, 0.0, 1.0))
	_cache["exhaust"] = mesh
	return mesh

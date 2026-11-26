class_name VoxelFlair
extends RefCounted
## VoxelRacing (P004): little touches that make each car its driver's own -
## exhaust pipes (they puff and pop), rims in the driver's colour and one
## signature gadget per driver. (P006: the racing numbers and their plates
## are gone; the vehicles carry their own exhausts.) Small voxel
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


## The signature gadget for a racer id: [mesh, where] - where is "roof",
## "nose", "tail" or "sides" (the car places it), or [] for none.
static func gadget(id: int) -> Array:
	var key := "gadget%d" % id
	if _cache.has(key):
		return _cache[key]
	var out: Array = []
	match id:
		1:  # The Professor: a mortarboard
			var g := VoxelGrid.new(Vector3i(7, 3, 7), _vs(), Vector3.ZERO)
			g.box(Vector3i(2, 0, 2), Vector3i(4, 1, 4), Vox.SOLID, Color(0.1, 0.1, 0.12))
			g.box(Vector3i(0, 2, 0), Vector3i(6, 2, 6), Vox.SOLID, Color(0.1, 0.1, 0.12))
			g.set_v(3, 2, 3, Vox.SOLID, VrStyle.YELLOW)
			g.set_v(6, 1, 3, Vox.SOLID, VrStyle.YELLOW)
			g.set_v(6, 0, 3, Vox.SOLID, VrStyle.YELLOW)
			out = [_done(g, Vector3(3.5, 0, 3.5)), "roof"]
		2:  # Mad Dog: roof spikes
			var g := VoxelGrid.new(Vector3i(7, 3, 9), _vs(), Vector3.ZERO)
			for z in [1, 4, 7]:
				for x in [1, 4]:
					g.set_v(x, 0, z, Vox.METAL, Color(0.75, 0.76, 0.8))
					g.set_v(x, 1, z, Vox.METAL, Color(0.85, 0.86, 0.9))
					g.set_v(x, 2, z, Vox.METAL, Color(0.95, 0.95, 1.0))
			out = [_done(g, Vector3(3.0, 0, 4.5)), "roof"]
		3:  # Sparrow: little winglets on the sides
			var g := VoxelGrid.new(Vector3i(6, 1, 26), _vs(), Vector3.ZERO)
			for z in 26:
				var edge := mini(z, 25 - z)
				if edge < 5:
					for x in range(maxi(0, 5 - edge), 6):
						g.set_v(x, 0, z, Vox.SOLID, Color(0.97, 0.97, 0.95) if x > 1 else Color(0.35, 0.65, 0.95))
			out = [_done(g, Vector3(3.0, 0, 13.0)), "sides"]
		4:  # The Wall: a bull bar on the nose
			var g := VoxelGrid.new(Vector3i(2, 5, 16), _vs(), Vector3.ZERO)
			g.box(Vector3i(0, 0, 0), Vector3i(1, 0, 15), Vox.METAL, Color(0.3, 0.31, 0.34))
			g.box(Vector3i(0, 4, 2), Vector3i(1, 4, 13), Vox.METAL, Color(0.3, 0.31, 0.34))
			for z in [0, 5, 10, 15]:
				g.box(Vector3i(0, 0, z), Vector3i(1, 4, z), Vox.METAL, Color(0.36, 0.37, 0.4))
			out = [_done(g, Vector3(0.0, 0, 8.0)), "nose"]
		5:  # Ghost: a little ghost riding on the roof
			var g := VoxelGrid.new(Vector3i(5, 6, 5), _vs(), Vector3.ZERO)
			g.box(Vector3i(0, 1, 0), Vector3i(4, 4, 4), Vox.SOLID, Color(0.97, 0.98, 1.0))
			g.box(Vector3i(1, 5, 1), Vector3i(3, 5, 3), Vox.SOLID, Color(0.97, 0.98, 1.0))
			for x in [0, 2, 4]:
				g.set_v(x, 0, 0, Vox.SOLID, Color(0.97, 0.98, 1.0))
				g.set_v(x, 0, 4, Vox.SOLID, Color(0.97, 0.98, 1.0))
			g.set_v(4, 3, 1, Vox.SOLID, Color(0.1, 0.1, 0.12))
			g.set_v(4, 3, 3, Vox.SOLID, Color(0.1, 0.1, 0.12))
			out = [_done(g, Vector3(2.5, 0, 2.5)), "roof"]
		6:  # Showboat: a tall antenna with a gold pennant
			var g := VoxelGrid.new(Vector3i(6, 18, 1), _vs(), Vector3.ZERO)
			for y in 18:
				g.set_v(0, y, 0, Vox.METAL, Color(0.8, 0.8, 0.85))
			for y in range(13, 18):
				for x in range(1, 6 - absi(y - 15) * 2 + 1):
					if x < 6:
						g.set_v(x, y, 0, Vox.GLOW, Color(1.0, 0.8, 0.2))
			out = [_done(g, Vector3(0.0, 0, 0.5)), "tail_roof"]
		7:  # Clockwork: a wind-up key on the tail (it turns)
			var g := VoxelGrid.new(Vector3i(2, 7, 9), _vs(), Vector3.ZERO)
			g.box(Vector3i(0, 0, 4), Vector3i(1, 2, 4), Vox.METAL, Color(0.75, 0.6, 0.25))
			for z in 9:
				for y in range(2, 7):
					var lobe := Vector2(z - 2.0, y - 4.5).length() < 2.3 or Vector2(z - 6.0, y - 4.5).length() < 2.3
					if lobe:
						g.set_v(0, y, z, Vox.METAL, Color(0.85, 0.68, 0.3))
			out = [_done(g, Vector3(1.0, 0, 4.5)), "key"]
		8:  # Wildcard: an ace sticking up from the roof
			var g := VoxelGrid.new(Vector3i(1, 8, 6), _vs(), Vector3.ZERO)
			g.box(Vector3i(0, 0, 0), Vector3i(0, 7, 5), Vox.SOLID, Color(0.97, 0.97, 0.95))
			for p in [Vector2i(3, 2), Vector2i(4, 1), Vector2i(4, 3), Vector2i(5, 2), Vector2i(4, 2)]:
				g.set_v(0, p.x, p.y + 1, Vox.SOLID, VrStyle.RED)
			out = [_done(g, Vector3(0.5, 0, 3.0)), "roof"]
		9:  # The Hunter: twin roof spotlights
			var g := VoxelGrid.new(Vector3i(3, 3, 10), _vs(), Vector3.ZERO)
			g.box(Vector3i(0, 0, 0), Vector3i(1, 0, 9), Vox.METAL, Color(0.2, 0.2, 0.22))
			for z in [1, 7]:
				g.box(Vector3i(0, 1, z), Vector3i(1, 2, z + 1), Vox.METAL, Color(0.18, 0.18, 0.2))
				g.set_v(2, 1, z, Vox.HEAD, Color(1.0, 0.98, 0.9))
				g.set_v(2, 2, z + 1, Vox.HEAD, Color(1.0, 0.98, 0.9))
			out = [_done(g, Vector3(1.0, 0, 5.0)), "roof"]
	_cache[key] = out
	return out

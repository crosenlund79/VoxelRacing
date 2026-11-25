class_name VoxelGrid
extends RefCounted
## Dense voxel volume: one material byte and one 0xRRGGBB colour per cell.
## Adapted from SirensWentQuiet's VoxelGrid (src/voxel/voxel_grid.gd): the
## outermost layer of cells is always empty, so the mesher reads neighbours
## without bounds checks. Index = (y * sz + z) * sx + x.
##
## Cell (x, y, z) covers [origin + (x, y, z) * vs, origin + (x+1, y+1, z+1) * vs).

var sx: int
var sy: int
var sz: int
var vs: float
var origin: Vector3
var mat := PackedByteArray()
var col := PackedInt32Array()


## size: the usable interior size; one empty border cell is added on each side.
## origin_inner: where interior cell (0, 0, 0) starts.
func _init(size: Vector3i, voxel_size: float, origin_inner: Vector3) -> void:
	sx = size.x + 2
	sy = size.y + 2
	sz = size.z + 2
	vs = voxel_size
	origin = origin_inner - Vector3.ONE * vs
	var n := sx * sy * sz
	mat.resize(n)
	col.resize(n)


## Interior coordinates (0-based, without the border).
func set_v(x: int, y: int, z: int, m: int, c: Color) -> void:
	if x < 0 or y < 0 or z < 0 or x >= sx - 2 or y >= sy - 2 or z >= sz - 2:
		return
	var i := ((y + 1) * sz + z + 1) * sx + x + 1
	mat[i] = m
	col[i] = (int(clampf(c.r, 0.0, 1.0) * 255.0) << 16) | (int(clampf(c.g, 0.0, 1.0) * 255.0) << 8) | int(clampf(c.b, 0.0, 1.0) * 255.0)


func get_m(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0 or x >= sx - 2 or y >= sy - 2 or z >= sz - 2:
		return 0
	return mat[((y + 1) * sz + z + 1) * sx + x + 1]


## Fill an interior box [from, to] inclusive.
func box(from: Vector3i, to: Vector3i, m: int, c: Color) -> void:
	for y in range(from.y, to.y + 1):
		for z in range(from.z, to.z + 1):
			for x in range(from.x, to.x + 1):
				set_v(x, y, z, m, c)

class_name Vox
extends RefCounted
## VoxelRacing: shared scale and helpers for the 3D voxel presentation.
##
## The race simulation stays HyperCars' 2D world (pixels, +Y down). The voxel
## world mirrors it in 3D: 2D (x, y) px -> 3D (x * PX, height * PX, y * PX).
## A 2D rotation r (radians, clockwise on screen) is a 3D yaw of -r.

## 3D units per 2D pixel (1 unit = 16 px).
const PX := 1.0 / 16.0
## World voxel (terrain, barriers, scenery) and fine voxel (cars) edge, in px.
const CELL_PX := 4.0
const CAR_VOXEL_PX := 2.0

## Material ids of a VoxelGrid cell.
const AIR := 0
const SOLID := 1
const GLASS := 2      ## glossy dark (windows), no emission
const HEAD := 3       ## emissive: headlamp lens (car head_glow)
const TAIL := 4       ## emissive: tail lamp (car tail_glow)
const GLOW := 5       ## emissive: lamp bulbs, floodlights (lamp_glow)
const METAL := 6      ## glossy (wheel hubs, paperclips)


static func to3(p: Vector2, height_px: float = 0.0) -> Vector3:
	return Vector3(p.x * PX, height_px * PX, p.y * PX)


static func to2(p: Vector3) -> Vector2:
	return Vector2(p.x / PX, p.z / PX)


static func yaw(rotation_2d: float) -> float:
	return -rotation_2d


## Deterministic 0..1 hash of three integers (per-voxel colour jitter).
static func hash3(x: int, y: int, z: int) -> float:
	var h := (x * 374761393 + y * 668265263 + z * 2147483647) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## An image's RGBA8 copy (decompressed), or null.
static func rgba(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null:
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img

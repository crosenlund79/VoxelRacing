class_name VoxelMesher
extends RefCounted
## Face-culled voxel mesher with baked per-vertex ambient occlusion.
## Adapted from SirensWentQuiet's VoxelMesher (src/voxel/voxel_mesher.gd):
## every exposed voxel face is one quad with its own colour; COLOR.a carries
## the classic 0fps-style vertex AO and the quad is split along the diagonal
## that keeps the AO gradient smooth.
##
## VoxelRacing additions: UV = (emissive kind 0..3, glossy + 0.9 * per-voxel
## random), UV2 = the corner of the face (0/1, 0/1) so the shader can bevel
## every voxel face, and a small per-voxel brightness jitter baked into the
## colour (the handcrafted, painted look).
##
## Directions: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z.

const AO_CURVE := [0.42, 0.62, 0.82, 1.0]
const NORMALS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const TAN_U := [Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0)]
const TAN_V := [Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(1, 0, 0)]
const NORMAL_I := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const CORNER_UV := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
## Faces pointing sideways / down are a little darker (painted-model shading
## that survives flat ambient light at night).
const FACE_SHADE := [0.9, 0.9, 1.0, 0.62, 0.86, 0.86]


static func _delta(g: VoxelGrid, v: Vector3i) -> int:
	return v.x + v.z * g.sx + v.y * g.sx * g.sz


static func _corners() -> Array:
	var out := []
	for d in 6:
		var n := Vector3(NORMAL_I[d])
		var u := Vector3(TAN_U[d])
		var v := Vector3(TAN_V[d])
		var c := Vector3(0.5, 0.5, 0.5) + n * 0.5
		out.append([c - (u + v) * 0.5, c + (u - v) * 0.5, c + (u + v) * 0.5, c + (v - u) * 0.5])
	return out


static var _CORNERS := _corners()


## Mesh arrays for the whole grid; `pivot` is subtracted from every vertex.
## jitter: per-voxel brightness variation (0 = none).
## P006 components: `parts` (one byte per grid cell, same indexing as g.mat)
## tags each voxel with a component id, written into UV.x as
## emit kind + 4 * id (the model shader hides components by id). Faces
## between two different components are kept (so a component can go and
## leave no hole), except against components flagged in `keep` (those
## never go).
static func build_arrays(g: VoxelGrid, pivot: Vector3 = Vector3.ZERO, jitter: float = 0.06,
		parts: PackedByteArray = PackedByteArray(), keep: PackedByteArray = PackedByteArray()) -> Array:
	var mat := g.mat
	var tagged := not parts.is_empty()
	var col := g.col
	var sx := g.sx
	var sz := g.sz
	var vs := g.vs
	var ao_curve := PackedFloat32Array(AO_CURVE)
	var dn := PackedInt32Array()
	var du := PackedInt32Array()
	var dv := PackedInt32Array()
	var corners := []
	for d in 6:
		dn.append(_delta(g, NORMAL_I[d]))
		du.append(_delta(g, TAN_U[d]))
		dv.append(_delta(g, TAN_V[d]))
		var cs := PackedVector3Array()
		for k in 4:
			cs.append(_CORNERS[d][k] * vs)
		corners.append(cs)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var inds := PackedInt32Array()
	var org := g.origin - pivot
	var nverts := 0
	for y in range(1, g.sy - 1):
		for z in range(1, sz - 1):
			var row := (y * sz + z) * sx
			for x in range(1, sx - 1):
				var i := row + x
				var m := mat[i]
				if m == 0:
					continue
				var base := org + Vector3(x, y, z) * vs
				var rnd := Vox.hash3(x, y, z)
				var emit := 0.0
				if m == Vox.HEAD:
					emit = 1.0
				elif m == Vox.TAIL:
					emit = 2.0
				elif m == Vox.GLOW:
					emit = 3.0
				var glossy := 1.0 if (m == Vox.GLASS or m == Vox.METAL or m == Vox.HEAD or m == Vox.TAIL) else 0.0
				var my_part := parts[i] if tagged else 0
				var fuv := Vector2(emit + 4.0 * my_part, glossy + rnd * 0.9)
				var c0 := Color.hex((col[i] << 8) | 0xff)
				var j := 1.0 + (rnd - 0.5) * 2.0 * jitter
				for d in 6:
					var ni := i + dn[d]
					if mat[ni] != 0:
						if not tagged:
							continue
						var np := parts[ni]
						if np == my_part or keep[np] != 0:
							continue
					var sh: float = FACE_SHADE[d] * j
					var c := Color(c0.r * sh, c0.g * sh, c0.b * sh)
					var a := ni
					var u := du[d]
					var v := dv[d]
					var s_um := 1 if mat[a - u] != 0 else 0
					var s_up := 1 if mat[a + u] != 0 else 0
					var s_vm := 1 if mat[a - v] != 0 else 0
					var s_vp := 1 if mat[a + v] != 0 else 0
					var c_mm := 1 if mat[a - u - v] != 0 else 0
					var c_pm := 1 if mat[a + u - v] != 0 else 0
					var c_pp := 1 if mat[a + u + v] != 0 else 0
					var c_mp := 1 if mat[a - u + v] != 0 else 0
					var ao0 := 0 if (s_um and s_vm) else 3 - (s_um + s_vm + c_mm)
					var ao1 := 0 if (s_up and s_vm) else 3 - (s_up + s_vm + c_pm)
					var ao2 := 0 if (s_up and s_vp) else 3 - (s_up + s_vp + c_pp)
					var ao3 := 0 if (s_um and s_vp) else 3 - (s_um + s_vp + c_mp)
					var cs: PackedVector3Array = corners[d]
					var nrm: Vector3 = NORMALS[d]
					for k in 4:
						verts.append(base + cs[k])
						norms.append(nrm)
						uvs.append(fuv)
						uv2s.append(CORNER_UV[k])
					cols.append(Color(c.r, c.g, c.b, ao_curve[ao0]))
					cols.append(Color(c.r, c.g, c.b, ao_curve[ao1]))
					cols.append(Color(c.r, c.g, c.b, ao_curve[ao2]))
					cols.append(Color(c.r, c.g, c.b, ao_curve[ao3]))
					inds.append(nverts)
					if ao0 + ao2 >= ao1 + ao3:
						inds.append(nverts + 2)
						inds.append(nverts + 1)
						inds.append(nverts)
						inds.append(nverts + 3)
						inds.append(nverts + 2)
					else:
						inds.append(nverts + 3)
						inds.append(nverts + 1)
						inds.append(nverts + 1)
						inds.append(nverts + 3)
						inds.append(nverts + 2)
					nverts += 4
	if nverts == 0:
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = inds
	return arrays


static func build_mesh(g: VoxelGrid, material: Material, pivot: Vector3 = Vector3.ZERO, jitter: float = 0.06,
		parts: PackedByteArray = PackedByteArray(), keep: PackedByteArray = PackedByteArray()) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var a := build_arrays(g, pivot, jitter, parts, keep)
	if not a.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		mesh.surface_set_material(0, material)
	return mesh

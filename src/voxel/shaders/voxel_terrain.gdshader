// VoxelRacing: the voxel terrain (ground, road, barriers, kerbs) and bridge
// decks. Geometry is a greedy-meshed heightfield of voxel columns; colour
// comes per cell from a colour map rendered from HyperCars' own 2D track art
// (nearest filtering: one colour per voxel). Top faces get ambient occlusion
// from higher neighbours and a lit lip where they step down; side faces show
// voxel layers (soil under grass). Tyre marks (HyperCars' 2D decal layer,
// rendered each frame into a small viewport) are sampled at voxel centres,
// so they land on the road as voxel-sized marks under the cars.
shader_type spatial;
render_mode depth_draw_opaque, cull_back;

uniform sampler2D color_map : source_color, filter_nearest;
uniform sampler2D height_map : filter_nearest;
uniform sampler2D class_map : filter_nearest;
uniform vec2 map_origin = vec2(0.0);
uniform float cell = 0.25;
uniform vec2 map_cells = vec2(1.0);
uniform bool use_heights = true;
uniform vec3 soil_color : source_color = vec3(0.5, 0.36, 0.24);
uniform vec3 soil_dark : source_color = vec3(0.34, 0.24, 0.17);
uniform float side_lines = 0.16;

uniform sampler2D decal_tex : source_color, filter_linear;
uniform float decal_on = 0.0;
uniform vec2 decal_cam = vec2(0.0);
uniform vec2 decal_zoom = vec2(1.0);
uniform vec2 decal_size = vec2(640.0, 360.0);
uniform float decal_px = 16.0;

varying vec3 w_pos;
varying vec3 w_nrm;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c));
}

float h_at(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(map_cells) - 1);
	return floor(texelFetch(height_map, c, 0).r * 255.0 + 0.5) - 64.0;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 n = normalize(w_nrm);
	vec2 q = (w_pos.xz - map_origin) / cell;
	bool top = n.y > 0.5;
	ivec2 ci = ivec2(floor(q - n.xz * 0.5));
	ci = clamp(ci, ivec2(0), ivec2(map_cells) - 1);
	vec3 col = texelFetch(color_map, ci, 0).rgb;
	float cls = floor(texelFetch(class_map, ci, 0).r * 255.0 + 0.5);
	float ao = 1.0;
	if (COLOR.a < 0.5) {
		// plain painted part (bridge concrete): vertex colour
		col = to_linear(COLOR.rgb);
		float lay = fract(w_pos.y / cell);
		float e = min(lay, 1.0 - lay);
		col *= 1.0 - 0.12 * (1.0 - smoothstep(0.0, 0.08, e));
	} else if (top) {
		float hc = use_heights ? h_at(ci) : 0.0;
		if (use_heights) {
			vec2 f = fract(q);
			float occ = 0.0;
			float lip = 0.0;
			ivec2 o[4] = ivec2[](ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1));
			float d[4] = float[](f.x, 1.0 - f.x, f.y, 1.0 - f.y);
			for (int k = 0; k < 4; k++) {
				float hn = h_at(ci + o[k]);
				occ += clamp(hn - hc - 0.5, 0.0, 2.0) * 0.6 * (1.0 - smoothstep(0.0, 0.6, d[k])) + step(hc + 0.5, hn) * 0.18 * (1.0 - smoothstep(0.0, 0.4, d[k]));
				lip += step(hn, hc - 0.5) * (1.0 - smoothstep(0.0, 0.16, d[k]));
			}
			ivec2 dg[4] = ivec2[](ivec2(-1, -1), ivec2(1, -1), ivec2(-1, 1), ivec2(1, 1));
			float dd[4] = float[](length(f), length(vec2(1.0 - f.x, f.y)), length(vec2(f.x, 1.0 - f.y)), length(1.0 - f));
			for (int k = 0; k < 4; k++) {
				float hn = h_at(ci + dg[k]);
				occ += clamp(hn - hc, 0.0, 1.0) * 0.4 * (1.0 - smoothstep(0.0, 0.7, dd[k]));
			}
			ao = 1.0 - 0.45 * clamp(occ, 0.0, 1.0);
			col *= 1.0 + 0.12 * clamp(lip, 0.0, 1.0);
			if (cls < 0.5 && hc > 0.5) {  // grass hills: sunnier, a touch yellower higher up
				float t = clamp(hc / 6.0, 0.0, 1.0);
				col *= mix(vec3(1.0), vec3(1.16, 1.14, 1.0), t);
			}
		}
		// tyre marks and other ground decals (road level only)
		if (decal_on > 0.5 && abs(hc) < 0.5) {
			vec2 pc = (map_origin + (vec2(ci) + 0.5) * cell) * decal_px;
			vec2 uv = ((pc - decal_cam) * decal_zoom + decal_size * 0.5) / decal_size;
			if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
				vec4 dc = texture(decal_tex, uv);
				// rubber: darken towards black, a little stronger than the 2D stamps
				col *= 1.0 - 0.85 * clamp(dc.a * 1.7, 0.0, 1.0);
			}
		}
	} else {
		float hc = use_heights ? h_at(ci) : 1.0;
		float depth = hc - w_pos.y / cell;
		float layer = floor(depth);
		float jit = hash12(vec2(ci) * 1.7 + layer * 13.1);
		if (cls < 0.5) {  // grass: a green lip over soil layers
			col = depth < 0.95 ? col * 0.9 : mix(soil_color, soil_dark, clamp(layer * 0.22 + jit * 0.3, 0.0, 1.0));
		} else if (cls < 1.5) {  // road edge (pit, ravine walls)
			col *= 0.62;
		} else {
			col *= 0.88;
		}
		col *= 0.94 + 0.12 * jit;
		// voxel block seams on the side faces
		float lay = fract(w_pos.y / cell);
		float along = fract(dot(w_pos.xz, vec2(abs(n.z), abs(n.x))) / cell);
		float e = min(min(lay, 1.0 - lay), min(along, 1.0 - along));
		col *= 1.0 - side_lines * (1.0 - smoothstep(0.0, 0.07, e));
	}
	ALBEDO = col;
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}

// VoxelRacing (P004): little voxel spectators, animated entirely here.
// Mesh parts (UV2.x): 0 legs, 1 torso, 2 head, 3 left arm, 4 right arm,
// 5 flag stick, 6 cap / hair, 7 flag cloth. The figure faces +Z.
// INSTANCE_CUSTOM: r = phase 0..1, g = excitement 0..1, b = head look
// (0.5 = straight ahead), a = (shirt + 16 * cloth) / 255 palette indices.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;

uniform vec3 palette[16];
uniform float flags = 0.0;      // 1: the right hand holds a flag up
uniform float calm = 0.0;       // marshals: less bouncing

varying flat float v_part;
varying flat vec3 v_shirt;
varying flat vec3 v_cloth;
varying flat vec3 v_skin;

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

void vertex() {
	float part = floor(UV2.x + 0.5);
	v_part = part;
	float phase = INSTANCE_CUSTOM.r * 6.2832;
	float ex = INSTANCE_CUSTOM.g;
	float look = (INSTANCE_CUSTOM.b - 0.5) * 3.0;
	float idx = floor(INSTANCE_CUSTOM.a * 255.0 + 0.5);
	v_shirt = palette[int(mod(idx, 16.0))];
	v_cloth = palette[int(floor(idx / 16.0))];
	float tone = fract(INSTANCE_CUSTOM.r * 7.31);
	v_skin = mix(vec3(0.93, 0.62, 0.45), vec3(0.36, 0.2, 0.12), tone * tone);
	float t = TIME;
	vec3 v = VERTEX;
	vec3 n = NORMAL;
	// arms (and what they hold) swing out and up around the shoulder
	if (part >= 2.5 && part <= 5.5 || part > 6.5) {
		float side = part < 3.5 ? -1.0 : 1.0;
		float a = 0.07 * sin(t * 1.6 + phase + side) + ex * (2.45 + 0.35 * sin(t * 9.0 + phase * 2.0 + side));
		if (flags > 0.5 && side > 0.0) {
			a = 2.75 + (0.18 + 0.32 * ex) * sin(t * (3.0 + 5.0 * ex) + phase);
		}
		vec2 piv = vec2(0.2 * side, 0.84);
		v.xy = rot(v.xy - piv, a * side) + piv;
		n.xy = rot(n.xy, a * side);
	}
	if (part > 6.5) {  // the cloth flutters
		v.z += 0.06 * sin(t * 11.0 + v.x * 12.0 + phase) * clamp(abs(VERTEX.x - 0.26) / 0.34, 0.0, 1.0);
	}
	// the head turns to watch
	if (part > 1.5 && part < 2.5 || part > 5.5 && part < 6.5) {
		v.xz = rot(v.xz, -look);
		n.xz = rot(n.xz, -look);
	}
	// idle bob; excited hops
	float hop = max(0.0, sin(t * (7.0 + 2.0 * fract(phase)) + phase * 1.3));
	v.y += 0.012 * sin(t * 2.1 + phase) + ex * (1.0 - calm) * 0.3 * hop * hop;
	VERTEX = v;
	NORMAL = n;
}

void fragment() {
	vec3 c = COLOR.rgb;
	if (v_part > 0.5 && v_part < 1.5) {
		c = v_shirt;
	} else if (v_part > 1.5 && v_part < 2.5) {
		c = v_skin;
	} else if (v_part > 2.5 && v_part < 4.5) {
		c = v_shirt * 0.92;  // sleeves
		if (UV2.y > 0.5) {
			c = v_skin;  // hands
		}
	} else if (v_part > 5.5 && v_part < 6.5) {
		c = v_shirt * 0.55;  // the cap in the team colour
	} else if (v_part > 6.5) {
		c = v_cloth;
	}
	ALBEDO = c;
	ROUGHNESS = 0.9;
}

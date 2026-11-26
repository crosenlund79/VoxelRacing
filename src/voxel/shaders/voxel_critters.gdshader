// VoxelRacing (P004): butterflies over the flowers and birds high above,
// animated entirely here. Mesh: body along +X, wings (UV2.x: 0 left, 1 right,
// 2 body) hinged on the body axis. Each instance wanders on its own loop
// around its anchor (the instance transform). INSTANCE_CUSTOM.r = phase.
shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;

uniform float radius = 1.4;
uniform float height = 0.6;
uniform float bob = 0.35;
uniform float speed = 0.8;
uniform float flap_speed = 26.0;
uniform float flap = 0.9;

vec2 rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

vec3 path(float t, float ph) {
	return vec3(cos(t * speed + ph) * radius + sin(t * speed * 2.3 + ph * 3.0) * radius * 0.3,
		height + sin(t * speed * 1.7 + ph * 2.0) * bob,
		sin(t * speed * 0.9 + ph * 1.7) * radius);
}

void vertex() {
	float ph = INSTANCE_CUSTOM.r * 6.2832;
	float t = TIME + ph * 3.0;
	float part = floor(UV2.x + 0.5);
	vec3 v = VERTEX;
	if (part < 1.5) {
		float side = part < 0.5 ? -1.0 : 1.0;
		float a = (0.25 + sin(t * flap_speed) * flap) * side;
		v.yz = rot(v.yz, a);
	}
	vec3 p0 = path(t, ph);
	vec3 p1 = path(t + 0.05, ph);
	vec3 d = p1 - p0;
	float yaw = atan(d.z, d.x);
	v.xz = rot(v.xz, yaw);
	VERTEX = v + p0;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.95;
}

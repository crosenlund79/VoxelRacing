// VoxelRacing: a gentle tilt-shift ("miniature") blur on the top and bottom
// bands of the 3D view only (the 2D HUD and effects are drawn after it).
// A full-screen quad samples the screen texture at a higher mip level the
// further a pixel is from the middle band. Works in Forward+ and Compatibility.
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, skip_vertex_transform, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
// Maximum mip level at the very edges, and the share of the screen height
// (from each edge) over which the blur fades in.
uniform float amount = 0.0;
uniform float band = 0.24;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	float e = abs(SCREEN_UV.y - 0.5) * 2.0;
	float w = smoothstep(1.0 - band * 2.0, 1.0, e);
	float lod = w * w * amount;
	vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb;
	if (lod > 0.3) {  // soften the mip blocks a little
		vec2 px = lod / vec2(textureSize(screen_tex, 0));
		c = (c * 2.0 + textureLod(screen_tex, SCREEN_UV + vec2(px.x, px.y), lod).rgb
			+ textureLod(screen_tex, SCREEN_UV - vec2(px.x, px.y), lod).rgb) * 0.25;
	}
	ALBEDO = c;
}

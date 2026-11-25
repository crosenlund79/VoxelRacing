shader_type canvas_item;
// Visual damage (DamageView): the shared wear drawing blended into a car's
// body - only where the body itself is painted - by `amount` (0 healthy ..
// 1 critical), plus a slight darkening. Read-only presentation.
uniform sampler2D wear : filter_linear;
uniform float amount = 0.0;

void fragment() {
	vec4 body = texture(TEXTURE, UV);
	vec4 w = texture(wear, UV);
	float k = clamp(amount, 0.0, 1.0);
	vec3 rgb = mix(body.rgb, w.rgb, w.a * k);
	float lum = dot(rgb, vec3(0.299, 0.587, 0.114));
	rgb = mix(rgb, vec3(lum), 0.3 * k);  // paint loses its shine
	rgb *= 1.0 - 0.2 * k;
	COLOR = vec4(rgb, body.a) * COLOR;
}

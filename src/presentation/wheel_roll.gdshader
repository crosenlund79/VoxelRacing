shader_type canvas_item;
// Rolling tread for the shared wheel (CarWheels): the wheel image's colours
// scroll along X (the rolling direction) by `roll` texture widths, inside the
// image's own unmoved outline, so any wheel drawing appears to roll.
// Where the scrolled sample falls on a transparent pixel (rounded tyre ends)
// the wheel's own colour is kept.
uniform float roll = 0.0;

void fragment() {
	vec4 own = texture(TEXTURE, UV);
	vec4 moved = texture(TEXTURE, vec2(fract(UV.x + roll), UV.y));
	vec3 rgb = mix(own.rgb, moved.rgb, step(0.5, moved.a));
	COLOR = vec4(rgb, own.a) * COLOR;
}

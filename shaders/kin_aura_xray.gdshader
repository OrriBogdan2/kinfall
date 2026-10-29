shader_type spatial;
// The same glow shell, drawn through grass and walls: your own and your teammates' kin always show.
// inside so it reads as an outline that's brightest at the silhouette.
render_mode unshaded, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, blend_add;
uniform vec4 color : source_color = vec4(1.0);
uniform float strength = 0.6;
uniform float grow = 0.035;
void vertex() {
	VERTEX += NORMAL * grow * (1.0 + 0.25 * sin(TIME * 4.0));
}
void fragment() {
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	float pulse = 0.85 + 0.15 * sin(TIME * 3.0);
	ALBEDO = color.rgb;
	ALPHA = clamp((0.06 + rim * 1.25) * strength * color.a * pulse, 0.0, 1.0);
}

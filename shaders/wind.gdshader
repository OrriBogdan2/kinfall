shader_type spatial;
// A current of air: soft streaks that flow along the mesh's length (UV.x) and fade at the edges.
render_mode unshaded, shadows_disabled, blend_add, depth_draw_never, cull_disabled;
uniform vec4 color : source_color = vec4(0.7, 0.95, 1.0, 0.5);
uniform float speed = 1.2;
uniform float tiles = 6.0;
void fragment() {
	float along = fract(UV.x * tiles - TIME * speed);
	float streak = smoothstep(0.0, 0.25, along) * (1.0 - smoothstep(0.35, 0.6, along));
	float across = 1.0 - abs(UV.y * 2.0 - 1.0);
	float ends = smoothstep(0.0, 0.06, UV.x) * (1.0 - smoothstep(0.94, 1.0, UV.x));
	ALBEDO = color.rgb;
	ALPHA = color.a * (0.25 + 0.75 * streak) * pow(across, 1.5) * ends;
}

shader_type spatial;
// Ground warning for incoming attacks. shape 0 = circle, 1 = rectangle that fills along its length.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0, 0.3, 0.2, 1.0);
uniform float progress = 0.0;
uniform int shape = 0;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float a = 0.0;
	if (shape == 0) {
		float r = length(uv);
		if (r > 1.0) { discard; }
		float edge = smoothstep(0.84, 0.93, r);
		float fill = step(r, progress) * 0.38;
		a = max(edge * 0.95, fill) + 0.1;
	} else {
		float edge = smoothstep(0.82, 0.95, abs(uv.x));
		float fill = step(1.0 - UV.y, progress) * 0.38;
		a = max(edge * 0.8, fill) + 0.1;
	}
	ALBEDO = color.rgb;
	ALPHA = a * color.a;
}

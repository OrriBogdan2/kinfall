shader_type spatial;
// A flat ring on the ground: team markers, shockwaves, revive progress.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0);
uniform float thickness = 0.12;
uniform float fill = 0.0;
uniform float arc = 1.0;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float ang = (atan(uv.x, -uv.y) / 6.2831853) + 0.5;
	float ring = smoothstep(1.0 - thickness - 0.04, 1.0 - thickness, r) * (1.0 - smoothstep(0.96, 1.0, r));
	if (ang > arc) { ring = 0.0; }
	float a = max(ring, step(r, 1.0) * fill);
	if (a <= 0.001) { discard; }
	ALBEDO = color.rgb;
	ALPHA = a * color.a;
}

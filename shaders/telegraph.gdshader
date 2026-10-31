shader_type spatial;
// Ground warning for incoming attacks. shape 0 = circle, 1 = rectangle that fills along its length.
// A crisp bright border, a faint field striped with slow diagonal hatching (so a warning never reads
// as a friendly marker), and the fill growing toward the edge with a hot leading line, so when it
// will land reads at a glance.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform vec4 color : source_color = vec4(1.0, 0.3, 0.2, 1.0);
uniform float progress = 0.0;
uniform int shape = 0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float a = 0.0;
	float hot = 0.0;
	float hatch = step(0.5, fract((wp.x + wp.z) * 1.6 - TIME * 0.8)) * 0.1;
	if (shape == 0) {
		float r = length(uv);
		if (r > 1.0) { discard; }
		float edge = smoothstep(0.86, 0.93, r) * (1.0 - smoothstep(0.985, 1.0, r));
		float inner = smoothstep(0.3, 0.95, r) * 0.18;
		float fill = step(r, progress) * (0.26 + 0.14 * r);
		float lead = (1.0 - smoothstep(0.0, 0.035, abs(r - progress))) * step(0.02, progress);
		a = max(max(edge, fill), inner + hatch) + lead * 0.7 + 0.06;
		hot = lead + edge * 0.35;
	} else {
		float sx = abs(uv.x);
		float edge = smoothstep(0.84, 0.94, sx) * (1.0 - smoothstep(0.985, 1.0, sx));
		float along = 1.0 - UV.y;
		float fill = step(along, progress) * 0.32;
		float lead = (1.0 - smoothstep(0.0, 0.025, abs(along - progress))) * step(0.02, progress);
		float inner = smoothstep(0.2, 0.95, sx) * 0.15;
		a = max(max(edge * 0.9, fill), inner + hatch) + lead * 0.7 + 0.06;
		hot = lead + edge * 0.3;
	}
	ALBEDO = mix(color.rgb, vec3(1.0, 0.95, 0.85), hot * 0.45);
	ALPHA = clamp(a, 0.0, 1.0) * color.a;
}

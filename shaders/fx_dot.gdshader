shader_type spatial;
// Particle bursts (hits, dust, pickups, explosions): a camera-facing soft dot with a crisp bright
// core, coloured by the particle (COLOR, faded by the burst's ramp). Dusty, pale colours stay soft
// puffs; bright colours get a white-hot centre.
render_mode unshaded, shadows_disabled, depth_draw_never, blend_mix, cull_disabled, fog_disabled;
uniform float core = 0.55;
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	if (d > 1.0) { discard; }
	float sat = max(max(COLOR.r, COLOR.g), COLOR.b) - min(min(COLOR.r, COLOR.g), COLOR.b);
	float hot = smoothstep(0.15, 0.45, sat);
	float body = 1.0 - smoothstep(0.35, 1.0, d);
	float c = 1.0 - smoothstep(0.0, 0.42, d);
	ALBEDO = mix(COLOR.rgb, vec3(1.0), c * core * hot) * (1.0 + hot * 0.6);
	ALPHA = clamp(body * (0.75 + hot * 0.25) + c * 0.3, 0.0, 1.0) * COLOR.a;
}

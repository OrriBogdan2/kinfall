shader_type spatial;
// A hit flash: a camera-facing star of sharp rays round a white-hot core, inside a soft glow,
// fading out as `life` runs from 0 to 1.
render_mode unshaded, shadows_disabled, depth_draw_never, blend_add, cull_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.8, 0.4, 1.0);
uniform float life = 0.0;
uniform float seed = 0.0;
uniform float rays = 6.0;
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float a = atan(uv.y, uv.x) + seed;
	float star = pow(abs(cos(a * rays * 0.5)), 18.0) * (1.0 - smoothstep(0.1, 0.95, d));
	float star2 = pow(abs(cos(a * rays * 0.5 + 1.5708 / rays)), 30.0) * (1.0 - smoothstep(0.05, 0.6, d)) * 0.6;
	float core = 1.0 - smoothstep(0.0, 0.28 + life * 0.2, d);
	float glow = (1.0 - smoothstep(0.0, 1.0, d)) * 0.35;
	float k = 1.0 - life;
	vec3 c = color.rgb * (glow + star + star2) + vec3(1.0) * core;
	ALBEDO = c * k * color.a;
	ALPHA = 1.0;
}

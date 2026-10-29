shader_type spatial;
// A soft cloud billboard: a lumpy round puff, lit warm on the sun's side and cool underneath,
// fading at its edges and close to the camera so ships can sail through them.
render_mode unshaded, shadows_disabled, depth_draw_never, blend_mix, cull_disabled, fog_disabled;
uniform vec4 lit : source_color = vec4(1.0, 0.86, 0.72, 1.0);
uniform vec4 shade : source_color = vec4(0.55, 0.5, 0.78, 1.0);
uniform float seed = 0.0;
uniform float alpha = 0.85;
uniform vec2 sun_side = vec2(0.6, 0.4);
#include "res://shaders/noise.gdshaderinc"
varying float cam_d;
void vertex() {
	// face the camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	cam_d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float n = fbm3(uv * 2.2 + seed * 7.3);
	float n2 = vnoise(uv * 6.0 + seed * 3.1);
	// a squashed blob with a flatter bottom
	vec2 q = uv * vec2(1.0, 1.25);
	q.y = q.y > 0.0 ? q.y * 1.35 : q.y;
	float d = length(q) - 0.55 - n * 0.42 - n2 * 0.06;
	float a = 1.0 - smoothstep(-0.12, 0.08, d);
	float light = clamp(dot(normalize(-uv + vec2(0.0001)), normalize(vec2(-sun_side.x, sun_side.y))) * 0.5 + 0.5, 0.0, 1.0);
	light = mix(light, 1.0 - UV.y, 0.5);
	vec3 col = mix(shade.rgb, lit.rgb, smoothstep(0.25, 0.85, light + n * 0.25));
	// a soft bright rim where the sun catches the edge
	col += lit.rgb * smoothstep(0.0, -0.08, d) * (1.0 - smoothstep(-0.08, -0.25, d)) * 0.25 * light;
	ALBEDO = col;
	ALPHA = a * alpha * smoothstep(4.0, 14.0, cam_d);
}

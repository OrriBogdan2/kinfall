shader_type spatial;
// A soft shaft of sunlight: a long quad that turns round its own length to face the camera, bright
// along its middle, fading to nothing at its sides and ends, with slow drifting streaks inside.
render_mode unshaded, shadows_disabled, depth_draw_never, blend_add, cull_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.82, 0.6, 1.0);
uniform float intensity = 0.1;
uniform float seed = 0.0;
#include "res://shaders/noise.gdshaderinc"
void vertex() {
	vec3 axis = normalize(MODEL_MATRIX[1].xyz);
	float len = length(MODEL_MATRIX[1].xyz);
	float wid = length(MODEL_MATRIX[0].xyz);
	vec3 org = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - org);
	vec3 side = normalize(cross(axis, to_cam));
	vec3 nrm = cross(side, axis);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side * wid, 0.0), vec4(axis * len, 0.0), vec4(nrm, 0.0), vec4(org, 1.0));
}
void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float across = 1.0 - smoothstep(0.0, 1.0, x);
	across *= across;
	float along = smoothstep(0.0, 0.25, 1.0 - UV.y) * smoothstep(0.0, 0.5, UV.y);
	float streak = 0.65 + 0.35 * vnoise(vec2(UV.x * 7.0 + seed * 3.0, UV.y * 1.5 - TIME * 0.05 + seed));
	ALBEDO = color.rgb * intensity * across * along * streak;
}

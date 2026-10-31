shader_type spatial;
// Ambient particles in the air (pollen, snow, embers, spores, sparks, motes): a camera-facing soft
// dot with a bright core, or a tumbling petal. COLOR comes from the particle system (its ramp fades
// each one in and out).
render_mode unshaded, shadows_disabled, depth_draw_never, blend_add, cull_disabled, fog_disabled;
uniform float softness = 1.0;    // 1 soft glow .. 0 crisp flake
uniform float core = 0.6;        // how bright the middle is
uniform float stretch = 1.0;     // >1 stretches along the motion (sparks)
uniform bool petal = false;      // a petal shape instead of a round dot
uniform float intensity = 1.0;
#include "res://shaders/vis.gdshaderinc"
varying vec3 wp;
void vertex() {
	wp = MODEL_MATRIX[3].xyz;
	if (!petal) {
		float s = length(MODEL_MATRIX[0].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s * stretch, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	}
}
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d;
	if (petal) {
		d = length(vec2(uv.x * 1.6, uv.y + uv.x * uv.x * 0.6));
	} else {
		d = length(uv);
	}
	float body = 1.0 - smoothstep(mix(0.55, 0.15, softness), 1.0, d);
	float c = 1.0 - smoothstep(0.0, 0.35, d);
	float fog = vis_fog(wp);
	ALBEDO = (COLOR.rgb * body + vec3(1.0) * c * core * body) * intensity * (1.0 - fog * 0.75);
	ALPHA = body * COLOR.a;
}

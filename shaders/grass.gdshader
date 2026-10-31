shader_type spatial;
// Grass tufts and tall grass: blades darker at the root, sunlit at the tip, swaying in the wind.
render_mode cull_disabled;
uniform float sway = 0.1;
uniform float shade = 0.55;
uniform vec4 tip_tint : source_color = vec4(1.08, 1.1, 0.86, 1.0);
#include "res://shaders/vis.gdshaderinc"
#include "res://shaders/noise.gdshaderinc"
varying vec3 wpos;
varying float tipk;
varying vec3 org;
void vertex() {
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float k = UV.y;
	float t = TIME * 1.7 + origin.x * 0.31 + origin.z * 0.23;
	float gust = sin(TIME * 0.6 + origin.x * 0.05) * 0.5 + 0.5;
	VERTEX.x += sin(t) * sway * k * k * (0.6 + gust);
	VERTEX.z += cos(t * 0.83) * sway * 0.6 * k * k;
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.75));
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tipk = k;
	org = origin;
}
void fragment() {
	// broad swathes of yellower and bluer grass across the ground, then dark roots and sunlit tips
	vec3 base = COLOR.rgb * mix(vec3(0.92, 0.98, 1.05), vec3(1.07, 1.04, 0.88), vnoise(org.xz * 0.11));
	vec3 c = base * mix(vec3(0.5, 0.55, 0.6), tip_tint.rgb, tipk);
	c += base * smoothstep(0.7, 1.0, tipk) * 0.1;
	c = vis_apply(c, vis_fog(wpos));
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		// lamps and glows: plain falloff. (The cel shade floor below is only for the sun; on a lamp
		// it lit whole screen clusters at once, which showed up as blocky squares at night.)
		float pl = smoothstep(-0.1, 0.4, dot(NORMAL, LIGHT)) * ATTENUATION;
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * pl;
	} else {
		float ndl = dot(NORMAL, LIGHT);
		float lit = smoothstep(-0.1, 0.4, ndl) * ATTENUATION;
		lit = mix(shade, 1.0, lit);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * lit;
	}
}

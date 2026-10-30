shader_type spatial;
// Stylized painted lighting: warm key light, cool coloured shadows, light from the sky above and a
// darker underside, a little hand-painted variation across each surface, a soft rim and an
// optional glossy highlight. Plus the hit flash.
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_amount = 0.35;
uniform vec4 rim_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform float glow = 0.0;
uniform float shade = 0.42;
uniform bool no_fog = false;
uniform vec4 shadow_tint : source_color = vec4(0.66, 0.62, 0.9, 1.0);   // shadows lean cool and violet
uniform vec4 light_tint : source_color = vec4(1.05, 1.0, 0.93, 1.0);    // light leans warm
uniform float paint = 0.07;     // how much the colour wanders across a surface
uniform float sky_ao = 0.22;    // undersides darker, tops lit by the sky
uniform float gloss = 0.0;      // 0 matte .. 1 shiny (a crisp highlight band)
#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/vis.gdshaderinc"
varying vec3 lpos;
varying vec3 wnorm;

void vertex() {
	lpos = VERTEX;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) { c *= COLOR.rgb; }
	// hand-painted variation: soft blotches of slightly lighter and darker paint
	float n = vnoise(lpos.xz * 7.0 + lpos.y * 4.0) * 0.6 + vnoise(lpos.xy * 15.0 + 3.1) * 0.4;
	c *= 1.0 + (n - 0.5) * 2.0 * paint;
	// sky light from above, a little bounce from below: shapes read as solid from the high camera
	c *= mix(1.0 - sky_ao, 1.0 + sky_ao * 0.3, wnorm.y * 0.5 + 0.5);
	float fog = no_fog ? 0.0 : vis_fog((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	c = vis_apply(c, fog);
	ALBEDO = mix(c, flash_color.rgb, flash);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = flash_color.rgb * flash * 0.9 + c * glow + rim_color.rgb * rim * rim_amount * 0.35 * (1.0 - fog);
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
		float lit = smoothstep(0.0, 0.06, ndl) * ATTENUATION;
		float band = smoothstep(0.35, 0.65, lit);
		// shadows take on a cool tint instead of just going grey; lit sides warm up a touch
		vec3 tone = mix(vec3(shade) * shadow_tint.rgb, light_tint.rgb, band);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * tone;
		if (gloss > 0.0) {
			vec3 hv = normalize(LIGHT + VIEW);
			float sp = pow(max(dot(NORMAL, hv), 0.0), mix(12.0, 90.0, gloss));
			SPECULAR_LIGHT += LIGHT_COLOR * smoothstep(0.45, 0.55, sp) * 0.35 * gloss * band * ATTENUATION;
		}
	}
}

shader_type spatial;
// Two-band cel lighting with a soft rim, plus a hit flash.
uniform vec4 albedo : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float rim_amount = 0.35;
uniform float glow = 0.0;
uniform float shade = 0.42;
uniform bool no_fog = false;
#include "res://shaders/vis.gdshaderinc"

void fragment() {
	vec3 c = albedo.rgb;
	if (use_vertex_color) { c *= COLOR.rgb; }
	float fog = no_fog ? 0.0 : vis_fog((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	c = vis_apply(c, fog);
	ALBEDO = mix(c, flash_color.rgb, flash);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = flash_color.rgb * flash * 0.9 + c * glow + vec3(1.0, 0.96, 0.88) * rim * rim_amount * 0.35 * (1.0 - fog);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.06, ndl) * ATTENUATION;
	lit = mix(shade, 1.0, smoothstep(0.35, 0.65, lit));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * lit;
}

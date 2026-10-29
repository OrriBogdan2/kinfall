shader_type spatial;
// The islands. Vertex colours give each tile its biome colour; this adds painterly grass patches and
// speckles on top, and layered rock strata, cracks and a darker base on the cliffs.
uniform float shade = 0.5;
uniform vec4 rim_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float rim_amount = 0.16;
uniform vec4 ao_color : source_color = vec4(0.12, 0.1, 0.18, 1.0);
#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/vis.gdshaderinc"
varying vec3 wpos;
varying vec3 wnorm;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec3 c = COLOR.rgb;
	float up = wnorm.y;
	if (up > 0.5) {
		// soft patches of lighter and darker ground, then tiny speckles of light
		float n = fbm3(wpos.xz * 0.22);
		c *= 0.86 + n * 0.28;
		float d = vnoise(wpos.xz * 1.6 + vec2(n * 3.0));
		c = mix(c, c * vec3(1.08, 1.12, 0.92), smoothstep(0.55, 0.9, d) * 0.45);
		float sp = vnoise(wpos.xz * 9.0);
		c += vec3(0.05, 0.06, 0.02) * smoothstep(0.86, 0.98, sp);
	} else if (up > -0.5) {
		float along = abs(wnorm.x) > 0.5 ? wpos.z : wpos.x;
		// strata: wobbly horizontal bands of rock
		float y = wpos.y * 1.6 + vnoise(vec2(along * 0.6, wpos.y * 0.3)) * 1.4;
		float band = fract(y);
		float strata = smoothstep(0.0, 0.1, band) * (1.0 - smoothstep(0.82, 1.0, band));
		float layer = h21(vec2(floor(y), 3.0));
		c *= 0.84 + strata * 0.12 + layer * 0.1;
		// cracks and chips
		float cr = vnoise(vec2(along * 3.1, wpos.y * 0.45));
		c *= 1.0 - smoothstep(0.88, 0.97, cr) * 0.4;
		c *= 0.94 + vnoise(vec2(along * 2.2, wpos.y * 2.2)) * 0.12;
		// darker toward the bottom, and shadowed just under the grass lip
		c = mix(c, ao_color.rgb, clamp(-wpos.y * 0.05, 0.0, 0.45));
	} else {
		c = mix(c, ao_color.rgb, 0.5);
	}
	float fog = vis_fog(wpos);
	c = vis_apply(c, fog);
	ALBEDO = c;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * rim_amount * (1.0 - fog);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.05, 0.25, ndl) * ATTENUATION;
	lit = mix(shade, 1.0, smoothstep(0.3, 0.7, lit));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * lit;
}

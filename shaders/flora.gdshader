shader_type spatial;
// The world's sculpted props (scripts/match/flora.gd): trees, boulders, bushes, flowers, crystals.
// Their colour is painted into the vertices (light tops, cool undersides, dark creases between leaf
// clumps); this adds the wind, hand-painted brushwork per material, the same warm-key / cool-shadow
// three-tone ramp as the characters (shaders/toon.gdshader), soft wrapped light through foliage, a
// crisp rim, and glow where the vertex alpha says so (embers, crystals).
// UV.x is the material: 0 leaves, 1 bark, 2 stone, 3 crystal, 4 snow, 5 petals, 6 moss.
// UV2.x is how far a vertex bends in the wind (0 at the roots), UV2.y how much it flutters.
uniform float sway = 0.06;          // metres the crown leans at full gust
uniform float flutter = 0.025;      // leaf jitter
uniform float glow = 2.2;           // emission strength where vertex alpha < 1
uniform float shade = 0.44;
uniform vec4 shadow_tint : source_color = vec4(0.64, 0.62, 0.92, 1.0);
uniform vec4 light_tint : source_color = vec4(1.06, 1.0, 0.92, 1.0);
uniform float rim_amount = 0.4;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.84, 1.0);
uniform float wrap = 0.0;           // foliage: light wraps further round, like light through leaves
uniform float sky_ao = 0.18;
uniform float brush = 1.0;          // brushwork strength
#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/vis.gdshaderinc"
varying vec3 lpos;
varying vec3 wpos;
varying flat float mat_id;
varying float glow_k;
varying float wy;

void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	float w = UV2.x;
	if (w > 0.0 && sway > 0.0) {
		float ph = org.x * 0.37 + org.z * 0.29;
		float gust = 0.55 + 0.45 * sin(TIME * 0.45 + org.x * 0.045 + org.z * 0.03);
		vec3 off = vec3(sin(TIME * 1.15 + ph), 0.0, cos(TIME * 0.93 + ph * 1.3) * 0.6) * sway * gust * w * w;
		float f = UV2.y * flutter;
		off += vec3(sin(TIME * 4.1 + VERTEX.y * 6.0 + ph * 3.0), sin(TIME * 3.3 + VERTEX.x * 5.0) * 0.4, cos(TIME * 3.7 + VERTEX.x * 6.0 + ph)) * f;
		// the offset is in world space: bring it into the instance's own (rotated, scaled) space
		mat3 m = mat3(MODEL_MATRIX);
		float s2 = max(dot(m[0], m[0]), 0.0001);
		VERTEX += transpose(m) * off / s2;
	}
	lpos = VERTEX;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wy = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	mat_id = UV.x;
	glow_k = 1.0 - COLOR.a;
}

void fragment() {
	vec3 c = COLOR.rgb;
	int id = int(mat_id + 0.5);
	float fw = fwidth(lpos.y) * 40.0;
	float near_k = (1.0 - smoothstep(0.4, 1.4, fw)) * brush;
	// soft blotches of lighter and darker paint everywhere
	float n = vnoise(wpos.xz * 1.3 + wpos.y * 0.9) * 0.6 + vnoise(lpos.xz * 6.0 + lpos.y * 3.0) * 0.4;
	c *= 0.94 + n * 0.12;
	if (id == 0 || id == 5) {
		// leaves: clustered dabs, brighter on top, darker where they turn away
		float d = vnoise(lpos.xz * 9.0 + lpos.y * 7.0) * 0.65 + vnoise(lpos.xy * 17.0 + lpos.z * 5.0) * 0.35;
		float dab = smoothstep(0.52, 0.72, d);
		c *= 1.0 + (dab * mix(-0.1, 0.2, smoothstep(-0.2, 0.7, wy)) - 0.03) * near_k;
	} else if (id == 1) {
		// bark: long vertical strokes
		float st = vnoise(vec2((lpos.x + lpos.z) * 22.0, lpos.y * 2.5)) * 0.7 + vnoise(vec2((lpos.x - lpos.z) * 40.0, lpos.y * 5.0)) * 0.3;
		c *= 1.0 + (st - 0.5) * 0.3 * near_k;
	} else if (id == 2) {
		// stone: thin strata and chipped flecks
		float y = lpos.y * 5.0 + vnoise(lpos.xz * 2.0) * 1.4;
		float band = fract(y);
		c *= 1.0 - (smoothstep(0.0, 0.06, band) * (1.0 - smoothstep(0.1, 0.18, band))) * 0.12 * near_k;
		float fl = vnoise(lpos.xz * 14.0 + lpos.yy * 9.0);
		c *= 1.0 + (smoothstep(0.7, 0.85, fl) * 0.1 - smoothstep(0.15, 0.05, fl) * 0.08) * near_k;
	} else if (id == 3) {
		// crystal: a bright inner facet that shifts with the view
		vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
		c *= 0.8 + 0.55 * smoothstep(0.0, 0.85, r.y);
	} else if (id == 4) {
		// snow: soft sparkle
		float sp = vnoise(lpos.xz * 30.0 + lpos.yy * 20.0);
		c += vec3(0.12) * smoothstep(0.9, 0.97, sp) * near_k;
	} else if (id == 6) {
		float d = vnoise(lpos.xz * 14.0 + lpos.y * 8.0);
		c *= 1.0 + (d - 0.5) * 0.22 * near_k;
	}
	// light from the sky above, a little darker underneath
	c *= mix(1.0 - sky_ao, 1.0 + sky_ao * 0.25, wy * 0.5 + 0.5);
	float fog = vis_fog(wpos);
	c = vis_apply(c, fog);
	ALBEDO = c;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = c * glow_k * glow * (1.0 - fog * 0.6) + rim_color.rgb * rim * rim_amount * 0.1 * (1.0 - fog);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	if (!LIGHT_IS_DIRECTIONAL) {
		float pl = smoothstep(-0.1, 0.4, dot(NORMAL, LIGHT)) * ATTENUATION;
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * pl;
	} else {
		float ndl = dot(NORMAL, LIGHT);
		float lo = mix(-0.03, -0.32, wrap);
		float lit = smoothstep(lo, lo + 0.2, ndl) * mix(ATTENUATION, 1.0, wrap * 0.25);
		float band = smoothstep(0.2, 0.8, lit);
		float face = smoothstep(0.42, 0.8, ndl) * ATTENUATION;
		vec3 tone = mix(vec3(shade) * shadow_tint.rgb, light_tint.rgb, band) * mix(0.93, 1.07, face);
		// warm bounce along the terminator
		float term = smoothstep(-0.34, 0.02, ndl) * (1.0 - smoothstep(0.02, 0.32, ndl));
		tone += vec3(1.0, 0.62, 0.4) * term * 0.1;
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * tone;
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float rim_l = smoothstep(0.66, 0.8, fres) * smoothstep(-0.25, 0.45, ndl);
		DIFFUSE_LIGHT += rim_color.rgb * LIGHT_COLOR * rim_l * rim_amount * 0.26 * mix(0.45, 1.0, ATTENUATION);
	}
}

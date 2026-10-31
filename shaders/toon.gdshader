shader_type spatial;
// Stylized painted lighting: warm key light, cool coloured shadows, light from the sky above and a
// darker underside, a whisper of hand-painted variation, a clean three-tone ramp with a soft
// terminator and a band of warm "subsurface" glow where light turns to shadow, a crisp rim that
// catches the key and fill lights, and an optional glossy highlight. Plus the hit flash.
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
uniform float paint = 0.035;    // how much the colour wanders across a surface
uniform float sky_ao = 0.22;    // undersides darker, tops lit by the sky
uniform float gloss = 0.0;      // 0 matte .. 1 shiny (a crisp highlight band)
uniform float sss = 0.18;       // warm glow along the terminator (skin, fur, soft things)
uniform vec4 sss_color : source_color = vec4(1.0, 0.45, 0.32, 1.0);
uniform float sheen = 0.06;     // a soft broad highlight on every surface facing the light
// Imported low-poly models carry each corner's averaged (smooth) normal in TANGENT (Assets.mesh).
// Blending toward it rounds off their facets in the shading while the silhouette stays crisp.
uniform float soften = 0.0;
// Imported (CC0 pack) models: their colours come from a shared palette texture. One band of hues in
// it (say the green of the leaves) can be repainted, keeping the texture's shading, so the same tree
// takes each biome's foliage colour. With use_vertex_color the per-instance colour is the repaint
// target instead (MultiMesh scatter), and the base albedo still tints everything.
uniform bool use_tex = false;
uniform sampler2D albedo_tex : source_color, filter_linear, repeat_disable;
uniform vec4 recolor_to : source_color = vec4(1.0);
uniform float recolor = 0.0;          // 0 keeps the texture's colour .. 1 fully repainted
uniform float recolor_hue = 0.33;     // the hue band to repaint (0..1, red = 0, green = 0.33)
uniform float recolor_width = 0.1;    // half-width of the band
uniform float recolor_min_sat = 0.25; // greys, whites and near-blacks are left alone
uniform float recolor_min_val = 0.0;  // (dark trunks can share a hue with orange leaves)
uniform float recolor_ref = 0.6;      // the band's typical brightness, which maps onto recolor_to
uniform float tex_sat = 1.0;          // overall saturation of the texture's own colours
uniform float color_tint = 0.0;       // with use_vertex_color: how much the instance colour also tints the rest
#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/vis.gdshaderinc"
varying vec3 lpos;
varying vec3 wnorm;

void vertex() {
	if (soften > 0.0) { NORMAL = normalize(mix(NORMAL, TANGENT, soften)); }
	lpos = VERTEX;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}

void fragment() {
	vec3 c = albedo.rgb;
	if (use_tex) {
		vec3 t = texture(albedo_tex, UV).rgb;
		vec3 hsv = rgb2hsv(t);
		vec3 target = use_vertex_color ? COLOR.rgb : recolor_to.rgb;
		float dh = abs(fract(hsv.x - recolor_hue + 0.5) - 0.5);
		float band = (1.0 - smoothstep(recolor_width * 0.7, recolor_width, dh)) * smoothstep(recolor_min_sat, recolor_min_sat + 0.1, hsv.y)
			* smoothstep(recolor_min_val, recolor_min_val + 0.08, hsv.z);
		vec3 painted = target * clamp(hsv.z / max(recolor_ref, 0.05), 0.55, 1.35);
		float lum = dot(t, vec3(0.3, 0.59, 0.11));
		t = mix(vec3(lum), t, tex_sat);
		c *= mix(t, painted, band * recolor);
		if (use_vertex_color) { c *= mix(vec3(1.0), COLOR.rgb, color_tint * (1.0 - band * recolor)); }
	} else if (use_vertex_color) { c *= COLOR.rgb; }
	// hand-painted variation: soft blotches of slightly lighter and darker paint
	float n = vnoise(lpos.xz * 7.0 + lpos.y * 4.0) * 0.6 + vnoise(lpos.xy * 15.0 + 3.1) * 0.4;
	c *= 1.0 + (n - 0.5) * 2.0 * paint;
	// sky light from above, a little bounce from below: shapes read as solid from the high camera
	c *= mix(1.0 - sky_ao, 1.0 + sky_ao * 0.3, wnorm.y * 0.5 + 0.5);
	float fog = no_fog ? 0.0 : vis_fog((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	c = vis_apply(c, fog);
	ALBEDO = mix(c, flash_color.rgb, flash);
	// a faint rim everywhere (so silhouettes lift off dark ground even in shadow); the crisp,
	// light-facing rim is added per light below
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = flash_color.rgb * flash * 0.9 + c * glow + rim_color.rgb * rim * rim_amount * 0.12 * (1.0 - fog);
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
		// the main split: a soft but clean terminator, then a gentle lift on faces turned to the light
		float lit = smoothstep(-0.03, 0.16, ndl) * ATTENUATION;
		float band = smoothstep(0.2, 0.8, lit);
		float face = smoothstep(0.42, 0.78, ndl) * ATTENUATION;
		vec3 tone = mix(vec3(shade) * shadow_tint.rgb, light_tint.rgb, band) * mix(0.93, 1.06, face);
		// warm light bleeding through just past the terminator, like skin or fur
		float term = smoothstep(-0.34, 0.02, ndl) * (1.0 - smoothstep(0.02, 0.32, ndl)) * mix(0.35, 1.0, ATTENUATION);
		tone += sss_color.rgb * term * sss;
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * tone;
		// a crisp rim on the edge that faces this light (key light rims gold, the fill rims cool)
		float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float rim_l = smoothstep(0.6, 0.74, fres) * smoothstep(-0.25, 0.45, ndl);
		DIFFUSE_LIGHT += rim_color.rgb * LIGHT_COLOR * rim_l * rim_amount * 0.16 * mix(0.45, 1.0, ATTENUATION);
		vec3 hv = normalize(LIGHT + VIEW);
		float nh = max(dot(NORMAL, hv), 0.0);
		SPECULAR_LIGHT += LIGHT_COLOR * pow(nh, 16.0) * sheen * band;
		if (gloss > 0.0) {
			float sp = pow(nh, mix(14.0, 110.0, gloss));
			SPECULAR_LIGHT += LIGHT_COLOR * (smoothstep(0.42, 0.52, sp) * 0.55 + sp * 0.25) * gloss * band * ATTENUATION;
		}
	}
}

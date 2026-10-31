shader_type spatial;
// The islands. Vertex colours give each surface its biome colour; this adds painterly grass patches
// and speckles on the ground, soft contact shadows where ground meets a cliff or a rock, faceted rock
// strata on the cliffs, smooth slate on sheer faces and layered rock under the islands.
// UV.x says what a surface is (see scripts/match/terrain_mesh.gd); 0 = an older mesh, picked by normal.
uniform float shade = 0.5;
uniform vec4 rim_color : source_color = vec4(1.0, 0.94, 0.82, 1.0);
uniform float rim_amount = 0.16;
uniform vec4 ao_color : source_color = vec4(0.12, 0.1, 0.18, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.7, 0.66, 0.92, 1.0);   // shadows lean cool and violet
uniform vec4 light_tint : source_color = vec4(1.05, 1.0, 0.93, 1.0);    // light leans warm
// tile heights (R: (level + 1) / 32, 0 = void) and blockers (G), for contact shadows
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec2 map_size = vec2(64.0, 64.0);
uniform bool use_ao = false;
uniform float ao_strength = 0.75;
// per tile: R the biome style (meadow, bloom, frost, ember, storm, gloom = 0..5, over 8), G how much
// of a painted path or soil runs there. Nearest-sampled for the style, smooth for the path.
uniform sampler2D biome_tex : filter_nearest, repeat_disable;
uniform sampler2D path_tex : filter_linear, repeat_disable;
uniform bool use_biome = false;
uniform float detail = 1.0;
#include "res://shaders/noise.gdshaderinc"
#include "res://shaders/vis.gdshaderinc"
varying vec3 wpos;
varying vec3 wnorm;
varying float style;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	style = UV.x;
}

float hgt(vec2 p) {
	vec2 t = texture(height_tex, p / map_size).rg;
	return (t.r * 32.0 - 1.0) * 0.8 + t.g * 0.7;
}

// How much higher ground and blockers crowd around this spot (0 open .. 1 tucked in a corner).
float contact(vec3 p) {
	float occ = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398 + 0.39;
		vec2 d = vec2(cos(a), sin(a));
		float h1 = hgt(p.xz + d * 0.55);
		float h2 = hgt(p.xz + d * 1.15);
		occ += clamp((h1 - p.y - 0.05) * 1.6, 0.0, 1.0) * 0.6 + clamp((h2 - p.y - 0.05) * 1.1, 0.0, 1.0) * 0.4;
	}
	return clamp(occ / 3.2, 0.0, 1.0);
}

vec3 ground(vec3 c) {
	// soft patches of lighter and darker ground, then tiny speckles of light
	float n = fbm3(wpos.xz * 0.22);
	c *= 0.86 + n * 0.28;
	float d = vnoise(wpos.xz * 1.6 + vec2(n * 3.0));
	c = mix(c, c * vec3(1.08, 1.12, 0.92), smoothstep(0.55, 0.9, d) * 0.45);
	float sp = vnoise(wpos.xz * 9.0);
	c += vec3(0.05, 0.06, 0.02) * smoothstep(0.86, 0.98, sp);
	return c;
}

// Painted ground, per biome: brush patches and strokes, then each biome's own details (clover and
// flower specks, fallen petals, wind-blown snow drifts, ash with glowing cracks, cracked storm slate,
// glowing gloom veins), worn paths with pebbles, and a bright painted lip where ground meets a drop.
float cell_dot(vec2 p, float dens, float rad, float seed, out float pick) {
	vec2 q = p * dens;
	vec2 i = floor(q);
	vec2 f = fract(q);
	float h = h21(i + seed);
	vec2 o = vec2(h21(i + seed + 3.1), h21(i + seed + 7.7)) * 0.6 + 0.2;
	pick = h;
	return 1.0 - smoothstep(rad * 0.6, rad, length(f - o));
}
vec3 ground_rich(vec3 c, float n_in, out vec3 emit) {
	emit = vec3(0.0);
	int b = int(texture(biome_tex, wpos.xz / map_size).r * 8.0 + 0.5);
	float path = texture(path_tex, wpos.xz / map_size).g;
	float near_k = (1.0 - smoothstep(0.08, 0.3, fwidth(wpos.x))) * detail;
	// brush strokes: soft directional streaks, as if the ground were painted with a wide brush
	vec2 q = vec2(wpos.x * 0.8 + wpos.z * 0.6, -wpos.x * 0.6 + wpos.z * 0.8);
	float stroke = vnoise(vec2(q.x * 0.7, q.y * 3.2)) * 0.6 + vnoise(vec2(q.x * 1.6, q.y * 7.0)) * 0.4;
	c *= 0.95 + stroke * 0.1;
	// warm sunlit swathes and cool hollows
	float sw = fbm3(wpos.xz * 0.09 + 11.0);
	c = mix(c, c * vec3(1.1, 1.08, 0.88), smoothstep(0.55, 0.8, sw) * 0.6);
	c = mix(c, c * vec3(0.84, 0.9, 1.06), smoothstep(0.42, 0.15, sw) * 0.55);
	float pick;
	if (b == 0) {
		// meadow: clover dabs and the odd tiny flower
		float cl = smoothstep(0.62, 0.8, vnoise(wpos.xz * 2.6 + 3.0)) * smoothstep(0.4, 0.7, n_in);
		c = mix(c, c * vec3(0.82, 1.05, 0.78), cl * 0.5);
		float d = cell_dot(wpos.xz, 2.2, 0.12, 1.0, pick) * step(0.86, pick) * (1.0 - path);
		c = mix(c, mix(vec3(1.0, 0.95, 0.6), vec3(1.0), step(0.93, pick)), d * near_k * 0.85);
	} else if (b == 1) {
		// bloom: drifts of fallen petals, small and pink, thick in some places and absent in others
		float drift = smoothstep(0.5, 0.75, fbm3(wpos.xz * 0.16 + 2.0));
		vec2 pp = wpos.xz + vec2(vnoise(wpos.xz * 2.0)) * 0.3;
		float d = cell_dot(vec2(pp.x * 0.7, pp.y), 3.4, 0.11, 5.0, pick) * step(0.35 + (1.0 - drift) * 0.6, pick);
		c = mix(c, mix(vec3(0.95, 0.5, 0.72), vec3(1.0, 0.76, 0.88), pick), d * near_k * 0.7);
		c = mix(c, c * vec3(1.06, 0.95, 1.0), drift * 0.25);
	} else if (b == 2) {
		// frost: snow drifts in soft ridges, blue on their lee side, sparkling on top
		float dn = fbm3(wpos.xz * 0.25);
		float dr = sin(dot(wpos.xz, vec2(0.55, 0.3)) * 1.6 + dn * 6.0) * 0.5 + 0.5;
		float ridge = smoothstep(0.55, 0.95, dr) * smoothstep(0.3, 0.6, dn);
		float lee = smoothstep(0.35, 0.05, dr) * smoothstep(0.3, 0.6, dn);
		c = mix(c, vec3(0.97, 0.99, 1.04), ridge * 0.7);
		c = mix(c, c * vec3(0.78, 0.86, 1.04), lee * 0.5);
		float sp = cell_dot(wpos.xz, 7.0, 0.1, 2.0, pick) * step(0.8, pick);
		c += vec3(0.25) * sp * near_k * (0.5 + 0.5 * sin(TIME * 2.0 + pick * 30.0));
	} else if (b == 3) {
		// ember: grey ash drifts and cracks that glow
		float ash = smoothstep(0.5, 0.75, fbm3(wpos.xz * 0.35 + 4.0));
		c = mix(c, vec3(0.42, 0.38, 0.38), ash * 0.45);
		float cn = vnoise(wpos.xz * 0.75 + vec2(vnoise(wpos.xz * 2.0) * 0.6));
		float crack = 1.0 - smoothstep(0.0, 0.03, abs(cn - 0.5));
		crack *= smoothstep(0.45, 0.7, fbm3(wpos.xz * 0.2 + 9.0)) * (1.0 - path);
		c = mix(c, vec3(0.16, 0.08, 0.06), crack * 0.8);
		emit = vec3(1.0, 0.42, 0.12) * crack * (0.75 + 0.25 * sin(TIME * 1.3 + wpos.x * 0.7 + wpos.z * 0.4));
		float cin = cell_dot(wpos.xz, 4.0, 0.08, 4.0, pick) * step(0.82, pick);
		c = mix(c, vec3(0.2, 0.14, 0.13), cin * near_k);
	} else if (b == 4) {
		// storm: cracked slate slabs showing through the grass
		float sl = smoothstep(0.55, 0.7, fbm3(wpos.xz * 0.3 + 2.0));
		vec2 cq = wpos.xz * 0.9 + vec2(vnoise(wpos.xz * 1.5)) * 0.35;
		vec2 cf = fract(cq);
		float seam = 1.0 - smoothstep(0.0, 0.05, min(min(cf.x, 1.0 - cf.x), min(cf.y, 1.0 - cf.y)));
		float tone = h21(floor(cq));
		vec3 slate = mix(vec3(0.42, 0.44, 0.58), vec3(0.56, 0.58, 0.72), tone);
		c = mix(c, slate * (1.0 - seam * 0.45), sl * 0.7 * (1.0 - path));
	} else if (b == 5) {
		// gloom: faint veins of violet light under the dark ground
		float vn = vnoise(wpos.xz * 0.6 + vec2(vnoise(wpos.xz * 1.7)) * 0.8);
		float vein = 1.0 - smoothstep(0.0, 0.025, abs(vn - 0.5));
		vein *= smoothstep(0.4, 0.65, fbm3(wpos.xz * 0.15 + 3.0)) * (1.0 - path);
		c = mix(c, vec3(0.5, 0.36, 0.9), vein * 0.4);
		emit = vec3(0.62, 0.42, 1.0) * vein * (0.3 + 0.25 * sin(TIME * 0.9 + wpos.z * 0.5));
	}
	if (path > 0.02) {
		// a worn path: paler down its middle, darker at its edges, studded with pebbles
		float mid = smoothstep(0.55, 0.95, path);
		float edge = smoothstep(0.15, 0.4, path) * (1.0 - smoothstep(0.45, 0.7, path));
		c *= 1.0 + mid * 0.08 - edge * 0.1;
		float pb = cell_dot(wpos.xz, 4.5, 0.2, 6.0, pick) * step(0.7, pick) * smoothstep(0.3, 0.6, path);
		vec3 stone = mix(vec3(0.62, 0.6, 0.6), vec3(0.8, 0.78, 0.74), pick);
		c = mix(c, stone * mix(vec3(1.0), c * 1.6, 0.35), pb * near_k * 0.8);
	}
	// the lip of a drop catches the light: a pale painted edge, then a darker band just inside
	float here = hgt(wpos.xz);
	float drop = 0.0;
	for (int i = 0; i < 4; i++) {
		float a = float(i) * 1.5708;
		drop = max(drop, clamp((wpos.y - hgt(wpos.xz + vec2(cos(a), sin(a)) * 0.42)) * 1.5, 0.0, 1.0));
	}
	c *= 1.0 + drop * 0.16;
	return c;
}

float along_of() {
	vec2 n = normalize(wnorm.xz + vec2(1e-4));
	return dot(wpos.xz, vec2(-n.y, n.x));
}

vec3 rock(vec3 c) {
	float along = along_of();
	// faceted rock: tall uneven columns crossed by thin strata
	float col = vnoise(vec2(along * 1.7, 3.0)) ;
	c *= 0.88 + col * 0.2;
	float y = wpos.y * 2.2 + vnoise(vec2(along * 0.9, wpos.y * 0.4)) * 1.2;
	float band = fract(y);
	float strata = smoothstep(0.0, 0.08, band) * (1.0 - smoothstep(0.86, 1.0, band));
	c *= 0.86 + strata * 0.14;
	float cr = vnoise(vec2(along * 3.4, wpos.y * 0.6));
	c *= 1.0 - smoothstep(0.86, 0.96, cr) * 0.35;
	return c;
}

void fragment() {
	vec3 c = COLOR.rgb;
	int st = int(style + 0.5);
	vec3 gemit = vec3(0.0);
	float up = wnorm.y;
	if (st == 0) {
		if (up > 0.5) {
			c = ground(c);
		} else if (up > -0.5) {
			float along = abs(wnorm.x) > 0.5 ? wpos.z : wpos.x;
			float y = wpos.y * 1.6 + vnoise(vec2(along * 0.6, wpos.y * 0.3)) * 1.4;
			float band = fract(y);
			float strata = smoothstep(0.0, 0.1, band) * (1.0 - smoothstep(0.82, 1.0, band));
			float layer = h21(vec2(floor(y), 3.0));
			c *= 0.84 + strata * 0.12 + layer * 0.1;
			float cr = vnoise(vec2(along * 3.1, wpos.y * 0.45));
			c *= 1.0 - smoothstep(0.88, 0.97, cr) * 0.4;
			c *= 0.94 + vnoise(vec2(along * 2.2, wpos.y * 2.2)) * 0.12;
			c = mix(c, ao_color.rgb, clamp(-wpos.y * 0.05, 0.0, 0.45));
		} else {
			c = mix(c, ao_color.rgb, 0.5);
		}
	} else if (st == 1) {
		float n0 = fbm3(wpos.xz * 0.22);
		c = ground(c);
		if (use_biome) { c = ground_rich(c, n0, gemit); }
		if (use_ao) {
			float o = contact(wpos);
			c = mix(c, c * ao_color.rgb * 2.2, o * ao_strength);
		}
	} else if (st == 2) {
		c = rock(c);
		if (use_ao) {
			// the foot of a terrace step sits in the shade of the step
			float o = contact(wpos + vec3(wnorm.x, 0.0, wnorm.z) * 0.3);
			c = mix(c, c * ao_color.rgb * 2.2, o * ao_strength * 0.6);
		}
	} else if (st == 3) {
		// sheer slate: smooth, with long faint vertical streaks and a cold sheen near the top
		float along = along_of();
		c *= 0.93 + vnoise(vec2(along * 1.3, wpos.y * 0.12)) * 0.12;
		c *= 0.97 + vnoise(vec2(along * 6.0, wpos.y * 0.25)) * 0.05;
	} else if (st == 4) {
		// under the island: layered rock fading into the haze
		float along = wpos.x * 0.7 + wpos.z * 0.7;
		float y = wpos.y * 0.9 + vnoise(vec2(along * 0.35, wpos.y * 0.2)) * 1.6;
		float band = fract(y);
		float ledge = smoothstep(0.0, 0.07, band) * (1.0 - smoothstep(0.8, 1.0, band));
		c *= 0.8 + ledge * 0.2 + h21(vec2(floor(y), 7.0)) * 0.08;
		c *= 0.92 + vnoise(wpos.xz * 1.3 + wpos.yy * 0.7) * 0.14;
	} else if (st == 5) {
		// cliff caps: the grass or stone lip along a rim
		c *= 0.94 + vnoise(vec2(along_of() * 4.0, wpos.y * 9.0)) * 0.12;
	} else {
		// carved stone (stairs)
		c *= 0.93 + vnoise(wpos.xz * 5.0 + wpos.yy * 3.0) * 0.12;
	}
	float fog = vis_fog(wpos);
	c = vis_apply(c, fog);
	ALBEDO = c;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * rim_amount * (1.0 - fog) + gemit * 0.9 * (1.0 - fog * 0.7);
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
		float lit = smoothstep(-0.05, 0.25, ndl) * ATTENUATION;
		float band = smoothstep(0.3, 0.7, lit);
		vec3 tone = mix(vec3(shade) * shadow_tint.rgb, light_tint.rgb, band);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * tone;
	}
}

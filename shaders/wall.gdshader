shader_type spatial;
render_mode depth_prepass_alpha;
// Toon stone for walls. Whatever part of a wall stands between the camera and the player
// dithers away, so you can always see yourself behind cover.
uniform float rim_amount = 0.12;
uniform float shade = 0.42;
uniform vec3 focus = vec3(0.0, -999.0, 0.0);
uniform float radius = 0.13;
#include "res://shaders/vis.gdshaderinc"
#include "res://shaders/noise.gdshaderinc"
varying vec3 wp;
varying vec3 wn;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 c = COLOR.rgb;
	// cut stone: courses of blocks with dark mortar, each block a slightly different shade
	vec2 q = abs(wn.y) > 0.5 ? wp.xz * vec2(2.2, 2.2) : vec2((abs(wn.x) > 0.5 ? wp.z : wp.x) * 2.0, wp.y * 3.0);
	float row = floor(q.y);
	q.x += mod(row, 2.0) * 0.5;
	vec2 cell = floor(q); vec2 fq = fract(q);
	float mortar = 1.0 - smoothstep(0.03, 0.08, min(min(fq.x, 1.0 - fq.x) * 0.6, min(fq.y, 1.0 - fq.y)));
	c *= 0.86 + h21(cell) * 0.22;
	c *= 0.93 + vnoise(wp.xz * 3.0 + wp.yy * 2.0) * 0.12;
	c = mix(c, c * 0.45, mortar * (abs(wn.y) > 0.5 ? 0.6 : 1.0));
	float cut = 0.0;
	vec4 fv = VIEW_MATRIX * vec4(focus, 1.0);
	if (fv.z < 0.0 && VERTEX.z > fv.z + 0.4) {
		vec2 a = VERTEX.xy / -VERTEX.z;
		vec2 b = fv.xy / -fv.z;
		float fade = 1.0 - smoothstep(radius * 0.55, radius, length(a - b));
		cut = fade;
	}
	c = vis_apply(c, vis_fog((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
	ALBEDO = c;
	ALPHA = 1.0 - cut * 0.78;     // see through the part of a wall that hides you, smoothly
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vec3(1.0, 0.96, 0.88) * rim * rim_amount * 0.35;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.06, ndl) * ATTENUATION;
	lit = mix(shade, 1.0, smoothstep(0.35, 0.65, lit));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * lit;
}

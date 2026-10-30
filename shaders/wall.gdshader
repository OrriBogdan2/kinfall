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
	// the stones are real geometry now: just a little weathering across each face, and the top
	// edges of each block catch a touch more light
	c *= 0.92 + vnoise(wp.xz * 3.0 + wp.yy * 2.0) * 0.14;
	c *= 0.96 + vnoise(wp.xz * 11.0 + wp.yy * 9.0) * 0.07;
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
	if (!LIGHT_IS_DIRECTIONAL) {
		// lamps and glows: plain falloff. (The cel shade floor below is only for the sun; on a lamp
		// it lit whole screen clusters at once, which showed up as blocky squares at night.)
		float pl = smoothstep(-0.1, 0.4, dot(NORMAL, LIGHT)) * ATTENUATION;
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * pl;
	} else {
		float ndl = dot(NORMAL, LIGHT);
		float lit = smoothstep(0.0, 0.06, ndl) * ATTENUATION;
		float band = smoothstep(0.35, 0.65, lit);
		vec3 tone = mix(vec3(shade) * vec3(0.7, 0.66, 0.92), vec3(1.05, 1.0, 0.93), band);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * tone;
	}
}

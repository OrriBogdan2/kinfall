shader_type spatial;
// The sea of clouds far below the islands: billowing layers, lit from the sun's side, with a glow
// where the sun catches them and a deeper colour in the troughs.
render_mode unshaded, shadows_disabled, depth_draw_never, blend_mix, cull_disabled, fog_disabled;
uniform vec4 deep : source_color = vec4(0.06, 0.07, 0.13, 1.0);
uniform vec4 light : source_color = vec4(0.22, 0.24, 0.38, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.75, 0.55, 1.0);
uniform vec2 sun_xz = vec2(0.6, -0.8);
uniform float scale = 0.035;
uniform float speed = 0.012;
uniform float glow_amount = 0.35;
#include "res://shaders/noise.gdshaderinc"
float fbm5(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * vnoise(p); p = p * 2.03 + vec2(5.2, 1.3); a *= 0.5; }
	return v;
}
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * scale;
	float t = TIME * speed;
	float n = fbm5(p + vec2(t, t * 0.6)) * 0.65 + fbm5(p * 2.3 - vec2(t * 1.7, 0.0)) * 0.35;
	// fake lighting: compare with a sample nudged toward the sun
	float n2 = fbm5(p + vec2(t, t * 0.6) + normalize(sun_xz) * 0.06) * 0.65 + fbm5((p + normalize(sun_xz) * 0.06) * 2.3 - vec2(t * 1.7, 0.0)) * 0.35;
	float lit = clamp((n - n2) * 6.0 + 0.5, 0.0, 1.0);
	float c = smoothstep(0.38, 0.8, n);
	vec3 col = mix(deep.rgb, light.rgb, c);
	col += light.rgb * lit * c * 0.35;
	// a warm glow on the sun's side of the sea
	vec2 rel = normalize(wpos.xz - CAMERA_POSITION_WORLD.xz + vec2(0.001));
	float sg = pow(max(dot(rel, normalize(sun_xz)), 0.0), 3.0);
	col += glow.rgb * sg * glow_amount * (0.4 + c * 0.6);
	// distance haze
	float dist = length(wpos.xz - CAMERA_POSITION_WORLD.xz);
	col = mix(col, mix(light.rgb, glow.rgb, 0.25), smoothstep(80.0, 600.0, dist) * 0.6);
	ALBEDO = col;
}

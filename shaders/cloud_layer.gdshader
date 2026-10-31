shader_type spatial;
// A layer of soft cloud drifting under the islands. Several of these at different depths, over the
// opaque cloud sea (clouds.gdshader), give the void its depth: billowing masses with sunlit tops and
// soft edges, a warm rim where the sun catches them, thinning to wisps and fading into the haze.
render_mode unshaded, shadows_disabled, depth_draw_never, blend_mix, cull_disabled, fog_disabled;
uniform vec4 lit : source_color = vec4(0.62, 0.66, 0.9, 1.0);
uniform vec4 shade : source_color = vec4(0.16, 0.18, 0.32, 1.0);
uniform vec4 rim : source_color = vec4(1.0, 0.82, 0.66, 1.0);
uniform vec4 haze : source_color = vec4(0.2, 0.22, 0.38, 1.0);
uniform vec2 sun_xz = vec2(0.6, -0.8);
uniform float scale = 0.05;
uniform float speed = 0.015;
uniform float cover = 0.55;      // higher: fewer, smaller clouds
uniform float alpha = 0.85;
uniform float seed = 0.0;
#include "res://shaders/noise.gdshaderinc"
float fbm4(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * vnoise(p); p = p * 2.07 + vec2(5.2, 1.3); a *= 0.5; }
	return v / 0.9375;
}
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * scale + vec2(seed * 3.7, seed * 1.9);
	vec2 drift = vec2(TIME * speed, TIME * speed * 0.45);
	float warp = vnoise(p * 0.6 + drift * 0.5) * 0.8;
	float n = fbm4(p + drift + warp);
	vec2 sd = normalize(sun_xz) * 0.07;
	float n2 = fbm4(p + drift + warp + sd);
	float dens = smoothstep(cover - 0.12, cover + 0.22, n);
	// the side toward the sun is lit, the far side in shadow; thick middles darker below
	float litk = clamp((n - n2) * 7.0 + 0.55, 0.0, 1.0);
	vec3 col = mix(shade.rgb, lit.rgb, litk * 0.75 + smoothstep(0.0, 1.0, dens) * 0.25);
	float edge = smoothstep(0.05, 0.35, dens) * (1.0 - smoothstep(0.4, 0.75, dens));
	col += rim.rgb * edge * litk * 0.35;
	float dist = length(wpos.xz - CAMERA_POSITION_WORLD.xz);
	col = mix(col, haze.rgb, smoothstep(40.0, 260.0, dist) * 0.7);
	ALBEDO = col;
	ALPHA = dens * alpha * (1.0 - smoothstep(180.0, 420.0, dist));
}

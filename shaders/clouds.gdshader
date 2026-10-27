shader_type spatial;
// A slow sea of clouds far below the islands.
render_mode unshaded, shadows_disabled, depth_draw_never, blend_mix, cull_disabled, fog_disabled;
uniform vec4 deep : source_color = vec4(0.06, 0.07, 0.13, 1.0);
uniform vec4 light : source_color = vec4(0.22, 0.24, 0.38, 1.0);
uniform float scale = 0.035;
uniform float speed = 0.012;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz * scale;
	float t = TIME * speed;
	float n = fbm(p + vec2(t, t * 0.6)) * 0.65 + fbm(p * 2.3 - vec2(t * 1.7, 0.0)) * 0.35;
	float c = smoothstep(0.42, 0.78, n);
	ALBEDO = mix(deep.rgb, light.rgb, c);
	ALPHA = 1.0;
}

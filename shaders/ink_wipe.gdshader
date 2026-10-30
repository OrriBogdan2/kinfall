shader_type canvas_item;
// A ragged ink wipe instead of a plain fade: the rect's colour alpha is how far the ink has
// spread (0 = clear, 1 = covered), sweeping down from the top in torn, brushy edges.
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
void fragment() {
	float prog = COLOR.a;
	float n = vnoise(UV * vec2(9.0, 5.0)) * 0.55 + vnoise(UV * vec2(23.0, 13.0)) * 0.25;
	float edge = n * 0.6 + UV.y * 0.4;
	float a = smoothstep(edge - 0.06, edge, prog * 1.2 - 0.1);
	COLOR = vec4(0.02, 0.015, 0.035, a);
}

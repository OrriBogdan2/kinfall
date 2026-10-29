// Cheap value noise shared by the environment shaders.
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm3(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 3; i++) { v += a * vnoise(p); p = p * 2.03 + vec2(13.1, 7.7); a *= 0.5; }
	return v / 0.875;
}

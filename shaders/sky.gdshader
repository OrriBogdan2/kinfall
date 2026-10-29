shader_type sky;
// A painted sky: a gradient from the zenith to a glowing horizon, a soft sun, and faint stars up high.
uniform vec4 top : source_color = vec4(0.05, 0.07, 0.16, 1.0);
uniform vec4 mid : source_color = vec4(0.22, 0.2, 0.42, 1.0);
uniform vec4 horizon : source_color = vec4(0.98, 0.62, 0.42, 1.0);
uniform vec4 below : source_color = vec4(0.12, 0.1, 0.22, 1.0);
uniform vec4 sun_col : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform vec3 sun_dir = vec3(0.4, 0.12, -0.9);
uniform float stars = 1.0;
float h(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 c;
	if (y >= 0.0) {
		c = mix(horizon.rgb, mid.rgb, smoothstep(0.0, 0.22, y));
		c = mix(c, top.rgb, smoothstep(0.18, 0.75, y));
	} else {
		c = mix(horizon.rgb, below.rgb, smoothstep(0.0, 0.18, -y));
	}
	vec3 sd = normalize(sun_dir);
	float s = max(dot(d, sd), 0.0);
	c += sun_col.rgb * (pow(s, 600.0) * 3.0 + pow(s, 24.0) * 0.45 + pow(s, 4.0) * 0.18);
	if (stars > 0.0 && y > 0.15) {
		vec3 q = floor(d * 220.0);
		float st = step(0.9975, h(q));
		c += vec3(st) * smoothstep(0.15, 0.6, y) * stars * (0.6 + 0.4 * sin(TIME * 2.0 + h(q) * 40.0));
	}
	COLOR = c;
}

shader_type canvas_item;
// Behind a modal menu: the screen softly blurred, pulled toward night-blue, darker at the edges.
// Fade it with the node's modulate alpha (UI.show_backdrop does).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float radius = 2.6;                          // blur reach, in pixels per tap
uniform vec4 tint : source_color = vec4(0.035, 0.04, 0.075, 0.58);
uniform float vignette = 0.35;

void fragment() {
	float a = COLOR.a;
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 acc = vec3(0.0);
	float w = 0.0;
	for (int x = -3; x <= 3; x++) {
		for (int y = -3; y <= 3; y++) {
			float d = float(x * x + y * y);
			if (d > 10.0) continue;
			float k = exp(-d * 0.22);
			acc += texture(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px).rgb * k;
			w += k;
		}
	}
	vec3 c = mix(acc / w, tint.rgb, tint.a);
	float r = length((UV - 0.5) * vec2(1.25, 1.0));
	c *= 1.0 - vignette * smoothstep(0.25, 0.85, r);
	COLOR = vec4(c, a);
}

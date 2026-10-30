shader_type canvas_item;
// The prologue's look: an inked storybook. Dark ink lines where colours change, flattened
// paint-like colour bands, a colour grade per scene, paper grain and a vignette.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform float tint_amount = 0.25;
uniform float ink = 1.0;
uniform float levels = 6.0;
uniform float grain = 0.05;
uniform float vignette = 0.6;
uniform float time_s = 0.0;

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE * 1.4;
	vec3 c = texture(screen_tex, uv).rgb;
	float tl = lum(texture(screen_tex, uv + vec2(-px.x, -px.y)).rgb);
	float tm = lum(texture(screen_tex, uv + vec2(0.0, -px.y)).rgb);
	float tr = lum(texture(screen_tex, uv + vec2(px.x, -px.y)).rgb);
	float ml = lum(texture(screen_tex, uv + vec2(-px.x, 0.0)).rgb);
	float mr = lum(texture(screen_tex, uv + vec2(px.x, 0.0)).rgb);
	float bl = lum(texture(screen_tex, uv + vec2(-px.x, px.y)).rgb);
	float bm = lum(texture(screen_tex, uv + vec2(0.0, px.y)).rgb);
	float br = lum(texture(screen_tex, uv + vec2(px.x, px.y)).rgb);
	float gx = -tl - 2.0 * ml - bl + tr + 2.0 * mr + br;
	float gy = -tl - 2.0 * tm - tr + bl + 2.0 * bm + br;
	float edge = smoothstep(0.12, 0.42, length(vec2(gx, gy)));
	// flatten into paint-like bands
	vec3 p = floor(c * levels + 0.5) / levels;
	c = mix(c, p, 0.5);
	// a duotone grade toward this scene's colour
	float l = lum(c);
	vec3 duo = mix(tint.rgb * 0.22, mix(tint.rgb, vec3(1.0), 0.55), smoothstep(0.0, 1.0, l));
	c = mix(c, duo, tint_amount);
	// paper grain that shimmers a little
	float g = hash(floor(uv / SCREEN_PIXEL_SIZE / 2.0) + floor(time_s * 10.0)) - 0.5;
	c += g * grain;
	// ink
	c = mix(c, vec3(0.07, 0.04, 0.09), edge * ink * 0.8);
	// vignette
	float d = distance(uv, vec2(0.5, 0.5));
	c *= 1.0 - smoothstep(0.32, 0.85, d) * vignette;
	COLOR = vec4(c, 1.0);
}

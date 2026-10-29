shader_type spatial;
// A ribbon of falling water: streaks scroll down, the edges and the bottom fade into mist.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform vec4 color : source_color = vec4(0.75, 0.9, 1.0, 0.8);
uniform float speed = 1.2;
#include "res://shaders/noise.gdshaderinc"
void fragment() {
	float streak = vnoise(vec2(UV.x * 18.0, UV.y * 2.0 - TIME * speed * 2.0));
	float streak2 = vnoise(vec2(UV.x * 40.0 + 3.0, UV.y * 5.0 - TIME * speed * 3.1));
	float s = smoothstep(0.35, 0.85, streak * 0.6 + streak2 * 0.4);
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	float fade = 1.0 - smoothstep(0.6, 1.0, UV.y);
	ALBEDO = mix(color.rgb * 0.8, vec3(1.0), s * 0.7);
	ALPHA = color.a * edge * fade * (0.55 + s * 0.45);
}

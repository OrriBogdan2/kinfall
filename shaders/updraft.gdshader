shader_type spatial;
// A column of rising air: thin streaks that climb the column, brightest at its silhouette and
// fading out at the top and bottom, so it reads as moving air rather than a glass tube.
render_mode unshaded, shadows_disabled, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.95, 0.75, 0.35);
uniform float speed = 0.6;
uniform float tiles = 4.0;
#include "res://shaders/noise.gdshaderinc"
void fragment() {
	// UV.x runs around the column, UV.y from top (0) to bottom (1)
	float lane = floor(UV.x * 28.0);
	float off = h21(vec2(lane, 3.1));
	float rise = fract((1.0 - UV.y) * tiles * (0.7 + off * 0.6) - TIME * speed * (0.8 + off * 0.5) + off * 7.0);
	float streak = smoothstep(0.0, 0.12, rise) * (1.0 - smoothstep(0.18, 0.42, rise));
	float lane_w = 1.0 - abs(fract(UV.x * 28.0) * 2.0 - 1.0);
	streak *= smoothstep(0.35, 0.9, lane_w) * step(0.45, off);
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float ends = smoothstep(0.05, 0.55, UV.y) * (1.0 - smoothstep(0.7, 1.0, UV.y));
	ALBEDO = color.rgb;
	ALPHA = color.a * ends * (streak * 0.8 + pow(rim, 4.0) * 0.1);
}

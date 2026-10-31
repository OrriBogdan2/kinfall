shader_type spatial;
// A melee swing: a crescent whose bright leading edge sweeps round the arc, leaving a tapering trail
// of streaks that fade behind it. UV.x runs along the arc (0 to 1), UV.y across it (0 at the blade's
// tip, 1 at the inner edge). progress goes 0 to 1 over the swing.
render_mode unshaded, shadows_disabled, depth_draw_never, blend_add, cull_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0);
uniform float progress = 0.0;
#include "res://shaders/noise.gdshaderinc"
void fragment() {
	float head = progress * 1.35;
	float behind = head - UV.x;
	if (behind < 0.0) { discard; }
	float trail = 1.0 - smoothstep(0.0, 0.75, behind);
	float lead = 1.0 - smoothstep(0.0, 0.08, behind);
	float across = 1.0 - smoothstep(0.0, 1.0, UV.y);
	float edge = 1.0 - smoothstep(0.0, 0.12, UV.y);
	float streak = 0.6 + 0.4 * vnoise(vec2(UV.x * 3.0 - progress * 4.0, UV.y * 9.0));
	float a = (across * across * streak * 0.8 + edge * 0.9) * trail + lead * across * 0.8;
	a *= 1.0 - smoothstep(0.75, 1.0, progress);
	vec3 c = mix(color.rgb, vec3(1.0), edge * 0.7 + lead * 0.5);
	ALBEDO = c * a * 1.4;
	ALPHA = 1.0;
}

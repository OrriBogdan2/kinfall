// Sight: what the local player can see is a cone in front of them plus a small circle around
// them. Walls cast sight shadows. Everything else is dimmed. Set from Match each frame.
global uniform float vis_on;
global uniform vec3 vis_focus;
global uniform vec2 vis_dir;
global uniform vec2 vis_size;
global uniform sampler2D vis_blocks;

float vis_fog(vec3 wp) {
	if (vis_on < 0.5) { return 0.0; }
	vec2 d = wp.xz - vis_focus.xz;
	float dist = length(d);
	float near_v = 1.0 - smoothstep(2.6, 3.6, dist);
	if (near_v >= 1.0) { return 0.0; }
	float c = dot(d / max(dist, 0.001), vis_dir);
	float cone = smoothstep(0.56, 0.68, c) * (1.0 - smoothstep(22.0, 25.0, dist));
	if (cone > 0.001) {
		float steps = clamp(floor(dist / 0.5), 1.0, 48.0);
		for (int i = 1; i < 48; i++) {
			float t = float(i) / steps;
			if (t >= 1.0 || dist * (1.0 - t) < 0.55) { break; }
			ivec2 tq = ivec2(floor(vis_focus.xz + d * t));
			if (tq.x < 0 || tq.y < 0 || tq.x >= int(vis_size.x) || tq.y >= int(vis_size.y)) { continue; }
			if (texelFetch(vis_blocks, tq, 0).r > 0.5) { cone = 0.0; break; }
		}
	}
	return 1.0 - max(near_v, cone);
}

vec3 vis_apply(vec3 c, float fog) {
	vec3 grey = vec3(dot(c, vec3(0.3, 0.59, 0.11))) * vec3(0.7, 0.76, 0.95);
	return mix(c, grey, fog * 0.55) * (1.0 - fog * 0.46);
}

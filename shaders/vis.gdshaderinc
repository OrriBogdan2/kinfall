// Sight, as in Supervive: everyone on your team lights up a small circle around them and a cone in
// front of them (where they aim). Walls and high ground cast sight shadows. Everything outside what
// your team can see is darkened and cooled, so the lit space reads at a glance. Set from Match.
global uniform float vis_on;
global uniform vec3 vis_focus;
global uniform vec2 vis_dir;
global uniform vec2 vis_size;
global uniform sampler2D vis_blocks : filter_linear;
global uniform float vis_range;
global uniform float vis_allies;
global uniform vec4 vis_ally0;     // xy = position (x, z), zw = aim direction
global uniform vec4 vis_ally1;
global uniform vec4 vis_ally2;

// How lit a point is by one viewer: 1 inside the circle or the unblocked cone, 0 outside.
float vis_one(vec2 eye, vec2 dir, float range, vec2 wp, int max_steps) {
	vec2 d = wp - eye;
	float dist = length(d);
	float near_v = 1.0 - smoothstep(3.2, 4.2, dist);
	if (near_v >= 1.0) { return 1.0; }
	float c = dot(d / max(dist, 0.001), dir);
	float cone = smoothstep(0.55, 0.66, c) * (1.0 - smoothstep(range - 2.5, range + 0.5, dist));
	if (cone > 0.001) {
		// sight shadows: march toward the point through a smoothed map of what blocks sight
		float steps = clamp(floor(dist / 0.4), 1.0, float(max_steps));
		float occ = 0.0;
		for (int i = 1; i < 64; i++) {
			if (i >= max_steps) { break; }
			float t = float(i) / steps;
			if (t >= 1.0 || dist * (1.0 - t) < 0.7) { break; }
			vec2 q = eye + d * t;
			float v = textureLod(vis_blocks, q / vis_size, 0.0).r;
			occ = max(occ, smoothstep(0.32, 0.72, v));
			if (occ > 0.99) { break; }
		}
		cone *= 1.0 - occ;
	}
	return max(near_v, cone);
}

float vis_fog(vec3 wp) {
	if (vis_on < 0.5) { return 0.0; }
	float lit = vis_one(vis_focus.xz, vis_dir, vis_range, wp.xz, 60);
	if (lit < 0.999 && vis_allies > 0.5) { lit = max(lit, vis_one(vis_ally0.xy, vis_ally0.zw, 24.0, wp.xz, 28)); }
	if (lit < 0.999 && vis_allies > 1.5) { lit = max(lit, vis_one(vis_ally1.xy, vis_ally1.zw, 24.0, wp.xz, 28)); }
	if (lit < 0.999 && vis_allies > 2.5) { lit = max(lit, vis_one(vis_ally2.xy, vis_ally2.zw, 24.0, wp.xz, 28)); }
	return 1.0 - lit;
}

// Outside sight: much darker, cooler and greyer. Inside: a touch brighter, so the lit space pops.
vec3 vis_apply(vec3 c, float fog) {
	if (vis_on < 0.5) { return c; }
	vec3 grey = vec3(dot(c, vec3(0.3, 0.59, 0.11))) * vec3(0.62, 0.7, 0.98);
	vec3 dark = mix(c, grey, 0.6) * 0.42;
	return mix(c * 1.06, dark, fog);
}

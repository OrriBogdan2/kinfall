shader_type spatial;
// Toon stone for walls. Whatever part of a wall stands between the camera and the player
// dithers away, so you can always see yourself behind cover.
uniform float rim_amount = 0.12;
uniform float shade = 0.42;
uniform vec3 focus = vec3(0.0, -999.0, 0.0);
uniform float radius = 0.13;

void fragment() {
	vec3 c = COLOR.rgb;
	vec4 fv = VIEW_MATRIX * vec4(focus, 1.0);
	if (fv.z < 0.0 && VERTEX.z > fv.z + 0.4) {
		vec2 a = VERTEX.xy / -VERTEX.z;
		vec2 b = fv.xy / -fv.z;
		float fade = 1.0 - smoothstep(radius * 0.55, radius, length(a - b));
		if (fade > 0.0) {
			int bx = int(mod(FRAGCOORD.x, 4.0));
			int by = int(mod(FRAGCOORD.y, 4.0));
			int bayer[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
			float th = (float(bayer[by * 4 + bx]) + 0.5) / 16.0;
			if (fade * 0.8 > th) { discard; }
		}
	}
	ALBEDO = c;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = vec3(1.0, 0.96, 0.88) * rim * rim_amount * 0.35;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(0.0, 0.06, ndl) * ATTENUATION;
	lit = mix(shade, 1.0, smoothstep(0.35, 0.65, lit));
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR / PI * lit;
}

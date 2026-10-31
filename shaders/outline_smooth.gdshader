shader_type spatial;
// The ink outline for imported, flat-shaded models: like outline.gdshader, but the copy grows along
// smoothed normals stored in TANGENT (Assets.mesh puts them there), so the shell stays closed at
// hard edges instead of splitting into slivers.
render_mode unshaded, cull_front, shadows_disabled;
uniform vec4 color : source_color = vec4(0.08, 0.065, 0.12, 1.0);
uniform float width = 0.00125;
void vertex() {
	float d = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	vec3 n = normalize(TANGENT);
	// keep the line about as thick on screen however the model is scaled
	float s = length(MODEL_MATRIX[0].xyz);
	VERTEX += n * clamp(d * width, 0.0042, 0.034) / max(s, 0.001);
}
void fragment() { ALBEDO = color.rgb; }

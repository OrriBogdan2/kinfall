shader_type spatial;
// Ink outline drawn from the inside of a slightly grown copy. It grows with distance so the line
// stays about the same thickness on screen, close up or zoomed out.
render_mode unshaded, cull_front, shadows_disabled;
uniform vec4 color : source_color = vec4(0.07, 0.06, 0.1, 1.0);
uniform float width = 0.0016;
void vertex() {
	float d = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
	VERTEX += NORMAL * clamp(d * width, 0.006, 0.045);
}
void fragment() { ALBEDO = color.rgb; }

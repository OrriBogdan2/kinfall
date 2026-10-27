shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec4 color : source_color = vec4(0.07, 0.06, 0.09, 1.0);
uniform float width = 0.035;
void vertex() { VERTEX += NORMAL * width; }
void fragment() { ALBEDO = color.rgb; }

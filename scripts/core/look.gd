class_name Look
## The shared look of every outdoor scene: a painted sky, soft filmic colour, a little bloom, haze
## that swallows whatever hangs below the islands, a warm key light and a cool rim light.

static var SKY: Shader = preload("res://shaders/sky.gdshader")

## p: top, mid, horizon, below (sky colours), ambient, fog (haze colour), stars (0..1)
static func environment(p: Dictionary) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY
	for k in ["top", "mid", "horizon", "below"]:
		if p.has(k): sm.set_shader_parameter(k, p[k])
	sm.set_shader_parameter("stars", float(p.get("stars", 1.0)))
	sm.set_shader_parameter("sun_dir", p.get("sun_dir", Vector3(0.45, 0.12, -0.88)))
	if p.has("sun_col"): sm.set_shader_parameter("sun_col", p["sun_col"])
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = p.get("ambient", Color("c4cbe6"))
	e.ambient_light_energy = float(p.get("ambient_energy", 0.5))
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = float(p.get("exposure", 1.05))
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 0.95
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = float(p.get("contrast", 1.06))
	e.adjustment_saturation = float(p.get("saturation", 1.14))
	# haze that thickens below the islands, so their roots fade into the clouds
	e.fog_enabled = true
	e.fog_light_color = p.get("fog", Color("2a3058"))
	e.fog_light_energy = 1.0
	e.fog_sun_scatter = 0.15
	e.fog_density = float(p.get("fog_density", 0.0015))
	e.fog_sky_affect = 0.0
	e.fog_height = float(p.get("fog_height", -3.0))
	e.fog_height_density = float(p.get("fog_height_density", 0.12))
	return e

## A warm key light with shadows and a cool fill from the other side that rims the silhouettes.
static func lights(parent: Node, key_col: Color, key_energy := 1.0, rot := Vector3(-52, -35, 0), shadow_dist := 60.0) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = rot
	sun.light_color = key_col
	sun.light_energy = key_energy
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = shadow_dist
	sun.shadow_bias = 0.03
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.shadow_opacity = 0.75
	sun.shadow_blur = 1.5
	parent.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.rotation_degrees = Vector3(-25, rot.y + 165.0, 0)
	fill.light_color = Color("8fb0ff")
	fill.light_energy = 0.28 * key_energy
	fill.shadow_enabled = false
	parent.add_child(fill)
	return sun

## Darkens the sky toward night (home's day cycle): k = 0 day, 1 night.
static func night(e: Environment, k: float) -> void:
	if e == null or e.sky == null:
		return
	var sm := e.sky.sky_material as ShaderMaterial
	if sm == null:
		return
	if not sm.has_meta("day"):
		sm.set_meta("day", [sm.get_shader_parameter("top"), sm.get_shader_parameter("mid"), sm.get_shader_parameter("horizon")])
	var day: Array = sm.get_meta("day")
	var nite := [Color("05060f"), Color("0d1230"), Color("2a2a55")]
	for i in 3:
		sm.set_shader_parameter(["top", "mid", "horizon"][i], (day[i] as Color).lerp(nite[i], k))
	sm.set_shader_parameter("stars", 0.4 + k)

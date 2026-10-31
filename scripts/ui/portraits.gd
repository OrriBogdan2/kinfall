class_name Portraits
extends RefCounted
## Head-and-shoulders portraits of hunters for the HUD (squad frames, the ally-knocked popup).
## Each is a tiny SubViewport with its own world: the hunter's model, a key light and a soft fill,
## rendered once into a texture. A greyed copy is made on demand for teammates who are out.

const SIZE := 96

## A viewport holding a portrait of this look. Add it to the tree; its texture fills in next frame.
static func make(cls: String, team_col: Color, wid: String, look: Dictionary) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8a93b8")
	e.ambient_light_energy = 0.9
	env.environment = e
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, 155, 0)
	key.light_color = Color("fff1dc")
	key.light_energy = 1.15
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, -25, 0)
	rim.light_color = team_col.lerp(Color.WHITE, 0.4)
	rim.light_energy = 0.6
	vp.add_child(rim)
	var mdl := Models.hunter(cls, team_col, wid, "", look)
	var ring := mdl.get_node_or_null("TeamRing")
	if ring:
		(ring as Node3D).visible = false
	vp.add_child(mdl)
	# no weapon in the way of the face
	var gun := mdl.get_node_or_null("Rig/Torso/Aim/Gun")
	if gun:
		(gun as Node3D).visible = false
	# the face looks down -Z; frame the head from a little off to one side
	var s := mdl.scale.y
	var head := Vector3(0, (0.42 + 0.86) * s, 0)
	var cam := Camera3D.new()
	cam.fov = 26.0
	vp.add_child(cam)
	cam.transform = Transform3D(Basis(), head + Vector3(-0.45, 0.1, -1.55) * s).looking_at(head + Vector3(0, -0.13 * s, 0), Vector3.UP)
	cam.current = true
	return vp

## A desaturated, darkened copy of a rendered portrait (null until the portrait has been drawn).
static func grey(tex: Texture2D) -> ImageTexture:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	var seen := false
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.05: seen = true
			var l := (c.r * 0.3 + c.g * 0.55 + c.b * 0.15) * 0.62
			img.set_pixel(x, y, Color(l, l, l * 1.05, c.a))
	return ImageTexture.create_from_image(img) if seen else null

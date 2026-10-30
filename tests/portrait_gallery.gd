extends Control
## Every class with a few random looks, as HUD portraits (tooling: renders a screenshot with -- --shot=...).

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color(0.08, 0.09, 0.12); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var rng := RandomNumberGenerator.new(); rng.seed = 7
	var i := 0
	for cls in Data.CLASSES:
		for j in 4:
			var look := Models.random_look()
			var vp := Portraits.make(cls, Data.TEAM_COLORS[j % Data.TEAM_COLORS.size()], String(Data.CLASSES[cls]["weapon"]), look)
			add_child(vp)
			var tr := TextureRect.new()
			tr.texture = vp.get_texture()
			tr.position = Vector2(10 + j * 104, 10 + i * 104)
			tr.size = Vector2(96, 96)
			add_child(tr)
		i += 1

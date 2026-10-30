extends Node3D
## Every hunter pose at once, driven by HunterAnim with made-up inputs: idle, run, strafe,
## backpedal, jump, fall, crouch, dodge, glide, ledge, reload, downed. Open tests/anim_lab.tscn, F6.

var rows: Array = []
const POSES := ["idle", "run", "strafe", "backpedal", "jump", "fall", "crouch", "dodge", "glide", "ledge", "reload", "downed", "drink"]

func _ready() -> void:
	var env := WorldEnvironment.new()
	env.environment = Look.environment({"top": Color("2a4a8a"), "mid": Color("6a8ad0"), "horizon": Color("ffd2a8"), "stars": 0.0})
	add_child(env)
	Look.lights(self, Color("fff1dc"), 1.0, Vector3(-45, -30, 0), 30.0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 16)
	ground.mesh = pm
	ground.material_override = Models.toon(Color("5f8d45"), false)
	add_child(ground)
	var poses: Array = POSES
	if "--lab-reload" in OS.get_cmdline_user_args():
		poses = ["r0.1", "r0.25", "r0.4", "r0.55", "r0.66", "r0.9"]
	for i in poses.size():
		var h := Models.hunter("medium", Data.TEAM_COLORS[0], "rifle", ["sage", "veil", "bastion", "pyra"][i % 4])
		h.position = Vector3((i % 7 - 3.0) * 1.8, 0, (i / 7) * 3.0 - 1.5)
		h.rotation.y = PI + 0.5
		add_child(h)
		var l := Label3D.new(); l.text = poses[i]; l.font_size = 40; l.pixel_size = 0.005
		l.position = h.position + Vector3(0, 1.9, 0); l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(l)
		rows.append([h, HunterAnim.new(h), poses[i]])
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4.2, 10.0); cam.rotation = Vector3(-0.38, 0, 0); cam.fov = 55
	if "--lab-reload" in OS.get_cmdline_user_args():
		cam.position = Vector3(0, 2.2, 4.6); cam.rotation = Vector3(-0.3, 0, 0); cam.fov = 60
	if "--lab-side" in OS.get_cmdline_user_args():
		cam.position = Vector3(-3.0, 1.2, 1.6); cam.rotation = Vector3(-0.1, -0.35, 0); cam.fov = 40
	add_child(cam)
	cam.make_current()

func _process(delta: float) -> void:
	for r in rows:
		var h: Node3D = r[0]
		var a: HunterAnim = r[1]
		var face := h.rotation.y
		var fwd := Vector3(-sin(face), 0, -cos(face))
		var right := Vector3(cos(face), 0, -sin(face))
		var s := {"face": face, "fired": 99.0}
		if String(r[2]).begins_with("r0"):
			s["reload"] = float(String(r[2]).substr(1))
		match String(r[2]):
			"run": s["vel"] = fwd * 5.5
			"strafe": s["vel"] = right * 5.0
			"backpedal": s["vel"] = -fwd * 4.0
			"jump": s["vel"] = Vector3(0, 7.0, 0); s["grounded"] = false
			"fall": s["vel"] = Vector3(0, -9.0, 0); s["grounded"] = false
			"crouch": s["crouch"] = 1.0
			"dodge": s["rolling"] = true; s["vel"] = fwd * 15.0
			"glide":
				s["gliding"] = true; s["grounded"] = false; s["vel"] = fwd * 8.0
				h.get_node("Rig/Torso/Glider").visible = true
			"ledge": s["ledge"] = true; s["grounded"] = false
			"reload": s["reload"] = fmod(Time.get_ticks_msec() / 1500.0, 1.0)
			"drink": s["drink"] = 0.5
			"downed":
				s["downed"] = true
				h.get_node("Rig").rotation.x = -1.35; h.get_node("Rig").position.y = 0.15
		a.update(delta, s)

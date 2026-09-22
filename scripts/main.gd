extends Node3D
## 夏迷路（Godot版プロトタイプ）: 真夏のひまわり迷路 1ステージ。
##
## 撮影モード（自己評価用）:
##   godot --path . -- --shots=<出力フォルダ> [--pose=x,y,z,yaw,pitch;...]

const SUN_DIR := Vector3(0.12, 0.88, 0.46)   # 太陽の方向（南・高度 約62度）

@onready var sun: DirectionalLight3D = $Sun
@onready var maze: Node3D = $Maze
@onready var player: CharacterBody3D = $Player
@onready var kimi: Node3D = $Kimi
@onready var clouds: Node3D = $Sky
@onready var pollen: GPUParticles3D = $Player/Pollen
@onready var cicada_bed: AudioStreamPlayer = $CicadaBed

var overlay: ColorRect
var title: Label
var hint: Label
var shot_dir := ""
var poses: Array = []
var ending := false
var autowalk := false
var walk_i := 0
var walk_t := 0.0


func _ready() -> void:
	if OS.has_feature("web"):
		# WebGL2(Compatibility)は空気遠近が無く霞みが白く出やすいので薄める
		var env: Environment = $WorldEnvironment.environment
		env.fog_density = 0.0012
	var sd := SUN_DIR.normalized()
	sun.look_at_from_position(Vector3.ZERO, -sd, Vector3.UP)
	maze.sun_dir = sd
	clouds.sun_dir = sd
	maze.build()
	clouds.build()
	_place_player()
	kimi.setup(maze, player)
	kimi.found.connect(_on_found)
	_setup_audio()
	_setup_pollen()
	_setup_heat_haze()
	_setup_ui()
	_parse_args()


func _place_player() -> void:
	var dc: Vector3 = maze.deck_center
	player.global_position = Vector3(dc.x, dc.y + 0.05, dc.z + 1.0)
	player.set_look(0.0, 0.05)   # 北（迷路の方）を向く


# ---------------------------------------------------------------- 音

func _setup_audio() -> void:
	var cicada: AudioStreamMP3 = load("res://audio/cicada.mp3")
	cicada.loop = true
	cicada_bed.stream = cicada
	cicada_bed.play()
	# 畑のあちこちで鳴く蝉（3D）
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var hm: float = maze.maze_half()
	var spots := [Vector3(-hm - 6, 3, -hm * 0.4), Vector3(hm + 8, 3, hm * 0.3), Vector3(hm * 0.2, 3, -hm - 10),
			Vector3(-hm * 0.5, 3, hm + 4), Vector3(hm * 0.6, 3, -hm * 0.6)]
	for i in spots.size():
		var a := AudioStreamPlayer3D.new()
		a.name = "Cicada%d" % i
		a.stream = cicada
		a.position = spots[i]
		a.unit_size = 14.0
		a.max_db = 0.0
		a.volume_db = -4.0
		a.pitch_scale = rng.randf_range(0.93, 1.08)
		a.attenuation_filter_cutoff_hz = 12000.0
		add_child(a)
		a.play(rng.randf_range(0.0, cicada.get_length() - 1.0))


# ---------------------------------------------------------------- 光の粒（花粉・埃）

func _setup_pollen() -> void:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9, 2.2, 9)
	pm.direction = Vector3(0.8, 0.3, 0.5)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	pm.gravity = Vector3(0.12, 0.03, 0.08)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.15
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.15, 1))
	curve.add_point(Vector2(0.85, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pollen.process_material = pm
	pollen.local_coords = false
	pollen.position = Vector3(0, 1.2, 0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.97, 0.85, 0.8)
	m.albedo_texture = _dot_texture()
	m.emission_enabled = true
	m.emission = Color(1.0, 0.95, 0.8)
	m.emission_energy_multiplier = 3.0
	quad.material = m
	pollen.draw_pass_1 = quad
	pollen.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 8, 24))


func _dot_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for x in 32:
		for y in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- 陽炎

func _setup_heat_haze() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "HeatHaze"
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/heat_haze.gdshader")
	mi.material_override = mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.get_node("Camera").add_child(mi)


# ---------------------------------------------------------------- 画面

func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	overlay = ColorRect.new()
	overlay.color = Color(1, 1, 1, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	title = Label.new()
	title.text = "夏迷路"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	title.add_theme_color_override("font_shadow_color", Color(0, 0.12, 0.35, 0.7))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.2, 0.45, 0.55))
	title.add_theme_constant_override("outline_size", 8)
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(-200, -160)
	title.size = Vector2(400, 90)
	layer.add_child(title)
	hint = Label.new()
	hint.text = "クリックで視点操作　WASD 移動　Shift 走る\n笑い声のする方へ（ヘッドホン推奨）"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	hint.add_theme_color_override("font_outline_color", Color(0.05, 0.12, 0.05, 0.75))
	hint.add_theme_constant_override("outline_size", 6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-300, -110)
	hint.size = Vector2(600, 60)
	layer.add_child(hint)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(title, "modulate:a", 0.0, 2.5)
	var tw2 := create_tween()
	tw2.tween_interval(9.0)
	tw2.tween_property(hint, "modulate:a", 0.0, 2.0)


func _on_found() -> void:
	if ending:
		return
	ending = true
	player.locked = true
	print("FOUND kimi at t=%.1f" % walk_t)
	if autowalk:
		get_tree().create_timer(1.0).timeout.connect(get_tree().quit)
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 1.0, 3.5).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cicada_bed, "volume_db", 0.0, 3.5)
	tw.tween_callback(func():
		title.text = "みつけた。"
		title.add_theme_color_override("font_color", Color(0.35, 0.45, 0.6))
		title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		title.modulate.a = 0.0)
	tw.tween_property(title, "modulate:a", 1.0, 2.0)


# ---------------------------------------------------------------- 自動テスト（迷路の正解ルートを歩く）

func _process(delta: float) -> void:
	if not autowalk or ending:
		return
	walk_t += delta
	if walk_t > 120.0:
		print("AUTOWALK TIMEOUT kimi_wp=%d" % kimi.wp)
		get_tree().quit()
		return
	var path: Array = maze.path_tiles
	if walk_i >= path.size():
		return
	var tgt: Vector3 = maze.tile_to_world(path[walk_i])
	var d := tgt - player.global_position
	d.y = 0.0
	var step := 4.0 * delta
	if d.length() <= step:
		player.global_position = Vector3(tgt.x, 0.05, tgt.z)
		walk_i += 1
		if walk_i % 10 == 0:
			print("walk %d/%d  kimi_wp=%d dist=%.1f" % [walk_i, path.size(), kimi.wp, kimi.global_position.distance_to(player.global_position)])
	else:
		player.global_position += d.normalized() * step
		player.set_look(atan2(-d.x, -d.z), 0.0)


# ---------------------------------------------------------------- 撮影モード

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shot_dir = a.substr(8)
		elif a == "--autowalk":
			autowalk = true
		elif a.begins_with("--pose="):
			for p in a.substr(7).split(";"):
				var v := p.split(",")
				if v.size() >= 5:
					poses.append([Vector3(float(v[0]), float(v[1]), float(v[2])), deg_to_rad(float(v[3])), deg_to_rad(float(v[4]))])
	if shot_dir != "":
		if not "--title" in OS.get_cmdline_user_args():
			title.visible = false
			hint.visible = false
		_run_shots()


func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(shot_dir)
	if poses.is_empty():
		poses.append(null)
	for i in poses.size():
		var p = poses[i]
		if p != null:
			if p[0].y < -50.0:   # y<-50 なら「君」の後方に置く
				var k := kimi.global_position
				var back := kimi.global_transform.basis.z
				kimi.set_process(false)
				player.global_position = k + back * (-p[0].y - 100.0 + 3.0)
				player.set_look(atan2(back.x, back.z), deg_to_rad(-3))
			else:
				player.global_position = p[0]
				player.set_look(p[1], p[2])
		for f in 50:
			await get_tree().process_frame
		var t0 := Time.get_ticks_usec()
		for f in 30:
			await get_tree().process_frame
		print("pose %d: %.1f fps" % [i, 30.0 / ((Time.get_ticks_usec() - t0) / 1000000.0)])
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_dir.path_join("shot_%02d.png" % i))
		print("saved shot %d" % i)
	print("fps=%d" % Engine.get_frames_per_second())
	get_tree().quit()

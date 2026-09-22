extends Node3D
## 画面効果：真夏の太陽のレンズフレアと眩しさ（ステージ1・2）、夏祭りの花火（ステージ3）。

var player: CharacterBody3D
var cam: Camera3D
var env: Environment
var cfg: Dictionary = {}
var sun_dir := Vector3.UP
var active := false            # プレイ中・タイトル中だけ動かす
var rng := RandomNumberGenerator.new()

# レンズフレア
var flare_root: Control
var glare: TextureRect          # 太陽のまわりの大きなにじみ
var ghosts: Array[TextureRect] = []
var veil: ColorRect             # 画面全体の白いかすみ
var flare_amt := 0.0
var flare_t := 0.0
const GHOSTS := [[0.35, 70.0, Color(1.0, 0.85, 0.5, 0.35)], [0.62, 36.0, Color(0.6, 0.9, 1.0, 0.4)],
	[0.9, 120.0, Color(0.8, 1.0, 0.7, 0.18)], [1.25, 54.0, Color(1.0, 0.6, 0.4, 0.3)], [1.6, 180.0, Color(0.7, 0.8, 1.0, 0.12)]]

# 花火
var fw_t := 3.0
var hanabi: AudioStream
var fw_pool: Array[GPUParticles3D] = []
var fw_next := 0
var fw_mat: StandardMaterial3D
var fw_colors := [Color(1.0, 0.18, 0.12), Color(1.0, 0.65, 0.1), Color(0.2, 0.6, 1.0), Color(0.35, 1.0, 0.35), Color(1.0, 0.3, 0.8), Color(1.0, 0.9, 0.6)]


func setup(player_: CharacterBody3D, env_: Environment, layer: CanvasLayer) -> void:
	player = player_
	cam = player.get_node("Camera")
	env = env_
	rng.randomize()
	hanabi = load("res://audio/hanabi.mp3")
	_build_flare(layer)
	_build_fireworks()


func set_stage(c: Dictionary) -> void:
	cfg = c
	sun_dir = (c.sun_dir as Vector3).normalized()
	fw_t = 3.5
	flare_amt = 0.0


# ================================================================ レンズフレア

func _radial(size: int, hardness: float) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size * 0.5
	for x in size:
		for y in size:
			var d := Vector2(x - h + 0.5, y - h + 0.5).length() / h
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = pow(a, hardness)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _add_sprite(tex: Texture2D, col: Color) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.modulate = col
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	t.material = m
	flare_root.add_child(t)
	return t


func _build_flare(layer: CanvasLayer) -> void:
	flare_root = Control.new()
	flare_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	flare_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flare_root)
	layer.move_child(flare_root, 0)
	veil = ColorRect.new()
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.color = Color(1.0, 0.98, 0.9, 0.0)
	flare_root.add_child(veil)
	var soft := _radial(128, 2.2)
	var ring := _radial(64, 0.8)
	glare = _add_sprite(soft, Color(1.0, 0.95, 0.82, 0.0))
	for g in GHOSTS:
		ghosts.append(_add_sprite(ring if g[1] < 100.0 else soft, g[2]))
	flare_root.visible = false


func _update_flare(delta: float) -> void:
	var strength: float = cfg.get("flare", 0.0)
	var target := 0.0
	var screen := Vector2.ZERO
	if strength > 0.0 and active:
		var fwd := -cam.global_transform.basis.z
		var facing := fwd.dot(sun_dir)
		var sun_pos := cam.global_position + sun_dir * 1000.0
		if not cam.is_position_behind(sun_pos):
			screen = cam.unproject_position(sun_pos)
			target = smoothstep(0.35, 0.97, facing)
			# 迷路の壁（植物）に遮られると、葉の隙間からちらちら漏れる
			var q := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + sun_dir * 30.0)
			q.exclude = [player.get_rid()]
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				flare_t += delta
				target *= 0.35 + 0.25 * sin(flare_t * 7.3) * sin(flare_t * 3.1)
	flare_amt = lerpf(flare_amt, target * strength, 1.0 - exp(-6.0 * delta))
	flare_root.visible = flare_amt > 0.01
	if not flare_root.visible:
		return
	var vp := get_viewport().get_visible_rect().size
	var center := vp * 0.5
	var gs := vp.y * 1.6
	glare.size = Vector2(gs, gs)
	glare.position = screen - glare.size * 0.5
	glare.modulate.a = 0.55 * flare_amt
	for i in ghosts.size():
		var g: Array = GHOSTS[i]
		var p: Vector2 = screen + (center - screen) * float(g[0])
		var s: float = g[1] * vp.y / 720.0
		ghosts[i].size = Vector2(s, s)
		ghosts[i].position = p - ghosts[i].size * 0.5
		ghosts[i].modulate.a = (g[2] as Color).a * flare_amt
	veil.color.a = 0.16 * flare_amt


# ================================================================ 花火

func _build_fireworks() -> void:
	var dot := _radial(32, 1.6)
	fw_mat = StandardMaterial3D.new()
	fw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fw_mat.vertex_color_use_as_albedo = true
	fw_mat.albedo_texture = dot
	fw_mat.albedo_color = Color(1.7, 1.7, 1.7)
	fw_mat.set_flag(BaseMaterial3D.FLAG_DISABLE_FOG, true)
	for i in 6:
		var p := GPUParticles3D.new()
		p.amount = 260
		p.lifetime = 2.6
		p.one_shot = true
		p.explosiveness = 0.97
		p.local_coords = false
		p.emitting = false
		p.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
		var q := QuadMesh.new()
		q.size = Vector2(1.5, 1.5)
		q.material = fw_mat
		p.draw_pass_1 = q
		add_child(p)
		fw_pool.append(p)


func _fw_material(col: Color, speed: float, kind: int) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = speed * (0.92 if kind == 0 else 0.4)
	pm.initial_velocity_max = speed
	pm.damping_min = speed * 0.45
	pm.damping_max = speed * 0.55
	pm.gravity = Vector3(0, -3.0, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(0.6, 0.8))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	# 開いた瞬間は白く、色へ、最後は暗く消える
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.add_point(0.08, col.lerp(Color.WHITE, 0.3))
	grad.add_point(0.2, col)
	grad.add_point(0.7, col * Color(0.8, 0.8, 0.8, 1))
	grad.set_color(grad.get_point_count() - 1, Color(col.r * 0.4, col.g * 0.3, col.b * 0.3, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	return pm


func launch() -> void:
	# 夕焼けと反対側の暗い空に上げる
	var dark := Vector3(-sun_dir.x, 0, -sun_dir.z).normalized()
	var side := Vector3(-dark.z, 0, dark.x)
	var base := dark * rng.randf_range(70.0, 95.0) + side * rng.randf_range(-45.0, 45.0)
	var burst_pos := base + Vector3(0, rng.randf_range(42.0, 62.0), 0)
	var col: Color = fw_colors[rng.randi() % fw_colors.size()]
	var big := rng.randf() < 0.35
	# 打ち上げ（火の粉を引きながら昇る）
	var rocket := GPUParticles3D.new()
	rocket.amount = 60
	rocket.lifetime = 0.7
	rocket.local_coords = false
	var rp := ParticleProcessMaterial.new()
	rp.direction = Vector3.DOWN
	rp.spread = 12.0
	rp.initial_velocity_min = 1.0
	rp.initial_velocity_max = 3.0
	rp.gravity = Vector3(0, -2.0, 0)
	rp.scale_min = 0.25
	rp.scale_max = 0.45
	var rg := Gradient.new()
	rg.set_color(0, Color(1.0, 0.85, 0.55, 1))
	rg.set_color(1, Color(1.0, 0.4, 0.1, 0))
	var rgt := GradientTexture1D.new()
	rgt.gradient = rg
	rp.color_ramp = rgt
	rocket.process_material = rp
	var rq := QuadMesh.new()
	rq.size = Vector2(0.8, 0.8)
	rq.material = fw_mat
	rocket.draw_pass_1 = rq
	rocket.visibility_aabb = AABB(Vector3(-10, -80, -10), Vector3(20, 90, 20))
	add_child(rocket)
	rocket.global_position = base + Vector3(0, 2, 0)
	var rise := rng.randf_range(1.3, 1.8)
	var tw := create_tween()
	tw.tween_property(rocket, "global_position", burst_pos, rise).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func():
		rocket.emitting = false
		_burst(burst_pos, col, big))
	tw.tween_interval(1.0)
	tw.tween_callback(rocket.queue_free)


func _burst(pos: Vector3, col: Color, big: bool) -> void:
	var p := fw_pool[fw_next]
	fw_next = (fw_next + 1) % fw_pool.size()
	p.process_material = _fw_material(col, 30.0 if big else 22.0, 0)
	p.amount_ratio = 1.0 if big else 0.7
	p.global_position = pos
	p.restart()
	p.emitting = true
	# 二重の菊：内側に別の色
	if big:
		var p2 := fw_pool[fw_next]
		fw_next = (fw_next + 1) % fw_pool.size()
		var col2: Color = fw_colors[rng.randi() % fw_colors.size()]
		p2.process_material = _fw_material(col2, 14.0, 1)
		p2.amount_ratio = 0.5
		p2.global_position = pos
		p2.restart()
		p2.emitting = true
	# 空と地面を一瞬その色に照らす
	var l := OmniLight3D.new()
	l.light_color = col.lerp(Color.WHITE, 0.3)
	l.light_energy = 0.0
	l.omni_range = 160.0
	l.omni_attenuation = 0.6
	add_child(l)
	l.global_position = pos
	var tw := create_tween()
	tw.tween_property(l, "light_energy", 5.0 if big else 3.0, 0.06)
	tw.tween_property(l, "light_energy", 0.0, 1.4).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)
	# 音は光より遅れて届く（音速 約340m/s）
	var dist := pos.distance_to(player.global_position)
	get_tree().create_timer(dist / 340.0).timeout.connect(func():
		var a := AudioStreamPlayer3D.new()
		a.stream = hanabi
		a.unit_size = 55.0
		a.max_db = 6.0
		a.volume_db = 2.0 if big else -1.0
		a.pitch_scale = rng.randf_range(0.9, 1.08)
		a.attenuation_filter_cutoff_hz = 8000.0
		add_child(a)
		a.global_position = pos
		a.play()
		a.finished.connect(a.queue_free))


func _process(delta: float) -> void:
	if player == null:
		return
	_update_flare(delta)
	if active and cfg.get("fireworks", false):
		fw_t -= delta
		if fw_t <= 0.0:
			launch()
			if rng.randf() < 0.3:
				get_tree().create_timer(rng.randf_range(0.3, 0.9)).timeout.connect(launch)
			fw_t = rng.randf_range(2.8, 6.5)

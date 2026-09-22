extends Node3D
## 「君」：白い帽子と白いサマードレスの後ろ姿。迷路の奥へ逃げながら笑う。
## 通常ステージは自律（プレイヤーが近づくと次の地点へ走る）。
## 最終ステージは game から scripted=true で台本どおりに動かす。

signal found

var maze: Node3D
var player: Node3D
var cfg: Dictionary = {}
var waypoints: Array[int] = []     # path_tiles のインデックス
var wp := 0
var path_i := 0
var moving := false
var done := false
var scripted := false
var laugh_allowed := true
var laugh_timer := 3.0
var hold := 0.0                   # スタート直後、見える所で待つ時間
var speed := 4.0
var dash := 6.5
var laughs: Array[AudioStream] = []
var rng := RandomNumberGenerator.new()

# 台本用：タイル列に沿って移動
var route: Array[Vector3] = []
var route_speed := 2.0

# アニメーション
var stride := 0.0
var cur_speed := 0.0
var last_pos := Vector3.ZERO
var anim_t := 0.0
var body: Node3D
var skirt: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hat: Node3D
var fade_mats: Array[StandardMaterial3D] = []
var burst: GPUParticles3D
var vanishing := false
var hat_rest := Vector3.ZERO      # 消えたあと帽子が落ちた場所
@onready var laugh: AudioStreamPlayer3D = $Laugh


func _ready() -> void:
	rng.randomize()
	laughs = [load("res://audio/laugh_0.mp3"), load("res://audio/laugh_1.mp3")]
	_build_model()
	laugh.position = Vector3(0, 1.4, 0)
	visible = false


func setup(maze_: Node3D, player_: Node3D, cfg_: Dictionary) -> void:
	maze = maze_
	player = player_
	cfg = cfg_
	done = false
	moving = false
	scripted = cfg.get("finale", false)
	laugh_allowed = not scripted
	speed = cfg.get("kimi_speed", 4.0)
	laugh.attenuation_filter_cutoff_hz = cfg.laugh.cutoff
	route.clear()
	waypoints.clear()
	wp = 0
	var n: int = maze.path_tiles.size()
	# 最初はスタートからまっすぐ見通せる位置に立ち、少し待ってから逃げる
	waypoints.append(_intro_index())
	for f in [0.28, 0.52, 0.76, 1.0]:
		var wi := clampi(int(round((n - 1) * f)), 0, n - 1)
		if wi > waypoints.back():
			waypoints.append(wi)
	path_i = waypoints[0]
	hold = 0.0 if maze.has_deck else 4.2
	position = maze.tile_to_world(maze.path_tiles[path_i])
	last_pos = position
	_face(path_i + 1)
	laugh_timer = 3.0 if maze.has_deck else 3.4
	_restore()
	visible = not scripted


## スタート地点からまっすぐ続く通路の、見通せるいちばん奥（2〜5タイル先）
func _intro_index() -> int:
	var p: Array = maze.path_tiles
	if p.size() < 3:
		return 0
	if maze.has_deck:
		# 見晴らし台から坂の下を見ると、迷路の入口に君が見える
		return 0
	var d: Vector2i = p[1] - p[0]
	var i := 1
	while i + 1 < p.size() and i < 5 and p[i + 1] - p[i] == d:
		i += 1
	return maxi(i, 2)


# ---------------------------------------------------------------- 消える（最終ステージ）

func _build_burst() -> void:
	burst = GPUParticles3D.new()
	burst.amount = 220
	burst.lifetime = 3.2
	burst.one_shot = true
	burst.explosiveness = 0.35
	burst.local_coords = false
	burst.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.28, 0.85, 0.28)
	pm.direction = Vector3(0.85, 0.9, 0.52)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0.6, 0.15, 0.35)
	pm.angular_velocity_min = -300.0
	pm.angular_velocity_max = 300.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.2
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(0.7, 0.8))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.98, 0.9))
	grad.set_color(1, Color(0.98, 0.78, 0.3))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_initial_ramp = gt
	burst.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.055)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.emission_enabled = true
	m.emission = Color(1.0, 0.92, 0.7)
	m.emission_energy_multiplier = 2.4
	q.material = m
	burst.draw_pass_1 = q
	burst.visibility_aabb = AABB(Vector3(-10, -3, -10), Vector3(20, 10, 20))
	add_child(burst)


## 見ている前で、光る花びらになって消える。帽子だけが風に飛ばされて道に落ちる
func vanish(wind_dir: Vector3) -> void:
	if vanishing:
		return
	vanishing = true
	route.clear()
	# 花びら（本体が消えても舞い続けるよう親へ移す）
	remove_child(burst)
	get_parent().add_child(burst)
	burst.global_position = global_position + Vector3(0, 0.9, 0)
	burst.restart()
	burst.emitting = true
	# 体が透けていく
	for m in fade_mats:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	var tw := create_tween().set_parallel()
	for m in fade_mats:
		var c := m.albedo_color
		tw.tween_property(m, "albedo_color", Color(c.r, c.g, c.b, 0.0), 2.4).set_ease(Tween.EASE_IN)
	tw.tween_property(body, "position:y", 0.3, 2.4)
	# 帽子だけが残って風に舞う
	var ht := hat.global_transform
	body.remove_child(hat)
	get_parent().add_child(hat)
	hat.global_transform = ht
	var w := Vector3(wind_dir.x, 0, wind_dir.z).normalized()
	# 落下点は通路の上（壁の中に落ちないよう、君の立っていたタイル内に収める）
	var tc: Vector3 = maze.tile_to_world(maze.world_to_tile(global_position))
	var land := tc + w * 0.75
	if maze.is_open(maze.world_to_tile(tc + w * 2.0)):
		land = tc + w * 1.6
	land.y = 0.03
	hat_rest = land
	var peak := ht.origin.lerp(land, 0.4) + Vector3(0, 0.9, 0)
	var ht2 := create_tween()
	ht2.tween_property(hat, "global_position", peak, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	ht2.parallel().tween_property(hat, "rotation", Vector3(0.9, 2.5, 0.4), 1.1)
	ht2.tween_property(hat, "global_position", land, 1.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	ht2.parallel().tween_property(hat, "rotation", Vector3(0.05, 4.2, -0.04), 1.6)
	var hide := create_tween()
	hide.tween_interval(2.5)
	hide.tween_callback(func(): visible = false)


## 次に遊ぶときのため元に戻す
func _restore() -> void:
	vanishing = false
	for m in fade_mats:
		m.albedo_color.a = 1.0
		m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	body.position = Vector3.ZERO
	if hat.get_parent() != body:
		hat.get_parent().remove_child(hat)
		body.add_child(hat)
	hat.position = Vector3(0, 1.76, 0)
	hat.rotation = Vector3(-0.08, 0, 0)
	if burst.get_parent() != self:
		burst.get_parent().remove_child(burst)
		add_child(burst)
	burst.emitting = false


# ---------------------------------------------------------------- 見た目

func _mat(c: Color, backlight := false, fade := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if fade:
		fade_mats.append(m)
	m.albedo_color = c
	m.roughness = 0.75
	if backlight:
		m.backlight_enabled = true
		m.backlight = Color(0.75, 0.72, 0.62)
		m.rim_enabled = true
		m.rim = 0.4
		m.rim_tint = 0.3
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _build_model() -> void:
	body = Node3D.new()
	add_child(body)
	var white := _mat(Color(0.97, 0.97, 0.95), true)
	var skin := _mat(Color(1.0, 0.84, 0.72), true)
	var hair := _mat(Color(0.12, 0.08, 0.05))
	var sandal := _mat(Color(0.55, 0.38, 0.22))
	# 脚：股関節で回る（脚＋サンダル）
	leg_l = Node3D.new(); leg_l.position = Vector3(-0.07, 0.66, 0); body.add_child(leg_l)
	leg_r = Node3D.new(); leg_r.position = Vector3(0.07, 0.66, 0); body.add_child(leg_r)
	for leg in [leg_l, leg_r]:
		var lm := CapsuleMesh.new()
		lm.radius = 0.045
		lm.height = 0.66
		_part(leg, lm, skin, Vector3(0, -0.31, 0))
		var foot := BoxMesh.new()
		foot.size = Vector3(0.08, 0.04, 0.2)
		_part(leg, foot, sandal, Vector3(0, -0.64, -0.03))
	var sk := CylinderMesh.new()
	sk.top_radius = 0.14
	sk.bottom_radius = 0.34
	sk.height = 0.62
	sk.radial_segments = 20
	skirt = _part(body, sk, white, Vector3(0, 0.86, 0))
	var torso := CylinderMesh.new()
	torso.top_radius = 0.12
	torso.bottom_radius = 0.13
	torso.height = 0.36
	_part(body, torso, white, Vector3(0, 1.33, 0))
	arm_l = Node3D.new(); arm_l.position = Vector3(-0.16, 1.47, 0); body.add_child(arm_l)
	arm_r = Node3D.new(); arm_r.position = Vector3(0.16, 1.47, 0); body.add_child(arm_r)
	for a in [arm_l, arm_r]:
		var am := CapsuleMesh.new()
		am.radius = 0.035
		am.height = 0.56
		_part(a, am, skin, Vector3(0, -0.26, 0))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.04; neck.bottom_radius = 0.045; neck.height = 0.1
	_part(body, neck, skin, Vector3(0, 1.55, 0))
	var head := SphereMesh.new()
	head.radius = 0.105; head.height = 0.23
	_part(body, head, skin, Vector3(0, 1.68, -0.01))
	var hb := SphereMesh.new()
	hb.radius = 0.115; hb.height = 0.25
	_part(body, hb, hair, Vector3(0, 1.69, 0.025))
	var hl := CapsuleMesh.new()
	hl.radius = 0.1; hl.height = 0.42
	_part(body, hl, hair, Vector3(0, 1.5, 0.07), Vector3(0.12, 0, 0), Vector3(1.0, 1.0, 0.5))
	# 帽子（最後に風で飛ばされて残るので、独立したノードにする）
	hat = Node3D.new()
	hat.position = Vector3(0, 1.76, 0)
	hat.rotation = Vector3(-0.08, 0, 0)
	body.add_child(hat)
	var hat_white := _mat(Color(0.97, 0.97, 0.95), true, false)
	var hat_ribbon := _mat(Color(0.25, 0.55, 0.85), false, false)
	var brim := CylinderMesh.new()
	brim.top_radius = 0.3; brim.bottom_radius = 0.31; brim.height = 0.012; brim.radial_segments = 32
	_part(hat, brim, hat_white, Vector3.ZERO)
	var crown := CylinderMesh.new()
	crown.top_radius = 0.1; crown.bottom_radius = 0.125; crown.height = 0.11
	_part(hat, crown, hat_white, Vector3(0, 0.06, 0))
	var band := CylinderMesh.new()
	band.top_radius = 0.127; band.bottom_radius = 0.128; band.height = 0.03
	_part(hat, band, hat_ribbon, Vector3(0, 0.025, 0))
	_build_burst()
	for c in body.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# ---------------------------------------------------------------- 動き

func _face(next_i: int) -> void:
	var n: int = maze.path_tiles.size()
	if next_i >= n:
		return
	var p: Vector3 = maze.tile_to_world(maze.path_tiles[next_i])
	var d := p - position
	if d.length() > 0.01:
		rotation.y = atan2(-d.x, -d.z)


func has_los() -> bool:
	var space := get_world_3d().direct_space_state
	var from: Vector3 = player.global_position + Vector3(0, 1.55, 0)
	var q := PhysicsRayQueryParameters3D.create(from, global_position + Vector3(0, 1.4, 0))
	q.exclude = [player.get_rid()]
	return space.intersect_ray(q).is_empty()


func play_laugh(variant := -1, pitch := 1.0) -> void:
	if variant < 0:
		variant = 0 if rng.randf() < 0.62 else 1
	laugh.stream = laughs[variant]
	laugh.pitch_scale = pitch * rng.randf_range(0.975, 1.025)
	laugh.play()


func _player_path_index() -> int:
	var t: Vector2i = maze.world_to_tile(player.global_position)
	return maze.path_tiles.find(t)


func _overtaken() -> bool:
	return _player_path_index() >= path_i


## 台本用：path_tiles の i 番目に立たせる
func place_at(i: int) -> void:
	path_i = clampi(i, 0, maze.path_tiles.size() - 1)
	position = maze.tile_to_world(maze.path_tiles[path_i])
	last_pos = position
	route.clear()
	_face(path_i + 1)


## 台本用：path_tiles を to_i まで、指定速度で進む
func run_to(to_i: int, spd: float) -> void:
	route.clear()
	to_i = clampi(to_i, 0, maze.path_tiles.size() - 1)
	for i in range(path_i + 1, to_i + 1):
		route.append(maze.tile_to_world(maze.path_tiles[i]))
	path_i = to_i
	route_speed = spd


## 台本用：任意のタイルに立たせ、face_to の方を向かせる
func place_tile(t: Vector2i, face_to: Vector2i) -> void:
	position = maze.tile_to_world(t)
	last_pos = position
	route.clear()
	var d: Vector3 = maze.tile_to_world(face_to) - position
	if d.length() > 0.01:
		rotation.y = atan2(-d.x, -d.z)


## 台本用：タイル列に沿って進む
func run_tiles(tiles: Array, spd: float) -> void:
	route.clear()
	for t in tiles:
		route.append(maze.tile_to_world(t))
	route_speed = spd


func route_done() -> bool:
	return route.is_empty()


## 出口で見つかったあと：前方へ駆けていく
func run_off(dir: Vector3, spd := 3.0) -> void:
	scripted = true
	route.clear()
	route.append(position + dir.normalized() * 8.0)
	route_speed = spd


func _process(delta: float) -> void:
	if maze == null or not visible:
		return
	anim_t += delta
	var dist := global_position.distance_to(player.global_position)
	var los := has_los()
	# 葉や壁の向こうの声はこもる
	var open_cut: float = cfg.laugh.cutoff
	laugh.attenuation_filter_cutoff_hz = lerpf(laugh.attenuation_filter_cutoff_hz, open_cut if los else open_cut * 0.25, 1.0 - exp(-5.0 * delta))
	laugh.volume_db = lerpf(laugh.volume_db, float(cfg.laugh.db) + (0.0 if los else -3.0), 1.0 - exp(-5.0 * delta))
	if vanishing:
		pass
	elif scripted:
		_follow_route(delta)
	elif not done:
		_auto(delta, dist, los)
	_animate(delta)


func _auto(delta: float, dist: float, los: bool) -> void:
	laugh_timer -= delta
	if hold > 0.0:
		hold -= delta
		if laugh_timer <= 0.0:
			play_laugh(0)
			var iv: Vector2 = cfg.laugh.interval
			laugh_timer = rng.randf_range(iv.x, iv.y)
		if dist > 3.0:
			return
	if laugh_timer <= 0.0 and laugh_allowed:
		play_laugh()
		var iv: Vector2 = cfg.laugh.interval
		laugh_timer = rng.randf_range(iv.x, iv.y) * (0.6 if dist < 12.0 else 1.0)
	var last := wp >= waypoints.size() - 1
	if not last and not moving and (dist < 4.5 or (los and dist < 11.0) or _overtaken()):
		moving = true
		wp += 1
		var pi := _player_path_index()
		while wp < waypoints.size() - 1 and waypoints[wp] <= pi + 2:
			wp += 1
		play_laugh()
		laugh_timer = rng.randf_range(2.5, 4.0)
	if moving:
		var target_i := waypoints[wp]
		var tgt: Vector3 = maze.tile_to_world(maze.path_tiles[mini(path_i + 1, target_i)])
		var d := tgt - position
		var step := (dash if dist < 3.5 else speed) * delta
		if d.length() <= step:
			position = tgt
			path_i = mini(path_i + 1, target_i)
			if path_i >= target_i:
				moving = false
		else:
			position += d.normalized() * step
			rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 1.0 - exp(-10.0 * delta))
		if not moving:
			_face(path_i + 1)
	if last and not moving and dist < 2.6:
		done = true
		found.emit()


func _follow_route(delta: float) -> void:
	if route.is_empty():
		return
	var tgt: Vector3 = route[0]
	var d := tgt - position
	var step := route_speed * delta
	if d.length() <= step:
		position = tgt
		route.pop_front()
	else:
		position += d.normalized() * step
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 1.0 - exp(-10.0 * delta))


func _animate(delta: float) -> void:
	# 実際の移動量から歩き/走りを判定し、脚・腕・体を動かす
	var moved := position - last_pos
	moved.y = 0.0
	last_pos = position
	var spd := moved.length() / maxf(delta, 0.0001)
	cur_speed = lerpf(cur_speed, spd, 1.0 - exp(-10.0 * delta))
	var run := clampf((cur_speed - 1.8) / 2.5, 0.0, 1.0)       # 0=歩き 1=走り
	var amt := clampf(cur_speed / 1.2, 0.0, 1.0)              # 0=静止
	# 歩幅に合わせて位相を進める（歩き 約0.55m / 走り 約0.9m で一歩）
	stride += cur_speed * delta / lerpf(0.55, 0.9, run) * PI
	var swing := sin(stride) * lerpf(0.42, 0.75, run) * amt
	leg_l.rotation.x = swing
	leg_r.rotation.x = -swing
	arm_l.rotation.x = -swing * lerpf(0.6, 1.0, run)
	arm_r.rotation.x = swing * lerpf(0.6, 1.0, run)
	body.position.y = absf(sin(stride)) * lerpf(0.02, 0.06, run) * amt + sin(anim_t * 1.6) * 0.004 * (1.0 - amt)
	body.rotation.x = -0.12 * run * amt   # 走るときは前傾
	skirt.rotation.x = sin(anim_t * 3.1) * 0.03 + 0.1 * run * amt
	skirt.rotation.z = sin(stride) * 0.04 * amt + sin(anim_t * 2.3) * 0.025

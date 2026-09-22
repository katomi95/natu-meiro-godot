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
	for f in [0.28, 0.52, 0.76, 1.0]:
		waypoints.append(clampi(int(round((n - 1) * f)), 0, n - 1))
	path_i = waypoints[0]
	position = maze.tile_to_world(maze.path_tiles[path_i])
	last_pos = position
	_face(path_i + 1)
	laugh_timer = rng.randf_range(2.2, 3.4)
	visible = not scripted


# ---------------------------------------------------------------- 見た目

func _mat(c: Color, backlight := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
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
	var ribbon := _mat(Color(0.25, 0.55, 0.85))
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
	var brim := CylinderMesh.new()
	brim.top_radius = 0.3; brim.bottom_radius = 0.31; brim.height = 0.012; brim.radial_segments = 32
	_part(body, brim, white, Vector3(0, 1.76, 0), Vector3(-0.08, 0, 0))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.1; crown.bottom_radius = 0.125; crown.height = 0.11
	_part(body, crown, white, Vector3(0, 1.82, 0), Vector3(-0.08, 0, 0))
	var band := CylinderMesh.new()
	band.top_radius = 0.127; band.bottom_radius = 0.128; band.height = 0.03
	_part(body, band, ribbon, Vector3(0, 1.785, 0), Vector3(-0.08, 0, 0))
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
	if scripted:
		_follow_route(delta)
	elif not done:
		_auto(delta, dist, los)
	_animate(delta)


func _auto(delta: float, dist: float, los: bool) -> void:
	laugh_timer -= delta
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

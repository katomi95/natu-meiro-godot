extends Node3D
## 「君」：白い帽子と白いサマードレスの後ろ姿。迷路の奥へ逃げながら笑う。

signal found

const SPEED := 4.0
const DASH := 6.5

var maze: Node3D
var player: Node3D
var waypoints: Array[int] = []     # path_tiles のインデックス
var wp := 0
var path_i := 0
var moving := false
var done := false
var laugh_timer := 3.0
var anim_t := 0.0
var laughs: Array[AudioStream] = []
var rng := RandomNumberGenerator.new()

var body: Node3D
var skirt: MeshInstance3D
var arm_l: Node3D
var arm_r: Node3D
@onready var laugh: AudioStreamPlayer3D = $Laugh


func setup(maze_: Node3D, player_: Node3D) -> void:
	maze = maze_
	player = player_
	rng.randomize()
	laughs = [load("res://audio/laugh_0.mp3"), load("res://audio/laugh_1.mp3")]
	var n: int = maze.path_tiles.size()
	for f in [0.28, 0.52, 0.76, 1.0]:
		waypoints.append(clampi(int(round((n - 1) * f)), 0, n - 1))
	path_i = waypoints[0]
	position = maze.tile_to_world(maze.path_tiles[path_i])
	_face(path_i + 1)
	_build_model()
	laugh.position = Vector3(0, 1.4, 0)


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
	# 脚
	for sx in [-0.07, 0.07]:
		var leg := CapsuleMesh.new()
		leg.radius = 0.045
		leg.height = 0.62
		_part(body, leg, skin, Vector3(sx, 0.32, 0))
		var foot := BoxMesh.new()
		foot.size = Vector3(0.08, 0.04, 0.2)
		_part(body, foot, sandal, Vector3(sx, 0.02, -0.03))
	# スカート（裾の広がったドレス）
	var sk := CylinderMesh.new()
	sk.top_radius = 0.14
	sk.bottom_radius = 0.34
	sk.height = 0.62
	sk.radial_segments = 20
	skirt = _part(body, sk, white, Vector3(0, 0.86, 0))
	# 胴
	var torso := CylinderMesh.new()
	torso.top_radius = 0.12
	torso.bottom_radius = 0.13
	torso.height = 0.36
	_part(body, torso, white, Vector3(0, 1.33, 0))
	# 腕（ノースリーブ）
	arm_l = Node3D.new(); arm_l.position = Vector3(-0.16, 1.47, 0); body.add_child(arm_l)
	arm_r = Node3D.new(); arm_r.position = Vector3(0.16, 1.47, 0); body.add_child(arm_r)
	for a in [arm_l, arm_r]:
		var am := CapsuleMesh.new()
		am.radius = 0.035
		am.height = 0.56
		_part(a, am, skin, Vector3(0, -0.26, 0))
	# 首・頭
	var neck := CylinderMesh.new()
	neck.top_radius = 0.04; neck.bottom_radius = 0.045; neck.height = 0.1
	_part(body, neck, skin, Vector3(0, 1.55, 0))
	var head := SphereMesh.new()
	head.radius = 0.105; head.height = 0.23
	_part(body, head, skin, Vector3(0, 1.68, -0.01))
	# 髪（後ろ姿なので背中側を大きく）
	var hb := SphereMesh.new()
	hb.radius = 0.115; hb.height = 0.25
	_part(body, hb, hair, Vector3(0, 1.69, 0.025))
	var hl := CapsuleMesh.new()
	hl.radius = 0.1; hl.height = 0.42
	_part(body, hl, hair, Vector3(0, 1.5, 0.07), Vector3(0.12, 0, 0), Vector3(1.0, 1.0, 0.5))
	# 麦わら…ではなく白い帽子
	var brim := CylinderMesh.new()
	brim.top_radius = 0.3; brim.bottom_radius = 0.31; brim.height = 0.012; brim.radial_segments = 32
	_part(body, brim, white, Vector3(0, 1.76, 0), Vector3(-0.08, 0, 0))
	var crown := CylinderMesh.new()
	crown.top_radius = 0.1; crown.bottom_radius = 0.125; crown.height = 0.11
	_part(body, crown, white, Vector3(0, 1.82, 0), Vector3(-0.08, 0, 0))
	var band := CylinderMesh.new()
	band.top_radius = 0.127; band.bottom_radius = 0.128; band.height = 0.03
	_part(body, band, ribbon, Vector3(0, 1.785, 0), Vector3(-0.08, 0, 0))
	# 影を落とす
	for c in body.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


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


func _player_path_index() -> int:
	var t: Vector2i = maze.world_to_tile(player.global_position)
	return maze.path_tiles.find(t)


func _overtaken() -> bool:
	return _player_path_index() >= path_i


func _play_laugh() -> void:
	laugh.stream = laughs[rng.randi() % laughs.size()]
	laugh.pitch_scale = rng.randf_range(0.97, 1.05)
	laugh.play()


func _process(delta: float) -> void:
	if maze == null or done:
		return
	anim_t += delta
	var dist := global_position.distance_to(player.global_position)
	var los := has_los()
	# 葉の向こうの声はこもる
	laugh.attenuation_filter_cutoff_hz = lerpf(laugh.attenuation_filter_cutoff_hz, 9000.0 if los else 1800.0, 1.0 - exp(-5.0 * delta))
	laugh.volume_db = lerpf(laugh.volume_db, 0.0 if los else -3.0, 1.0 - exp(-5.0 * delta))
	laugh_timer -= delta
	if laugh_timer <= 0.0:
		_play_laugh()
		laugh_timer = rng.randf_range(5.0, 9.0) if dist > 12.0 else rng.randf_range(3.5, 6.0)
	var last := wp >= waypoints.size() - 1
	if not last and not moving and (dist < 4.5 or (los and dist < 11.0) or _overtaken()):
		moving = true
		wp += 1
		# 追い越されていたら、プレイヤーより先の地点まで逃げる
		var pi := _player_path_index()
		while wp < waypoints.size() - 1 and waypoints[wp] <= pi + 2:
			wp += 1
		_play_laugh()
		laugh_timer = rng.randf_range(2.5, 4.0)
	if moving:
		var target_i := waypoints[wp]
		var tgt: Vector3 = maze.tile_to_world(maze.path_tiles[mini(path_i + 1, target_i)])
		var d := tgt - position
		var step := (DASH if dist < 3.5 else SPEED) * delta
		if d.length() <= step:
			position = tgt
			path_i = mini(path_i + 1, target_i)
			if path_i >= target_i:
				moving = false
		else:
			position += d.normalized() * step
			var want := atan2(-d.x, -d.z)
			rotation.y = lerp_angle(rotation.y, want, 1.0 - exp(-10.0 * delta))
		if not moving:
			_face(path_i + 1)
	if last and not moving and dist < 2.6:
		done = true
		found.emit()
	# アニメーション（走る / 立ち止まって揺れる）
	var run := 1.0 if moving else 0.0
	body.position.y = absf(sin(anim_t * 9.0)) * 0.05 * run + sin(anim_t * 1.6) * 0.004
	arm_l.rotation.x = sin(anim_t * 9.0) * 0.6 * run
	arm_r.rotation.x = -sin(anim_t * 9.0) * 0.6 * run
	skirt.rotation.x = sin(anim_t * 3.1) * 0.03 + 0.08 * run
	skirt.rotation.z = sin(anim_t * 2.3) * 0.025

extends Node3D
## 入道雲：大きな球の集合を MultiMesh で積み上げる。

@export var sun_dir := Vector3(0.12, 0.88, 0.46)


## kind: cumulus（入道雲） / cumulus_low（低めの雲） / dusk（夕焼けの雲） / none
func build(kind := "cumulus") -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if kind == "none":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var xs := []
	var cs := []
	# 方位(度, 0=北=-Z), 距離, 規模, 雲底, 雲頂
	var clouds := [
		[-8.0, 2300.0, 1.25, 260.0, 1900.0],
		[38.0, 2600.0, 0.95, 280.0, 1350.0],
		[-52.0, 2500.0, 0.85, 250.0, 1100.0],
		[95.0, 2800.0, 0.8, 300.0, 1000.0],
		[-110.0, 2700.0, 0.9, 260.0, 1250.0],
		[160.0, 3000.0, 0.6, 300.0, 700.0],
	]
	if kind == "cumulus_low":
		clouds = [[-20.0, 2600.0, 0.75, 240.0, 900.0], [30.0, 2800.0, 0.7, 260.0, 800.0], [120.0, 2700.0, 0.8, 250.0, 1000.0],
			[-100.0, 2600.0, 0.7, 240.0, 850.0], [70.0, 3000.0, 0.6, 250.0, 700.0], [-150.0, 3000.0, 0.7, 250.0, 800.0]]
	elif kind == "dusk":
		clouds = [[-60.0, 2600.0, 0.8, 300.0, 900.0], [15.0, 3000.0, 0.7, 320.0, 800.0], [110.0, 2800.0, 0.9, 300.0, 1100.0]]
	for c in clouds:
		var az := deg_to_rad(c[0])
		var center: Vector3 = Vector3(sin(az), 0, -cos(az)) * float(c[1])
		var right := Vector3(cos(az), 0, sin(az))
		var sc: float = c[2]
		var base: float = c[3]
		var top: float = c[4]
		var bw := 700.0 * sc
		# 雲底：横に広い
		for i in 16:
			var t := rng.randf_range(-1.0, 1.0)
			var r := rng.randf_range(160.0, 260.0) * sc
			var p: Vector3 = center + right * t * bw + Vector3(0, base + r * 0.55, 0) + (center.normalized() * rng.randf_range(-200, 200))
			xs.append(_x(p, r)); cs.append(Color(r, rng.randf(), base, 0))
		# 塔：もくもくと積み上がる
		var y := base + 200.0 * sc
		var w := bw * 0.55
		while y < top:
			var f := (y - base) / (top - base)
			var r := lerpf(300.0, 220.0, f) * sc * rng.randf_range(0.85, 1.15)
			for k in 4:
				var off: Vector3 = right * rng.randf_range(-w, w) * (1.0 - f * 0.45) + center.normalized() * rng.randf_range(-150, 150)
				var p: Vector3 = center + off + Vector3(0, y + rng.randf_range(-60, 60), 0)
				xs.append(_x(p, r * rng.randf_range(0.7, 1.0))); cs.append(Color(r, rng.randf(), base, 0))
			y += r * 0.55
		# 頂部のカリフラワー
		for i in 9:
			var r := rng.randf_range(160.0, 240.0) * sc
			var p: Vector3 = center + right * rng.randf_range(-w, w) * 0.6 + Vector3(0, top - rng.randf_range(0, 250) * sc, 0) + center.normalized() * rng.randf_range(-120, 120)
			xs.append(_x(p, r)); cs.append(Color(r, rng.randf(), base, 0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = sphere
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
		mm.set_instance_custom_data(i, cs[i])
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/cloud.gdshader")
	mat.set_shader_parameter("sun_dir", sun_dir)
	if kind == "dusk":
		mat.set_shader_parameter("lit_color", Color(1.0, 0.62, 0.38))
		mat.set_shader_parameter("shade_color", Color(0.3, 0.25, 0.42))
		mat.set_shader_parameter("horizon_color", Color(0.95, 0.56, 0.32))
		mat.set_shader_parameter("brightness", 1.05)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Cumulonimbus"
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-5000, -100, -5000), Vector3(10000, 4000, 10000))
	add_child(mmi)


func _x(p: Vector3, r: float) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3(r, r * 0.92, r)), p)

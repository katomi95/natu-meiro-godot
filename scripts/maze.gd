extends Node3D
## 迷路：生成・スタイル別の壁（ひまわり / 夏草 / 夏祭り / 町）・地面・当たり判定・見晴らし台・遠景。
## build(cfg) を呼ぶたびに作り直す。

const TILE := 2.6
const FIELD_MARGIN := 26.0        # 迷路の外に広がる畑の幅
const DECK_H := 1.9               # 見晴らし台の高さ
const RAMP_LEN := 7.0

var cfg: Dictionary = {}
var cells := 9
var G := 19
var sun_dir := Vector3(0.12, 0.88, 0.46)
var wall := []                    # wall[x][z] : bool
var young := {}                   # 背の低いひまわり（向こうが見える）タイル
var start_tile := Vector2i(1, 17)
var entrance_tile := Vector2i(1, 18)
var goal_tile := Vector2i.ZERO
var path_tiles: Array[Vector2i] = []
var deck_center := Vector3.ZERO
var has_deck := false
var rng := RandomNumberGenerator.new()
## Web(WebGL2)版は密度を落として軽くする
var lite := OS.has_feature("web")

var plant_mat: ShaderMaterial
var grass_mat: ShaderMaterial
var tall_mat: ShaderMaterial
var lantern_lights: Array[OmniLight3D] = []


func build(cfg_: Dictionary) -> void:
	cfg = cfg_
	for c in get_children():
		remove_child(c)
		c.queue_free()
	lantern_lights.clear()
	young.clear()
	cells = cfg.cells
	G = cells * 2 + 1
	start_tile = Vector2i(1, G - 2)
	entrance_tile = Vector2i(1, G - 1)
	has_deck = cfg.get("deck", false)
	sun_dir = (cfg.sun_dir as Vector3).normalized()
	rng.seed = cfg.seed
	_generate_maze()
	plant_mat = ShaderMaterial.new()
	plant_mat.shader = load("res://shaders/plant.gdshader")
	plant_mat.set_shader_parameter("wind_strength", cfg.wind)
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	if cfg.get("fade", false):
		grass_mat.set_shader_parameter("tip_color", Color(0.72, 0.7, 0.36))
		grass_mat.set_shader_parameter("base_color", Color(0.26, 0.3, 0.1))
	var e := tile_to_world(entrance_tile)
	deck_center = Vector3(e.x, DECK_H, e.z + TILE * 0.5 + RAMP_LEN + 2.0)
	_build_ground()
	match cfg.style:
		"sunflower":
			_build_sunflowers()
			_build_grass()
		"grass":
			_build_tall_grass()
			_build_grass()
		"festival":
			_build_festival()
		"town":
			_build_town()
	_build_collision()
	if has_deck:
		_build_deck()
	_build_distance()


# ---------------------------------------------------------------- 迷路

func tile_to_world(t: Vector2i) -> Vector3:
	return Vector3((t.x - (G - 1) * 0.5) * TILE, 0.0, (t.y - (G - 1) * 0.5) * TILE)


func world_to_tile(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / TILE + (G - 1) * 0.5), roundi(p.z / TILE + (G - 1) * 0.5))


func is_wall(t: Vector2i) -> bool:
	if t.x < 0 or t.y < 0 or t.x >= G or t.y >= G:
		return false
	return wall[t.x][t.y]


func is_open(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < G and t.y < G and not wall[t.x][t.y]


func _open_neighbors(t: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if is_open(t + d):
			out.append(d)
	return out


func _generate_maze() -> void:
	wall = []
	for x in G:
		var col := []
		for z in G:
			col.append(true)
		wall.append(col)
	# 穴掘り法
	var stack: Array[Vector2i] = [Vector2i(0, cells - 1)]
	var visited := {Vector2i(0, cells - 1): true}
	wall[1][G - 2] = false
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var opts: Array[Vector2i] = []
		for d in dirs:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < cells and n.y < cells and not visited.has(n):
				opts.append(n)
		if opts.is_empty():
			stack.pop_back()
			continue
		var n2: Vector2i = opts[rng.randi() % opts.size()]
		visited[n2] = true
		wall[n2.x * 2 + 1][n2.y * 2 + 1] = false
		wall[c.x + n2.x + 1][c.y + n2.y + 1] = false
		stack.append(n2)
	# ループを作って迷いすぎないように（braid）
	var loops: int = cfg.get("loops", 4)
	var opened := 0
	var guard := 0
	while opened < loops and guard < 5000:
		guard += 1
		var x := rng.randi_range(1, G - 2)
		var z := rng.randi_range(1, G - 2)
		if not wall[x][z]:
			continue
		if (x % 2 == 1 and z % 2 == 0 and not wall[x][z - 1] and not wall[x][z + 1]) or \
				(x % 2 == 0 and z % 2 == 1 and not wall[x - 1][z] and not wall[x + 1][z]):
			wall[x][z] = false
			opened += 1
	if has_deck:
		wall[entrance_tile.x][entrance_tile.y] = false
	# 出口：経路長が path_len に近く、周囲を広場にしても近道ができないセル
	var dist := _bfs(start_tile)
	var target: int = cfg.path_len
	var cands: Array = []
	for k in dist.keys():
		if k.x % 2 == 1 and k.y % 2 == 1 and k.x >= 3 and k.y >= 3 and k.x <= G - 4 and k.y <= G - 4:
			cands.append(k)
	cands.sort_custom(func(a, b): return absi(dist[a] - target) < absi(dist[b] - target))
	var saved := wall.duplicate(true)
	for k in cands:
		wall = saved.duplicate(true)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				wall[k.x + dx][k.y + dz] = false
		var p := find_path(start_tile, k)
		if p.size() >= dist[k] * 0.8:
			goal_tile = k
			path_tiles = p
			break
	print("maze %s goal=%s path_len=%d" % [cfg.name, goal_tile, path_tiles.size()])
	for x in range(1, G - 1):
		for z in range(1, G - 1):
			if wall[x][z] and rng.randf() < 0.07:
				young[Vector2i(x, z)] = true


func _bfs(from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var q: Array[Vector2i] = [from]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if is_open(n) and not dist.has(n):
				dist[n] = dist[c] + 1
				q.append(n)
	return dist


func find_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var prev := {a: a}
	var q: Array[Vector2i] = [a]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == b:
			break
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if is_open(n) and not prev.has(n):
				prev[n] = c
				q.append(n)
	var out: Array[Vector2i] = []
	if not prev.has(b):
		return out
	var t := b
	while t != a:
		out.push_front(t)
		t = prev[t]
	out.push_front(a)
	return out


## 通路の中心線からの距離（踏み固められた土の筋を作るため）
func path_center_dist(p: Vector3) -> float:
	var t := world_to_tile(p)
	var best := 99.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var c := t + Vector2i(dx, dz)
			if not is_open(c):
				continue
			var cw := tile_to_world(c)
			var any := false
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if is_open(c + d):
					any = true
					var ew := tile_to_world(c + d)
					best = minf(best, _seg_dist(Vector2(p.x, p.z), Vector2(cw.x, cw.z), Vector2(ew.x, ew.z)))
			if not any:
				best = minf(best, Vector2(p.x - cw.x, p.z - cw.z).length())
	return best


func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - (a + ab * t)).length()


func maze_half() -> float:
	return G * TILE * 0.5


## 迷路の外側（パディング）かどうか
func _outside(p: Vector3) -> bool:
	var hm := maze_half()
	return absf(p.x) >= hm or absf(p.z) >= hm


# ---------------------------------------------------------------- MultiMesh

func _make_mm(mesh: Mesh, xforms: Array, customs: Array, mat: Material, shadows: bool, name_: String, colors := []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	# Compatibilityレンダラーでは COLOR にインスタンス色が掛かるので明示する
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i] if i < customs.size() else Color(0, 0, 0, 0))
		mm.set_instance_color(i, colors[i] if i < colors.size() else Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _rc() -> Color:
	return Color(rng.randf(), rng.randf(), 0, 0)


# ---------------------------------------------------------------- ひまわり

func _flower_xform(pos: Vector3, s: float, face_sun: bool) -> Transform3D:
	var sh := Vector2(sun_dir.x, sun_dir.z).normalized()
	var yaw := atan2(sh.x, sh.y)
	if cfg.get("droop", false):
		yaw = 0.6 + rng.randf_range(-0.75, 0.75)
	elif face_sun:
		yaw += rng.randf_range(-0.55, 0.55)
	else:
		yaw = rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(s * rng.randf_range(0.9, 1.1), s, s * rng.randf_range(0.9, 1.1)))
	b = Basis(Vector3(1, 0, 0), rng.randf_range(-0.06, 0.06)) * b
	return Transform3D(b, pos)


func _build_sunflowers() -> void:
	var droop: bool = cfg.get("droop", false)
	var fade: bool = cfg.get("fade", false)
	var near_mesh := Props.sunflower(true, droop, fade)
	var far_mesh := Props.sunflower(false, droop, fade)
	var near_x := []
	var near_c := []
	var far_x := []
	var far_c := []
	var hm := maze_half()
	for x in G:
		for z in G:
			if not wall[x][z]:
				continue
			var t := Vector2i(x, z)
			var c := tile_to_world(t)
			var is_young := young.has(t) and not fade
			var n := 4 if not is_young else 3
			for i in n:
				for j in n:
					if fade and rng.randf() < 0.12:
						continue
					var p := c + Vector3((i + 0.5) / n - 0.5, 0, (j + 0.5) / n - 0.5) * (TILE - 0.35)
					p += Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
					var s := rng.randf_range(0.88, 1.22) if not is_young else rng.randf_range(0.5, 0.62)
					near_x.append(_flower_xform(p, s, rng.randf() < 0.9))
					near_c.append(_rc())
	var outer := hm + FIELD_MARGIN
	var e := tile_to_world(entrance_tile)
	var step := 1.35 if lite else 0.95
	var gx := -outer
	while gx < outer:
		var gz := -outer
		while gz < outer:
			var p := Vector3(gx + rng.randf_range(-0.4, 0.4), 0, gz + rng.randf_range(-0.4, 0.4))
			gz += step
			if absf(p.x) < hm and absf(p.z) < hm:
				continue
			if has_deck and absf(p.x - e.x) < 3.2 and p.z > hm - 0.5 and p.z < deck_center.z + 3.5:
				continue
			var rr := Vector2(p.x, p.z).length()
			if rr > outer - rng.randf() * 8.0:
				continue
			var s := rng.randf_range(0.85, 1.2)
			if rr < hm + 8.0:
				near_x.append(_flower_xform(p, s, rng.randf() < 0.9))
				near_c.append(_rc())
			else:
				far_x.append(_flower_xform(p, s, rng.randf() < 0.9))
				far_c.append(_rc())
		gx += step
	_make_mm(near_mesh, near_x, near_c, plant_mat, true, "SunflowersNear")
	_make_mm(far_mesh, far_x, far_c, plant_mat, false, "SunflowersFar")
	print("sunflowers near=%d far=%d" % [near_x.size(), far_x.size()])


# ---------------------------------------------------------------- 草

func _build_grass() -> void:
	var mesh := Props.grass_clump(false)
	var xs := []
	var cs := []
	var hm := maze_half()
	var ext := hm + 4.0
	var gstep := 0.46 if lite else 0.36
	var e := tile_to_world(entrance_tile)
	var x := -ext
	while x < ext:
		var z := -ext
		while z < ext + (RAMP_LEN + 6.0 if has_deck else 0.0):
			var p := Vector3(x + rng.randf_range(-0.2, 0.2), 0, z + rng.randf_range(-0.2, 0.2))
			z += gstep
			var inside := absf(p.x) < hm and absf(p.z) < hm
			if not inside and z > ext and absf(p.x - e.x) > 4.0:
				continue
			var keep := 1.0
			if inside and is_open(world_to_tile(p)):
				keep = smoothstep(0.25, 0.85, path_center_dist(p)) * 0.9 + 0.1
			elif inside:
				keep = 0.55
			if rng.randf() > keep:
				continue
			var s := rng.randf_range(0.7, 1.3) * (1.0 if keep > 0.5 else 0.75)
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s)), p))
			cs.append(_rc())
		x += gstep
	var mmi := _make_mm(mesh, xs, cs, grass_mat, false, "Grass")
	mmi.visibility_range_end = 70.0
	print("grass clumps=%d" % xs.size())


## 夏草：背丈より高い草の壁
func _build_tall_grass() -> void:
	tall_mat = ShaderMaterial.new()
	tall_mat.shader = load("res://shaders/grass.gdshader")
	tall_mat.set_shader_parameter("sway_amp", 4.5)
	tall_mat.set_shader_parameter("base_color", Color(0.1, 0.24, 0.04))
	tall_mat.set_shader_parameter("tip_color", Color(0.55, 0.72, 0.2))
	var meshes := [Props.grass_clump(true, 11), Props.grass_clump(true, 12), Props.grass_clump(true, 13)]
	var sets := [[], [], []]
	var customs := [[], [], []]
	var hm := maze_half()
	var outer := hm + 14.0
	var step := TILE / (3.0 if not lite else 2.4)
	var gx := -outer
	while gx < outer:
		var gz := -outer
		while gz < outer:
			var p := Vector3(gx + rng.randf_range(-0.35, 0.35), 0, gz + rng.randf_range(-0.35, 0.35))
			gz += step
			var inside := absf(p.x) < hm and absf(p.z) < hm
			if inside:
				var t := world_to_tile(p)
				if not is_wall(t):
					continue
				# 通路側に少しはみ出してもよいが、中央へは出ない
				var c := tile_to_world(t)
				p = c + (p - c) * 0.85
			elif Vector2(p.x, p.z).length() > outer - rng.randf() * 6.0:
				continue
			var s := rng.randf_range(0.85, 1.25)
			var k := rng.randi() % 3
			sets[k].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.15), s)), p))
			customs[k].append(_rc())
		gx += step
	for k in 3:
		_make_mm(meshes[k], sets[k], customs[k], tall_mat, true, "TallGrass%d" % k)


# ---------------------------------------------------------------- 夏祭り

func _face_open(t: Vector2i) -> float:
	## 隣の通路の方を向く yaw（正面 -Z が通路を向く）
	var ns := _open_neighbors(t)
	if ns.is_empty():
		return float(rng.randi() % 4) * PI * 0.5
	var d: Vector2i = ns[rng.randi() % ns.size()]
	return atan2(-float(d.x), -float(d.y))


func _build_festival() -> void:
	var roof_cols := [Color(0.85, 0.12, 0.1), Color(0.15, 0.3, 0.75), Color(0.95, 0.5, 0.1)]
	var goods_cols := [Color(1, 0.3, 0.4), Color(0.2, 0.6, 1.0), Color(1, 0.85, 0.2)]
	var stall_sets := [[], [], []]
	var people := []
	var people_c := []
	var people_col := []
	var lanterns := []
	var lantern_col := []
	var yukata := [Color(0.18, 0.22, 0.5), Color(0.85, 0.35, 0.45), Color(0.95, 0.9, 0.85), Color(0.3, 0.5, 0.75),
		Color(0.5, 0.25, 0.55), Color(0.9, 0.55, 0.2), Color(0.2, 0.45, 0.35), Color(0.75, 0.2, 0.2),
		Color(0.95, 0.75, 0.8), Color(0.25, 0.25, 0.3), Color(0.55, 0.75, 0.85), Color(0.9, 0.85, 0.5)]
	var pad := 3
	var idx := 0
	for x in range(-pad, G + pad):
		for z in range(-pad, G + pad):
			var t := Vector2i(x, z)
			var inside := x >= 0 and z >= 0 and x < G and z < G
			if inside and not wall[x][z]:
				continue
			var c := tile_to_world(t)
			idx += 1
			var yaw := _face_open(t) if inside else float(rng.randi() % 4) * PI * 0.5
			if idx % 3 == 0 or (not inside and rng.randf() < 0.5):
				var s := 1.05 + rng.randf() * 0.1
				var k := rng.randi() % 3
				stall_sets[k].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * 1.1, s)), c))
			else:
				var n := 2 if inside else 1
				for i in n:
					var p := c + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
					var s := rng.randf_range(1.1, 1.3)
					people.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
					people_c.append(_rc())
					people_col.append(yukata[rng.randi() % yukata.size()])
			# 提灯（通路に面した壁の上）
			if inside and rng.randf() < 0.7 and not _open_neighbors(t).is_empty():
				var d: Vector2i = _open_neighbors(t)[0]
				var lp := c + Vector3(d.x, 0, d.y) * TILE * 0.42 + Vector3(0, 2.95 + rng.randf() * 0.3, 0)
				lanterns.append(Transform3D(Basis(), lp))
				lantern_col.append(Color(0.95, 0.22, 0.1) if rng.randf() < 0.7 else Color(1.0, 0.72, 0.4))
	var stall_mat := StandardMaterial3D.new()
	stall_mat.vertex_color_use_as_albedo = true
	stall_mat.roughness = 0.8
	stall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 3:
		_make_mm(Props.stall(roof_cols[k], goods_cols[k]), stall_sets[k], [], stall_mat, true, "Stalls%d" % k)
	var crowd_mat := ShaderMaterial.new()
	crowd_mat.shader = load("res://shaders/crowd.gdshader")
	_make_mm(Props.person(true), people, people_c, crowd_mat, true, "CrowdBody", people_col)
	_make_mm(Props.person(false), people, people_c, crowd_mat, true, "CrowdHead")
	# 提灯
	var lm := SphereMesh.new()
	lm.radius = 0.2
	lm.height = 0.52
	lm.radial_segments = 12
	lm.rings = 8
	# 赤い提灯と白い提灯（和紙越しの灯り）
	var red_x := []
	var white_x := []
	for i in lanterns.size():
		if (lantern_col[i] as Color).g < 0.5:
			red_x.append(lanterns[i])
		else:
			white_x.append(lanterns[i])
	for pair in [[red_x, Color(1.0, 0.16, 0.06), "LanternsRed"], [white_x, Color(1.0, 0.8, 0.5), "LanternsWhite"]]:
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = pair[1]
		lmat.emission_enabled = true
		lmat.emission = pair[1]
		lmat.emission_energy_multiplier = 2.2
		lmat.roughness = 0.9
		_make_mm(lm, pair[0], [], lmat, false, pair[2])
	# 通路沿いの提灯の一部に本物の灯り
	var placed: Array[Vector3] = []
	var max_lights := 10 if lite else 18
	for lt in lanterns:
		var p: Vector3 = lt.origin
		var ok := true
		for q in placed:
			if q.distance_to(p) < 6.5:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)
		var l := OmniLight3D.new()
		l.position = p + Vector3(0, -0.3, 0)
		l.light_color = Color(1.0, 0.6, 0.3)
		l.light_energy = 1.6
		l.omni_range = 6.0
		l.omni_attenuation = 1.2
		add_child(l)
		lantern_lights.append(l)
		if placed.size() >= max_lights:
			break
	print("festival stalls=%d people=%d lanterns=%d" % [stall_sets[0].size() + stall_sets[1].size() + stall_sets[2].size(), people.size(), lanterns.size()])


# ---------------------------------------------------------------- 町（夕立）

func _build_town() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := [Color(0.5, 0.47, 0.41), Color(0.4, 0.4, 0.4), Color(0.34, 0.26, 0.2), Color(0.56, 0.54, 0.48), Color(0.36, 0.38, 0.41)]
	var roofs := [Color(0.18, 0.2, 0.25), Color(0.25, 0.22, 0.2), Color(0.3, 0.34, 0.4)]
	var pad := 4
	for x in range(-pad, G + pad):
		for z in range(-pad, G + pad):
			var t := Vector2i(x, z)
			var inside := x >= 0 and z >= 0 and x < G and z < G
			if inside and not wall[x][z]:
				continue
			var c := tile_to_world(t)
			var h := rng.randf_range(3.6, 7.2)
			var wc: Color = walls[rng.randi() % walls.size()]
			wc.a = 1.0
			Props.box(st, c + Vector3(0, h * 0.5, 0), Vector3(TILE, h, TILE), wc)
			var rc: Color = roofs[rng.randi() % roofs.size()]
			Props.box(st, c + Vector3(0, h + 0.17, 0), Vector3(TILE * 1.08, 0.34, TILE * 1.08), rc)
			if not inside:
				continue
			# 通路に面した側：庇と窓（ブロック塀の家も）
			for d in _open_neighbors(t):
				var nd := Vector3(d.x, 0, d.y)
				var side := Vector3(-d.y, 0, d.x)
				var face := c + nd * TILE * 0.5
				var eave_y := rng.randf_range(2.5, 2.9)
				Props.box(st, face + nd * 0.35 + Vector3(0, eave_y, 0), (side.abs() * TILE + nd.abs() * 0.7 + Vector3(0, 0.08, 0)), rc)
				var floors := int(h / 2.6)
				for f in floors:
					var wy := 1.6 + f * 2.6
					for sx in [-0.26, 0.26]:
						if rng.randf() < 0.3:
							continue
						var lit := rng.randf() < 0.3
						var win := Color(1.0, 0.72, 0.4, 0.0) if lit else Color(0.1, 0.12, 0.14, 1.0)
						Props.box(st, face + nd * 0.02 + side * TILE * sx + Vector3(0, wy, 0), side.abs() * TILE * 0.3 + nd.abs() * 0.04 + Vector3(0, 0.8, 0), win)
				if rng.randf() < 0.35:
					# ブロック塀
					Props.box(st, face + nd * 0.08 + Vector3(0, 0.8, 0), side.abs() * TILE + nd.abs() * 0.16 + Vector3(0, 1.6, 0), Color(0.62, 0.62, 0.6))
	var mi := MeshInstance3D.new()
	mi.name = "Town"
	mi.mesh = st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/town.gdshader")
	mi.material_override = mat
	add_child(mi)
	# 電柱（通路沿い）と自販機
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.5, 0.49, 0.47)
	pole_mat.roughness = 0.4
	var k := 0
	for t in path_tiles:
		k += 1
		if k % 5 != 2:
			continue
		var ns := _open_neighbors(t)
		var c := tile_to_world(t)
		var off := Vector3(0.95, 0, 0.95)
		if ns.size() > 0:
			var d: Vector2i = ns[0]
			off = Vector3(-d.y, 0, d.x) * 0.95
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.11
		cm.bottom_radius = 0.15
		cm.height = 8.0
		pole.mesh = cm
		pole.material_override = pole_mat
		pole.position = c + off + Vector3(0, 4.0, 0)
		add_child(pole)
	var vend_mat := StandardMaterial3D.new()
	vend_mat.albedo_color = Color(0.9, 0.92, 0.95)
	vend_mat.emission_enabled = true
	vend_mat.emission = Color(0.85, 0.92, 1.0)
	vend_mat.emission_energy_multiplier = 2.2
	var vends := 0
	for x in range(1, G - 1):
		for z in range(1, G - 1):
			var t := Vector2i(x, z)
			if not is_open(t) or t == start_tile or path_tiles.has(t) or _open_neighbors(t).size() != 1 or vends >= 3:
				continue
			var d: Vector2i = _open_neighbors(t)[0]
			var back := -Vector3(d.x, 0, d.y)
			var p := tile_to_world(t) + back * (TILE * 0.5 - 0.4)
			var vm := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.9, 1.85, 0.7)
			vm.mesh = bm
			vm.material_override = vend_mat
			vm.position = p + Vector3(0, 0.925, 0)
			vm.rotation.y = atan2(back.x, back.z)
			add_child(vm)
			var l := OmniLight3D.new()
			l.position = p - back * 0.8 + Vector3(0, 1.4, 0)
			l.light_color = Color(0.8, 0.9, 1.0)
			l.light_energy = 1.4
			l.omni_range = 5.0
			add_child(l)
			vends += 1


# ---------------------------------------------------------------- 地面・当たり判定

func _build_ground() -> void:
	var res := 8
	var img := Image.create(G * res, G * res, false, Image.FORMAT_R8)
	var hm := maze_half()
	for px in G * res:
		for pz in G * res:
			var p := Vector3(-hm + (px + 0.5) / res * TILE, 0, -hm + (pz + 0.5) / res * TILE)
			var val := 0.0
			if is_open(world_to_tile(p)):
				val = 1.0 - smoothstep(0.3, 0.95, path_center_dist(p))
			img.set_pixel(px, pz, Color(val, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	mat.set_shader_parameter("path_mask", tex)
	mat.set_shader_parameter("mask_rect", Vector4(-hm, -hm, hm * 2.0, hm * 2.0))
	mat.set_shader_parameter("mode", int(cfg.get("ground", 0)))
	if cfg.get("fade", false):
		mat.set_shader_parameter("grass_color", Color(0.4, 0.44, 0.18))
		mat.set_shader_parameter("meadow_color", Color(0.5, 0.52, 0.26))
	if cfg.style == "grass":
		mat.set_shader_parameter("grass_color", Color(0.2, 0.34, 0.08))
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(2400, 2400)
	mi.mesh = pm
	mi.material_override = mat
	add_child(mi)


func _build_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Walls"
	add_child(body)
	for x in G:
		for z in G:
			if wall[x][z]:
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(TILE, 4.0, TILE)
				cs.shape = bs
				cs.position = tile_to_world(Vector2i(x, z)) + Vector3(0, 2.0, 0)
				body.add_child(cs)
	var floor_cs := CollisionShape3D.new()
	var fs := BoxShape3D.new()
	fs.size = Vector3(400, 1, 400)
	floor_cs.shape = fs
	floor_cs.position = Vector3(0, -0.5, 0)
	body.add_child(floor_cs)


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Basis(), collide := false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = Transform3D(rot, pos)
	parent.add_child(mi)
	if collide:
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		sb.transform = mi.transform
		sb.add_child(cs)
		parent.add_child(sb)
	if mat == null:
		mi.visible = false


func _build_deck() -> void:
	var deck := Node3D.new()
	deck.name = "Overlook"
	add_child(deck)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.30, 0.19)
	wood.roughness = 0.85
	var e := tile_to_world(entrance_tile)
	var ramp_start_z := e.z + TILE * 0.5
	var ramp_end_z := ramp_start_z + RAMP_LEN
	var ang := atan2(DECK_H, RAMP_LEN)
	var ramp_len := sqrt(RAMP_LEN * RAMP_LEN + DECK_H * DECK_H)
	var rot := Basis(Vector3.RIGHT, ang)
	_box(deck, Vector3(2.0, 0.12, ramp_len), Vector3(e.x, DECK_H * 0.5 - 0.05, (ramp_start_z + ramp_end_z) * 0.5), wood, rot, true)
	var dz := deck_center.z
	_box(deck, Vector3(4.0, 0.16, 4.0), Vector3(e.x, DECK_H - 0.08, dz), wood, Basis(), true)
	for sx in [-1.8, 1.8]:
		for sz in [-1.8, 1.8]:
			_box(deck, Vector3(0.14, DECK_H, 0.14), Vector3(e.x + sx, DECK_H * 0.5, dz + sz), wood)
	var rail_h := 1.0
	for sx in [-2.0, 2.0]:
		_box(deck, Vector3(0.06, 0.06, 4.0), Vector3(e.x + sx, DECK_H + rail_h, dz), wood)
		_box(deck, Vector3(0.1, 2.0, 4.0), Vector3(e.x + sx, DECK_H + 1.0, dz), null, Basis(), true)
		for k in 5:
			_box(deck, Vector3(0.06, rail_h, 0.06), Vector3(e.x + sx, DECK_H + rail_h * 0.5, dz - 2.0 + k), wood)
	_box(deck, Vector3(4.0, 0.06, 0.06), Vector3(e.x, DECK_H + rail_h, dz + 2.0), wood)
	_box(deck, Vector3(4.0, 2.0, 0.1), Vector3(e.x, DECK_H + 1.0, dz + 2.0), null, Basis(), true)
	for sx in [-1.1, 1.1]:
		_box(deck, Vector3(0.1, 4.0, RAMP_LEN + 0.5), Vector3(e.x + sx, 2.0, (ramp_start_z + ramp_end_z) * 0.5), null, Basis(), true)
		_box(deck, Vector3(0.05, 0.05, ramp_len), Vector3(e.x + sx * 0.95, DECK_H * 0.5 + 0.9, (ramp_start_z + ramp_end_z) * 0.5), wood, rot)
	for sx in [-1.0, 1.0]:
		_box(deck, Vector3(1.0, 4.0, 0.1), Vector3(e.x + sx * 1.5, 2.0, dz - 2.0), null, Basis(), true)


# ---------------------------------------------------------------- 遠景（木立・山・電柱）

func _build_distance() -> void:
	var style: String = cfg.style
	if style == "town":
		return
	var far := Node3D.new()
	far.name = "Distance"
	add_child(far)
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 6
	var tree_mat := StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.13, 0.26, 0.08) if not cfg.get("fade", false) else Color(0.25, 0.3, 0.12)
	if style == "festival":
		tree_mat.albedo_color = Color(0.06, 0.08, 0.06)
	tree_mat.roughness = 1.0
	var xs := []
	var rmin := 150.0 if style != "festival" else 45.0
	for i in 220:
		var a := rng.randf() * TAU
		var d := rng.randf_range(rmin, rmin + 110.0)
		var base := Vector3(cos(a) * d, 0, sin(a) * d)
		var h := rng.randf_range(8.0, 16.0)
		for k in 3:
			var rr := h * rng.randf_range(0.35, 0.5)
			var p := base + Vector3(rng.randf_range(-4, 4), rr * 0.75 + h * rng.randf_range(0.0, 0.35), rng.randf_range(-4, 4))
			xs.append(Transform3D(Basis().scaled(Vector3(rr, rr * 1.1, rr)), p))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = sphere
	mm.instance_count = xs.size()
	for i in xs.size():
		mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "TreeLine"
	mmi.multimesh = mm
	mmi.material_override = tree_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.add_child(mmi)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 160
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.9
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var h0 := 35.0 + (noise.get_noise_1d(float(i) / segs * 8.0) * 0.5 + 0.5) * 120.0
		var h1 := 35.0 + (noise.get_noise_1d(float(i + 1) / segs * 8.0) * 0.5 + 0.5) * 120.0
		var R := 900.0
		var p0 := Vector3(cos(a0) * R, 0, sin(a0) * R)
		var p1 := Vector3(cos(a1) * R, 0, sin(a1) * R)
		var t0 := Vector3(cos(a0) * (R + 250), h0, sin(a0) * (R + 250))
		var t1 := Vector3(cos(a1) * (R + 250), h1, sin(a1) * (R + 250))
		var nn := -Vector3(cos(a0), -0.6, sin(a0)).normalized()
		for vv in [p0, t0, t1, p0, t1, p1]:
			st.set_normal(nn)
			st.add_vertex(vv)
	var hills := MeshInstance3D.new()
	hills.name = "Hills"
	hills.mesh = st.commit()
	var hill_mat := StandardMaterial3D.new()
	hill_mat.albedo_color = Color(0.18, 0.32, 0.16) if style != "festival" else Color(0.08, 0.08, 0.14)
	hill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hills.material_override = hill_mat
	hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.add_child(hills)
	if style == "festival":
		return
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.45, 0.43, 0.40)
	var wire_mat := StandardMaterial3D.new()
	wire_mat.albedo_color = Color(0.08, 0.08, 0.08)
	var prev_top := Vector3.INF
	var pz := -105.0
	for i in 11:
		var px := -150.0 + i * 30.0
		var top := Vector3(px, 10.0, pz + sin(i * 0.7) * 3.0)
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.13
		cm.bottom_radius = 0.18
		cm.height = 10.0
		pole.mesh = cm
		pole.material_override = pole_mat
		pole.position = Vector3(top.x, 5.0, top.z)
		far.add_child(pole)
		_box(far, Vector3(1.6, 0.12, 0.12), top + Vector3(0, -0.6, 0), pole_mat)
		if prev_top != Vector3.INF:
			for off in [-0.7, 0.7]:
				_wire(far, prev_top + Vector3(off, -0.6, 0), top + Vector3(off, -0.6, 0), wire_mat)
		prev_top = top


func _wire(parent: Node3D, a: Vector3, b: Vector3, mat: Material) -> void:
	var segs := 8
	var prev := a
	for i in range(1, segs + 1):
		var t := float(i) / segs
		var p := a.lerp(b, t) - Vector3(0, sin(t * PI) * 0.9, 0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.025
		cm.bottom_radius = 0.025
		cm.height = prev.distance_to(p)
		cm.radial_segments = 4
		cm.rings = 1
		mi.mesh = cm
		mi.material_override = mat
		var mid := (prev + p) * 0.5
		var y := (p - prev).normalized()
		var x := y.cross(Vector3.FORWARD).normalized()
		var z := x.cross(y)
		mi.transform = Transform3D(Basis(x, y, z), mid)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		prev = p

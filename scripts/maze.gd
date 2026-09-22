extends Node3D
## ひまわり迷路：迷路生成・ひまわり/草の MultiMesh 配置・当たり判定・見晴らし台・遠景。

const TILE := 2.6
const CELLS := 9
const G := CELLS * 2 + 1          # タイル数（壁込み）
const FIELD_MARGIN := 26.0        # 迷路の外に広がるひまわり畑の幅
const DECK_H := 1.9               # 見晴らし台の高さ
const RAMP_LEN := 7.0

@export var sun_dir := Vector3(0.12, 0.88, 0.46)

var wall := []                    # wall[x][z] : bool
var young := {}                   # 背の低いひまわり（向こうが見える）タイル
var start_tile := Vector2i(1, G - 2)
var entrance_tile := Vector2i(1, G - 1)
var goal_tile := Vector2i.ZERO
var path_tiles: Array[Vector2i] = []
var deck_center := Vector3.ZERO
var rng := RandomNumberGenerator.new()
## Web(WebGL2)版は密度を落として軽くする
var lite := OS.has_feature("web")

var plant_mat: ShaderMaterial
var grass_mat: ShaderMaterial


func build() -> void:
	rng.seed = 20260801
	_generate_maze()
	plant_mat = ShaderMaterial.new()
	plant_mat.shader = load("res://shaders/plant.gdshader")
	grass_mat = ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	var e := tile_to_world(entrance_tile)
	deck_center = Vector3(e.x, DECK_H, e.z + TILE * 0.5 + RAMP_LEN + 2.0)
	_build_ground()
	_build_sunflowers()
	_build_grass()
	_build_collision()
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


func _generate_maze() -> void:
	wall = []
	for x in G:
		var col := []
		for z in G:
			col.append(true)
		wall.append(col)
	# 穴掘り法
	var stack: Array[Vector2i] = [Vector2i(0, CELLS - 1)]
	var visited := {Vector2i(0, CELLS - 1): true}
	wall[1][G - 2] = false
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var c: Vector2i = stack.back()
		var opts: Array[Vector2i] = []
		for d in dirs:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < CELLS and n.y < CELLS and not visited.has(n):
				opts.append(n)
		if opts.is_empty():
			stack.pop_back()
			continue
		var n2: Vector2i = opts[rng.randi() % opts.size()]
		visited[n2] = true
		wall[n2.x * 2 + 1][n2.y * 2 + 1] = false
		wall[c.x + n2.x + 1][c.y + n2.y + 1] = false
		stack.append(n2)
	# ループを少し作って迷いすぎないように
	var opened := 0
	while opened < 7:
		var x := rng.randi_range(1, G - 2)
		var z := rng.randi_range(1, G - 2)
		if not wall[x][z]:
			continue
		if (x % 2 == 1 and z % 2 == 0 and not wall[x][z - 1] and not wall[x][z + 1]) or \
				(x % 2 == 0 and z % 2 == 1 and not wall[x - 1][z] and not wall[x + 1][z]):
			wall[x][z] = false
			opened += 1
	wall[entrance_tile.x][entrance_tile.y] = false
	# ゴール = 入口から遠いセル。周囲を広場にしても近道ができないものを選ぶ
	var dist := _bfs(start_tile)
	var cands: Array = []
	for k in dist.keys():
		if k.x % 2 == 1 and k.y % 2 == 1 and k.x >= 3 and k.y >= 3 and k.x <= G - 4 and k.y <= G - 4:
			cands.append(k)
	cands.sort_custom(func(a, b): return dist[a] > dist[b])
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
	print("maze goal=%s path_len=%d" % [goal_tile, path_tiles.size()])
	# 通路に面した壁の一部を「若いひまわり」にして、ときどき向こうが見えるように
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


# ---------------------------------------------------------------- ひまわりのメッシュ

func _v(st: SurfaceTool, p: Vector3, n: Vector3, c: Color, u: float) -> void:
	st.set_color(c)
	st.set_normal(n)
	st.set_uv(Vector2(u, 0.0))
	st.add_vertex(p)


func build_sunflower_mesh(detail: bool, H := 2.5) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = 7 if detail else 11
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_c := Color(0.36, 0.45, 0.07, 0.0)
	var segs := 8 if detail else 4
	var sides := 6 if detail else 4
	var stem_pt := func(t: float) -> Vector3: return Vector3(0.0, t * H, 0.10 * pow(t, 4.0))
	# 茎
	for i in segs:
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p0: Vector3 = stem_pt.call(t0)
		var p1: Vector3 = stem_pt.call(t1)
		var r0 := lerpf(0.034, 0.018, t0)
		var r1 := lerpf(0.034, 0.018, t1)
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var n0 := Vector3(cos(a0), 0, sin(a0))
			var n1 := Vector3(cos(a1), 0, sin(a1))
			_v(st, p0 + n0 * r0, n0, stem_c, 0.0)
			_v(st, p1 + n0 * r1, n0, stem_c, 0.0)
			_v(st, p1 + n1 * r1, n1, stem_c, 0.0)
			_v(st, p0 + n0 * r0, n0, stem_c, 0.0)
			_v(st, p1 + n1 * r1, n1, stem_c, 0.0)
			_v(st, p0 + n1 * r0, n1, stem_c, 0.0)
	# 葉（ハート形、付け根から上に出て垂れ下がる）
	var nl := 8 if detail else 4
	var lsteps := 6 if detail else 3
	for k in nl:
		var f := float(k) / (nl - 1)
		var h := lerpf(0.42, 0.86, f) * H
		var yaw := k * 2.4 + r.randf_range(-0.3, 0.3)
		var L := lerpf(0.46, 0.26, f) * r.randf_range(0.85, 1.15)
		var dir := Vector3(cos(yaw), 0, sin(yaw))
		var side := Vector3(-sin(yaw), 0, cos(yaw))
		var base: Vector3 = stem_pt.call(h / H) + dir * 0.02
		var lc := Color(0.16, 0.36, 0.04, 0.5).lerp(Color(0.36, 0.42, 0.06, 0.5), (1.0 - f) * 0.5 * r.randf())
		var up_n := (Vector3.UP * 1.0 + dir * 0.25).normalized()
		var prev := []
		for j in lsteps + 1:
			var t := float(j) / lsteps
			var c := base + dir * (0.05 + t * L) + Vector3.UP * (t * 0.28 * L - t * t * 0.62 * L)
			var w := L * 0.46 * sin(PI * pow(t, 0.7)) if j < lsteps else 0.0
			var le := c + side * w - Vector3.UP * w * 0.28
			var ri := c - side * w - Vector3.UP * w * 0.28
			var cur := [c, le, ri, t]
			if j > 0:
				var c0: Vector3 = prev[0]; var l0: Vector3 = prev[1]; var r0v: Vector3 = prev[2]; var u0: float = prev[3]
				var nL := (up_n + side * 0.35).normalized()
				var nR := (up_n - side * 0.35).normalized()
				_v(st, c0, up_n, lc, u0); _v(st, l0, nL, lc, u0); _v(st, c, up_n, lc, t)
				_v(st, l0, nL, lc, u0); _v(st, le, nL, lc, t); _v(st, c, up_n, lc, t)
				_v(st, c0, up_n, lc, u0); _v(st, c, up_n, lc, t); _v(st, r0v, nR, lc, u0)
				_v(st, r0v, nR, lc, u0); _v(st, c, up_n, lc, t); _v(st, ri, nR, lc, t)
			prev = cur
	# 花：太陽の方(+Z)へ、やや上向き
	var top: Vector3 = stem_pt.call(1.0)
	var n := Vector3(0, 0.38, 1).normalized()
	var rt := Vector3.RIGHT
	var up := n.cross(rt).normalized()
	rt = up.cross(n).normalized()
	var C := top + n * 0.03
	var Rd := 0.14
	var dseg := 16 if detail else 8
	# 花芯（ドーム）
	var rings := 3 if detail else 1
	for i in rings:
		var a0 := float(i) / rings
		var a1 := float(i + 1) / rings
		var col0 := Color(0.30, 0.22, 0.05, 0.0).lerp(Color(0.20, 0.10, 0.02, 0.0), a0)
		var col1 := Color(0.30, 0.22, 0.05, 0.0).lerp(Color(0.20, 0.10, 0.02, 0.0), a1)
		for s in dseg:
			var t0 := TAU * s / dseg
			var t1 := TAU * (s + 1) / dseg
			var d0 := rt * cos(t0) + up * sin(t0)
			var d1 := rt * cos(t1) + up * sin(t1)
			var q00 := C + d0 * Rd * a0 + n * 0.035 * (1.0 - a0 * a0)
			var q01 := C + d1 * Rd * a0 + n * 0.035 * (1.0 - a0 * a0)
			var q10 := C + d0 * Rd * a1 + n * 0.035 * (1.0 - a1 * a1)
			var q11 := C + d1 * Rd * a1 + n * 0.035 * (1.0 - a1 * a1)
			var nn0 := (n + d0 * a1 * 0.5).normalized()
			var nn1 := (n + d1 * a1 * 0.5).normalized()
			_v(st, q00, n, col0, 0.0); _v(st, q10, nn0, col1, 0.0); _v(st, q11, nn1, col1, 0.0)
			if i > 0:
				_v(st, q00, n, col0, 0.0); _v(st, q11, nn1, col1, 0.0); _v(st, q01, n, col0, 0.0)
	# がく（裏側）
	var back_c := Color(0.22, 0.40, 0.08, 0.0)
	var apex := C - n * 0.09
	for s in dseg:
		var t0 := TAU * s / dseg
		var t1 := TAU * (s + 1) / dseg
		var d0 := rt * cos(t0) + up * sin(t0)
		var d1 := rt * cos(t1) + up * sin(t1)
		_v(st, C + d0 * Rd * 1.08, (d0 * 0.5 - n).normalized(), back_c, 0.0)
		_v(st, apex, -n, back_c, 0.0)
		_v(st, C + d1 * Rd * 1.08, (d1 * 0.5 - n).normalized(), back_c, 0.0)
	# 花びら（二重）
	var layers := 2 if detail else 1
	var np := 20 if detail else 14
	for l in layers:
		for i in np:
			var a := (i + 0.5 * l) / np * TAU + r.randf_range(-0.06, 0.06)
			var d := rt * cos(a) + up * sin(a)
			var pp := n.cross(d).normalized()
			var plen := r.randf_range(0.11, 0.16)
			var w := r.randf_range(0.026, 0.034)
			var base := C + d * Rd * 0.85 - n * (0.01 + 0.012 * l)
			var mid := C + d * (Rd + plen * 0.45) - n * (0.012 + 0.014 * l)
			var tip := C + d * (Rd + plen) - n * (0.035 + 0.03 * l) + pp * r.randf_range(-0.01, 0.01)
			var pc := Color(0.98, 0.64, 0.0, 1.0).lerp(Color(0.95, 0.46, 0.0, 1.0), 0.35 * l + r.randf() * 0.25)
			var pn := (n + d * 0.15).normalized()
			_v(st, base, pn, pc, 0.0); _v(st, mid + pp * w, pn, pc, 0.0); _v(st, mid - pp * w, pn, pc, 0.0)
			_v(st, mid + pp * w, pn, pc, 0.0); _v(st, tip, pn, pc, 0.0); _v(st, mid - pp * w, pn, pc, 0.0)
	return st.commit()


# ---------------------------------------------------------------- 配置

func _make_mm(mesh: Mesh, xforms: Array, customs: Array, mat: Material, shadows: bool, name_: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	# Compatibilityレンダラーでは COLOR にインスタンス色が掛かるので白を明示する
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_custom_data(i, customs[i])
		mm.set_instance_color(i, Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = name_
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


func _flower_xform(pos: Vector3, s: float, face_sun: bool) -> Transform3D:
	var sh := Vector2(sun_dir.x, sun_dir.z).normalized()
	var yaw := atan2(sh.x, sh.y)
	if face_sun:
		yaw += rng.randf_range(-0.55, 0.55)
	else:
		yaw = rng.randf() * TAU
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(s * rng.randf_range(0.9, 1.1), s, s * rng.randf_range(0.9, 1.1)))
	# ほんの少し傾ける
	b = Basis(Vector3(1, 0, 0), rng.randf_range(-0.06, 0.06)) * b
	return Transform3D(b, pos)


func _build_sunflowers() -> void:
	var near_mesh := build_sunflower_mesh(true)
	var far_mesh := build_sunflower_mesh(false)
	var near_x := []
	var near_c := []
	var far_x := []
	var far_c := []
	var hm := maze_half()
	# 迷路の壁
	for x in G:
		for z in G:
			if not wall[x][z]:
				continue
			var t := Vector2i(x, z)
			var c := tile_to_world(t)
			var is_young := young.has(t)
			var n := 4 if not is_young else 3
			for i in n:
				for j in n:
					var p := c + Vector3((i + 0.5) / n - 0.5, 0, (j + 0.5) / n - 0.5) * (TILE - 0.35)
					p += Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
					var s := rng.randf_range(0.88, 1.22) if not is_young else rng.randf_range(0.5, 0.62)
					near_x.append(_flower_xform(p, s, rng.randf() < 0.9))
					near_c.append(Color(rng.randf(), rng.randf(), 0, 0))
	# 迷路の外の畑（見晴らし台から見える海）
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
			# 見晴らし台と坂道の場所は空ける
			if absf(p.x - e.x) < 3.2 and p.z > hm - 0.5 and p.z < deck_center.z + 3.5:
				continue
			# 外周は円形に（四角い縁を見せない）
			var rr := Vector2(p.x, p.z).length()
			if rr > outer - rng.randf() * 8.0:
				continue
			var s := rng.randf_range(0.85, 1.2)
			if Vector2(p.x, p.z).length() < hm + 8.0:
				near_x.append(_flower_xform(p, s, rng.randf() < 0.9))
				near_c.append(Color(rng.randf(), rng.randf(), 0, 0))
			else:
				far_x.append(_flower_xform(p, s, rng.randf() < 0.9))
				far_c.append(Color(rng.randf(), rng.randf(), 0, 0))
		gx += step
	_make_mm(near_mesh, near_x, near_c, plant_mat, true, "SunflowersNear")
	_make_mm(far_mesh, far_x, far_c, plant_mat, false, "SunflowersFar")
	print("sunflowers near=%d far=%d" % [near_x.size(), far_x.size()])


func build_grass_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for b in 7:
		var a := r.randf() * TAU
		var o := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.14)
		var face := r.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face))
		var lean := Vector3(-sin(face), 0, cos(face)) * r.randf_range(-0.12, 0.12) + Vector3(r.randf_range(-0.06, 0.06), 0, r.randf_range(-0.06, 0.06))
		var h := r.randf_range(0.28, 0.6)
		var w := r.randf_range(0.018, 0.03)
		var nrm := side.cross(Vector3.UP).normalized()
		var segs := 3
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			var p0 := o + Vector3.UP * h * t0 + lean * t0 * t0
			var p1 := o + Vector3.UP * h * t1 + lean * t1 * t1
			var w0 := w * (1.0 - t0)
			var w1 := w * (1.0 - t1)
			st.set_normal(nrm); st.set_uv(Vector2(0, t0)); st.add_vertex(p0 - side * w0)
			st.set_normal(nrm); st.set_uv(Vector2(0, t0)); st.add_vertex(p0 + side * w0)
			st.set_normal(nrm); st.set_uv(Vector2(0, t1)); st.add_vertex(p1 + side * w1)
			if s < segs - 1:
				st.set_normal(nrm); st.set_uv(Vector2(0, t0)); st.add_vertex(p0 - side * w0)
				st.set_normal(nrm); st.set_uv(Vector2(0, t1)); st.add_vertex(p1 + side * w1)
				st.set_normal(nrm); st.set_uv(Vector2(0, t1)); st.add_vertex(p1 - side * w1)
	return st.commit()


func _build_grass() -> void:
	var mesh := build_grass_mesh()
	var xs := []
	var cs := []
	var hm := maze_half()
	var ext := hm + 4.0
	var n := 0
	var gstep := 0.46 if lite else 0.36
	var x := -ext
	while x < ext:
		var z := -ext
		while z < ext + RAMP_LEN + 6.0:
			var p := Vector3(x + rng.randf_range(-0.2, 0.2), 0, z + rng.randf_range(-0.2, 0.2))
			z += gstep
			var inside := absf(p.x) < hm and absf(p.z) < hm
			if not inside and z > ext:
				# 見晴らし台周辺だけ
				var e := tile_to_world(entrance_tile)
				if absf(p.x - e.x) > 4.0:
					continue
			var keep := 1.0
			if inside and is_open(world_to_tile(p)):
				var d := path_center_dist(p)
				keep = smoothstep(0.25, 0.85, d) * 0.9 + 0.1
			elif inside:
				keep = 0.55
			if rng.randf() > keep:
				continue
			var s := rng.randf_range(0.7, 1.3) * (1.0 if keep > 0.5 else 0.75)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
			xs.append(Transform3D(b, p))
			cs.append(Color(rng.randf(), rng.randf(), 0, 0))
			n += 1
		x += gstep
	var mmi := _make_mm(mesh, xs, cs, grass_mat, false, "Grass")
	mmi.visibility_range_end = 70.0
	print("grass clumps=%d" % n)


func _build_ground() -> void:
	# 通路マスク（土の筋）
	var res := 8
	var img := Image.create(G * res, G * res, false, Image.FORMAT_R8)
	var hm := maze_half()
	for px in G * res:
		for pz in G * res:
			var p := Vector3(-hm + (px + 0.5) / res * TILE, 0, -hm + (pz + 0.5) / res * TILE)
			var v := 0.0
			if is_open(world_to_tile(p)):
				v = 1.0 - smoothstep(0.3, 0.95, path_center_dist(p))
			img.set_pixel(px, pz, Color(v, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	mat.set_shader_parameter("path_mask", tex)
	mat.set_shader_parameter("mask_rect", Vector4(-hm, -hm, hm * 2.0, hm * 2.0))
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
	# 坂道
	_box(deck, Vector3(2.0, 0.12, ramp_len), Vector3(e.x, DECK_H * 0.5 - 0.05, (ramp_start_z + ramp_end_z) * 0.5), wood, rot, true)
	# デッキ
	var dz := deck_center.z
	_box(deck, Vector3(4.0, 0.16, 4.0), Vector3(e.x, DECK_H - 0.08, dz), wood, Basis(), true)
	# 柱
	for sx in [-1.8, 1.8]:
		for sz in [-1.8, 1.8]:
			_box(deck, Vector3(0.14, DECK_H, 0.14), Vector3(e.x + sx, DECK_H * 0.5, dz + sz), wood)
	# 手すり（見た目＋当たり）
	var rail_h := 1.0
	for sx in [-2.0, 2.0]:
		_box(deck, Vector3(0.06, 0.06, 4.0), Vector3(e.x + sx, DECK_H + rail_h, dz), wood)
		_box(deck, Vector3(0.1, 2.0, 4.0), Vector3(e.x + sx, DECK_H + 1.0, dz), null, Basis(), true)
		for k in 5:
			_box(deck, Vector3(0.06, rail_h, 0.06), Vector3(e.x + sx, DECK_H + rail_h * 0.5, dz - 2.0 + k), wood)
	_box(deck, Vector3(4.0, 0.06, 0.06), Vector3(e.x, DECK_H + rail_h, dz + 2.0), wood)
	_box(deck, Vector3(4.0, 2.0, 0.1), Vector3(e.x, DECK_H + 1.0, dz + 2.0), null, Basis(), true)
	# 坂道の両脇の見えない壁
	for sx in [-1.1, 1.1]:
		_box(deck, Vector3(0.1, 4.0, RAMP_LEN + 0.5), Vector3(e.x + sx, 2.0, (ramp_start_z + ramp_end_z) * 0.5), null, Basis(), true)
		_box(deck, Vector3(0.05, 0.05, ramp_len), Vector3(e.x + sx * 0.95, DECK_H * 0.5 + 0.9, (ramp_start_z + ramp_end_z) * 0.5), wood, rot)
	# デッキ側面を埋める（坂の横から落ちないよう）
	for sx in [-1.0, 1.0]:
		_box(deck, Vector3(1.0, 4.0, 0.1), Vector3(e.x + sx * 1.5, 2.0, dz - 2.0), null, Basis(), true)
	# 見えない当たり判定は描画しない
	for c in deck.get_children():
		if c is MeshInstance3D and c.material_override == null:
			c.visible = false


# ---------------------------------------------------------------- 遠景（木立・山・電柱）

func _build_distance() -> void:
	var far := Node3D.new()
	far.name = "Distance"
	add_child(far)
	# 木立：球の集まり
	var sphere := SphereMesh.new()
	sphere.radial_segments = 12
	sphere.rings = 6
	var tree_mat := StandardMaterial3D.new()
	tree_mat.albedo_color = Color(0.13, 0.26, 0.08)
	tree_mat.roughness = 1.0
	var xs := []
	for i in 220:
		var a := rng.randf() * TAU
		# 南側（見晴らし台の背後）は薄く
		var d := rng.randf_range(150.0, 260.0)
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
	# 山並み
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
		for v in [p0, t0, t1, p0, t1, p1]:
			st.set_normal(nn)
			st.add_vertex(v)
	var hills := MeshInstance3D.new()
	hills.name = "Hills"
	hills.mesh = st.commit()
	var hill_mat := StandardMaterial3D.new()
	hill_mat.albedo_color = Color(0.18, 0.32, 0.16)
	hill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	hills.material_override = hill_mat
	hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.add_child(hills)
	# 電柱と電線（北側の農道沿い）
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

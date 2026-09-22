class_name Props
## 迷路の壁や小物のメッシュを SurfaceTool で組み立てる（頂点カラーで塗り分け）。


static func v(st: SurfaceTool, p: Vector3, n: Vector3, c: Color, u := 0.0, uv_y := 0.0) -> void:
	st.set_color(c)
	st.set_normal(n)
	st.set_uv(Vector2(u, uv_y))
	st.add_vertex(p)


## 直方体（中心・大きさ・回転）
static func box(st: SurfaceTool, center: Vector3, size: Vector3, c: Color, b := Basis()) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
		[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)],
		[Vector3(0, -1, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var a: Vector3 = f[1]
		var bb: Vector3 = f[2]
		var o := n * h
		var ea := a * (h * a).length()
		var eb := bb * (h * bb).length()
		var p00 := b * (o - ea - eb) + center
		var p10 := b * (o + ea - eb) + center
		var p11 := b * (o + ea + eb) + center
		var p01 := b * (o - ea + eb) + center
		var wn := (b * n).normalized()
		v(st, p00, wn, c); v(st, p10, wn, c); v(st, p11, wn, c)
		v(st, p00, wn, c); v(st, p11, wn, c); v(st, p01, wn, c)


## 円錐台（軸はY）
static func frustum(st: SurfaceTool, base: Vector3, h: float, r0: float, r1: float, c: Color, sides := 10) -> void:
	for s in sides:
		var a0 := TAU * s / sides
		var a1 := TAU * (s + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var slope := (r0 - r1) / h
		var n0 := (d0 + Vector3.UP * slope).normalized()
		var n1 := (d1 + Vector3.UP * slope).normalized()
		var top := base + Vector3.UP * h
		v(st, base + d0 * r0, n0, c); v(st, top + d0 * r1, n0, c); v(st, top + d1 * r1, n1, c)
		v(st, base + d0 * r0, n0, c); v(st, top + d1 * r1, n1, c); v(st, base + d1 * r0, n1, c)
	if r1 > 0.001:
		for s in sides:
			var a0 := TAU * s / sides
			var a1 := TAU * (s + 1) / sides
			var top := base + Vector3.UP * h
			v(st, top, Vector3.UP, c); v(st, top + Vector3(cos(a1), 0, sin(a1)) * r1, Vector3.UP, c); v(st, top + Vector3(cos(a0), 0, sin(a0)) * r1, Vector3.UP, c)


static func sphere(st: SurfaceTool, center: Vector3, r: Vector3, c: Color, seg := 10, rings := 6) -> void:
	for i in rings:
		var t0 := PI * i / rings
		var t1 := PI * (i + 1) / rings
		for s in seg:
			var a0 := TAU * s / seg
			var a1 := TAU * (s + 1) / seg
			var q := [
				Vector3(sin(t0) * cos(a0), cos(t0), sin(t0) * sin(a0)),
				Vector3(sin(t1) * cos(a0), cos(t1), sin(t1) * sin(a0)),
				Vector3(sin(t1) * cos(a1), cos(t1), sin(t1) * sin(a1)),
				Vector3(sin(t0) * cos(a1), cos(t0), sin(t0) * sin(a1)),
			]
			for k in [0, 1, 2, 0, 2, 3]:
				var d: Vector3 = q[k]
				v(st, center + d * r, (d / r).normalized(), c)


# ---------------------------------------------------------------- ひまわり
## droop: 花がうなだれる（夏の終わり） / fade: 色が抜ける
static func sunflower(detail: bool, droop := false, fade := false, H := 2.5) -> ArrayMesh:
	var r := RandomNumberGenerator.new()
	r.seed = (7 if detail else 11) + (100 if droop else 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_c := Color(0.36, 0.45, 0.07, 0.0) if not fade else Color(0.5, 0.44, 0.18, 0.0)
	var segs := 8 if detail else 4
	var sides := 6 if detail else 4
	var nod := 0.10 if not droop else 0.26
	var stem_pt := func(t: float) -> Vector3: return Vector3(0.0, t * H - (0.12 * pow(t, 6.0) if droop else 0.0), nod * pow(t, 4.0))
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
			v(st, p0 + n0 * r0, n0, stem_c); v(st, p1 + n0 * r1, n0, stem_c); v(st, p1 + n1 * r1, n1, stem_c)
			v(st, p0 + n0 * r0, n0, stem_c); v(st, p1 + n1 * r1, n1, stem_c); v(st, p0 + n1 * r0, n1, stem_c)
	# 葉
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
		var droop_leaf := 0.62
		if fade:
			lc = Color(0.5, 0.48, 0.2, 0.5).lerp(Color(0.62, 0.5, 0.24, 0.5), r.randf())
			droop_leaf = 1.1
		var up_n := (Vector3.UP * 1.0 + dir * 0.25).normalized()
		var prev := []
		for j in lsteps + 1:
			var t := float(j) / lsteps
			var c := base + dir * (0.05 + t * L) + Vector3.UP * (t * 0.28 * L - t * t * droop_leaf * L)
			var w := L * 0.46 * sin(PI * pow(t, 0.7)) if j < lsteps else 0.0
			var le := c + side * w - Vector3.UP * w * 0.28
			var ri := c - side * w - Vector3.UP * w * 0.28
			if j > 0:
				var c0: Vector3 = prev[0]; var l0: Vector3 = prev[1]; var r0v: Vector3 = prev[2]; var u0: float = prev[3]
				var nL := (up_n + side * 0.35).normalized()
				var nR := (up_n - side * 0.35).normalized()
				v(st, c0, up_n, lc, u0); v(st, l0, nL, lc, u0); v(st, c, up_n, lc, t)
				v(st, l0, nL, lc, u0); v(st, le, nL, lc, t); v(st, c, up_n, lc, t)
				v(st, c0, up_n, lc, u0); v(st, c, up_n, lc, t); v(st, r0v, nR, lc, u0)
				v(st, r0v, nR, lc, u0); v(st, c, up_n, lc, t); v(st, ri, nR, lc, t)
			prev = [c, le, ri, t]
	# 花
	var top: Vector3 = stem_pt.call(1.0)
	var n := Vector3(0, 0.38, 1).normalized() if not droop else Vector3(0, -0.85, 0.52).normalized()
	var rt := Vector3.RIGHT
	var up := n.cross(rt).normalized()
	rt = up.cross(n).normalized()
	var C := top + n * 0.03
	var Rd := 0.14
	var dseg := 16 if detail else 8
	var disc_a := Color(0.30, 0.22, 0.05, 0.0) if not fade else Color(0.26, 0.2, 0.1, 0.0)
	var disc_b := Color(0.20, 0.10, 0.02, 0.0) if not fade else Color(0.18, 0.12, 0.06, 0.0)
	var rings := 3 if detail else 1
	for i in rings:
		var a0 := float(i) / rings
		var a1 := float(i + 1) / rings
		var col0 := disc_a.lerp(disc_b, a0)
		var col1 := disc_a.lerp(disc_b, a1)
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
			v(st, q00, n, col0); v(st, q10, nn0, col1); v(st, q11, nn1, col1)
			if i > 0:
				v(st, q00, n, col0); v(st, q11, nn1, col1); v(st, q01, n, col0)
	var back_c := Color(0.22, 0.40, 0.08, 0.0) if not fade else Color(0.45, 0.42, 0.2, 0.0)
	var apex := C - n * 0.09
	for s in dseg:
		var t0 := TAU * s / dseg
		var t1 := TAU * (s + 1) / dseg
		var d0 := rt * cos(t0) + up * sin(t0)
		var d1 := rt * cos(t1) + up * sin(t1)
		v(st, C + d0 * Rd * 1.08, (d0 * 0.5 - n).normalized(), back_c)
		v(st, apex, -n, back_c)
		v(st, C + d1 * Rd * 1.08, (d1 * 0.5 - n).normalized(), back_c)
	var layers := 2 if detail else 1
	var np := 20 if detail else 14
	for l in layers:
		for i in np:
			# 夏の終わりは花びらが抜け落ちている
			if fade and r.randf() < 0.45:
				continue
			var a := (i + 0.5 * l) / np * TAU + r.randf_range(-0.06, 0.06)
			var d := rt * cos(a) + up * sin(a)
			var pp := n.cross(d).normalized()
			var plen := r.randf_range(0.11, 0.16) * (0.8 if fade else 1.0)
			var w := r.randf_range(0.026, 0.034)
			var curl := 1.0 if not fade else 2.2
			var base := C + d * Rd * 0.85 - n * (0.01 + 0.012 * l)
			var mid := C + d * (Rd + plen * 0.45) - n * (0.012 + 0.014 * l) * curl
			var tip := C + d * (Rd + plen) - n * (0.035 + 0.03 * l) * curl + pp * r.randf_range(-0.01, 0.01)
			var pc := Color(0.98, 0.64, 0.0, 1.0).lerp(Color(0.95, 0.46, 0.0, 1.0), 0.35 * l + r.randf() * 0.25)
			if fade:
				pc = Color(0.86, 0.66, 0.26, 1.0).lerp(Color(0.66, 0.46, 0.2, 1.0), r.randf())
			var pn := (n + d * 0.15).normalized()
			v(st, base, pn, pc); v(st, mid + pp * w, pn, pc); v(st, mid - pp * w, pn, pc)
			v(st, mid + pp * w, pn, pc); v(st, tip, pn, pc); v(st, mid - pp * w, pn, pc)
	return st.commit()


# ---------------------------------------------------------------- 草
## blades 本の草の株。tall=true で背丈より高い夏草。UV.y = 根元0〜先端1
static func grass_clump(tall: bool, seed_ := 3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	var blades := 7 if not tall else 18
	for b in blades:
		var a := r.randf() * TAU
		var o := Vector3(cos(a), 0, sin(a)) * r.randf_range(0.0, 0.14 if not tall else 0.45)
		var face := r.randf() * TAU
		var side := Vector3(cos(face), 0, sin(face))
		var bend := Vector3(-sin(face), 0, cos(face))
		var h := r.randf_range(0.28, 0.6) if not tall else r.randf_range(1.5, 3.0)
		var lean := bend * r.randf_range(-0.12, 0.12) * (1.0 if not tall else 5.0) + Vector3(r.randf_range(-0.06, 0.06), 0, r.randf_range(-0.06, 0.06))
		var w := r.randf_range(0.018, 0.03) if not tall else r.randf_range(0.03, 0.06)
		var nrm := side.cross(Vector3.UP).normalized()
		var segs := 3 if not tall else 5
		for s in segs:
			var t0 := float(s) / segs
			var t1 := float(s + 1) / segs
			var p0 := o + Vector3.UP * h * t0 + lean * t0 * t0
			var p1 := o + Vector3.UP * h * t1 + lean * t1 * t1
			var w0 := w * (1.0 - t0 * 0.9)
			var w1 := w * (1.0 - t1 * 0.9) if s < segs - 1 else 0.0
			st.set_normal(nrm); st.set_uv(Vector2(0, t0)); st.add_vertex(p0 - side * w0)
			st.set_normal(nrm); st.set_uv(Vector2(0, t0)); st.add_vertex(p0 + side * w0)
			st.set_normal(nrm); st.set_uv(Vector2(0, t1)); st.add_vertex(p1 + side * w1)
			if s < segs - 1:
				st.set_normal(nrm); st.set_uv(Vector2(0, t0)); st.add_vertex(p0 - side * w0)
				st.set_normal(nrm); st.set_uv(Vector2(0, t1)); st.add_vertex(p1 + side * w1)
				st.set_normal(nrm); st.set_uv(Vector2(0, t1)); st.add_vertex(p1 - side * w1)
		# エノコログサの穂
		if tall and r.randf() < 0.3:
			var tip := o + Vector3.UP * h + lean
			var hd := bend * 0.18 + Vector3.DOWN * 0.08
			for k in 4:
				var ang := TAU * k / 4.0
				var off := Vector3(cos(ang), 0, sin(ang)) * 0.025
				st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 1)); st.add_vertex(tip + off)
				st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 1)); st.add_vertex(tip + hd)
				st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 1)); st.add_vertex(tip + hd * 0.4 - off)
	return st.commit()


# ---------------------------------------------------------------- 夏祭り
## 屋台。正面(カウンター側)は -Z。roof に屋根の色
static func stall(roof: Color, goods: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.42, 0.3, 0.2)
	var white := Color(0.94, 0.93, 0.9)
	box(st, Vector3(0, 0.45, -0.45), Vector3(2.1, 0.9, 0.5), white)          # カウンター
	box(st, Vector3(0, 0.93, -0.45), Vector3(2.2, 0.06, 0.62), wood)
	box(st, Vector3(0, 0.75, 0.6), Vector3(2.1, 1.5, 0.25), Color(0.25, 0.2, 0.17))  # 奥の棚
	for sx in [-1.05, 1.05]:
		for sz in [-0.72, 0.72]:
			box(st, Vector3(sx, 1.2, sz), Vector3(0.07, 2.4, 0.07), wood)
	# 紅白（または色×白）の縞の屋根
	var strips := 7
	var rot := Basis(Vector3.RIGHT, deg_to_rad(-14))
	for i in strips:
		var x := -1.2 + (i + 0.5) * 2.4 / strips
		box(st, Vector3(x, 2.45, 0.0), Vector3(2.4 / strips + 0.005, 0.05, 1.9), roof if i % 2 == 0 else white, rot)
	# のれん・看板
	box(st, Vector3(0, 2.12, -0.95), Vector3(2.3, 0.34, 0.03), roof)
	box(st, Vector3(0, 2.62, -1.0), Vector3(1.3, 0.34, 0.05), Color(1.0, 0.92, 0.6))
	# 商品
	for i in 5:
		box(st, Vector3(-0.8 + i * 0.4, 1.02, -0.45), Vector3(0.26, 0.14, 0.26), goods.lerp(Color(1, 1, 1), (i % 2) * 0.3))
	return st.commit()


## 浴衣の人。tint=true の部分はインスタンス色（浴衣の柄色）で塗る
static func person(tint: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if tint:
		frustum(st, Vector3(0, 0.08, 0), 1.2, 0.21, 0.15, Color.WHITE, 12)       # 浴衣
		for sx in [-0.19, 0.19]:
			frustum(st, Vector3(sx, 0.75, 0), 0.5, 0.06, 0.07, Color.WHITE, 6)   # 袖
	else:
		frustum(st, Vector3(0, 0.78, 0), 0.16, 0.18, 0.175, Color(0.95, 0.8, 0.35), 12)  # 帯
		sphere(st, Vector3(0, 1.43, 0), Vector3(0.105, 0.12, 0.105), Color(0.93, 0.78, 0.66))
		sphere(st, Vector3(0, 1.47, 0.02), Vector3(0.115, 0.11, 0.115), Color(0.08, 0.06, 0.05))
		frustum(st, Vector3(0, 1.28, 0), 0.08, 0.04, 0.045, Color(0.93, 0.78, 0.66), 6)
		for sx in [-0.08, 0.08]:
			box(st, Vector3(sx, 0.04, 0), Vector3(0.09, 0.08, 0.2), Color(0.35, 0.25, 0.18))  # 下駄
	return st.commit()

extends Node3D
## 夏迷路（Godot版）: タイトル → 5ステージ → 「夏が終わった。」 → タイトル。
##
## テスト用の引数:
##   -- --stage=N                 タイトルを飛ばしてステージNから
##   -- --shots=<dir> --pose=...  撮影モード（x,y,z,yaw,pitch;... / y<-50 で「君」の後ろ）
##   -- --autowalk [--fast]       正解ルートを自動で歩き、エンディングまで確認

@onready var sun: DirectionalLight3D = $Sun
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var maze: Node3D = $Maze
@onready var player: CharacterBody3D = $Player
@onready var kimi: Node3D = $Kimi
@onready var clouds: Node3D = $Sky
@onready var pollen: GPUParticles3D = $Player/Pollen
@onready var cicada_bed: AudioStreamPlayer = $CicadaBed

var stages: Array = Stages.all()
var stage := 0
var cfg: Dictionary = {}
var state := "title"
var rng := RandomNumberGenerator.new()
var web := OS.has_feature("web")
var env: Environment
var sky_mat: ShaderMaterial
var haze_mat: ShaderMaterial
var t_title := 0.0

# 画面
var overlay: ColorRect
var flash_rect: ColorRect
var title_box: VBoxContainer
var start_btn: Button
var end_label: Label
var pause_label: Label
var hint: Label

# 音
var amb := {}                 # name -> AudioStreamPlayer
var amb_gain := {"cicada": 0.5, "wind": 0.55, "festival": 0.5, "crowd": 0.5, "rain": 0.65}
var amb_level := {}
var cicadas3d: Array[AudioStreamPlayer3D] = []
var step_player: AudioStreamPlayer
var sfx := {}
var bird_t := 8.0
var insect_t := 3.0
var higurashi_t := 6.0

# 天気（夕立）
var rain: GPUParticles3D
var rain_t := 0.0
var thunder_t := 6.0
var flash_v := 0.0
var lull := false
var amb_base := 1.0

# 最終ステージ
var petals: GPUParticles3D
var fin_phase := 0
var fin_t := 0.0
var fin_spot := Vector3.ZERO
var fin_wait := 0.0
var fin_from := Vector3.ZERO
var solo: AudioStreamPlayer3D

# テスト
var shot_dir := ""
var poses: Array = []
var autowalk := false
var walk_i := 0
var walk_total := 0.0


func _ready() -> void:
	rng.randomize()
	env = world_env.environment
	sky_mat = env.sky.sky_material
	_setup_audio()
	_setup_particles()
	_setup_heat_haze()
	_setup_ui()
	player.stepped.connect(_on_step)
	kimi.found.connect(_on_found)
	var args := OS.get_cmdline_user_args()
	var start_stage := -1
	for a in args:
		if a.begins_with("--stage="):
			start_stage = int(a.substr(8))
		elif a.begins_with("--shots="):
			shot_dir = a.substr(8)
		elif a == "--autowalk":
			autowalk = true
		elif a == "--fast":
			Engine.time_scale = 3.0
		elif a.begins_with("--pose="):
			for p in a.substr(7).split(";"):
				if p == "start":
					poses.append(null)
					continue
				if p == "fin" or p == "behind" or p == "follow" or p.begins_with("look:"):
					poses.append(p)
					continue
				var v := p.split(",")
				if v.size() >= 5:
					poses.append([Vector3(float(v[0]), float(v[1]), float(v[2])), deg_to_rad(float(v[3])), deg_to_rad(float(v[4]))])
	if "--title" in args and shot_dir != "":
		_enter_title()
		overlay.color.a = 0.0
		_run_shots()
	elif start_stage >= 0 or autowalk or shot_dir != "":
		title_box.visible = false
		overlay.color.a = 0.0
		_load_stage(maxi(start_stage, 0))
		state = "finale" if cfg.get("finale", false) else "play"
		player.locked = false
		if shot_dir != "":
			hint.visible = false
			_run_shots()
	else:
		_enter_title()


# ================================================================ ステージ

func _load_stage(i: int) -> void:
	stage = i
	cfg = stages[i]
	maze.build(cfg)
	_apply_look(cfg)
	kimi.setup(maze, player, cfg)
	player.eye = cfg.eye
	_place_player()
	rain.emitting = cfg.get("rain", false)
	rain_t = 0.0
	thunder_t = rng.randf_range(4.0, 8.0)
	fin_phase = 0
	fin_t = 0.0
	walk_i = 0
	_set_amb(cfg.amb, 2.5)


func _place_player() -> void:
	player.velocity = Vector3.ZERO
	if maze.has_deck:
		var dc: Vector3 = maze.deck_center
		player.global_position = Vector3(dc.x, dc.y + 0.05, dc.z + 1.0)
		player.set_look(0.0, 0.05)
	else:
		var st: Vector2i = maze.start_tile
		player.global_position = maze.tile_to_world(st) + Vector3(0, 0.05, 0)
		var nxt: Vector2i = maze.path_tiles[1] if maze.path_tiles.size() > 1 else st
		var d: Vector3 = maze.tile_to_world(nxt) - maze.tile_to_world(st)
		player.set_look(atan2(-d.x, -d.z), 0.0)


## 空・光・フォグ・色調をステージに合わせる
func _apply_look(c: Dictionary) -> void:
	var sd: Vector3 = (c.sun_dir as Vector3).normalized()
	sun.look_at_from_position(Vector3.ZERO, -sd, Vector3.UP if absf(sd.y) < 0.99 else Vector3.FORWARD)
	sun.light_energy = c.sun_energy
	sun.light_color = c.sun_color
	sun.shadow_enabled = c.sun_energy > 0.5
	var sk: Dictionary = c.sky
	sky_mat.set_shader_parameter("zenith_color", sk.zenith)
	sky_mat.set_shader_parameter("mid_color", sk.mid)
	sky_mat.set_shader_parameter("horizon_color", sk.horizon)
	sky_mat.set_shader_parameter("energy", sk.energy)
	sky_mat.set_shader_parameter("overcast", sk.overcast)
	sky_mat.set_shader_parameter("cirrus", sk.cirrus)
	sky_mat.set_shader_parameter("cloud_tint", Color(1.0, 0.7, 0.55) if c.style == "festival" else Color(1, 1, 1))
	sky_mat.set_shader_parameter("flash", 0.0)
	env.fog_density = c.fog * (0.55 if web else 1.0)
	env.fog_light_color = c.fog_color
	env.volumetric_fog_density = c.vol_fog
	env.ambient_light_energy = c.ambient
	env.tonemap_exposure = c.exposure
	env.adjustment_saturation = c.saturation
	env.adjustment_contrast = c.contrast
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssr_enabled = c.style == "town"
	else:
		# Compatibility(WebGL2)は間接光が無いぶん暗いので、夕方・雨のステージを持ち上げる
		if c.style in ["festival", "town"]:
			var boost: float = {"festival": 1.3, "town": 1.3}.get(c.style, 1.0)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_sky_contribution = 0.0
			env.ambient_light_color = (sk.horizon as Color).lerp(sk.mid, 0.5) * float(sk.energy)
			if c.style == "town":
				env.ambient_light_color = Color(0.46, 0.51, 0.58)
			env.ambient_light_energy = c.ambient * boost
		else:
			env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
			env.ambient_light_sky_contribution = 1.0
			env.ambient_light_energy = c.ambient
		env.tonemap_exposure = c.exposure * (1.25 if c.style == "town" else 1.0)
	amb_base = env.ambient_light_energy
	clouds.sun_dir = sd
	clouds.build(c.clouds)
	var hazy: bool = c.style in ["sunflower", "grass"] and not c.get("fade", false)
	haze_mat.set_shader_parameter("strength", 0.0016 if hazy else 0.0)
	player.get_node("Camera/HeatHaze").visible = hazy
	pollen.emitting = c.style in ["sunflower", "grass"]
	pollen.amount_ratio = 0.5 if c.get("fade", false) else 1.0


# ================================================================ 音

func _mk_player(stream: AudioStream, loop := false) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.stream = stream
	a.volume_db = -80.0
	add_child(a)
	if loop:
		a.play()
	return a


func _wav_loop(path: String) -> AudioStream:
	var s: AudioStreamWAV = load(path)
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _setup_audio() -> void:
	var cicada: AudioStreamMP3 = load("res://audio/cicada.mp3")
	cicada.loop = true
	cicada_bed.stream = cicada
	cicada_bed.volume_db = -80.0
	cicada_bed.play()
	amb["cicada"] = cicada_bed
	var fest: AudioStreamMP3 = load("res://audio/festival.mp3")
	fest.loop = true
	amb["festival"] = _mk_player(fest, true)
	amb["crowd"] = _mk_player(_wav_loop("res://audio/synth/crowd_loop.wav"), true)
	amb["wind"] = _mk_player(_wav_loop("res://audio/synth/wind_loop.wav"), true)
	amb["rain"] = _mk_player(_wav_loop("res://audio/synth/rain_loop.wav"), true)
	for k in amb.keys():
		amb_level[k] = 0.0
	# 畑のあちこちで鳴く蝉（3D）
	for i in 5:
		var a := AudioStreamPlayer3D.new()
		a.stream = cicada
		a.unit_size = 14.0
		a.max_db = 0.0
		a.volume_db = -80.0
		a.pitch_scale = rng.randf_range(0.93, 1.08)
		add_child(a)
		a.play(rng.randf_range(0.0, cicada.get_length() - 1.0))
		cicadas3d.append(a)
	var angs := [0.3, 1.6, 2.7, 3.9, 5.1]
	for i in 5:
		cicadas3d[i].position = Vector3(cos(angs[i]), 0.12, sin(angs[i])) * 30.0
	for n in ["thunder_near", "thunder_far", "step_dirt", "step_grass", "step_wet", "bird", "insect", "higurashi", "gust", "cicada_solo"]:
		sfx[n] = load("res://audio/synth/%s.wav" % n)
	step_player = AudioStreamPlayer.new()
	step_player.volume_db = -14.0
	player.add_child(step_player)
	solo = AudioStreamPlayer3D.new()
	solo.stream = _wav_loop("res://audio/synth/cicada_solo.wav")
	solo.unit_size = 30.0
	solo.volume_db = -80.0
	add_child(solo)


## 環境音レイヤーを目標の大きさへ（0..1）
func _set_amb(levels: Dictionary, time: float) -> void:
	for k in amb.keys():
		var target: float = levels.get(k, 0.0)
		amb_level[k] = target
		var db := linear_to_db(maxf(target * amb_gain[k], 0.0001))
		var tw := create_tween()
		tw.tween_property(amb[k], "volume_db", db, time)
	var c: float = levels.get("cicada", 0.0)
	for a in cicadas3d:
		var tw := create_tween()
		tw.tween_property(a, "volume_db", linear_to_db(maxf(c * 0.9, 0.0001)), time)


func _oneshot(stream: AudioStream, db := 0.0, pitch := 1.0) -> void:
	var a := AudioStreamPlayer.new()
	a.stream = stream
	a.volume_db = db
	a.pitch_scale = pitch
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


func _oneshot3d(stream: AudioStream, pos: Vector3, db := 0.0, unit := 8.0, cutoff := 9000.0, pitch := 1.0) -> void:
	var a := AudioStreamPlayer3D.new()
	a.stream = stream
	a.position = pos
	a.volume_db = db
	a.unit_size = unit
	a.max_db = 6.0
	a.attenuation_filter_cutoff_hz = cutoff
	a.pitch_scale = pitch
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)


func _around(rmin: float, rmax: float, h := 3.0) -> Vector3:
	var a := rng.randf() * TAU
	return player.global_position + Vector3(cos(a), 0, sin(a)) * rng.randf_range(rmin, rmax) + Vector3(0, h, 0)


func _on_step(running: bool) -> void:
	if state == "title" or cfg.is_empty():
		return
	var kind: String = cfg.get("step", "dirt")
	step_player.stream = sfx["step_" + kind]
	step_player.pitch_scale = rng.randf_range(0.85, 1.15)
	step_player.volume_db = (-12.0 if running else -15.0) + (-3.0 if kind == "grass" else 0.0)
	step_player.play()
	if cfg.style in ["sunflower", "grass"] and kind != "grass" and rng.randf() < 0.5:
		_oneshot(sfx["step_grass"], -24.0, rng.randf_range(0.9, 1.2))


func _ambient_events(delta: float) -> void:
	if cfg.get("birds", false):
		bird_t -= delta
		if bird_t <= 0.0:
			bird_t = rng.randf_range(9.0, 22.0)
			_oneshot3d(sfx.bird, _around(25, 65, 8), -8.0, 20.0, 8000.0, rng.randf_range(0.9, 1.15))
	if cfg.get("insects", false) and fin_phase < 2:
		insect_t -= delta
		if insect_t <= 0.0:
			insect_t = rng.randf_range(1.6, 5.0)
			_oneshot3d(sfx.insect, _around(6, 24, 0.3), -14.0, 6.0, 9000.0, rng.randf_range(0.85, 1.2))


# ================================================================ 天気（夕立）

func _weather(delta: float) -> void:
	# 16秒周期で雨が弱まる（11〜15秒）。君の声が聞こえるのはその間だけ
	rain_t += delta
	var ph := fmod(rain_t, 16.0)
	var now_lull := ph > 11.0 and ph < 15.0
	if now_lull != lull:
		lull = now_lull
		kimi.laugh_allowed = lull
		var tw := create_tween()
		tw.tween_property(amb.rain, "volume_db", linear_to_db(amb_gain.rain * (0.28 if lull else 1.0)), 1.2)
		rain.amount_ratio = 0.35 if lull else 1.0
		if lull and kimi.visible and not kimi.done:
			get_tree().create_timer(rng.randf_range(0.9, 1.8)).timeout.connect(func():
				if state == "play" and stage == 3:
					kimi.play_laugh())
	thunder_t -= delta
	if thunder_t <= 0.0:
		thunder_t = rng.randf_range(9.0, 19.0)
		if rng.randf() < 0.55:
			_oneshot(sfx.thunder_far, -6.0, rng.randf_range(0.85, 1.05))
		else:
			flash_v = 1.0
			get_tree().create_timer(rng.randf_range(0.15, 0.6)).timeout.connect(func(): _oneshot(sfx.thunder_near, 0.0, rng.randf_range(0.9, 1.05)))
	if flash_v > 0.0:
		flash_v = maxf(flash_v - delta * 3.2, 0.0)
		var f := flash_v * flash_v
		flash_rect.color.a = f * 0.55
		sky_mat.set_shader_parameter("flash", f * 1.5)
		env.ambient_light_energy = amb_base * (1.0 + f * 2.4)


# ================================================================ 最終ステージ

func _finale(delta: float) -> void:
	fin_t += delta
	var ptile: Vector2i = maze.world_to_tile(player.global_position)
	match fin_phase:
		0:
			# 静かな畑。遠くでヒグラシ
			higurashi_t -= delta
			if higurashi_t <= 0.0:
				higurashi_t = rng.randf_range(20.0, 38.0)
				_oneshot3d(sfx.higurashi, _around(40, 70, 6), -10.0, 25.0)
			var near_exit := ptile.distance_to(maze.goal_tile) < 3.0
			if fin_t > 16.0 or near_exit:
				var pp: Array = maze.find_path(ptile, maze.goal_tile)
				if pp.size() < 3:
					pp = maze.find_path(maze.start_tile, maze.goal_tile)
				var k := mini(6, pp.size() - 2)
				kimi.visible = true
				kimi.place_tile(pp[k], pp[k + 1])
				kimi.run_tiles(pp.slice(k + 1, mini(k + 3, pp.size())), 1.2)
				kimi.play_laugh(0)
				fin_phase = 1
				fin_t = 0.0
		1:
			if player.global_position.distance_to(kimi.global_position) < 5.2 or fin_t > 18.0:
				# 笑って、見通しのよいまっすぐな通路の先まで駆けていく
				kimi.play_laugh(0, 1.0)
				fin_from = kimi.global_position
				kimi.run_tiles(_straight_run(maze.world_to_tile(kimi.global_position)), 3.6)
				fin_phase = 2
				fin_t = 0.0
				fin_wait = 0.0
		2:
			if not kimi.vanishing:
				if kimi.route_done():
					fin_wait += delta
					# 立ち止まった君がプレイヤーから見えた瞬間に消える
					# （角の先で待っていても、曲がって目に入ったところで消える）
					var d := player.global_position.distance_to(kimi.global_position)
					if (kimi.has_los() and d < 20.0 and fin_wait > 0.5) or d < 4.0 or fin_wait > 30.0:
						kimi.vanish(Vector3(0.85, 0, 0.52))
						_oneshot3d(sfx.gust, kimi.global_position + Vector3(0, 1.5, 0), -8.0, 6.0)
						fin_spot = kimi.hat_rest
						fin_t = 0.0
			elif player.global_position.distance_to(fin_spot) < 2.2 or fin_t > 14.0:
				# 帽子のところまで来ても、誰もいない
				_set_amb({"cicada": 0.0, "wind": 0.1}, 3.0)
				var tw := create_tween().set_parallel()
				tw.tween_property(env, "adjustment_saturation", 0.6, 6.0)
				tw.tween_property(sun, "light_energy", cfg.sun_energy * 0.65, 20.0)
				tw.tween_property(env, "fog_density", env.fog_density * 2.1, 20.0)
				fin_phase = 3
				fin_t = 0.0
		3:
			if fin_t > 4.6:
				# すぐ後ろで「ふっ」
				var back: Vector3 = player.global_transform.basis.z
				_oneshot3d(kimi.laughs[1], player.global_position + back * 2.1 + Vector3(0, 1.5, 0), 0.0, 2.4, 9000.0, 0.95)
				fin_phase = 4
				fin_t = 0.0
		4:
			if fin_t > 2.8:
				# 一陣の風
				_oneshot(sfx.gust, -2.0)
				_set_amb({"cicada": 0.0, "wind": 1.0}, 1.5)
				var pm: ShaderMaterial = maze.plant_mat
				var tw := create_tween().set_parallel()
				tw.tween_method(func(v): pm.set_shader_parameter("wind_strength", v), cfg.wind, cfg.wind * 2.7, 1.5)
				tw.tween_property(env, "adjustment_saturation", 0.45, 3.0)
				petals.global_position = player.global_position + Vector3(0, 2, 0)
				petals.emitting = true
				fin_phase = 5
				fin_t = 0.0
		5:
			petals.global_position = player.global_position + Vector3(0, 2, 0)
			if fin_t > 6.5:
				# 遠くで一匹だけ
				_set_amb({"cicada": 0.0, "wind": 0.35}, 3.0)
				var pm: ShaderMaterial = maze.plant_mat
				var tw := create_tween().set_parallel()
				tw.tween_method(func(v): pm.set_shader_parameter("wind_strength", v), cfg.wind * 2.7, cfg.wind, 4.0)
				tw.tween_property(env, "adjustment_saturation", 0.3, 5.0)
				petals.amount_ratio = 0.3
				solo.position = player.global_position + Vector3(26, 4, -18)
				solo.volume_db = -30.0
				solo.play()
				create_tween().tween_property(solo, "volume_db", -6.0, 2.5)
				fin_phase = 6
				fin_t = 0.0
		6:
			if fin_t > 6.5:
				create_tween().tween_property(solo, "volume_db", -60.0, 2.4)
				petals.emitting = false
				fin_phase = 7
				fin_t = 0.0
		7:
			if fin_t > 3.0:
				fin_phase = 8
				_end()


## 君のいるタイルから同じ向きにまっすぐ続く通路（2〜4タイル）。消える瞬間を見通せるように
func _straight_run(from: Vector2i) -> Array:
	var best_score := -99.0
	var best: Array = []
	var away: Vector3 = kimi.global_position - player.global_position
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var run: Array = []
		var t: Vector2i = from + d
		while maze.is_open(t) and run.size() < 4:
			run.append(t)
			t += d
		# プレイヤーから遠ざかる向きを優先
		var al: float = Vector3(d.x, 0, d.y).dot(away.normalized())
		var score: float = run.size() + (4.0 if al > 0.7 else (0.0 if al > -0.3 else -6.0))
		if run.size() >= 2 and score > best_score:
			best_score = score
			best = run
	if best.is_empty():
		var pp: Array = maze.find_path(from, maze.goal_tile)
		return pp.slice(1, mini(4, pp.size()))
	return best


# ================================================================ 進行

func _process(delta: float) -> void:
	match state:
		"title":
			t_title += delta
			player.set_look(sin(t_title * 0.09) * 0.3, 0.06 + sin(t_title * 0.07) * 0.04)
		"play", "finale":
			_ambient_events(delta)
			if cfg.get("rain", false):
				_weather(delta)
			if state == "finale":
				_finale(delta)
			var paused := Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not autowalk and shot_dir == ""
			pause_label.visible = paused and not hint.visible
			player.locked = paused
	if autowalk and state in ["play", "finale"]:
		_autowalk(delta)


func _unhandled_input(event: InputEvent) -> void:
	if state in ["play", "finale"] and event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if hint.visible:
			var tw := create_tween()
			tw.tween_interval(4.0)
			tw.tween_property(hint, "modulate:a", 0.0, 2.0)
			tw.tween_callback(func(): hint.visible = false)


func _enter_title() -> void:
	state = "title"
	t_title = 0.0
	_load_stage(0)
	kimi.visible = false
	player.locked = true
	_set_amb({"cicada": 0.75, "wind": 0.15}, 2.0)
	title_box.visible = true
	title_box.modulate.a = 1.0
	start_btn.disabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fade_to(Color(0, 0, 0, 0), 2.6)


func _on_start() -> void:
	if state != "title":
		return
	start_btn.disabled = true
	state = "trans"
	# 遠くでかすかに笑い声
	get_tree().create_timer(0.42).timeout.connect(func():
		var fwd: Vector3 = -player.global_transform.basis.z
		_oneshot3d(kimi.laughs[0], player.global_position + fwd * 34.0 + Vector3(0, 1.5, 0), -4.0, 9.0, 2600.0))
	var tw := create_tween()
	tw.tween_property(title_box, "modulate:a", 0.0, 1.4)
	tw.tween_callback(func(): title_box.visible = false)
	tw.tween_callback(func(): _fade_to(Color(0.965, 0.984, 1.0, 1.0), 1.8))
	tw.tween_interval(1.9)
	tw.tween_callback(func():
		_place_player()
		kimi.setup(maze, player, cfg)
		_set_amb(cfg.amb, 2.5)
		hint.visible = true
		hint.modulate.a = 1.0)
	tw.tween_interval(0.26)
	tw.tween_callback(func():
		_fade_to(Color(0.965, 0.984, 1.0, 0.0), 2.8)
		state = "play"
		player.locked = false)


func _on_found() -> void:
	if state != "play":
		return
	# 出口で追いつくと、君は先へ駆けていく
	var fwd: Vector3 = kimi.global_position - player.global_position
	fwd.y = 0.0
	kimi.run_off(fwd if fwd.length() > 0.1 else -player.global_transform.basis.z, 3.2)
	kimi.play_laugh(1)
	state = "trans"
	get_tree().create_timer(1.35).timeout.connect(_next_stage)


func _next_stage() -> void:
	var to := stage + 1
	var col: Color = stages[to].trans
	player.locked = true
	var tw := create_tween()
	tw.tween_method(func(a): overlay.color = Color(col.r, col.g, col.b, a), 0.0, 1.0, 2.2)
	tw.tween_interval(0.15)
	tw.tween_callback(func(): _load_stage(to))
	tw.tween_interval(0.26)
	tw.tween_method(func(a): overlay.color = Color(col.r, col.g, col.b, a), 1.0, 0.0, 2.6)
	tw.tween_callback(func():
		state = "finale" if cfg.get("finale", false) else "play"
		player.locked = false
		print("STAGE %d %s" % [stage, cfg.name]))


func _end() -> void:
	state = "end"
	player.locked = true
	print("END")
	var bus := AudioServer.get_bus_index("Master")
	var tw := create_tween()
	tw.tween_method(func(v): overlay.color = Color(0, 0, 0, v), 0.0, 1.0, 3.2)
	tw.parallel().tween_method(func(v): AudioServer.set_bus_volume_db(bus, v), 0.0, -60.0, 3.2)
	tw.tween_interval(0.2)
	tw.tween_property(end_label, "modulate:a", 1.0, 2.4)
	tw.tween_interval(5.2)
	tw.tween_property(end_label, "modulate:a", 0.0, 2.4)
	tw.tween_interval(2.6)
	tw.tween_callback(func():
		if autowalk:
			get_tree().quit()
			return
		AudioServer.set_bus_volume_db(bus, 0.0)
		_enter_title())


func _fade_to(c: Color, time: float) -> void:
	var tw := create_tween()
	tw.tween_property(overlay, "color", c, time)


# ================================================================ パーティクル・陽炎

func _setup_particles() -> void:
	# 光の粒（花粉・埃）
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
	# 雨
	rain = GPUParticles3D.new()
	rain.amount = 1400 if web else 3000
	rain.lifetime = 0.9
	rain.local_coords = false
	rain.position = Vector3(0, 9, 0)
	var rp := ParticleProcessMaterial.new()
	rp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	rp.emission_box_extents = Vector3(12, 1, 12)
	rp.direction = Vector3(0.08, -1, 0.03)
	rp.spread = 2.0
	rp.initial_velocity_min = 13.0
	rp.initial_velocity_max = 16.0
	rp.gravity = Vector3(0, -4, 0)
	rain.process_material = rp
	var rq := QuadMesh.new()
	rq.size = Vector2(0.016, 0.6)
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	rm.billboard_keep_scale = true
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(0.75, 0.8, 0.88, 0.35)
	rq.material = rm
	rain.draw_pass_1 = rq
	rain.visibility_aabb = AABB(Vector3(-14, -12, -14), Vector3(28, 14, 28))
	rain.emitting = false
	player.add_child(rain)
	# 最後の突風で舞う花びら
	petals = GPUParticles3D.new()
	petals.amount = 160
	petals.lifetime = 4.0
	petals.local_coords = false
	var pp := ParticleProcessMaterial.new()
	pp.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pp.emission_box_extents = Vector3(10, 1.5, 10)
	pp.direction = Vector3(0.85, 0.2, 0.52)
	pp.spread = 25.0
	pp.initial_velocity_min = 3.0
	pp.initial_velocity_max = 6.0
	pp.gravity = Vector3(0, -0.6, 0)
	pp.angular_velocity_min = -360.0
	pp.angular_velocity_max = 360.0
	pp.turbulence_enabled = true
	pp.turbulence_noise_strength = 1.5
	pp.scale_min = 0.6
	pp.scale_max = 1.2
	petals.process_material = pp
	var pq := QuadMesh.new()
	pq.size = Vector2(0.07, 0.03)
	var pmat := StandardMaterial3D.new()
	pmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	pmat.albedo_color = Color(0.95, 0.72, 0.2)
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pq.material = pmat
	petals.draw_pass_1 = pq
	petals.visibility_aabb = AABB(Vector3(-20, -6, -20), Vector3(40, 12, 40))
	petals.emitting = false
	add_child(petals)


func _dot_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for x in 32:
		for y in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


func _setup_heat_haze() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "HeatHaze"
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mi.mesh = q
	haze_mat = ShaderMaterial.new()
	haze_mat.shader = load("res://shaders/heat_haze.gdshader")
	# 透明物の中で最初に描く（後に描くと雨や花粉を塗りつぶしてしまう）
	haze_mat.render_priority = -127
	mi.material_override = haze_mat
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.get_node("Camera").add_child(mi)


# ================================================================ 画面

func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.08, 0.18, 0.75))
	l.add_theme_constant_override("outline_size", maxi(6, int(size / 7.0)))
	l.add_theme_color_override("font_shadow_color", Color(0, 0.05, 0.15, 0.45))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _setup_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0.9, 0.93, 1.0, 0.0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(flash_rect)
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 1)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	# タイトル
	title_box = VBoxContainer.new()
	title_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_box.alignment = BoxContainer.ALIGNMENT_CENTER
	title_box.add_theme_constant_override("separation", 18)
	layer.add_child(title_box)
	var t := _label("夏　迷　路", 88, Color(1, 0.99, 0.94))
	t.add_theme_color_override("font_outline_color", Color(0.18, 0.3, 0.55, 0.55))
	t.add_theme_constant_override("outline_size", 16)
	title_box.add_child(t)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 40)
	title_box.add_child(sp)
	start_btn = Button.new()
	start_btn.text = "は じ め る"
	start_btn.add_theme_font_size_override("font_size", 20)
	start_btn.add_theme_color_override("font_outline_color", Color(0.04, 0.08, 0.18, 0.75))
	start_btn.add_theme_constant_override("outline_size", 6)
	start_btn.custom_minimum_size = Vector2(240, 52)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.12, 0.25, 0.28)
	sb.border_color = Color(1, 1, 1, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	var sbh := sb.duplicate()
	sbh.bg_color = Color(0.05, 0.12, 0.25, 0.45)
	start_btn.add_theme_stylebox_override("normal", sb)
	start_btn.add_theme_stylebox_override("hover", sbh)
	start_btn.add_theme_stylebox_override("pressed", sbh)
	start_btn.add_theme_stylebox_override("focus", sb)
	start_btn.pressed.connect(_on_start)
	title_box.add_child(start_btn)
	title_box.add_child(_label("W A S D　移動　／　マウス　視点　／　Shift　走る", 16, Color(1, 1, 1, 0.9)))
	title_box.add_child(_label("音を頼りに進んでください。ヘッドホン推奨。", 14, Color(1, 1, 1, 0.75)))
	title_box.add_child(_label("効果音：ポケットサウンド / 効果音素材", 12, Color(1, 1, 1, 0.6)))
	# プレイ中のヒント・一時停止・エンディング
	hint = _label("クリックで視点操作", 18, Color(1, 1, 1, 0.9))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-300, -90)
	hint.size = Vector2(600, 40)
	hint.visible = false
	layer.add_child(hint)
	pause_label = _label("クリックで再開", 20, Color(1, 1, 1, 0.9))
	pause_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_label.visible = false
	layer.add_child(pause_label)
	end_label = _label("夏が終わった。", 40, Color(0.94, 0.91, 0.87))
	end_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))
	end_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	end_label.modulate.a = 0.0
	layer.add_child(end_label)


# ================================================================ テスト

func _autowalk(delta: float) -> void:
	walk_total += delta
	if walk_total > 600.0:
		print("AUTOWALK TIMEOUT stage=%d" % stage)
		get_tree().quit()
		return
	var path: Array = maze.path_tiles
	if walk_i >= path.size():
		return
	var tgt: Vector3 = maze.tile_to_world(path[walk_i])
	var d := tgt - player.global_position
	d.y = 0.0
	var step := 3.5 * delta
	if d.length() <= step:
		player.global_position = Vector3(tgt.x, 0.05, tgt.z)
		walk_i += 1
	else:
		player.global_position += d.normalized() * step
		player.set_look(atan2(-d.x, -d.z), 0.0)
		_on_step_accum(step)


var _acc := 0.0
func _on_step_accum(s: float) -> void:
	_acc += s
	if _acc > 0.62:
		_acc = 0.0
		_on_step(false)


func _run_shots() -> void:
	DirAccess.make_dir_recursive_absolute(shot_dir)
	if poses.is_empty():
		poses.append(null)
	for i in poses.size():
		var p = poses[i]
		if p is String:
			# 最終ステージ確認用: fin=君を出す / look:N=Nフレーム待って君(帽子)の方を向く
			if p == "fin":
				fin_t = 100.0
				for f in 3:
					await get_tree().process_frame
				continue
			if p == "follow":
				# 君が走り出した地点へ（まっすぐな通路の手前）
				player.global_position = Vector3(fin_from.x, 0.05, fin_from.z)
				continue
			if p == "behind":
				var kt: Vector2i = maze.world_to_tile(kimi.global_position)
				var back: Vector3 = kimi.global_transform.basis.z
				var bt: Vector2i = kt + Vector2i(roundi(back.x), roundi(back.z))
				if not maze.is_open(bt):
					for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if maze.is_open(kt + dd):
							bt = kt + dd
							break
				player.global_position = maze.tile_to_world(bt) + Vector3(0, 0.05, 0)
				var dk: Vector3 = kimi.global_position - player.global_position
				player.set_look(atan2(-dk.x, -dk.z), -0.1)
				for f in 3:
					await get_tree().process_frame
				continue
			for f in int(p.substr(5)):
				await get_tree().process_frame
			var tgt: Vector3 = kimi.global_position if kimi.visible and not kimi.vanishing else kimi.hat.global_position
			var d: Vector3 = tgt - player.global_position
			player.set_look(atan2(-d.x, -d.z), -0.12)
			await get_tree().process_frame
			var im := get_viewport().get_texture().get_image()
			im.save_png(shot_dir.path_join("shot_%02d.png" % i))
			print("saved shot %d phase=%d vanishing=%s dist=%.1f" % [i, fin_phase, kimi.vanishing, d.length()])
			continue
		if p != null:
			if p[0].y < -50.0:   # y<-50 なら「君」の後方に置く（y<-150 は止めずに走らせる）
				var k: Vector3 = kimi.global_position
				var back: Vector3 = kimi.global_transform.basis.z
				if p[0].y > -150.0:
					kimi.set_process(false)
				else:
					p[0].y += 103.0
				player.global_position = k + back * (-p[0].y - 100.0 + 3.0)
				player.set_look(atan2(back.x, back.z), deg_to_rad(-3))
			else:
				player.global_position = p[0]
				player.set_look(p[1], p[2])
		var frames := 50 if p == null or p[0].y > -50.0 else 9
		for f in frames:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot_dir.path_join("shot_%02d.png" % i))
		print("saved shot %d fps=%d" % [i, Engine.get_frames_per_second()])
	get_tree().quit()

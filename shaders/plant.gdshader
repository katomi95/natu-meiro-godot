// ひまわり用：頂点カラーで部位を塗り分け、高さに応じて風で揺らす。
// 葉・花びらは BACKLIGHT で逆光時に透ける。
// COLOR.a : 0=茎・花芯 / 0.5=葉 / 1.0=花びら
shader_type spatial;
render_mode world_vertex_coords, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform float wind_strength = 0.16;
uniform vec2 wind_dir = vec2(0.85, 0.52);
uniform float plant_height = 2.6;
uniform float translucency = 0.75;

varying float v_part;
varying float v_tint;

void vertex() {
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	float h = max(VERTEX.y, 0.0);
	float bend = pow(h / plant_height, 1.8);
	// 大きな突風の波（ゆっくり畑を渡っていく）
	float gust = sin(dot(VERTEX.xz, wind_dir) * 0.16 - TIME * 1.1) * 0.5 + 0.5;
	gust = gust * gust * 0.85 + 0.15;
	float sway = sin(TIME * 1.7 + phase) * 0.35 + sin(TIME * 2.9 + phase * 1.7) * 0.15;
	vec2 off = wind_dir * (gust + sway * 0.5) * wind_strength * bend;
	off += vec2(-wind_dir.y, wind_dir.x) * sway * 0.05 * bend;
	VERTEX.xz += off;
	VERTEX.y -= dot(off, off) * 0.8;
	// 葉のはためき（UV.x = 葉の付け根からの距離）
	float leaf = UV.x;
	VERTEX.y += sin(TIME * 7.0 + phase * 3.0 + h * 4.0) * 0.035 * leaf * (0.4 + gust);
	v_part = COLOR.a;
	v_tint = INSTANCE_CUSTOM.g;
}

void fragment() {
	vec3 c = COLOR.rgb * mix(0.86, 1.12, v_tint);
	// 葉の裏は白っぽく
	if (!FRONT_FACING && v_part > 0.3 && v_part < 0.75) {
		c = c * vec3(1.25, 1.3, 1.05) + vec3(0.03, 0.04, 0.0);
	}
	ALBEDO = c;
	ROUGHNESS = 0.72;
	SPECULAR = 0.35;
	float thin = step(0.3, v_part);
	BACKLIGHT = c * translucency * thin * (0.6 + 0.6 * step(0.75, v_part));
}

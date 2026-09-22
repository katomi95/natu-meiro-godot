// 入道雲：球の集合をノイズで膨らませ、日向は白く、影は青く。
// INSTANCE_CUSTOM : r=球の半径 / g=乱数 / b=雲底の高さ
shader_type spatial;
render_mode world_vertex_coords, unshaded, fog_disabled, cull_back, shadows_disabled;

uniform vec3 sun_dir = vec3(0.12, 0.88, 0.46);
uniform vec3 lit_color : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 shade_color : source_color = vec3(0.42, 0.52, 0.74);
uniform vec3 horizon_color : source_color = vec3(0.80, 0.90, 1.0);
uniform float brightness = 1.35;

varying vec3 wpos;
varying float v_base;

float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x), u.y),
			mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x), u.y), u.z);
}
float fbm3(vec3 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += noise3(p) * a; p *= 2.1; a *= 0.5; }
	return v;
}

void vertex() {
	float r = INSTANCE_CUSTOM.r;
	float n = fbm3(VERTEX * 0.006 + INSTANCE_CUSTOM.g * 10.0);
	// world_vertex_coords では NORMAL にインスタンスのスケールが乗っているので正規化する
	VERTEX += normalize(NORMAL) * (n - 0.35) * r * 0.55;
	wpos = VERTEX;
	v_base = INSTANCE_CUSTOM.b;
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 L = normalize(sun_dir);
	float det = fbm3(wpos * 0.012);
	float ndl = dot(wn, L) + (det - 0.5) * 0.7;
	vec3 col = mix(shade_color, lit_color, smoothstep(-0.2, 0.6, ndl));
	// 底は灰色がかる
	col *= mix(0.62, 1.0, smoothstep(v_base, v_base + 650.0, wpos.y));
	// 下向きの面は影になる
	col *= mix(0.78, 1.0, smoothstep(-0.8, 0.1, wn.y));
	// 縁の銀色の光
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	col += pow(1.0 - clamp(dot(wn, V), 0.0, 1.0), 3.0) * 0.18;
	col *= brightness;
	// 地平線付近は空気で霞む
	vec3 dir = normalize(wpos - CAMERA_POSITION_WORLD);
	col = mix(col, horizon_color * 1.25, exp(-max(dir.y, 0.0) * 9.0) * 0.6);
	ALBEDO = col;
}

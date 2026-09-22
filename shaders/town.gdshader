// 雨の町：頂点カラーで塗り分け。COLOR.a が 0 の面は灯りのついた窓
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

varying vec3 wpos;

float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float lit = 1.0 - step(0.5, COLOR.a);
	// 雨に濡れた壁の縦の筋
	float streak = hash(vec2(floor(wpos.x * 6.0 + wpos.z * 6.0), 0.0));
	vec3 c = COLOR.rgb * mix(0.9, 1.0, streak);
	ALBEDO = c * (1.0 - lit * 0.6);
	ROUGHNESS = mix(0.6, 0.85, streak);
	SPECULAR = 0.5;
	EMISSION = COLOR.rgb * lit * 3.0;
}

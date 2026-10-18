// 取り込んだ「君」のモデル用（local/kimi.glb があるときだけ使う）。
// ボーンの無い一枚メッシュなので、裾から下を左右交互に振って歩かせる。
shader_type spatial;
render_mode cull_disabled, diffuse_burley, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform float hem = -0.2;        // これより下が脚（モデル座標）
uniform float swing = 0.0;       // 歩幅（ラジアン）
uniform float sway = 0.0;        // スカートの揺れ
uniform float wind_phase = 0.0;

void vertex() {
	float y = VERTEX.y;
	if (y < hem) {
		// 裾を軸に、左右の脚を逆向きに振る（付け根ほど弱く）
		float w = clamp((hem - y) / 0.16, 0.0, 1.0);
		float a = swing * sign(VERTEX.x) * w;
		float dy = y - hem;
		float z = VERTEX.z;
		VERTEX.y = hem + dy * cos(a) - z * sin(a);
		VERTEX.z = dy * sin(a) + z * cos(a);
	} else {
		// スカートはふわりと揺れる
		float w = clamp((hem + 0.34 - y) / 0.34, 0.0, 1.0);
		VERTEX.x += sway * w;
		VERTEX.z += sin(wind_phase * 2.1 + y * 7.0) * 0.009 * w;
	}
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = clamp(texture(orm_tex, UV).g, 0.3, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.4;
	ALPHA = c.a * alpha;
	// 夏の逆光で白い服が少し透ける
	BACKLIGHT = c.rgb * 0.35;
}

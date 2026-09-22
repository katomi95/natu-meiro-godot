// 陽炎：遠く・地平線付近の画面をゆらゆら歪ませるポストエフェクト。
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture;
uniform float strength = 0.0016;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

void fragment() {
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float dist = -view.z;
	vec3 wdir = normalize((INV_VIEW_MATRIX * vec4(view.xyz, 0.0)).xyz);
	float k = smoothstep(12.0, 90.0, dist) * (1.0 - smoothstep(0.02, 0.22, wdir.y));
	float w = sin(SCREEN_UV.y * 220.0 - TIME * 7.0 + sin(SCREEN_UV.x * 35.0 + TIME * 1.7) * 2.5);
	float w2 = sin(SCREEN_UV.y * 97.0 + TIME * 4.3 + SCREEN_UV.x * 12.0);
	vec2 off = vec2(w * 0.7 + w2 * 0.3, w2 * 0.4) * strength * k;
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
}

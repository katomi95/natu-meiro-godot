shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D path_mask : filter_linear, repeat_disable;
uniform vec4 mask_rect = vec4(-26.0, -26.0, 52.0, 52.0); // x, z, 幅, 奥行
uniform vec3 dirt_color : source_color = vec3(0.72, 0.58, 0.40);
uniform vec3 dirt_dark : source_color = vec3(0.50, 0.39, 0.26);
uniform vec3 grass_color : source_color = vec3(0.26, 0.42, 0.10);
uniform vec3 meadow_color : source_color = vec3(0.40, 0.55, 0.16);
// 0=草と土の道 / 1=砂利の参道（夏祭り） / 2=濡れたアスファルト（夕立）
uniform int mode = 0;

varying vec3 wpos;

float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += noise(p) * a; p *= 2.03; a *= 0.5; }
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz - mask_rect.xy) / mask_rect.zw;
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	float dirt = texture(path_mask, uv).r * inside;
	float n = fbm(wpos.xz * 0.9);
	float n2 = fbm(wpos.xz * 6.0);
	dirt = smoothstep(0.35, 0.75, dirt + (n - 0.5) * 0.5);
	vec3 soil = mix(dirt_dark, dirt_color, n2);
	float far = smoothstep(40.0, 120.0, length(wpos.xz));
	vec3 grass = mix(grass_color * mix(0.7, 1.15, n), meadow_color * mix(0.8, 1.1, n), far);
	ALBEDO = mix(grass, soil, dirt);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	if (mode == 1) {
		vec3 gravel = mix(vec3(0.42, 0.38, 0.33), vec3(0.62, 0.57, 0.5), n2);
		gravel *= mix(0.85, 1.05, fbm(wpos.xz * 25.0));
		ALBEDO = mix(gravel, grass * 0.8, smoothstep(0.62, 0.8, n) * 0.5);
	} else if (mode == 2) {
		float puddle = smoothstep(0.52, 0.6, fbm(wpos.xz * 0.35 + 3.0));
		vec3 asphalt = mix(vec3(0.11, 0.115, 0.12), vec3(0.19, 0.19, 0.2), n2);
		ALBEDO = mix(asphalt, vec3(0.02, 0.025, 0.03), puddle);
		ROUGHNESS = mix(0.42, 0.04, puddle);
		SPECULAR = 0.6;
		METALLIC = 0.0;
	}
}

shader_type spatial;
render_mode world_vertex_coords, cull_disabled, diffuse_burley;

uniform vec2 wind_dir = vec2(0.85, 0.52);
uniform vec3 base_color : source_color = vec3(0.14, 0.30, 0.05);
uniform vec3 tip_color : source_color = vec3(0.62, 0.78, 0.22);
uniform vec3 dry_color : source_color = vec3(0.78, 0.72, 0.36);
uniform float sway_amp = 1.0;

varying float v_t;
varying float v_var;

void vertex() {
	float t = UV.y; // 0=根元 1=先端
	float phase = INSTANCE_CUSTOM.r * 6.2831;
	float gust = sin(dot(VERTEX.xz, wind_dir) * 0.22 - TIME * 1.4) * 0.5 + 0.5;
	float flutter = sin(TIME * 3.3 + phase + VERTEX.x * 2.0) * 0.5;
	vec2 off = wind_dir * (gust * 0.16 + flutter * 0.05) * t * t * sway_amp;
	VERTEX.xz += off;
	VERTEX.y -= dot(off, off) * 1.2;
	v_t = t;
	v_var = INSTANCE_CUSTOM.g;
	// 草は上向き法線にしてふんわり明るく
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.65));
}

void fragment() {
	vec3 c = mix(base_color, tip_color, v_t);
	c = mix(c, dry_color, smoothstep(0.55, 1.0, v_var) * v_t * 0.8);
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	BACKLIGHT = c * 0.7;
	AO = mix(0.35, 1.0, v_t);
	AO_LIGHT_AFFECT = 0.4;
}

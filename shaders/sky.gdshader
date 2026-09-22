// 真夏の正午の空：天頂は濃い群青、地平は白く霞む。太陽は大きく眩しく。
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.03, 0.22, 0.78);
uniform vec3 mid_color : source_color = vec3(0.16, 0.48, 0.98);
uniform vec3 horizon_color : source_color = vec3(0.74, 0.88, 1.0);
uniform vec3 ground_color : source_color = vec3(0.46, 0.56, 0.42);
uniform float energy = 1.25;

void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(mid_color, zenith_color, smoothstep(0.25, 1.0, h));
	col = mix(horizon_color, col, smoothstep(0.0, 0.32, pow(h, 0.8)));
	// 地平線ぎわの白い熱気
	col = mix(col, vec3(0.85, 0.92, 1.0), exp(-h * 30.0) * 0.5);
	if (d.y < 0.0) {
		col = mix(horizon_color, ground_color, smoothstep(0.0, 0.2, -d.y));
	}
	float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
	vec3 sun = LIGHT0_COLOR * (smoothstep(0.99985, 0.99992, sd) * 60.0 + pow(sd, 350.0) * 3.0 + pow(sd, 18.0) * 0.35);
	COLOR = col * energy + sun;
}

// 真夏の正午の空：天頂は濃い群青、地平は白く霞む。太陽は大きく眩しく。
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.03, 0.22, 0.78);
uniform vec3 mid_color : source_color = vec3(0.16, 0.48, 0.98);
uniform vec3 horizon_color : source_color = vec3(0.74, 0.88, 1.0);
uniform vec3 ground_color : source_color = vec3(0.46, 0.56, 0.42);
uniform float energy = 1.25;
uniform float overcast = 0.0;   // 夕立の厚い雲
uniform float cirrus = 0.0;     // 夏の終わり・夕暮れの薄い筋雲
uniform vec3 cloud_tint : source_color = vec3(1.0);
uniform float flash = 0.0;      // 稲光

float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += noise(p) * a; p *= 2.07; a *= 0.5; }
	return v;
}

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
	vec2 puv = d.xz / (max(d.y, 0.0) + 0.12);
	if (cirrus > 0.0 && d.y > 0.0) {
		vec2 q = puv * vec2(0.9, 3.5);
		float c = smoothstep(0.52, 0.85, fbm(q * 0.8)) * smoothstep(0.0, 0.25, d.y);
		col = mix(col, vec3(1.0, 0.98, 0.95) * cloud_tint * 1.1, c * cirrus * 0.75);
	}
	if (overcast > 0.0) {
		float c = fbm(puv * 0.6);
		vec3 oc = mix(vec3(0.16, 0.18, 0.21), vec3(0.34, 0.37, 0.41), c);
		col = mix(col, oc, overcast);
		sun *= 1.0 - overcast;
	}
	COLOR = col * energy + sun + vec3(0.8, 0.85, 1.0) * flash;
}

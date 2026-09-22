// 夏祭りの人混み：ゆっくり体を揺らし、ときどき上下に弾む
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

void vertex() {
	float ph = INSTANCE_CUSTOM.r * 6.2831;
	float h = VERTEX.y;
	VERTEX.x += sin(TIME * 1.1 + ph) * 0.05 * h;
	VERTEX.z += sin(TIME * 0.8 + ph * 1.3) * 0.03 * h;
	VERTEX.y += abs(sin(TIME * (1.5 + INSTANCE_CUSTOM.g) + ph)) * 0.025;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 0.8;
}

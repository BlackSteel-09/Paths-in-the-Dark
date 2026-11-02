shader_type spatial;
render_mode unshaded, fog_disabled, cull_front, depth_draw_never, blend_mix;

uniform vec4 sky_tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 star_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float star_density : hint_range(20.0, 400.0) = 180.0;
uniform float star_threshold : hint_range(0.8, 0.9999) = 0.985;
uniform float star_size : hint_range(0.005, 0.08) = 0.02;
uniform float star_brightness : hint_range(0.0, 5.0) = 1.5;
uniform float horizon_fade : hint_range(0.0, 1.0) = 0.25;

varying vec3 local_dir;

float hash12(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	local_dir = normalize(VERTEX);
}

void fragment() {
	vec3 d = normalize(local_dir);

	float phi = atan(d.x, d.z);
	float theta = acos(clamp(d.y, -1.0, 1.0));

	vec2 uv = vec2(phi / (2.0 * 3.14159265) + 0.5, theta / 3.14159265);

	vec2 grid = vec2(star_density, star_density * 0.5);
	vec2 cell_uv = uv * grid;
	vec2 cell = floor(cell_uv);
	vec2 f = fract(cell_uv) - 0.5;

	float rnd = hash12(cell);
	float star_mask = step(star_threshold, rnd);

	vec2 offset = vec2(
		hash12(cell + vec2(1.7, 9.2)),
		hash12(cell + vec2(8.3, 2.8))
	) - 0.5;

	float dist = length(f - offset * 0.7);
	float star = smoothstep(star_size, 0.0, dist) * star_mask;

	float twinkle = 0.85 + 0.15 * sin(TIME * 1.7 + rnd * 20.0);

	float fade_to_horizon = smoothstep(-0.15, horizon_fade, d.y);

	vec3 col = sky_tint.rgb;
	col += star_color.rgb * star * twinkle * star_brightness * fade_to_horizon;

	ALBEDO = star_color.rgb;
	EMISSION = star_color.rgb * star_brightness;
	ALPHA = clamp(star * twinkle * star_brightness * fade_to_horizon, 0.0, 1.0);;
}
// Stylized Water
// Depth-tinted water with foam where it meets objects, moving normal maps and
// vertex waves.
// Godot 4.7 · CC0 1.0 · godotlearning.com/shaders/stylized-water
shader_type spatial;
// blend_mix: ALPHA is transparency. depth_draw_opaque: depth is written for
// opaque surfaces only, and writing ALPHA makes this one transparent, so the
// water writes no depth. cull_back: the underside is not drawn. diffuse_burley
// and specular_schlick_ggx are Godot's default lighting models.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Colour where the water is shallow. Alpha is how opaque it is there.
uniform vec4 shallow_color : source_color = vec4(0.24, 0.8, 0.76, 0.45);
// Colour where the water is depth_distance metres deep or more.
uniform vec4 deep_color : source_color = vec4(0.02, 0.17, 0.33, 0.94);
// Metres of water (measured straight down) over which the colour goes from
// shallow_color to deep_color.
uniform float depth_distance : hint_range(0.1, 10.0) = 2.0;
// Colour of the foam. Alpha is how opaque the foam is.
uniform vec4 foam_color : source_color = vec4(0.96, 0.98, 1.0, 1.0);
// Metres of water depth that still get foam. 0 turns foam off.
uniform float foam_width : hint_range(0.0, 1.0) = 0.2;
// How high a crest can rise above the plane, in metres. 0 turns waves off.
uniform float wave_height : hint_range(0.0, 1.0) = 0.1;
// Length of the longest wave in metres. The other three are shorter.
uniform float wave_length : hint_range(0.5, 20.0) = 4.0;
// Speed of the waves and of the normal map scroll. 0 freezes the water. The
// 0.01 step stops the water jumping when TIME wraps round after an hour.
uniform float wave_speed : hint_range(0.0, 2.0, 0.01) = 0.5;
// Two tileable normal maps, scrolled in different directions and added.
uniform sampler2D normal_map_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map_b : hint_normal, filter_linear_mipmap, repeat_enable;
// Strength of the small ripples from the normal maps. 0 leaves only the waves.
uniform float normal_scale : hint_range(0.0, 2.0) = 0.25;
// Metres covered by one tile of normal_map_a. normal_map_b tiles twice as often.
uniform float normal_tile_size : hint_range(0.5, 50.0) = 8.0;
// Surface roughness of the water. Low values give a small, sharp sun glint.
uniform float roughness : hint_range(0.0, 1.0) = 0.06;

// The depth buffer of everything opaque drawn before the water.
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// Four sine waves: direction (unit vector), length as a fraction of
// wave_length, share of wave_height, and how many half turns each makes per
// unit of TIME * wave_speed. Whole numbers of half turns make every wave repeat
// after 2 units, which is 4 seconds at the default wave_speed of 0.5.
const vec2 WAVE_DIR[4] = vec2[4](
	vec2(0.958, 0.287), vec2(-0.447, 0.894), vec2(0.6, -0.8), vec2(-0.894, -0.447)
);
const float WAVE_LENGTH[4] = float[4](1.0, 0.71, 0.53, 0.37);
const float WAVE_SHARE[4] = float[4](0.4, 0.27, 0.2, 0.13);
const float WAVE_HALF_TURNS[4] = float[4](1.0, 2.0, 2.0, 3.0);

varying vec2 world_xz;

// Height of the surface at a world position, and its slope along x and z.
vec3 waves(vec2 xz, float t) {
	float height = 0.0;
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		float k = TAU / (wave_length * WAVE_LENGTH[i]);
		float phase = k * dot(WAVE_DIR[i], xz) - PI * WAVE_HALF_TURNS[i] * t;
		float amplitude = wave_height * WAVE_SHARE[i];
		height += amplitude * sin(phase);
		// d/dx and d/dz of amplitude * sin(phase): the chain rule gives
		// amplitude * cos(phase) * k * direction.
		slope += amplitude * cos(phase) * k * WAVE_DIR[i];
	}
	return vec3(height, slope);
}

void vertex() {
	// Waves are placed in world space, so tiles of water side by side line up.
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_xz = world.xz;
	vec3 wave = waves(world.xz, TIME * wave_speed);
	VERTEX.y += wave.x;
	// The surface y = h(x, z) has the normal (-dh/dx, 1, -dh/dz). Tangent and
	// binormal tilt by the slope along their own direction, so normal mapping
	// follows the waves.
	vec2 slope = wave.yz;
	NORMAL = normalize(vec3(-slope.x, 1.0, -slope.y));
	TANGENT = normalize(vec3(TANGENT.x, dot(TANGENT.xz, slope), TANGENT.z));
	BINORMAL = normalize(vec3(BINORMAL.x, dot(BINORMAL.xz, slope), BINORMAL.z));
}

void fragment() {
	float t = TIME * wave_speed;

	// Ripples: two normal maps scrolling in different directions. Each moves a
	// whole number of tiles every 2 units of t, so the scroll loops with the waves.
	vec2 uv = world_xz / normal_tile_size;
	vec2 uv_a = uv + vec2(0.5, 0.0) * t;
	vec2 uv_b = uv * 2.0 + vec2(-0.5, 0.5) * t;
	vec2 ripple_a = texture(normal_map_a, uv_a).rg * 2.0 - 1.0;
	vec2 ripple_b = texture(normal_map_b, uv_b).rg * 2.0 - 1.0;
	// Adding the x and y slopes of two normal maps blends them; Godot rebuilds
	// the blue channel from x and y.
	vec2 ripple = ripple_a + ripple_b;
	ripple /= max(1.0, length(ripple) / 0.95);

	// Depth: rebuild the position of whatever opaque surface is behind this
	// pixel, then measure how far below the water surface it is.
	float raw_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// OpenGL (Compatibility): NDC depth runs from -1 to 1.
	vec3 ndc = vec3(SCREEN_UV, raw_depth) * 2.0 - 1.0;
#else
	// Vulkan (Forward+ and Mobile): NDC depth runs from 0 to 1.
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
#endif
	vec4 behind_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	behind_view.xyz /= behind_view.w;
	vec3 behind_world = (INV_VIEW_MATRIX * vec4(behind_view.xyz, 1.0)).xyz;
	vec3 surface_world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float water_depth = max(surface_world.y - behind_world.y, 0.0);

	// Colour: shallow to deep over depth_distance metres.
	vec4 water = mix(shallow_color, deep_color, clamp(water_depth / depth_distance, 0.0, 1.0));

	// Foam: 1 where the water touches something, 0 at foam_width metres deep.
	// A threshold taken from the ripples breaks the band into moving patches.
	float edge = foam_width > 0.0 ? 1.0 - clamp(water_depth / foam_width, 0.0, 1.0) : 0.0;
	float threshold = clamp(0.5 + 0.35 * (ripple_a.x + ripple_b.y), 0.05, 0.95);
	float foam = smoothstep(threshold - 0.06, threshold + 0.06, edge);

	ALBEDO = mix(water.rgb, foam_color.rgb, foam);
	ALPHA = mix(water.a, foam_color.a, foam);
	ROUGHNESS = mix(roughness, 0.9, foam);
	SPECULAR = 0.5;
	NORMAL_MAP = vec3(ripple * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_scale * (1.0 - foam);
}

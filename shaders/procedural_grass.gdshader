shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 grass_color : source_color = vec4(0.20, 0.314, 0.227, 1.0);
uniform float wind_strength : hint_range(0.0, 1.5) = 0.3;
uniform float wind_speed : hint_range(0.0, 8.0) = 2.0;
uniform float growth : hint_range(0.1, 8.0) = 1.0;
uniform float color_variation : hint_range(0.0, 1.0) = 0.25;
uniform float grass_brightness : hint_range(0.5, 4.0) = 2.0;

varying float blade_height;
varying float blade_variation;

void vertex() {
    // UV.y is zero at the root, one at the tip. The root stays planted.
    float h = clamp(UV.y, 0.0, 1.0);
    blade_height = h;
    blade_variation = INSTANCE_CUSTOM.r;
    float phase = INSTANCE_CUSTOM.g * 6.2831853;
    vec3 root_world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    float t = TIME * wind_speed;
    float sway = sin(t + phase + root_world.x * 0.3 + root_world.z * 0.3);
    float sway_cross = cos(t * 1.3 + phase + root_world.x * 0.27);
    float tip_influence = h * h;
    VERTEX.y *= growth;
    VERTEX.x *= mix(1.0, growth, 0.08);
    VERTEX.z *= mix(1.0, growth, 0.08);
    VERTEX.x += sway * wind_strength * tip_influence;
    VERTEX.z += sway_cross * wind_strength * tip_influence * 0.5;
}

void fragment() {
    vec3 root = grass_color.rgb * 0.4;
    vec3 tip = grass_color.rgb * 1.15;

    float variation = 0.7 + blade_variation * 0.4;

    vec3 base = mix(
        root,
        tip,
        clamp(blade_height, 0.0, 1.0)
    );

    base *= variation;
    base *= grass_brightness;

    ALBEDO = base;
    ROUGHNESS = 1.0;
}

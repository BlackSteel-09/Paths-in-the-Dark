shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float submersion : hint_range(0.0, 1.0) = 0.0;
uniform float distortion_strength : hint_range(0.0, 0.01) = 0.0018;
uniform vec4 center_tint : source_color = vec4(0.0, 0.117647, 0.235294, 1.0);
uniform vec4 edge_tint : source_color = vec4(0.0, 0.039216, 0.156863, 1.0);
uniform float tint_strength : hint_range(0.0, 1.5) = 1.0;

void fragment() {
    vec2 uv = SCREEN_UV;
    vec2 warp = vec2(
        sin(uv.y * 18.0 + TIME * 0.65),
        cos(uv.x * 14.0 + TIME * 0.55)
    ) * distortion_strength * submersion;
    vec3 scene_color = texture(screen_texture, clamp(uv + warp, vec2(0.001), vec2(0.999))).rgb;

    vec2 centred = (uv - vec2(0.5)) * vec2(1.45, 1.0);
    float edge = smoothstep(0.18, 0.76, length(centred));
    vec3 tint = mix(center_tint.rgb, edge_tint.rgb, edge);
    // Preserve the reference's radial blue tint, but intensify it underwater.
    float opacity = clamp(mix(0.42, 0.82, edge) * submersion * tint_strength, 0.0, 0.96);
    COLOR = vec4(mix(scene_color, tint, opacity), 1.0);
}

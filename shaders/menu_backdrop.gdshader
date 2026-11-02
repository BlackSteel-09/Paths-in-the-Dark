shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 5.0) = 2.4;
uniform float global_darkness : hint_range(0.0, 1.0) = 0.65;
uniform float left_darkness : hint_range(0.0, 1.0) = 0.85;
uniform float falloff : hint_range(0.1, 8.0) = 2.6;
void fragment() {
    vec3 scene_color = textureLod(screen_texture, SCREEN_UV, blur_lod).rgb;
    float left_weight = pow(clamp(1.0 - SCREEN_UV.x, 0.0, 1.0), falloff);
    float darkness = clamp(global_darkness + left_darkness * left_weight, 0.0, 0.98);
    vec3 veil = vec3(0.012, 0.010, 0.025);
    COLOR = vec4(mix(scene_color, veil, darkness), 1.0);
}

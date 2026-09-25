shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 surface_color : source_color = vec4(1.0,1.0,1.0,0.5);
uniform sampler2D surface_texture : source_color, hint_default_white, filter_linear, repeat_enable;
void fragment() {
    vec4 value = surface_color * texture(surface_texture, UV) * COLOR;
    ALBEDO = value.rgb;
    ALPHA = value.a;
}

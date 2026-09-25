shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
uniform vec4 outline_color : source_color = vec4(1.0, 0.7, 0.15, 1.0);
uniform float width_pixels = 1.0;
uniform bool hover_only = false;
uniform mat4 hover_camera;
uniform mat4 hover_projection;
varying float edge_distance;
varying float visible_edge;
void vertex() {
    vec4 p = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    vec4 q = MODELVIEW_MATRIX * vec4(CUSTOM0.xyz, 1.0);
    vec3 n1 = MODELVIEW_NORMAL_MATRIX * NORMAL;
    vec3 n2 = MODELVIEW_NORMAL_MATRIX * CUSTOM1.xyz;
    vec3 sight = PROJECTION_MATRIX[3][3] == 0.0 ? (p.xyz + q.xyz) * 0.5 : vec3(0.0, 0.0, -1.0);
    visible_edge = CUSTOM1.w > 0.5 || dot(n1, sight) * dot(n2, sight) < 0.0 ? 1.0 : 0.0;
    if (hover_only && (distance(INV_VIEW_MATRIX[3].xyz, hover_camera[3].xyz) > 0.0001 || distance(INV_VIEW_MATRIX[2].xyz, hover_camera[2].xyz) > 0.0001 || abs(abs(PROJECTION_MATRIX[0][0]) - abs(hover_projection[0][0])) > 0.0001 || abs(abs(PROJECTION_MATRIX[1][1]) - abs(hover_projection[1][1])) > 0.0001)) visible_edge = 0.0;
    // Godot reverse-Z uses z=w at the near plane in both rendering backends.
    vec4 a = PROJECTION_MATRIX * p;
    vec4 b = PROJECTION_MATRIX * q;
    float da = a.w - a.z;
    float db = b.w - b.z;
    if (da < 0.0 && db < 0.0) visible_edge = 0.0;
    else if (da < 0.0) a = mix(a, b, da / (da - db));
    else if (db < 0.0) b = mix(b, a, db / (db - da));
    vec2 direction = (b.xy / max(b.w, 0.0001) - a.xy / max(a.w, 0.0001)) * VIEWPORT_SIZE;
    float length_px = length(direction);
    vec2 perpendicular = length_px > 0.0001 ? vec2(-direction.y, direction.x) / length_px : vec2(0.0);
    float half_width = width_pixels * 0.5 + 0.75;
    a.xy += perpendicular * UV.x * half_width * 2.0 / VIEWPORT_SIZE * a.w;
    a.z += 0.000001 * a.w;
    POSITION = a;
    edge_distance = UV.x * (1.0 - 2.0 * UV.y) * half_width;
}
void fragment() {
    if (visible_edge < 0.5) discard;
    ALBEDO = outline_color.rgb;
    ALPHA = outline_color.a * (1.0 - smoothstep(width_pixels * 0.5 - 0.5, width_pixels * 0.5 + 0.5, abs(edge_distance)));
}

#ifndef MOLD_POLYLINE_RASTER
#define MOLD_POLYLINE_RASTER
// Rendering and optional ribbon normals must expand the same triangle.
float mold_polyline_raster_scale(vec3 position, vec4 c0, vec4 c1, vec4 c2,
        mat4 model_view, mat4 projection, vec2 viewport, float padding_pixels,
        out float pixel_coverage) {
    vec2 extrusion = c0.xy;
    float radius = c0.w;
    bool is_segment = c0.z < 0.5;
    vec2 width_direction = is_segment ? vec2(c1.x, c2.x)
        : extrusion / max(length(extrusion), 0.00001);
    vec4 center_clip = projection * model_view * vec4(position, 1.0);
    vec4 edge_clip = projection * model_view
        * vec4(position + vec3(width_direction * radius, 0.0), 1.0);
    float half_width_pixels = projected_pixel_distance(center_clip, edge_clip, viewport);
    float target_width_pixels = half_width_pixels * 2.0;
    pixel_coverage = target_width_pixels;
    // Width normals differ across a join; its shared extrusion does not.
    // Keep true-normal width for coverage, but expand shared vertices identically.
    float extrusion_length = length(extrusion);
    if (extrusion_length < 0.00001) return 1.0;
    vec4 support_clip = projection * model_view
        * vec4(position + vec3(extrusion * (radius / extrusion_length), 0.0), 1.0);
    float support_width_pixels = projected_pixel_distance(center_clip, support_clip, viewport) * 2.0;
    float raster_width_pixels = max(1.0, support_width_pixels + padding_pixels * 2.0);
    return support_width_pixels > 0.0 ? raster_width_pixels / support_width_pixels : 1.0;
}
#endif

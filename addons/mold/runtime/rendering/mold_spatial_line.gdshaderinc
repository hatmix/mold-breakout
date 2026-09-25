#ifndef MOLD_SPATIAL_LINE_INCLUDED
#define MOLD_SPATIAL_LINE_INCLUDED
// Stock minimum-width expansion for spatial lines, shared with surface normals.
float mold_spatial_line_raster_scale(float progress, mat4 model, mat4 view,
        mat4 projection, vec2 viewport, out float pixel_coverage) {
    vec3 center_view = (view * model[3]).xyz;
    vec3 line_axis_view = (view * vec4(model[1].xyz, 0.0)).xyz;
    vec3 width_x_view = (view * vec4(model[0].xyz, 0.0)).xyz;
    vec3 width_z_view = (view * vec4(model[2].xyz, 0.0)).xyz;
    vec3 anchor_view = center_view + line_axis_view * (progress - 0.5);
    vec3 view_direction = projection[3][3] > 0.5
        ? vec3(0.0, 0.0, -1.0) : anchor_view;
    vec3 screen_normal_view = cross(view_direction, line_axis_view);
    float normal_length = length(screen_normal_view);
    if (normal_length < 0.00001) {
        screen_normal_view = cross(vec3(0.0, 0.0, -1.0), line_axis_view);
        normal_length = length(screen_normal_view);
    }
    screen_normal_view = normal_length < 0.00001
        ? vec3(1.0, 0.0, 0.0) : screen_normal_view / normal_length;
    float target_diameter = max(length(width_x_view), length(width_z_view));
    vec4 anchor_clip = projection * vec4(anchor_view, 1.0);
    float target_width_pixels = projected_pixel_distance(anchor_clip,
        projection * vec4(anchor_view + screen_normal_view * target_diameter, 1.0), viewport);
    pixel_coverage = target_width_pixels;
    return max(target_width_pixels, 1.0) / max(target_width_pixels, 0.00001);
}

#if defined(MOLD_SURFACE_NORMAL_OS) || defined(MOLD_SURFACE_NORMAL_WS)
vec3 mold_spatial_line_normal(vec3 position, vec3 normal, float half_length,
        float raster_scale, mat4 model, mat4 view, mat4 projection, vec2 viewport) {
    // The generated surface is (s(y)*x, y, s(y)*z). Transform its smooth
    // normal by the inverse-transpose Jacobian, including depth-varying s(y).
    // Centered differences use 0.1% of the local line span; this stays above
    // projection rounding noise and follows the stock clamp at line endpoints.
    float epsilon = max(2.0 * half_length, 1.0) * 0.001;
    float unused_coverage;
    float before = mold_spatial_line_raster_scale(
        clamp((position.y - epsilon) / (2.0 * half_length) + 0.5, 0.0, 1.0),
        model, view, projection, viewport, unused_coverage);
    float after = mold_spatial_line_raster_scale(
        clamp((position.y + epsilon) / (2.0 * half_length) + 0.5, 0.0, 1.0),
        model, view, projection, viewport, unused_coverage);
    float slope = (after - before) / (2.0 * epsilon);
    return vec3(normal.x / raster_scale,
        normal.y - slope * dot(position.xz, normal.xz) / raster_scale,
        normal.z / raster_scale);
}
#endif
#endif

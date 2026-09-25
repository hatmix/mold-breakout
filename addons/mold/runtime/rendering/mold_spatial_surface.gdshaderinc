#ifndef MOLD_SPATIAL_SURFACE
#define MOLD_SPATIAL_SURFACE

#if defined(MOLD_SURFACE_NORMAL_OS) || defined(MOLD_SURFACE_NORMAL_WS)
#define MOLD_SURFACE_NORMAL
#endif
#if defined(MOLD_SURFACE_POSITION_OS) || defined(MOLD_SURFACE_POSITION_WS) || defined(MOLD_SURFACE_NORMAL)
#define MOLD_SURFACE_ENABLED
#endif
#ifdef MOLD_SURFACE_POSITION_OS
varying vec3 mold_position_os;
#endif
#ifdef MOLD_SURFACE_POSITION_WS
varying vec3 mold_position_ws;
#endif
#if defined(MOLD_SURFACE_NORMAL_OS) && defined(MOLD_SURFACE_NORMAL_WS)
// Preserve linear interpolation while sharing spare scalar slots. This keeps
// all surface fields plus custom data and an appearance within Mobile's budget.
varying vec4 mold_surface_normals_xy;
#define mold_normal_os vec3(mold_surface_normals_xy.xy, mold_gradient_and_coverage.z)
#define mold_normal_ws vec3(mold_surface_normals_xy.zw, mold_gradient_and_coverage.w)
#else
#ifdef MOLD_SURFACE_NORMAL_OS
varying vec3 mold_normal_os;
#endif
#ifdef MOLD_SURFACE_NORMAL_WS
varying vec3 mold_normal_ws;
#endif
#endif

#ifdef MOLD_SURFACE_ENABLED
// Normalize again after interpolation. Collapsed surfaces return finite zero.
vec3 mold_normalize_normal(vec3 value) {
    return value * inversesqrt(max(dot(value, value), 1e-30));
}
vec3 mold_transform_normal(mat4 transform, vec3 normal) {
    vec3 x = transform[0].xyz, y = transform[1].xyz, z = transform[2].xyz;
    vec3 transformed = cross(y, z) * normal.x + cross(z, x) * normal.y
        + cross(x, y) * normal.z;
    transformed *= dot(x, cross(y, z)) < 0.0 ? -1.0 : 1.0;
    return mold_normalize_normal(transformed);
}
// Use the original model-view matrix for billboard object coordinates, avoiding
// subtraction of large absolute world positions. Singular frames return zero.
vec3 mold_inverse_position(mat4 transform, vec3 position) {
    vec3 x = transform[0].xyz, y = transform[1].xyz, z = transform[2].xyz;
    vec3 delta = position - transform[3].xyz;
    float determinant = dot(x, cross(y, z));
    if (abs(determinant) < 1e-30) return vec3(0.0);
    return vec3(dot(cross(y, z), delta), dot(cross(z, x), delta),
        dot(cross(x, y), delta)) / determinant;
}
#endif

#ifdef MOLD_SURFACE_NORMAL
vec3 mold_ribbon_normal(vec3 position, vec3 previous, vec4 input_c0,
        vec4 input_c1, vec4 input_c2, vec2 input_uv, vec2 input_uv2,
        int vertex_id, mat4 model_view, mat4 model, mat4 projection,
        mat4 inverse_view, vec2 viewport, float padding_pixels) {
    int local_id = int(round(input_uv.x)) & 63;
#ifdef MOLD_GPU_POLYLINE
    local_id = vertex_id % mold_gpu_vertices_per_segment;
#endif
    int corner = local_id % 3;
    vec3 edges[2];
    for (int i = 0; i < 2; i++) {
        int peer_id = local_id - corner + (corner + i + 1) % 3;
        vec3 peer; vec2 peer_uv; vec4 c0, c1, c2;
#ifdef MOLD_GPU_POLYLINE
        vec4 color; vec3 author;
        mat4 peer_model_view = model_view;
        mold_gpu_vertex(vertex_id - local_id + peer_id, peer, color, peer_uv,
            c0, c1, c2, peer_model_view, model, projection, author);
#else
        int config = int(round(input_uv.x)) / 64 - 128;
        float scale = max(length(model[0].xyz), max(length(model[1].xyz), length(model[2].xyz)));
        mold_billboard_vertex(vec4(previous, 0.0), vec4(input_c1.xyz, input_c0.w),
            vec4(input_c2.xyz, input_c1.w), vec4(input_c0.xyz, 0.0),
            vec4(float(config & 3), input_uv.y, input_uv2.x, input_uv2.y), peer_id,
            (config >> 2) & 3, (config >> 4) & 3, input_c2.w, model_view, scale,
            abs(projection[3][3]) < 0.5, mold_stroke_near(projection), peer, peer_uv, c0, c1, c2);
#endif
        float pixels;
        float edge_scale = mold_polyline_raster_scale(peer, c0, c1, c2,
            mat4(1.0), projection, viewport, padding_pixels, pixels);
        peer.xy += c0.xy * (edge_scale - 1.0);
        // Work with view-space differences to retain small ribbons far away.
        edges[i] = mat3(inverse_view) * (peer - position);
    }
    // Godot's front faces are clockwise; the planar ribbon's authored normal is +Z.
    return mold_normalize_normal(-cross(edges[0], edges[1]));
}
#endif
#endif

// Package-owned processors. Define mold_custom_fragment between common and here.
#ifndef MOLD_SPATIAL_PROCESSORS_INCLUDED
#define MOLD_SPATIAL_PROCESSORS_INCLUDED
void vertex() {
#ifdef MOLD_SURFACE_ENABLED
    mat4 mold_original_model_view = MODELVIEW_MATRIX;
#endif
#ifdef MOLD_SURFACE_NORMAL
#ifdef MOLD_GPU_POLYLINE
    vec3 mold_input_vertex = vec3(0.0);
    vec4 mold_input_c0 = vec4(0.0), mold_input_c1 = vec4(0.0), mold_input_c2 = vec4(0.0);
    vec2 mold_input_uv = vec2(0.0), mold_input_uv2 = vec2(0.0);
#else
    vec3 mold_input_vertex = VERTEX;
    vec4 mold_input_c0 = CUSTOM0, mold_input_c1 = CUSTOM1, mold_input_c2 = CUSTOM2;
    vec2 mold_input_uv = UV, mold_input_uv2 = UV2;
#endif
#endif
#ifdef MOLD_GPU_POLYLINE
    vec4 gpu_custom0, gpu_custom1, gpu_custom2;
    vec3 gpu_author_position;
    mold_gpu_vertex(VERTEX_ID, VERTEX, COLOR, UV, gpu_custom0, gpu_custom1, gpu_custom2, MODELVIEW_MATRIX, MODEL_MATRIX, PROJECTION_MATRIX, gpu_author_position);
    NORMAL = vec3(0.0, 0.0, 1.0);
#endif
#ifdef MOLD_POLYGON
    mold_polygon_vertex(VERTEX, COLOR, UV, UV2);
    mold_polygon_position = VERTEX.xy;
    NORMAL = vec3(0.0, 0.0, 1.0);
#endif
    #ifdef MOLD_GPU_POLYLINE
    vec3 mold_author_position = gpu_author_position;
    bool mold_is_billboard = mold_gpu_geometry == 1;
#else
    vec3 mold_author_position = VERTEX;
    bool mold_is_billboard = UV.x >= 8192.0;
#endif
    vec4 mold_custom0 = CUSTOM0, mold_custom1 = CUSTOM1, mold_custom2 = CUSTOM2;
    if (UV.x >= 8192.0) {
        int config = int(round(UV.x)) / 64 - 128;
        vec4 a = vec4(CUSTOM1.xyz,CUSTOM0.w), b = vec4(CUSTOM2.xyz,CUSTOM1.w);
        mold_author_position = mold_stroke_start(int(round(UV.x)) & 63) ? a.xyz : b.xyz;
        vec4 metrics = vec4(float(config & 3),UV.y,UV2.x,UV2.y);
        float scale = max(length(MODEL_MATRIX[0].xyz),max(length(MODEL_MATRIX[1].xyz),length(MODEL_MATRIX[2].xyz)));
        mold_billboard_vertex(vec4(VERTEX,0.0),a,b,vec4(CUSTOM0.xyz,0.0),metrics,int(round(UV.x)) & 63,
            (config >> 2) & 3,(config >> 4) & 3,CUSTOM2.w,MODELVIEW_MATRIX,scale,
            abs(PROJECTION_MATRIX[3][3]) < 0.5,mold_stroke_near(PROJECTION_MATRIX),VERTEX,UV,mold_custom0,mold_custom1,mold_custom2);
        MODELVIEW_MATRIX = mat4(1.0);
        NORMAL = vec3(0.0,0.0,1.0);
    }

#ifdef MOLD_INSTANCED
    // Split the native index into half-float-exact chunks for Compatibility.
    // Ordinary batches have no custom data and continue to use INSTANCE_ID.
    int resolved_instance_index = INSTANCE_CUSTOM.z > 0.5
        ? int(INSTANCE_CUSTOM.x) + int(INSTANCE_CUSTOM.y) * 1024 : INSTANCE_ID;
    primary_color = mold_fetch(resolved_instance_index, 0);
    secondary_color = mold_fetch(resolved_instance_index, 1);
    shape_data = mold_fetch(resolved_instance_index, 2);
    dash_data = mold_fetch(resolved_instance_index, 3);
    mold_flags = mold_fetch(resolved_instance_index, 4);
    gradient_data = mold_fetch(resolved_instance_index, 5);
    lod_data = mold_fetch(resolved_instance_index, 6);
#endif
#ifdef MOLD_CUSTOM_DATA
#ifdef MOLD_INSTANCED
    mold_resolved_instance_index = resolved_instance_index;
#else
    // GPU polyline custom streams contain one record per material.
    mold_resolved_instance_index = 0;
#endif
#endif
    #ifdef MOLD_GPU_POLYLINE
    mold_vertex_color = COLOR;
#else
    mold_vertex_color = MOLD_IS_POLYLINE ? CUSTOM3 : COLOR;
#endif
    if (MOLD_IS_ROUNDED) mold_deform_rounded(shape_data, CUSTOM0, VERTEX, NORMAL);
    mold_torus_cap_or_line_pixel_coverage = 0.0;
    if (MOLD_IS_CAPSULE) VERTEX.y += sign(VERTEX.y) * shape_data.y;
    else if (MOLD_IS_TORUS) {
        bool cap_vertex = UV.x < 0.0 || UV.x > 1.0;
        if (cap_vertex) {
            float cap_progress = UV.x > 1.0 ? 1.0 : 0.0;
            float cap_angle = shape_data.z + shape_data.w * cap_progress;
            float cap_cos = cos(cap_angle);
            float cap_sin = sin(cap_angle);
            float cap_scale = shape_data.y / MOLD_TORUS_BASE_TUBE_RADIUS;
            float cap_cross_x =
                (VERTEX.x - MOLD_TORUS_BASE_MAJOR_RADIUS) * cap_scale;
            vec3 cap_position = vec3(
                0.5 - shape_data.y + cap_cross_x,
                VERTEX.y * cap_scale,
                0.0);
            VERTEX = vec3(
                cap_position.x * cap_cos - cap_position.z * cap_sin,
                cap_position.y,
                cap_position.x * cap_sin + cap_position.z * cap_cos);
            NORMAL = vec3(
                NORMAL.x * cap_cos - NORMAL.z * cap_sin,
                NORMAL.y,
                NORMAL.x * cap_sin + NORMAL.z * cap_cos);
            UV.x = fract(-cap_angle / MOLD_TAU + 1.0);
            mold_torus_cap_or_line_pixel_coverage = 1.0;
        } else {
            float span = clamp(shape_data.w, 0.0, MOLD_TAU);
            float major_angle = span >= MOLD_TAU
                ? -UV.x * MOLD_TAU
                : shape_data.z + span * (1.0 - UV.x);
            float minor_angle = UV.y * MOLD_TAU;
            vec3 radial = vec3(cos(major_angle), 0.0, sin(major_angle));
            vec3 tube_normal =
                radial * cos(minor_angle) + vec3(0.0, sin(minor_angle), 0.0);
            VERTEX = radial * (0.5 - shape_data.y) + tube_normal * shape_data.y;
            NORMAL = tube_normal;
            if (span < MOLD_TAU)
                UV.x = fract(-major_angle / MOLD_TAU + 1.0);
        }
    }
    mold_line_progress = 0.0;
    mold_line_across = 0.0;
    mold_line_edge = 0.0;
    mold_line_along = 0.0;
    mold_polyline_coord = vec4(0.0);
    if (MOLD_IS_LINE) {
        bool local_is_polyline = MOLD_IS_POLYLINE;
        bool is_planar_line = MOLD_IS_2D || local_is_polyline;
        bool local_aa = mold_local_aa_quality() > 0;
        if (is_planar_line) {
            // Preserve the quad's out-of-range support UVs until after its
            // analytic line bounds are established. Clamping at vertices
            // would interpolate the padding itself into dash progress.
            mold_line_progress = local_is_polyline ? clamp(UV.x, 0.0, 1.0) : UV.x;
            mold_line_across = (local_is_polyline ? clamp(UV.y, 0.0, 1.0) : UV.y) * 2.0 - 1.0;
            float padding_pixels = local_aa ? MOLD_AA_PADDING_PIXELS : 0.0;
            if (local_is_polyline) {
                vec2 extrusion = mold_custom0.xy;
                bool is_segment = mold_custom0.z < 0.5;
                float edge_scale = mold_polyline_raster_scale(VERTEX, mold_custom0,
                    mold_custom1, mold_custom2, MODELVIEW_MATRIX, PROJECTION_MATRIX,
                    VIEWPORT_SIZE, padding_pixels, mold_torus_cap_or_line_pixel_coverage);
                VERTEX.xy += extrusion * (edge_scale - 1.0);
                vec4 analytic_coord = mold_custom1;
                vec4 analytic_change = mold_custom2;
                if (is_segment) { analytic_coord.x = 0.0; analytic_change.x = 0.0; }
                mold_polyline_coord = analytic_coord + analytic_change * (edge_scale - 1.0);
                mold_line_along = mold_custom0.z;
                mold_line_edge = mold_polyline_coord.y;
            } else {
                vec3 center_view = (VIEW_MATRIX * MODEL_MATRIX[3]).xyz;
                vec3 length_view = (VIEW_MATRIX * vec4(MODEL_MATRIX[0].xyz, 0.0)).xyz;
                vec3 width_view = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xyz;
                vec3 anchor_view = center_view + length_view * (mold_line_progress - 0.5);
                if (MOLD_BILLBOARD) {
                    vec3 view_direction = PROJECTION_MATRIX[3][3] > 0.5
                        ? vec3(0.0, 0.0, -1.0) : anchor_view;
                    vec3 side_view = cross(view_direction, length_view);
                    float side_length = length(side_view);
                    if (side_length < 0.00001) {
                        side_view = cross(vec3(0.0, 0.0, -1.0), length_view);
                        side_length = length(side_view);
                    }
                    width_view = (side_length < 0.00001 ? vec3(1.0, 0.0, 0.0)
                        : side_view / side_length) * length(MODEL_MATRIX[1].xyz);
                }
                vec4 anchor_clip = PROJECTION_MATRIX * vec4(anchor_view, 1.0);
                float width_pixels = projected_pixel_distance(anchor_clip,
                    PROJECTION_MATRIX * vec4(anchor_view + width_view, 1.0), VIEWPORT_SIZE);
                mold_torus_cap_or_line_pixel_coverage = width_pixels;
                float length_pixels = projected_pixel_distance(
                    PROJECTION_MATRIX * vec4(center_view - length_view * 0.5, 1.0),
                    PROJECTION_MATRIX * vec4(center_view + length_view * 0.5, 1.0), VIEWPORT_SIZE);
                float width_scale = max(1.0, width_pixels + padding_pixels * 2.0)
                    / max(width_pixels, 0.00001);
            float length_scale = (length_pixels + padding_pixels * 2.0)
                / max(length_pixels, 0.00001);
            mold_line_along = (UV.x * 2.0 - 1.0) * length_scale;
            VERTEX.xy *= vec2(length_scale, width_scale);
            UV = (UV - vec2(0.5)) * vec2(length_scale, width_scale) + vec2(0.5);
            mold_line_edge = mold_line_across * width_scale;
            // The shared quad includes longitudinal support padding. Dash
            // progress must cover only the analytic line endpoints.
            mold_line_progress = mold_line_along * 0.5 + 0.5;
        }
        } else {
            float half_length = MOLD_IS_CAPSULE ? max(MOLD_CAPSULE_HALF_HEIGHT + shape_data.y, 0.00001) : 0.5;
            mold_line_progress = clamp(VERTEX.y / (2.0 * half_length) + 0.5, 0.0, 1.0);
            float raster_scale = mold_spatial_line_raster_scale(mold_line_progress,
                MODEL_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE,
                mold_torus_cap_or_line_pixel_coverage);
#ifdef MOLD_SURFACE_NORMAL
            NORMAL = mold_spatial_line_normal(VERTEX, NORMAL, half_length, raster_scale,
                MODEL_MATRIX, VIEW_MATRIX, PROJECTION_MATRIX, VIEWPORT_SIZE);
#endif
            VERTEX.xz *= raster_scale;
        }
    }
#ifdef MOLD_SURFACE_ENABLED
    vec3 mold_generated_position_view = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
#endif
#ifdef MOLD_SURFACE_NORMAL
    vec3 mold_generated_normal_world = mold_transform_normal(MODEL_MATRIX, NORMAL);
    if (mold_is_billboard) {
        mold_generated_normal_world = mold_ribbon_normal(VERTEX, mold_input_vertex,
            mold_input_c0, mold_input_c1, mold_input_c2, mold_input_uv, mold_input_uv2,
            VERTEX_ID, mold_original_model_view, MODEL_MATRIX, PROJECTION_MATRIX,
            INV_VIEW_MATRIX, VIEWPORT_SIZE, mold_local_aa_quality() > 0 ? MOLD_AA_PADDING_PIXELS : 0.0);
    }
#endif
    if (MOLD_BILLBOARD) {
        vec3 billboard_center_view = (VIEW_MATRIX * MODEL_MATRIX[3]).xyz;
        vec3 billboard_vertex_view;
        if (MOLD_IS_LINE) {
            vec3 billboard_tangent_view = (VIEW_MATRIX * vec4(MODEL_MATRIX[0].xyz, 0.0)).xyz;
            vec3 billboard_centerline_view = billboard_center_view + billboard_tangent_view * VERTEX.x;
            vec3 billboard_view_direction = PROJECTION_MATRIX[3][3] > 0.5
                ? vec3(0.0, 0.0, -1.0)
                : billboard_centerline_view;
            vec3 billboard_side_view = cross(billboard_view_direction, billboard_tangent_view);
            float billboard_side_length = length(billboard_side_view);
            if (billboard_side_length < 0.00001) {
                billboard_side_view = cross(vec3(0.0, 0.0, -1.0), billboard_tangent_view);
                billboard_side_length = length(billboard_side_view);
            }
            billboard_side_view = billboard_side_length < 0.00001
                ? vec3(1.0, 0.0, 0.0)
                : billboard_side_view / billboard_side_length;
            billboard_vertex_view = billboard_centerline_view
                + billboard_side_view * VERTEX.y * length(MODEL_MATRIX[1].xyz);
#ifdef MOLD_SURFACE_NORMAL
            mold_generated_normal_world = mold_normalize_normal(cross(
                mat3(INV_VIEW_MATRIX) * billboard_tangent_view,
                mat3(INV_VIEW_MATRIX) * billboard_side_view) * NORMAL.z);
#endif
        } else if (MOLD_BILLBOARD_FIXED_Y) {
            vec3 billboard_center_world = MODEL_MATRIX[3].xyz;
            vec3 billboard_facing_world = PROJECTION_MATRIX[3][3] > 0.5
                ? INV_VIEW_MATRIX[2].xyz
                : INV_VIEW_MATRIX[3].xyz - billboard_center_world;
            vec3 billboard_horizontal_world = vec3(
                billboard_facing_world.x, 0.0, billboard_facing_world.z);
            float billboard_horizontal_length = length(billboard_horizontal_world);
            vec3 billboard_right_world;
            if (billboard_horizontal_length < 0.00001) {
                billboard_right_world = vec3(MODEL_MATRIX[0].x, 0.0, MODEL_MATRIX[0].z);
                float billboard_right_length = length(billboard_right_world);
                billboard_right_world = billboard_right_length < 0.00001
                    ? vec3(1.0, 0.0, 0.0)
                    : billboard_right_world / billboard_right_length;
            } else {
                billboard_right_world = cross(
                    vec3(0.0, 1.0, 0.0),
                    billboard_horizontal_world / billboard_horizontal_length);
            }
            vec2 billboard_scale = vec2(
                length(MODEL_MATRIX[0].xyz),
                length(MODEL_MATRIX[1].xyz));
            vec3 billboard_vertex_world = billboard_center_world
                + billboard_right_world * VERTEX.x * billboard_scale.x
                + vec3(0.0, 1.0, 0.0) * VERTEX.y * billboard_scale.y;
            billboard_vertex_view = (VIEW_MATRIX * vec4(billboard_vertex_world, 1.0)).xyz;
#ifdef MOLD_SURFACE_NORMAL
            mold_generated_normal_world = mold_normalize_normal(
                cross(billboard_right_world, vec3(0.0, 1.0, 0.0)) * NORMAL.z);
#endif
        } else {
            vec2 billboard_scale = vec2(
                length(MODEL_MATRIX[0].xyz),
                length(MODEL_MATRIX[1].xyz));
            billboard_vertex_view = billboard_center_view
                + vec3(VERTEX.xy * billboard_scale, 0.0);
#ifdef MOLD_SURFACE_NORMAL
            mold_generated_normal_world = mold_normalize_normal(
                cross(INV_VIEW_MATRIX[0].xyz, INV_VIEW_MATRIX[1].xyz) * NORMAL.z);
#endif
        }
        POSITION = PROJECTION_MATRIX * vec4(billboard_vertex_view, 1.0);
#ifdef MOLD_SURFACE_ENABLED
        mold_generated_position_view = billboard_vertex_view;
#endif
    } else {
        POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
    }
#ifdef MOLD_SURFACE_POSITION_OS
    mold_position_os = mold_is_billboard || MOLD_BILLBOARD
        ? mold_inverse_position(mold_original_model_view, mold_generated_position_view) : VERTEX;
#endif
#ifdef MOLD_SURFACE_POSITION_WS
    mold_position_ws = mold_is_billboard || MOLD_BILLBOARD
        ? (INV_VIEW_MATRIX * vec4(mold_generated_position_view, 1.0)).xyz
        : (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
#endif
#ifdef MOLD_SURFACE_NORMAL_OS
    vec3 mold_object_normal = mold_is_billboard || MOLD_BILLBOARD
        ? mold_normalize_normal(transpose(mat3(MODEL_MATRIX)) * mold_generated_normal_world)
        : mold_normalize_normal(NORMAL);
#ifdef MOLD_SURFACE_NORMAL_WS
    mold_surface_normals_xy.xy = mold_object_normal.xy;
    mold_gradient_and_coverage.z = mold_object_normal.z;
#else
    mold_normal_os = mold_object_normal;
#endif
#endif
#ifdef MOLD_SURFACE_NORMAL_WS
#ifdef MOLD_SURFACE_NORMAL_OS
    mold_surface_normals_xy.zw = mold_generated_normal_world.xy;
    mold_gradient_and_coverage.w = mold_generated_normal_world.z;
#else
    mold_normal_ws = mold_generated_normal_world;
#endif
#endif
#ifdef MOLD_APPEARANCE
#ifdef MOLD_SURFACE
 mold_effect_position=VERTEX;
#elif defined(MOLD_PENCIL)
 // Project paper from authored world coordinates. Cached/GPU billboard polylines
 // produce view-space vertices; every other path retains object-space vertices.
 // Do not reconstruct from POSITION: generic billboards are camera-facing in
 // clip space, and using that position makes the paper grain follow the camera.
 vec3 effect_world=mold_is_billboard
  ? (INV_VIEW_MATRIX*vec4(VERTEX,1.0)).xyz
  : (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 mold_effect_paper=PencilPaper(effect_world);
#endif
#endif
    // Reuse polyline coordinates for deformed primitive-local position.
    if (int(round(gradient_data.w)) / 32 >= 100) mold_polyline_coord.xyz = VERTEX;
    mold_gradient_t = 0.0;
    if (packed_gradient(1, 8) == 1 && !MOLD_IS_POLYLINE) {
        int shape_kind = int(round(gradient_data.w)) / 32;
        vec3 center = vec3(0.0); vec3 half_extent = vec3(0.5);
        if (shape_kind == 125) { center.y = 0.25; half_extent.y = 0.25; }
        else if (shape_kind == 135) half_extent.y = max(0.0001, MOLD_CAPSULE_HALF_HEIGHT + shape_data.y);
        else if (shape_kind == 140) half_extent.y = max(0.0001, shape_data.y);
        vec3 local_gradient = packed_gradient(16, 2) == 0 ? transpose(mat3(MODEL_MATRIX)) * gradient_data.xyz : gradient_data.xyz;
        float half_range = max(dot(abs(local_gradient), half_extent), 0.00001);
        mold_gradient_t = clamp(dot((mold_is_billboard ? mold_author_position : VERTEX) - center, local_gradient) / (2.0 * half_range) + 0.5, 0.0, 1.0);
    }
    // Polyline UV.x already stores normalized cumulative local path distance.
    if (MOLD_IS_POLYLINE) mold_gradient_t = mold_line_progress;
}

void fragment() {
    vec2 coverage = mold_evaluate_coverage(UV, FRAGCOORD.xy);
    vec4 result = mold_evaluate_base_color(UV);
    mold_apply_appearance(UV, result, coverage.x);
#ifdef MOLD_CUSTOM_FRAGMENT
    mold_custom_fragment(UV, FRAGCOORD, result, coverage);
#endif
    result = mold_prepare_output(result, coverage, FRAGCOORD.xy);
#ifndef MOLD_RD_OUTPUT
    ALBEDO = mold_output_color(result.rgb);
#ifdef MOLD_WRITE_ALPHA
    ALPHA = result.a;
#endif
#endif
}
#endif

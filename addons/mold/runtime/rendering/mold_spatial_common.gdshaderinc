// Common declarations and fragment stages. Include before defining custom hooks.
#ifndef MOLD_SPATIAL_COMMON_INCLUDED
#define MOLD_SPATIAL_COMMON_INCLUDED
#ifndef MOLD_BLEND_MODE
#define MOLD_BLEND_MODE 0
#endif
#ifndef MOLD_COVERAGE_OUTPUT
#define MOLD_COVERAGE_OUTPUT false
#endif
#ifdef MOLD_INSTANCED
#ifndef MOLD_INSTANCE_SAMPLER_DECLARED
#define MOLD_INSTANCE_SAMPLER_DECLARED
uniform sampler2D mold_instance_data : filter_nearest, repeat_disable;
#endif
varying flat vec4 primary_color;
varying flat vec4 secondary_color;
varying flat vec4 shape_data;
varying flat vec4 dash_data;
varying flat vec4 mold_flags;
varying flat vec4 gradient_data;
varying flat vec4 lod_data;
#define emission_strength mold_flags.x
#define angular_data lod_data.zw
vec4 mold_fetch(int instance_id, int slot) {
    int linear_index = instance_id * 7 + slot;
    int width = textureSize(mold_instance_data, 0).x;
    return texelFetch(mold_instance_data, ivec2(linear_index % width, linear_index / width), 0);
}
#else
uniform vec4 primary_color = vec4(1.0);
uniform vec4 secondary_color = vec4(1.0);
uniform float emission_strength = 0.0;
uniform vec4 shape_data = vec4(0.0);
uniform vec4 dash_data = vec4(0.0);
uniform vec4 gradient_data = vec4(0.0, 1.0, 0.0, 0.0);
uniform vec2 angular_data = vec2(0.0, 6.28318530718);
#endif
uniform vec2 mold_viewport_size = vec2(1.0);
uniform bool mold_msaa_enabled = false;
// Shape flags have the same layout for uniforms and instance textures.
#ifndef MOLD_INSTANCED
uniform vec4 mold_flags = vec4(0.0);
#endif
#define MOLD_IS_2D (mold_flags.y > 0.5)
#define MOLD_IS_CAPSULE (mold_flags.z > 0.5 && mold_flags.z < 1.5)
#define MOLD_IS_TORUS (mold_flags.z > 1.5 && mold_flags.z < 2.5)
#define MOLD_IS_LINE ((int(round(mold_flags.w)) & 4) != 0)
#define MOLD_IS_POLYLINE ((int(round(mold_flags.w)) & 8) != 0)
#define MOLD_BILLBOARD ((int(round(mold_flags.w)) & 2) != 0)
#define MOLD_BILLBOARD_FIXED_Y ((int(round(mold_flags.w)) & 16) != 0)
#define MOLD_IS_ROUNDED (mold_flags.z > 2.5)
#define MOLD_CAPSULE_HALF_HEIGHT 1.0
// Pack interpolated scalars into two slots, leaving room for optional surface
// inputs on Mobile. Component interpolation is identical to scalar varyings.
varying vec4 mold_line_values;
#if defined(MOLD_SURFACE_NORMAL_OS) && defined(MOLD_SURFACE_NORMAL_WS)
// The spare components hold the two optional normal Z values.
varying vec4 mold_gradient_and_coverage;
#else
varying vec2 mold_gradient_and_coverage;
#endif
#define mold_gradient_t mold_gradient_and_coverage.x
#define mold_line_progress mold_line_values.x
#define mold_line_across mold_line_values.y
#define mold_line_edge mold_line_values.z
#define mold_line_along mold_line_values.w
varying vec4 mold_polyline_coord;
// These shape categories are mutually exclusive. Sharing the scalar keeps the
// mobile renderer below its varying-component limit.
#define mold_torus_cap_or_line_pixel_coverage mold_gradient_and_coverage.y
varying vec4 mold_vertex_color;
const float MOLD_TAU = 6.28318530718;
const float MOLD_TORUS_BASE_MAJOR_RADIUS = 0.375;
const float MOLD_TORUS_BASE_TUBE_RADIUS = 0.125;
const float MOLD_AA_PADDING_PIXELS = 1.0;

#include "mold_color_output.gdshaderinc"

#include "mold_evaluation.gdshaderinc"

#include "mold_rounded_primitive.gdshaderinc"
#include "mold_billboard_polyline.gdshaderinc"
#ifdef MOLD_GPU_POLYLINE
#include "mold_gpu_polyline.gdshaderinc"
// Only the spatial body uses these aliases; the helper above keeps its inputs.
#define CUSTOM0 gpu_custom0
#define CUSTOM1 gpu_custom1
#define CUSTOM2 gpu_custom2
#endif
#ifdef MOLD_POLYGON
#include "mold_polygon.gdshaderinc"
#endif
#include "mold_polyline_raster.gdshaderinc"
#include "mold_spatial_line.gdshaderinc"
#include "mold_spatial_surface.gdshaderinc"
#ifdef MOLD_APPEARANCE
#include "mold_appearance_uniforms.gdshaderinc"
#ifdef MOLD_SURFACE
varying vec3 mold_effect_position;
#ifdef MOLD_PAINT
#include "mold_paint_surface.gdshaderinc"
#else
#include "mold_pencil_surface.gdshaderinc"
#endif
#else
#ifdef MOLD_PAINT
#include "mold_paint_stroke.gdshaderinc"
#include "mold_paint_shape.gdshaderinc"
#else
#include "mold_pencil_stroke.gdshaderinc"
#include "mold_pencil_shape.gdshaderinc"
varying vec2 mold_effect_paper;
#endif
#endif
#endif

#ifdef MOLD_CUSTOM_DATA
#include "mold_instance_data.gdshaderinc"
varying flat int mold_resolved_instance_index;
// Raw streams are fetched only by effects that request them; no vec4 varyings.
vec4 mold_custom_data() { return mold_custom_data_fetch(mold_resolved_instance_index); }
vec4 mold_custom_data_2() { return mold_custom_data_2_fetch(mold_resolved_instance_index); }
#endif

// x is analytic coverage; y is thin-line opacity. Keep these separate until output.
vec2 mold_evaluate_coverage(vec2 uv, vec2 fragment_position) {
#ifdef MOLD_INSTANCED
    float lod_threshold = dither_threshold(fragment_position);
    if (lod_data.y > 0.5) lod_threshold = 1.0 - lod_threshold;
    if (lod_data.x < 0.99999 && lod_data.x < lod_threshold) discard;
#endif
    bool local_is_line = MOLD_IS_LINE;
    bool local_is_polyline = MOLD_IS_POLYLINE;
    bool is_planar_line = local_is_line && (MOLD_IS_2D || local_is_polyline);
    bool rounded_line_2d = is_planar_line && !local_is_polyline
        && shape_data.x > 1.5 && shape_data.x < 2.5;
    bool local_aa = mold_local_aa_quality() > 0;
    float coverage = rounded_line_2d ? shape_coverage(uv, shape_data, dash_data)
        : is_planar_line ? 1.0
        : (MOLD_IS_2D ? shape_coverage(uv, shape_data, dash_data) : 1.0);
    #ifdef MOLD_POLYGON
    coverage *= mold_polygon_coverage();
#endif
    float thin_line_coverage = 1.0;
    if (local_is_line) {
        vec4 line_dash = dash_data;
        if (!local_is_polyline) coverage *= dashed_mask(mold_line_progress, mold_line_across, line_dash);
        else if (line_dash.x > 0.0) coverage *= line_dash.x >= 1.0 ? 0.0 : dash_aa(1.0-line_dash.x-mold_line_progress);
        if (is_planar_line) {
            if (local_is_polyline) {
                float edge = mold_line_along > 1.5 ? length(mold_polyline_coord.xy) : mold_polyline_coord.y;
                float pixel_coverage = polyline_pixel_coverage(edge);
                thin_line_coverage = clamp(pixel_coverage, 0.0, 1.0);
                if (local_aa) {
                    float outline = line_local_aa(edge, pixel_coverage);
                    float caps = min(polyline_cap_aa(mold_polyline_coord.z, pixel_coverage),
                        polyline_cap_aa(mold_polyline_coord.w, pixel_coverage));
                    coverage *= min(outline, caps);
                } else if (mold_line_along > 1.5)
                    coverage *= step(length(mold_polyline_coord.xy), 1.0);
            } else {
                float pixel_coverage = mold_torus_cap_or_line_pixel_coverage;
                thin_line_coverage = clamp(pixel_coverage, 0.0, 1.0);
                if (local_aa && !rounded_line_2d) {
                    coverage *= line_local_aa(mold_line_edge, pixel_coverage);
                    coverage *= line_local_aa(mold_line_along, pixel_coverage);
                } else if (!rounded_line_2d)
                    coverage *= step(abs(mold_line_edge), 1.0) * step(abs(mold_line_along), 1.0);
                coverage *= angular_mask(uv * 2.0 - vec2(1.0), angular_data.x, angular_data.y);
            }
        } else thin_line_coverage = clamp(
            mold_torus_cap_or_line_pixel_coverage, 0.0, 1.0);
    }
    if (MOLD_IS_TORUS) {
        float span = clamp(shape_data.w, 0.0, MOLD_TAU);
        if (mold_torus_cap_or_line_pixel_coverage > 0.5) {
            if (span <= 0.0 || span >= MOLD_TAU) coverage = 0.0;
        } else if (span <= 0.0) coverage = 0.0;
    }
    return vec2(coverage, thin_line_coverage);
}

vec4 mold_evaluate_base_color(vec2 uv) {
    #ifdef MOLD_POLYGON
    return evaluated_color(uv, gradient_data.xy) * mold_polygon_color(mold_polygon_position);
#else
    return evaluated_color(uv, gradient_data.xy) * mold_vertex_color;
#endif
}

void mold_apply_appearance(vec2 uv, inout vec4 result, inout float coverage) {
#ifdef MOLD_APPEARANCE
#ifdef MOLD_SURFACE
#ifdef MOLD_PAINT
#ifndef MOLD_COVERAGE_ONLY
 MoldPaintSurface(mold_effect_position,result);
#endif
#else
 MoldPencilSurface(mold_effect_position,result,coverage);
#endif
#else
#ifdef MOLD_PAINT
#ifdef MOLD_POLYGON
 MoldPaintFill(mold_polygon_position,vec3(0.0),result,coverage);
#else
 if(!MOLD_IS_LINE && MOLD_IS_2D) MoldPaintShape(uv,shape_data,result,coverage);
 else MoldPaintStroke(vec2(mold_line_progress,mold_line_across),result,coverage);
#endif
#else
#ifdef MOLD_POLYGON
 MoldPencilFill(mold_polygon_position,mold_effect_paper,result,coverage);
#else
 if(!MOLD_IS_LINE && MOLD_IS_2D) MoldPencilShape(uv,shape_data,mold_effect_paper,result,coverage);
 else MoldPencilStroke(vec2(mold_line_progress,mold_line_across),mold_effect_paper,mold_vertex_color.a,result,coverage);
#endif
#endif
#endif
#endif
}

// Applies Godot blend/coverage policy without writing ALPHA or encoding RGB.
vec4 mold_prepare_output(vec4 result, vec2 coverage_values, vec2 fragment_position) {
    float coverage = coverage_values.x;
    float thin_line_coverage = coverage_values.y;
    if (MOLD_BLEND_MODE == 4) {
        if (coverage * thin_line_coverage * result.a < dither_threshold(fragment_position)) discard;
        result.a = 1.0;
    } else if (MOLD_BLEND_MODE == 0) {
        if (MOLD_COVERAGE_OUTPUT) {
            result.a *= coverage * thin_line_coverage;
            if (result.a <= 0.000001) discard;
        } else {
            if (thin_line_coverage < 0.99999) {
                if (coverage * thin_line_coverage * result.a < dither_threshold(fragment_position)) discard;
            } else if (coverage < 0.5) discard;
            result.a = 1.0;
        }
    } else {
        result.a *= coverage * thin_line_coverage;
        if (result.a <= 0.000001) discard;
    }
    return result;
}
#endif

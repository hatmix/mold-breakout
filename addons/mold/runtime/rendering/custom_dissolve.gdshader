shader_type spatial;
render_mode unshaded, cull_back;
#define MOLD_INSTANCED
#define MOLD_BLEND_MODE 0
#define MOLD_COVERAGE_OUTPUT false
#define MOLD_CUSTOM_DATA
#define MOLD_CUSTOM_FRAGMENT
#define MOLD_SURFACE_POSITION_OS
#define MOLD_SURFACE_NORMAL_OS
#include "mold_spatial_common.gdshaderinc"
// 3D gradient Perlin noise (not interpolated value noise). No texture required.
vec3 dissolve_gradient(vec3 cell) {
    vec3 h = vec3(dot(cell, vec3(127.1,311.7,74.7)),
                  dot(cell, vec3(269.5,183.3,246.1)),
                  dot(cell, vec3(113.5,271.9,124.6)));
    vec3 g = fract(sin(h) * 43758.5453) * 2.0 - 1.0;
    return g / max(length(g), 0.0001);
}
float dissolve_perlin(vec3 p) {
    vec3 cell = floor(p);
    vec3 f = fract(p);
    vec3 u = f*f*f*(f*(f*6.0-15.0)+10.0);
    float n000 = dot(dissolve_gradient(cell), f);
    float n100 = dot(dissolve_gradient(cell+vec3(1,0,0)), f-vec3(1,0,0));
    float n010 = dot(dissolve_gradient(cell+vec3(0,1,0)), f-vec3(0,1,0));
    float n110 = dot(dissolve_gradient(cell+vec3(1,1,0)), f-vec3(1,1,0));
    float n001 = dot(dissolve_gradient(cell+vec3(0,0,1)), f-vec3(0,0,1));
    float n101 = dot(dissolve_gradient(cell+vec3(1,0,1)), f-vec3(1,0,1));
    float n011 = dot(dissolve_gradient(cell+vec3(0,1,1)), f-vec3(0,1,1));
    float n111 = dot(dissolve_gradient(cell+vec3(1,1,1)), f-vec3(1,1,1));
    return clamp(0.5 + 0.5 * mix(
        mix(mix(n000,n100,u.x),mix(n010,n110,u.x),u.y),
        mix(mix(n001,n101,u.x),mix(n011,n111,u.x),u.y),u.z), 0.0, 1.0);
}

// Mold supplies geometry, shape/LOD coverage, linear color and final output.
void mold_custom_fragment(vec2 uv, vec4 fragment_coord, inout vec4 color, inout vec2 coverage) {
    vec4 shader_data = mold_custom_data();
    vec4 highlight_data = mold_custom_data_2();
    // x = progress, y = frequency, z = seed, w = edge width.
    float progress = clamp(shader_data.x, 0.0, 1.0);
    if (progress >= 1.0) discard;
    vec3 p = mold_position_os * max(shader_data.y, 0.001)
        + shader_data.z * vec3(1.0, 1.37, 2.11);
    float remaining = dissolve_perlin(p) - progress;
    if (progress > 0.0 && remaining < 0.0) discard;
    float edge = 0.0;
    if (progress > 0.0 && shader_data.w > 0.0)
        edge = 1.0 - smoothstep(0.0, shader_data.w, remaining);
    float shade = 0.4 + 0.6 * max(dot(mold_normalize_normal(mold_normal_os),
        normalize(vec3(-0.4, 0.7, 0.6))), 0.0);
    // Shade and interpolate in linear RGB; Mold converts once at final output.
    color.rgb = mix(color.rgb * shade,
        max(highlight_data.rgb, vec3(0.0)) * max(highlight_data.w, 0.0), edge);
}
#include "mold_spatial_processors.gdshaderinc"

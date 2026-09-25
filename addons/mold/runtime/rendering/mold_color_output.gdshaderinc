// Shared linear-to-render-target conversion, also used by low-level custom shaders.
#ifndef MOLD_COLOR_OUTPUT_INCLUDED
#define MOLD_COLOR_OUTPUT_INCLUDED
vec3 mold_linear_to_srgb(vec3 color) {
    vec3 lower = color * 12.92;
    vec3 higher = 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
    return mix(higher, lower, lessThanEqual(color, vec3(0.0031308)));
}
vec3 mold_output_color(vec3 linear_color) {
    return OUTPUT_IS_SRGB ? mold_linear_to_srgb(linear_color) : linear_color;
}
#endif

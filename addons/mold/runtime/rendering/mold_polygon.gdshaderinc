// One RGBA32F position texel and one color texel per contour vertex.
// CPU meshes bake positions/colors; GPU carriers reference points through UV2.x.
uniform sampler2D mold_polygon_points : filter_nearest, repeat_disable;
uniform int mold_polygon_count = 0;
uniform int mold_polygon_aa_quality = 2;
uniform bool mold_polygon_gpu = false;
uniform bool mold_polygon_uniform_color = false;
uniform vec4 mold_polygon_constant_color = vec4(1.0);
uniform vec4 mold_polygon_bounds = vec4(0.0, 0.0, 1.0, 1.0);
varying vec2 mold_polygon_position;
vec4 mold_polygon_fetch(int index) {
    int width = textureSize(mold_polygon_points, 0).x;
    return texelFetch(mold_polygon_points, ivec2(index % width, index / width), 0);
}
void mold_polygon_vertex(inout vec3 position, inout vec4 color, inout vec2 uv, vec2 reference) {
    if (mold_polygon_gpu) {
        int point = int(round(reference.x));
        position = mold_polygon_fetch(point * 2).xyz;
        color = mold_polygon_fetch(point * 2 + 1);
    }
    uv = (position.xy - mold_polygon_bounds.xy) / max(mold_polygon_bounds.zw, vec2(0.00001));
}
float mold_polygon_coverage() {
    if (mold_polygon_aa_quality == 0) return 1.0;
    // Filter only the authored boundary, never tessellation diagonals. All triangles
    // evaluate the same field, including triangles that touch a boundary only at a vertex.
    float distance_to_edge = 1e20;
    vec2 a = mold_polygon_fetch((mold_polygon_count - 1) * 2).xy;
    for (int i = 0; i < mold_polygon_count; i++) {
        vec2 b = mold_polygon_fetch(i * 2).xy;
        vec2 edge = b - a;
        float t = clamp(dot(mold_polygon_position - a, edge) / max(dot(edge, edge), 1e-20), 0.0, 1.0);
        distance_to_edge = min(distance_to_edge, length(mold_polygon_position - a - t * edge));
        a = b;
    }
    // Inward one-pixel filter: no overlapping fringe geometry, including concave tips.
    float width = max(mold_partial_derivative(distance_to_edge), 0.00001);
    return mold_aa(-distance_to_edge + width * 0.5);
}

// Mean-value coordinates (Hormann/Floater): interpolate over the entire contour,
// independently of tessellation. Signed half angles also support concave contours.
vec4 mold_polygon_color(vec2 position) {
    if (mold_polygon_uniform_color) return mold_polygon_constant_color;
    vec4 weighted_color = vec4(0.0);
    float total_weight = 0.0;
    vec2 a = mold_polygon_fetch((mold_polygon_count - 1) * 2).xy - position;
    vec4 color_a = mold_polygon_fetch((mold_polygon_count - 1) * 2 + 1);
    float radius_a = length(a);
    for (int i = 0; i < mold_polygon_count; i++) {
        vec2 b = mold_polygon_fetch(i * 2).xy - position;
        vec4 color_b = mold_polygon_fetch(i * 2 + 1);
        float radius_b = length(b);
        if (radius_a <= 1e-20) return color_a;
        if (radius_b <= 1e-20) return color_b;
        vec2 unit_a = a / radius_a;
        vec2 unit_b = b / radius_b;
        float cosine = clamp(dot(unit_a, unit_b), -1.0, 1.0);
        float sine = unit_a.x * unit_b.y - unit_a.y * unit_b.x;
        // The edge limit avoids the half-angle singularity at pi. Beyond an edge's
        // endpoints cosine is positive, so collinear extensions do not snap colors.
        if (cosine < 0.0 && abs(sine) < 1e-6)
            return mix(color_a, color_b, radius_a / (radius_a + radius_b));
        float tangent = cosine > -0.5 ? sine / (1.0 + cosine) : (1.0 - cosine) / sine;
        float weight_a = tangent / radius_a;
        float weight_b = tangent / radius_b;
        weighted_color += color_a * weight_a + color_b * weight_b;
        total_weight += weight_a + weight_b;
        a = b; color_a = color_b; radius_a = radius_b;
    }
    // For a valid simple contour and an interior point the signed sum is nonzero.
    return weighted_color / total_weight;
}

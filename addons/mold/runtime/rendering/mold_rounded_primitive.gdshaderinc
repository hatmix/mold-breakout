// Rounded templates encode a reference offset of 0.25 on every axis.
// Kind 3 stores normalized local radii in shape_data.yzw; kind 4 stores
// pyramid parameters. CUSTOM0.xyz preserves the template normal without
// Godot's NORMAL compression.
// Call before model/view transforms. UVs remain attached to the template.
void mold_deform_rounded(vec4 shape, vec4 direction, inout vec3 vertex, inout vec3 normal) {
    if (shape.x > 3.5) {
        // Pyramid: roundness, height/diameter, cos(pi/sides). Insetting all
        // faces is a homothety about the incenter. Roundness 1 is the insphere.
        float aspect = max(shape.z, 1e-20);
        float apothem = 0.5 * shape.w;
        float slant = length(vec2(aspect, apothem));
        float center_height = apothem / (slant + apothem);
        vec3 scale = vec3(1.0, aspect, 1.0);
        vec3 support = vertex * 2.0 - direction.xyz * 0.5;
        vec3 sphere_normal = normalize(direction.xyz / scale);
        vec3 incenter = vec3(0.0, -0.5 + center_height, 0.0);
        vec3 radius = vec3(aspect * center_height, center_height, aspect * center_height);
        vertex = mix(support, incenter, shape.y) + sphere_normal * radius * shape.y;
        normal = normalize(direction.xyz);
        return;
    }
    vec3 radii = shape.yzw;
    vec3 center = vertex - direction.xyz * 0.25;
    vertex = center * (vec3(2.0) - 4.0 * radii) + direction.xyz * radii;
    vec3 safe_radii = max(radii, vec3(1e-30));
    float smallest = min(safe_radii.x, min(safe_radii.y, safe_radii.z));
    normal = normalize(direction.xyz * (smallest / safe_radii));
}

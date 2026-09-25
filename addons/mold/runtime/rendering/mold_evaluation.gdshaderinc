#include "mold_ellipse.gdshaderinc"
int mold_local_aa_quality() {
	int flags = int(round(mold_flags.w));
	return (flags & 1) == 0 ? 0 : ((flags & 32) != 0 ? 2 : 1);
}

float mold_partial_derivative(float value) {
	if (mold_local_aa_quality() == 1) return fwidth(value);
	vec2 derivative = vec2(dFdx(value), dFdy(value));
	return length(derivative);
}

float mold_aa(float d) {
	if (mold_local_aa_quality() == 0) return step(d, 0.0);
	float width = max(mold_partial_derivative(d), 0.00001);
	return clamp(0.5 - d / width, 0.0, 1.0);
}

float line_local_aa(float coordinate, float pixel_coverage) {
    if (mold_local_aa_quality() == 0) return step(abs(coordinate), 1.0);
	float derivative = max(mold_partial_derivative(coordinate), 0.00001);
	float signed_distance = abs(coordinate) - 1.0;
	float aa_offset = clamp(pixel_coverage / 1.1, 0.0, 1.0) * 0.5;
	return 1.0 - clamp(signed_distance / derivative + aa_offset, 0.0, 1.0);
}

// Polyline support meshes contain centerline vertices whose extrusion is zero,
// so recover the full stroke width from the analytic edge coordinate.
float polyline_pixel_coverage(float edge) {
	vec2 derivative = vec2(dFdx(edge), dFdy(edge));
	return 2.0 / max(length(derivative), 0.00001);
}

float polyline_cap_aa(float coordinate, float pixel_coverage) {
    if (mold_local_aa_quality() == 0) return step(coordinate, 1.0);
    float derivative = max(mold_partial_derivative(coordinate), 0.00001);
    float offset = clamp(pixel_coverage / 1.1, 0.0, 1.0) * 0.5;
    return 1.0 - clamp((coordinate - 1.0) / derivative + offset, 0.0, 1.0);
}

// Editor-authored nodes live under a 2x2 staging viewport, not the 3D view.
// Pass VIEWPORT_SIZE from vertex() so AA follows the viewport rendering this mesh.
float projected_pixel_distance(vec4 from_clip, vec4 to_clip, vec2 viewport_size) {
	vec2 from_ndc = from_clip.xy / max(abs(from_clip.w), 0.00001);
	vec2 to_ndc = to_clip.xy / max(abs(to_clip.w), 0.00001);
	return length((to_ndc - from_ndc) * viewport_size * 0.5);
}

float box_distance(vec2 p) { return max(abs(p.x), abs(p.y)) - 1.0; }

float rounded_box_distance(vec2 p, float roundness) {
	float radius = clamp(roundness, 0.0, 1.0);
	vec2 q = abs(p) - (vec2(1.0) - vec2(radius));
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

vec2 local_rectangle_extent(float aspect_marker) {
	float aspect = max(-aspect_marker, 0.00001);
	return aspect >= 1.0 ? vec2(aspect, 1.0) : vec2(1.0, 1.0 / aspect);
}

float local_rounded_box_distance(vec2 p, float aspect_marker, float roundness) {
	vec2 extent = local_rectangle_extent(aspect_marker);
	float radius = clamp(roundness, 0.0, 1.0);
	vec2 q = abs(p * extent) - (extent - vec2(radius));
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
}

float polygon_distance(vec2 p, float sides) {
	float angle = atan(p.x, -p.y);
	float sector = MOLD_TAU / max(sides, 3.0);
	return cos(floor(0.5 + angle / sector) * sector - angle) * length(p) / cos(3.14159265359 / max(sides, 3.0)) - 1.0;
}

float rounded_polygon(vec2 p, float sides, float roundness) {
	roundness = clamp(roundness, 0.0, 1.0);
	if (roundness <= 0.00001) return mold_aa(polygon_distance(p, sides));
	float count = floor(max(abs(sides), 3.0));
	float full_angle = MOLD_TAU / count;
	float half_angle = full_angle * 0.5;
	float diagonal = 1.0 / cos(half_angle);
	float chamfer = max(roundness * half_angle, 0.00001);
	float remaining = half_angle - chamfer;
	float ratio = tan(remaining) / tan(half_angle);
	vec2 center = vec2(cos(half_angle), sin(half_angle)) * ratio * diagonal;
	float distance_a = length(center);
	float distance_b = 1.0 - center.x;
	p *= diagonal;
	vec2 polar = vec2(atan(p.y, p.x), length(p));
	polar.x += 7.85398163397;
	polar.x = abs(mod(polar.x + half_angle, full_angle) - half_angle);
	p = vec2(cos(polar.x), sin(polar.x)) * polar.y;
	float angle_ratio = 1.0 - (polar.x - remaining) / chamfer;
	float distance_c = sqrt(distance_a * distance_a + distance_b * distance_b - 2.0 * distance_a * distance_b * cos(3.14159265359 - half_angle * angle_ratio));
	float normalized = p.x;
	if ((half_angle - polar.x) < chamfer) normalized = polar.y / max(distance_c, 0.00001);
	return mold_aa(normalized - 1.0);
}

float angular_mask(vec2 p, float start, float span) {
	span = clamp(span, 0.0, MOLD_TAU);
	if (span >= MOLD_TAU - 0.00001) return 1.0;
	if (span <= 0.00001) return 0.0;
	float angle = mod(atan(p.x, p.y) - start + MOLD_TAU * 2.0, MOLD_TAU);
	float delta = abs(mod(angle - span * 0.5 + 3.14159265359, MOLD_TAU) - 3.14159265359);
	return mold_aa((delta - span * 0.5) * max(length(p), 0.00001));
}

float angular_progress(vec2 p, float start, float span) {
	span = max(clamp(span, 0.0, MOLD_TAU), 0.00001);
	float angle = mod(atan(p.x, p.y) - start + MOLD_TAU * 2.0, MOLD_TAU);
	return clamp(angle / span, 0.0, 1.0);
}

float dash_aa(float signed_distance) {
	if (mold_local_aa_quality() == 0) return step(0.0, signed_distance);
	float width = max(mold_partial_derivative(signed_distance), 0.00001);
	return clamp(signed_distance / width + 0.5, 0.0, 1.0);
}

float dash_repeat_span(vec4 dash) {
	return dash.x;
}

float dash_shape_type(vec4 dash) {
	float code = dash.y;
	return code < 0.25 ? 0.0 : (code < 0.55 ? 1.0 : 2.0);
}

float dash_shape_modifier(vec4 dash) {
	float type = dash_shape_type(dash);
	float center = 0.1 + type * 0.3;
	return clamp((dash.y - center) / 0.075, -1.0, 1.0);
}

float dash_segment_mask(float progress, float across, vec4 dash) {
	float total = dash_repeat_span(dash);
	if (total <= 0.0) return 1.0;
	float visible_ratio = 1.0 - clamp(dash.z, 0.0, 1.0);
	if (visible_ratio >= 0.99999) return 1.0;
	across = clamp(across, -1.0, 1.0);
	float type = dash_shape_type(dash);
	float modifier = dash_shape_modifier(dash);
	float coordinate = progress * total + dash.w + (1.0 - visible_ratio) * 0.5;
	float phase_per_across = fwidth(coordinate) / max(fwidth(across), 0.00001);
	if (type < 0.5)
		coordinate += modifier * across * visible_ratio * 0.25;
	else if (type < 1.5)
		coordinate += abs(across) * phase_per_across * modifier;
	float phase = fract(coordinate);
	float half_visible = visible_ratio * 0.5;
	float signed_distance = half_visible - abs(phase - 0.5);
	if (type > 1.5) {
		float cap = clamp(phase_per_across, 0.0, half_visible);
		float profile = sqrt(max(1.0 - across * across, 0.0));
		signed_distance = half_visible - cap * (1.0 - profile) - abs(phase - 0.5);
	}
	return dash_aa(signed_distance);
}

float dashed_mask(float progress, float across, vec4 dash) {
	if (dash_repeat_span(dash) <= 0.0) return 1.0;
	return dash_segment_mask(progress, across, dash);
}

float rectangle_perimeter_progress(vec2 uv, vec2 rim_thickness) {
	vec2 distance_from_outer = min(uv, vec2(1.0) - uv);
	vec2 edge_depth = distance_from_outer / max(rim_thickness, vec2(0.00001));
	vec2 extent = 1.0 / max(rim_thickness, vec2(0.00001));
	float perimeter = max(2.0 * (extent.x + extent.y), 0.00001);
	if (edge_depth.x < edge_depth.y)
		return uv.x < 0.5 ? (2.0 * extent.x + extent.y + (1.0 - uv.y) * extent.y) / perimeter
			: (extent.x + uv.y * extent.y) / perimeter;
	return uv.y < 0.5 ? uv.x * extent.x / perimeter
		: (extent.x + extent.y + (1.0 - uv.x) * extent.x) / perimeter;
}

float rectangle_rim_across(vec2 uv, vec2 rim_thickness) {
	vec2 distance_from_outer = min(uv, vec2(1.0) - uv);
	vec2 edge_depth = distance_from_outer / max(rim_thickness, vec2(0.00001));
	float depth = edge_depth.x < edge_depth.y ? edge_depth.x : edge_depth.y;
	return clamp(depth * 2.0 - 1.0, -1.0, 1.0);
}

float local_rectangle_rim_across(vec2 uv, vec4 shape) {
	vec2 p = uv * 2.0 - 1.0;
	float distance_to_outer = local_rounded_box_distance(p, shape.y, shape.w);
	float thickness = max(shape.z * 2.0, 0.00001);
	return clamp((-distance_to_outer / thickness) * 2.0 - 1.0, -1.0, 1.0);
}

float local_rectangle_rim_coverage(vec2 uv, vec4 shape, vec4 dash) {
	vec2 p = uv * 2.0 - 1.0;
	vec2 extent = local_rectangle_extent(shape.y);
	float distance_to_outer = local_rounded_box_distance(p, shape.y, shape.w);
	float thickness = max(shape.z * 2.0, 0.00001);
	float outer = mold_aa(distance_to_outer);
	float inner = mold_aa(distance_to_outer + thickness);
	vec2 rim = clamp(vec2(shape.z) / extent, vec2(0.00001), vec2(0.5));
	return clamp(outer - inner, 0.0, 1.0) * dashed_mask(
		rectangle_perimeter_progress(uv, rim),
		local_rectangle_rim_across(uv, shape), dash);
}

float polygon_perimeter_progress(vec2 p, float sides) {
	float angle = atan(p.x, -p.y);
	float count = max(sides, 3.0);
	float sector = MOLD_TAU / count;
	float edge = floor(angle / sector + 0.5);
	float along = tan(angle - edge * sector) / max(tan(sector * 0.5), 0.00001) * 0.5 + 0.5;
	return fract((edge + clamp(along, 0.0, 1.0)) / count);
}

float disc_rim_rim_across(vec2 p, float thickness) {
	float depth = (1.0 - length(p)) / max(thickness, 0.00001);
	return clamp(depth * 2.0 - 1.0, -1.0, 1.0);
}

float polygon_rim_across(vec2 p, float sides, float thickness) {
	float depth = -polygon_distance(p, sides) / max(thickness, 0.00001);
	return clamp(depth * 2.0 - 1.0, -1.0, 1.0);
}

int packed_gradient(int divisor, int modulus) {
	return (int(round(gradient_data.w)) / divisor) % modulus;
}

vec3 oklab_to_linear(vec3 c) {
	vec3 lms = vec3(c.x + 0.3963377774 * c.y + 0.2158037573 * c.z, c.x - 0.1055613458 * c.y - 0.0638541728 * c.z, c.x - 0.0894841775 * c.y - 1.2914855480 * c.z);
	lms = lms * lms * lms;
	return vec3(4.0767416621 * lms.x - 3.3077115913 * lms.y + 0.2309699292 * lms.z, -1.2684380046 * lms.x + 2.6097574011 * lms.y - 0.3413193965 * lms.z, -0.0041960863 * lms.x - 0.7034186147 * lms.y + 1.7076147010 * lms.z);
}

float radial_bounds_progress(vec2 uv, vec4 shape) {
 if(shape.x>10.5) {
  float d=mold_ellipse_nearest((uv*2.0-1.0)*(shape.yz+vec2(shape.w)),shape.yz).x;
  return clamp(0.5+0.5*d/max(shape.w,1e-8),0.0,1.0);
 }
	vec2 p = uv * 2.0 - 1.0; float kind = shape.x;
	if (kind < 2.5) return clamp(max(abs(p.x), abs(p.y)), 0.0, 1.0);
	if (kind < 4.5) {
		float across = shape.y < 0.0
			? local_rectangle_rim_across(uv, shape)
			: rectangle_rim_across(uv, vec2(shape.y, shape.z));
		return clamp((1.0 - across) * 0.5, 0.0, 1.0);
	}
	if (kind < 5.5) return clamp(length(p), 0.0, 1.0);
	if (kind < 6.5) return clamp((1.0 - disc_rim_rim_across(p, shape.z)) * 0.5, 0.0, 1.0);
	if (kind < 8.5) return clamp(polygon_distance(p, shape.y) + 1.0, 0.0, 1.0);
	return clamp((1.0 - polygon_rim_across(p, shape.y, shape.z)) * 0.5, 0.0, 1.0);
}

float radial_progress(vec2 uv, vec4 shape, vec2 extent) {
	vec2 p = uv * 2.0 - 1.0; float kind = shape.x;
	if (kind < 4.5 || kind > 6.5) return clamp(length(p * extent) / max(max(extent.x, extent.y), 0.00001), 0.0, 1.0);
	return clamp(length(p), 0.0, 1.0);
}

float spatial_color_progress(int color_mode, vec3 p) {
	int kind = int(round(gradient_data.w)) / 32;
	if (color_mode == 4) {
		// Local +X toward +Z, around +Y. Torus arcs fit their authored range.
		if (dot(p.xz, p.xz) < 0.0000000001) return 0.0;
		float start = kind == 140 ? shape_data.z : 0.0;
		float span = kind == 140 ? shape_data.w : MOLD_TAU;
		float angle = mod(atan(p.z, p.x) - start + MOLD_TAU * 2.0, MOLD_TAU);
		if (angle > MOLD_TAU - 0.00001) angle = 0.0;
		return clamp(angle / max(span, 0.00001), 0.0, 1.0);
	}
	if (color_mode == 3 && kind == 140) {
		float tube_radius = shape_data.y;
		return clamp((length(p.xz) - (0.5 - 2.0 * tube_radius))
			/ max(2.0 * tube_radius, 0.00001), 0.0, 1.0);
	}
	// Bounds mode intentionally uses the same center distance on other solids.
	vec3 half_extent = vec3(0.5);
	if (kind == 135) half_extent.y = max(0.00001, 1.0 + shape_data.y);
	else if (kind == 140) half_extent.y = shape_data.y;
	vec3 extent = half_extent * gradient_data.xyz;
	return clamp(length(p * gradient_data.xyz)
		/ max(max(extent.x, max(extent.y, extent.z)), 0.00001), 0.0, 1.0);
}

float color_progress(vec2 uv, vec2 extent) {
	int color_mode = packed_gradient(1, 8);
	if (int(round(gradient_data.w)) / 32 >= 100 && color_mode >= 2)
		return spatial_color_progress(color_mode, mold_polyline_coord.xyz);
	if (color_mode == 2) return radial_progress(uv, shape_data, extent);
	if (color_mode == 3) return radial_bounds_progress(uv, shape_data);
	if (color_mode == 4) {
		if (shape_data.x > 10.5) return angular_progress((uv*2.0-1.0)*(shape_data.yz+vec2(shape_data.w))/shape_data.yz, angular_data.x, angular_data.y);
		if (shape_data.x > 4.5 && shape_data.x < 6.5) return angular_progress(uv * 2.0 - 1.0, shape_data.y, shape_data.w);
		if ((shape_data.x > 0.5 && shape_data.x < 4.5) ||
				(shape_data.x > 6.5 && shape_data.x < 10.5))
			return angular_progress(uv * 2.0 - 1.0, angular_data.x, angular_data.y);
		return angular_progress(uv * 2.0 - 1.0, 0.0, MOLD_TAU);
	}
	return mold_gradient_t;
}

vec4 evaluated_color(vec2 uv, vec2 extent) {
	if (packed_gradient(1, 8) == 0) return primary_color;
	vec4 result = mix(primary_color, secondary_color, color_progress(uv, extent));
	if (packed_gradient(8, 2) == 1) result.rgb = oklab_to_linear(result.rgb);
	result.rgb *= 1.0 + max(emission_strength, 0.0) * 0.12;
	return result;
}

float shape_coverage(vec2 uv, vec4 shape, vec4 dash) {
 if (shape.x > 10.5) {
  vec2 radii=shape.yz;
  vec2 point=(uv*2.0-1.0)*(radii+vec2(shape.w));
  vec2 nearest=mold_ellipse_nearest(point,radii);
  float coverage=mold_aa(abs(nearest.x)-shape.w);
  float progress=0.0;
  if(dash.x>0.0) progress=mold_ellipse_progress(radii,nearest.y,angular_data.x,angular_data.y);
  return coverage*angular_mask(point/radii,angular_data.x,angular_data.y)
   *dashed_mask(progress,clamp(-nearest.x/max(shape.w,1e-8),-1.0,1.0),dash);
 }

	float kind = shape.x;
	vec2 p = uv * 2.0 - 1.0;
	float planar_angular = angular_mask(p, angular_data.x, angular_data.y);
	if (kind < 1.5) return mold_aa(box_distance(p)) * planar_angular;
	if (kind < 2.5) return mold_aa(shape.y < 0.0
		? local_rounded_box_distance(p, shape.y, shape.z)
		: rounded_box_distance(p, shape.z)) * planar_angular;
	if (kind < 3.5) {
		vec2 rim = clamp(vec2(shape.y, shape.z), vec2(0.00001), vec2(0.5));
		float outer = mold_aa(box_distance(p));
		float inner = mold_aa(box_distance(p / max(vec2(1.0) - rim * 2.0, vec2(0.00001))));
		return clamp(outer - inner, 0.0, 1.0) * dashed_mask(rectangle_perimeter_progress(uv, rim), rectangle_rim_across(uv, rim), dash) * planar_angular;
	}
	if (kind < 4.5) {
		if (shape.y < 0.0) return local_rectangle_rim_coverage(uv, shape, dash) * planar_angular;
		vec2 rim = clamp(vec2(shape.y, shape.z), vec2(0.00001), vec2(0.5));
		float outer = mold_aa(rounded_box_distance(p, shape.w));
		vec2 inner_scale = max(vec2(1.0) - rim * 2.0, vec2(0.00001));
		float inner = mold_aa(rounded_box_distance(p / inner_scale, clamp(shape.w / min(inner_scale.x, inner_scale.y), 0.0, 1.0)));
		return clamp(outer - inner, 0.0, 1.0) * dashed_mask(rectangle_perimeter_progress(uv, rim), rectangle_rim_across(uv, rim), dash) * planar_angular;
	}
	if (kind < 5.5) return mold_aa(length(p) - 1.0) * angular_mask(p, shape.y, shape.w);
	if (kind < 6.5) {
		float rim = max(shape.z, 0.00001);
		float coverage = clamp(mold_aa(length(p) - 1.0) - mold_aa(length(p) - max(1.0 - rim, 0.0)), 0.0, 1.0);
		float progress = angular_progress(p, shape.y, shape.w);
		return coverage * angular_mask(p, shape.y, shape.w) * dash_segment_mask(progress, disc_rim_rim_across(p, rim), dash);
	}
	if (kind < 7.5) return mold_aa(polygon_distance(p, shape.y)) * planar_angular;
	if (kind < 8.5) return rounded_polygon(p, shape.y, shape.z) * planar_angular;
	if (kind < 9.5) {
		float outer = mold_aa(polygon_distance(p, shape.y));
		float scale = max(1.0 - shape.z, 0.00001);
		float inner = mold_aa(polygon_distance(p / scale, shape.y));
		return clamp(outer - inner, 0.0, 1.0) * dashed_mask(polygon_perimeter_progress(p, shape.y), polygon_rim_across(p, shape.y, shape.z), dash) * planar_angular;
	}
	float outer = rounded_polygon(p, shape.y, shape.w);
	float scale = max(1.0 - shape.z, 0.00001);
	float inner = rounded_polygon(p / scale, shape.y, clamp(shape.w / scale, 0.0, 1.0));
	return clamp(outer - inner, 0.0, 1.0) * dashed_mask(polygon_perimeter_progress(p, shape.y), polygon_rim_across(p, shape.y, shape.z), dash) * planar_angular;
}

int bayer_2x2(ivec2 p) {
	return p.x * 2 + p.y * 3 - p.x * p.y * 4;
}

float dither_threshold(vec2 position) {
	ivec2 p = ivec2(position) & ivec2(15);
	int rank = bayer_2x2(p & ivec2(1)) * 64;
	rank += bayer_2x2((p >> 1) & ivec2(1)) * 16;
	rank += bayer_2x2((p >> 2) & ivec2(1)) * 4;
	rank += bayer_2x2((p >> 3) & ivec2(1));
	return float(rank + 1) / 257.0;
}


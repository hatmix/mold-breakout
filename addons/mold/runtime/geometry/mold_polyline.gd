class_name MoldPolyline
extends RefCounted

enum Geometry { FLAT_2D, BILLBOARD }
var _geometry := Geometry.FLAT_2D
var geometry: int:
	get: return _geometry


enum Join { MITER, BEVEL, ROUND }
enum Cap { BUTT, SQUARE, ROUND }

static var _next_geometry_id := 0

var _source_curve: MoldCurve
var _curve_stroke: MoldStroke
var _curve_sampling: MoldCurveSampling

var _render_points: Array[MoldPolylinePoint] = []
var _point_color_interpolation := MoldStyle.ColorInterpolation.LINEAR_RGB
var point_color_interpolation: int:
	get: return _point_color_interpolation

var _points: Array[MoldPolylinePoint] = []
var _thickness := 0.05
var _closed := false
var _join := Join.MITER
var _cap := Cap.BUTT
var _miter_limit := 4.0
var _bounds := AABB()
var _length := 0.0
var _geometry_id := 0
var _dash_source_id := 0
var _dash := MoldDash.new()
var dash: MoldDash:
	get: return _dash.duplicate_dash()

var points: Array[MoldPolylinePoint]:
	get: return _duplicate_points()
var thickness: float:
	get: return _thickness
var closed: bool:
	get: return _closed
var join: int:
	get: return _join
var cap: int:
	get: return _cap
var miter_limit: float:
	get: return _miter_limit
var bounds: AABB:
	get: return _bounds
var length: float:
	get: return _length


func _init(value_points: Array[MoldPolylinePoint] = [], value_thickness := 0.05,
		value_closed := false, value_join := Join.MITER, value_cap := Cap.BUTT,
		value_miter_limit := 4.0,
		value_geometry := Geometry.FLAT_2D, sampled_curve := false, value_point_color_interpolation := MoldStyle.ColorInterpolation.LINEAR_RGB) -> void:
	assert(value_point_color_interpolation in [MoldStyle.ColorInterpolation.LINEAR_RGB, MoldStyle.ColorInterpolation.OKLAB])
	_point_color_interpolation = value_point_color_interpolation
	assert(value_geometry in [Geometry.FLAT_2D, Geometry.BILLBOARD])
	_geometry = value_geometry
	assert(is_finite(value_thickness) and value_thickness > 0.0, "Polyline thickness must be positive and finite.")
	assert(value_join >= Join.MITER and value_join <= Join.ROUND, "Invalid polyline join.")
	assert(value_cap >= Cap.BUTT and value_cap <= Cap.ROUND, "Invalid polyline cap.")
	assert(is_finite(value_miter_limit) and value_miter_limit >= 1.0, "Polyline miter limit must be at least one.")
	var count := value_points.size()
	if not sampled_curve and value_closed and count > 2 and value_points[0].position == value_points[count - 1].position:
		count -= 1
	assert(count >= (3 if value_closed else 2), "A polyline needs at least two open or three closed points.")
	for index in count:
		var point := value_points[index].duplicate_point()
		if index > 0:
			assert(geometry == Geometry.BILLBOARD or absf(point.position.z - _points[0].position.z) <= 0.00001, "Polyline points must lie on one local XY plane.")
			assert(sampled_curve or _planar_distance_squared(_points[index - 1], point) >= 0.000000000001, "Consecutive polyline points cannot share an XY position.")
		_points.append(point)
	if value_closed:
		assert(sampled_curve or _planar_distance_squared(_points[-1], _points[0]) >= 0.000000000001, "The closing segment cannot have zero XY length.")
	_thickness = value_thickness
	_closed = value_closed
	_join = value_join
	_cap = value_cap
	_miter_limit = value_miter_limit
	_render_points = _sample_point_colors()
	_length = _calculate_length()
	_bounds = _calculate_bounds()
	MoldPolyline._next_geometry_id += 1
	_geometry_id = MoldPolyline._next_geometry_id
	_dash_source_id = _geometry_id


func with_point(index: int, point: MoldPolylinePoint) -> MoldPolyline:
	if _source_curve: push_error("Edit curve controls with set_curve."); return null
	assert(index >= 0 and index < _points.size(), "Polyline point index is out of range.")
	var copy := _duplicate_points()
	copy[index] = point.duplicate_point()
	return _copy(copy)


func with_points(value: Array[MoldPolylinePoint]) -> MoldPolyline:
	if _source_curve: push_error("Edit curve controls with set_curve."); return null
	return _copy(value)


func _copy(value_points: Array[MoldPolylinePoint]) -> MoldPolyline:
	return MoldPolyline.new(value_points, _thickness, _closed, _join, _cap, _miter_limit, geometry, false, point_color_interpolation).with_dash(_dash)


func _duplicate_points() -> Array[MoldPolylinePoint]:
	var copy: Array[MoldPolylinePoint] = []
	var count := _points.size()
	copy.resize(count)
	for index in count: copy[index] = _points[index].duplicate_point()
	return copy


func _calculate_bounds() -> AABB:
	var minimum := _render_points[0].position
	var maximum := minimum
	var padding := 0.0
	for point in _render_points:
		minimum = Vector3(minf(minimum.x, point.position.x), minf(minimum.y, point.position.y), minf(minimum.z, point.position.z))
		maximum = Vector3(maxf(maximum.x, point.position.x), maxf(maximum.y, point.position.y), maxf(maximum.z, point.position.z))
		padding = maxf(padding, _thickness * point.thickness * 0.5 * maxf(_miter_limit, sqrt(2.0) if _cap == Cap.SQUARE else 1.0))
	return AABB(minimum - Vector3.ONE * padding, maximum - minimum + Vector3.ONE * padding * 2.0)


func _calculate_length() -> float:
	var result := 0.0
	var point_count := _render_points.size()
	for index in range(1, point_count):
		result += sqrt(_planar_distance_squared(_render_points[index],_render_points[index-1]))
	if _closed:
		result += sqrt(_planar_distance_squared(_render_points[0],_render_points[-1]))
	return result


func _planar_distance_squared(first: MoldPolylinePoint, second: MoldPolylinePoint) -> float:
	if geometry == Geometry.BILLBOARD: return first.position.distance_squared_to(second.position)
	return Vector2(first.position.x - second.position.x, first.position.y - second.position.y).length_squared()


func _sample_point_colors() -> Array[MoldPolylinePoint]:
	var varying_color := false
	for i in range(1, _points.size()): varying_color = varying_color or _points[i].color != _points[0].color
	var sample_color := varying_color and point_color_interpolation == MoldStyle.ColorInterpolation.OKLAB
	if not sample_color: return _points
	const subdivisions := 16
	var result: Array[MoldPolylinePoint] = []
	var count := _points.size()
	var segments := count if _closed else count-1
	for i in segments:
		var a := _points[i]
		var b := _points[(i+1)%count]
		var color_a := MoldPointColors.convert(a.color, point_color_interpolation, false)
		var color_b := MoldPointColors.convert(b.color, point_color_interpolation, false)
		for step in subdivisions:
			var t := float(step)/subdivisions
			result.append(a if step == 0 else MoldPolylinePoint.new(a.position.lerp(b.position,t),MoldPointColors.convert(color_a.lerp(color_b,t),point_color_interpolation,true),lerpf(a.thickness,b.thickness,t)))
	if not _closed: result.append(_points[-1])
	return result

static func billboard_local_bounds(local: AABB, basis: Basis) -> AABB:
	if absf(basis.determinant())<0.00000001: return local
	var radius := local.size.length()*0.5*maxf(basis.x.length(),maxf(basis.y.length(),basis.z.length()))
	var inverse := basis.inverse()
	var extent := (inverse.x.abs()+inverse.y.abs()+inverse.z.abs())*radius
	return AABB(local.get_center()-extent,extent*2)


var _evaluation_curve: MoldCurve

## Cached mathematical path in local space, independent of rendering subdivisions.
func get_curve() -> MoldCurve:
	if _source_curve: return _source_curve
	if _evaluation_curve: return _evaluation_curve
	var count := _points.size()
	var positions := PackedVector3Array()
	positions.resize(count)
	for i in count: positions[i] = _points[i].position
	_evaluation_curve = MoldCurve.linear(positions, _closed)
	return _evaluation_curve

## Clamped parameter, not normalized distance. Returns local position.
func evaluate(t: float) -> Vector3:
	return get_curve().evaluate(t)

func evaluate_derivative(t: float, incoming := false) -> Vector3:
	return get_curve().evaluate_derivative(t, incoming)

func evaluate_tangent(t: float, incoming := false) -> Vector3:
	return get_curve().evaluate_tangent(t, incoming)

func bake_distance_table(tolerance := 0.001, max_depth := 20) -> MoldCurveDistanceTable:
	return get_curve().bake_distance_table(tolerance, max_depth)

## Dashes are baked into retained mesh geometry; Auto uses the CPU backend.
func with_dash(value: MoldDash) -> MoldPolyline:
	var resolved := value if value != null else MoldDash.new()
	if not MoldPathDashes.validate(resolved, length, closed): return null
	if _dash.equals(resolved): return self
	var result := MoldPolyline.new(_points, thickness, closed, join, cap, miter_limit, geometry, true, point_color_interpolation)
	result._dash_source_id = _dash_source_id
	result._render_points = _render_points
	result._source_curve = _source_curve
	result._curve_stroke = _curve_stroke
	result._curve_sampling = _curve_sampling
	result._dash = resolved.duplicate_dash()
	return result

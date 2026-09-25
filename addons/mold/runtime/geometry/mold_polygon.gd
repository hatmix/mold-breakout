class_name MoldPolygon
extends RefCounted

enum Triangulation { EAR_CLIPPING, FAST_CONVEX_ONLY }
var _triangulation: Triangulation
var triangulation: Triangulation:
	get: return _triangulation

## A simple closed local-XY contour. The caller owns geometric validity.
## Colors interpolate over the complete contour. No holes or self-intersections.
var _vertices: PackedVector3Array
var _colors: PackedColorArray
var _triangles: PackedInt32Array
var vertices: PackedVector3Array:
	get: return _vertices.duplicate()
var colors: PackedColorArray:
	get: return _colors.duplicate()
var triangles: PackedInt32Array:
	get: return _triangles.duplicate()
var count: int:
	get: return _vertices.size()

func _init(value_vertices: PackedVector3Array, value_colors := PackedColorArray(), value_triangles := PackedInt32Array(), value_triangulation: Triangulation = Triangulation.EAR_CLIPPING) -> void:
	assert(value_vertices.size() >= 3, "A polygon needs at least three vertices.")
	assert(value_colors.is_empty() or value_colors.size() == value_vertices.size(), "One color per vertex is required.")
	_vertices = value_vertices.duplicate()
	_colors = value_colors.duplicate()
	if _colors.is_empty():
		_colors.resize(count)
		_colors.fill(Color.WHITE)
	_triangulation = value_triangulation
	_triangles = value_triangles.duplicate()
	if _triangles.is_empty():
		_triangles = _convex_fan(_vertices) if triangulation == Triangulation.FAST_CONVEX_ONLY else _triangulate(_vertices)
	assert(not _triangles.is_empty() and _triangles.size() % 3 == 0, "Polygon triangulation failed.")
	for index in _triangles: assert(index >= 0 and index < count, "Triangle index out of range.")

func with_vertices(value: PackedVector3Array, preserve_triangles := false) -> MoldPolygon:
	return MoldPolygon.new(value, _colors, _triangles if preserve_triangles else PackedInt32Array(), triangulation)

static func _triangulate(points: PackedVector3Array) -> PackedInt32Array:
	var planar := PackedVector2Array()
	planar.resize(points.size())
	for i in points.size(): planar[i] = Vector2(points[i].x, points[i].y)
	return Geometry2D.triangulate_polygon(planar)

static func _convex_fan(points: PackedVector3Array) -> PackedInt32Array:
	var area := 0.0
	var point_count := points.size()
	for i in point_count:
		var a := points[i]
		var b := points[(i + 1) % point_count]
		area += a.x * b.y - b.x * a.y
	var indices := PackedInt32Array()
	indices.resize((point_count - 2) * 3)
	for i in range(1, point_count - 1):
		var offset := (i - 1) * 3
		indices[offset] = 0
		indices[offset + 1] = i if area >= 0 else i + 1
		indices[offset + 2] = i + 1 if area >= 0 else i
	return indices

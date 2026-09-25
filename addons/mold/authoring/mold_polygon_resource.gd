@tool
class_name MoldPolygonResource
extends Resource

@export var points: Array[MoldPolygonPointResource] = [
	_point(Vector3(-0.5,-0.5,0)), _point(Vector3(0.5,-0.5,0)), _point(Vector3(0,0.5,0))
]:
	set(value):
		for point in points:
			if point and point.changed.is_connected(_on_point_changed): point.changed.disconnect(_on_point_changed)
		points = value
		_connect_points()
		emit_changed()

## FastConvexOnly requires a convex contour supplied by the caller.
@export_enum("EarClipping", "FastConvexOnly") var triangulation: int = MoldPolygon.Triangulation.EAR_CLIPPING:
	set(value): triangulation=value; emit_changed()

func _init() -> void:
	_connect_points()

func _connect_points() -> void:
	for point in points:
		if point and not point.changed.is_connected(_on_point_changed): point.changed.connect(_on_point_changed)

func _on_point_changed() -> void:
	emit_changed()

func to_polygon() -> MoldPolygon:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(points.size())
	colors.resize(points.size())
	for i in points.size():
		assert(points[i] != null, "A polygon point is missing.")
		vertices[i] = points[i].position
		colors[i] = points[i].color
	return MoldPolygon.new(vertices, colors, PackedInt32Array(), triangulation)

static func _point(position: Vector3) -> MoldPolygonPointResource:
	var point := MoldPolygonPointResource.new()
	point.position = position
	return point

func matches_geometry(value: MoldPolygon) -> bool:
	if not value or value.count != points.size() or value.triangulation != triangulation: return false
	for i in points.size():
		if not points[i] or points[i].position != value._vertices[i]: return false
	return true

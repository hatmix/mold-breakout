class_name MoldPolylinePoint
extends RefCounted

var position: Vector3
var color: Color
var thickness: float


func _init(value_position := Vector3.ZERO, value_color := Color.WHITE, value_thickness := 1.0) -> void:
	assert(value_position.is_finite(), "Polyline point positions must be finite.")
	assert(is_finite(value_thickness) and value_thickness >= 0.0, "Polyline point thickness must be nonnegative and finite.")
	position = value_position
	color = value_color
	thickness = value_thickness


func duplicate_point() -> MoldPolylinePoint:
	return MoldPolylinePoint.new(position, color, thickness)

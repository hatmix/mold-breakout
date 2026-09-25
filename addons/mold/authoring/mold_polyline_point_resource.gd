@tool
class_name MoldPolylinePointResource
extends Resource

@export var position := Vector3.ZERO:
	set(value):
		position = value if value.is_finite() else Vector3.ZERO
		emit_changed()
@export var color := Color.WHITE:
	set(value):
		color = value
		emit_changed()
@export_range(0.0, 10.0, 0.01, "or_greater") var thickness := 1.0:
	set(value):
		thickness = maxf(value, 0.001 if self is MoldCurvePointResource else 0.0) if is_finite(value) else 1.0
		emit_changed()


func to_point() -> MoldPolylinePoint:
	return MoldPolylinePoint.new(position, color, thickness)

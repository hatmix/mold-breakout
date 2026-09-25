@tool
class_name MoldCurveControl
extends MoldPolylineControl
@export var curve: MoldCurveResource=MoldCurveResource.new():
 set(value):
  if curve and curve.changed.is_connected(_path_changed):curve.changed.disconnect(_path_changed)
  curve=value if value else MoldCurveResource.new()
  if not curve.changed.is_connected(_path_changed):curve.changed.connect(_path_changed)
  _path_changed()
func _enter_tree() -> void:
 super._enter_tree()
 if not curve.changed.is_connected(_path_changed):curve.changed.connect(_path_changed)
func _resolve_path() -> MoldPolyline:return _runtime_path if _runtime_path else curve.to_polyline()
func set_curve(value: MoldCurve, stroke: MoldStroke, sampling: MoldCurveSampling=null) -> void:
 set_polyline(value.to_polyline(stroke,sampling))
func _validate_property(property: Dictionary) -> void:
 if property.name=="polyline":property.usage&=~PROPERTY_USAGE_EDITOR

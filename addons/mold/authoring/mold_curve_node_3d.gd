@tool
class_name MoldCurveNode3D
extends MoldPolylineNode3D
var _curve_queued := false
@export var curve: MoldCurveResource:
	get: return polyline as MoldCurveResource
	set(value): polyline=value if value else MoldCurveResource.new()
func _init() -> void:
	polyline=MoldCurveResource.new()
func _on_polyline_resource_changed() -> void:
	_cached_polyline=null
	if _curve_queued or not is_inside_tree(): return
	_curve_queued=true; call_deferred("_flush_curve")
func _flush_curve() -> void:
	_curve_queued=false
	if is_inside_tree(): super._on_polyline_resource_changed()
func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray() if _current_polyline() else PackedStringArray(["Curve controls or sampling settings are invalid."])
func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	if property.name=="polyline": property.usage=PROPERTY_USAGE_NONE

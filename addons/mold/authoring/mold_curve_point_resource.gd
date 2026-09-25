@tool
class_name MoldCurvePointResource
extends MoldPolylinePointResource
@export var in_offset := Vector3.ZERO:
	set(value): in_offset=value; emit_changed()
@export var out_offset := Vector3.ZERO:
	set(value): out_offset=value; emit_changed()
@export var mode: MoldBezierKnot.HandleMode = MoldBezierKnot.HandleMode.AUTO:
	set(value): mode=value; emit_changed()
@export_range(0.000001,10,0.000001,"or_greater","hide_slider") var weight := 1.0:
	set(value): weight=maxf(value, 0.000001) if is_finite(value) else 1.0; emit_changed()

func _validate_property(property: Dictionary) -> void:
	if property.name == "thickness": property.hint_string = "0,10,0.01,or_greater"
	if property.name in ["in_offset","out_offset"]: property.usage &= ~PROPERTY_USAGE_EDITOR

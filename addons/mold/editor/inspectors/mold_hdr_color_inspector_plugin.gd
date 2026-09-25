@tool
extends EditorInspectorPlugin

const MoldHdrColorProperty = preload("mold_hdr_color_property.gd")

func _can_handle(object: Object) -> bool:
	return object is MoldStyleResource or object is MoldPolylinePointResource or object is MoldPencilSettings

func _parse_property(object: Object, type: Variant.Type, name: String,
		_hint_type: PropertyHint, _hint_string: String, _usage_flags: int,
		_wide: bool) -> bool:
	if type != TYPE_COLOR: return false
	var is_style_color := object is MoldStyleResource \
		and name in [&"color", &"secondary_color"]
	var is_point_color := object is MoldPolylinePointResource and name == &"color"
	var is_paper_color := object is MoldPencilSettings and name == &"paper_color"
	if not is_style_color and not is_point_color and not is_paper_color: return false
	add_property_editor(name, MoldHdrColorProperty.new())
	return true

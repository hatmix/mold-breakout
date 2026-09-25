@tool
extends EditorInspectorPlugin

const PointList = preload("mold_point_list_property.gd")
const EnumProperty = preload("mold_enum_property.gd")
const GEOMETRY_CHOICES = ["Flat 2D", "Billboard"]
const CURVE_CHOICES = ["Bézier", "Quadratic Bézier", "Catmull-Rom", "Hermite", "B-Spline", "NURBS", "Linear"]

# Match the Polyline component order, independent of resource inheritance.
var building_curve_editor := false
const CURVE_FIELDS = ["points","point_color_interpolation","closed","thickness","kind","parameterization","degree","knot_vector","join","miter_limit","adaptive","curve_subdivisions","tolerance","cap","geometry"]
var state
func _init(editor): state = editor
func _can_handle(object: Object) -> bool: return state.polyline_resource(object) or state.polygon_resource(object) or not state.shape_property(object).is_empty()
func _parse_property(object: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_string: String, _usage: int, _wide: bool) -> bool:
	if building_curve_editor: return false
	if state.curve_resource(object) and name.to_snake_case() in CURVE_FIELDS: return true
	if state.polyline_resource(object) and name in ["geometry", "Geometry"]:
		add_property_editor(name,EnumProperty.new(["Flat 2D"] if _canvas_resource(object) else GEOMETRY_CHOICES, state.set_geometry)); return true
	if (state.polyline_resource(object) or state.polygon_resource(object)) and name in ["points","Points"]:
		add_property_editor(name,PointList.new(state)); return true
	return false
func _parse_begin(object: Object) -> void:
	if state.curve_resource(object):
		var properties := {}
		for property in object.get_property_list(): properties[property.name]=property
		# The factory invokes inspector plugins; queue editors only after all are built.
		var editors := []
		building_curve_editor = true
		for field_name in CURVE_FIELDS:
			var name: String = state.resource_field(object,field_name,field_name.to_pascal_case())
			var property: Dictionary = properties[name]
			if not (property.usage & PROPERTY_USAGE_EDITOR): continue
			var editor: EditorProperty
			match field_name:
				"points": editor=PointList.new(state)
				"closed": editor=EnumProperty.new(["Open","Closed"], state.set_curve_closed)
				"kind": editor=EnumProperty.new(CURVE_CHOICES, state.set_curve_kind)
				"geometry": editor=EnumProperty.new(["Flat 2D"] if _canvas_resource(object) else GEOMETRY_CHOICES, state.set_geometry)
				_: editor=EditorInspector.instantiate_property_editor(object,property.type,name,property.hint,property.hint_string,property.usage)
			if editor: editors.append([name,editor])
		building_curve_editor = false
		for entry in editors: add_property_editor(entry[0],entry[1],false,String(entry[0]).to_snake_case().capitalize())
		return
	if state.polygon_resource(object): return
	if state.polyline_resource(object): return
	var box := VBoxContainer.new()
	var indices := CheckBox.new()
	indices.text = "Show Point Indices"
	indices.button_pressed = state.show_indices
	indices.toggled.connect(state.set_show_indices)
	box.add_child(indices)
	state.index_buttons = state.index_buttons.filter(func(ref): return is_instance_valid(ref.get_ref()))
	state.index_buttons.append(weakref(indices))
	var toggle := Button.new()
	toggle.text = "Done" if state.target == object else "Edit Points"
	toggle.set_meta("mold_target",object)
	toggle.pressed.connect(func():
		var selected := EditorInterface.get_selection().get_selected_nodes()
		if selected.size() == 1 and selected[0] == object:
			state.set_target(null if state.target == object else object))
	box.add_child(toggle)
	state.toggle_buttons = state.toggle_buttons.filter(func(ref): return is_instance_valid(ref.get_ref()))
	state.toggle_buttons.append(weakref(toggle))
	var unique := Button.new()
	unique.text = "Make Shape Unique"
	unique.pressed.connect(func(): state.make_unique(object))
	box.add_child(unique)
	var hint := Label.new()
	hint.text = "Select a point, then drag an axis or plane. Billboard polylines also expose Z, XZ and YZ.\nShared resources edit all users; Make Unique isolates this node.\nKeep the contour valid. Explicit triangles remain unchanged."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	add_custom_control(box)

func _canvas_resource(object: Object) -> bool:
	var owner := EditorInterface.get_inspector().get_edited_object()
	if not owner is Control: return false
	for name in ["curve","polyline"]:
		var key: String = state.resource_field(object,name,name.to_pascal_case())
		for property in owner.get_property_list():
			if property.name==key and owner.get(key)==object: return true
	return false

@tool
extends EditorInspectorPlugin
const Properties = preload("../mold_editor_properties.gd")
const AppearancePanel = preload("mold_appearance_panel.gd")
var undo: EditorUndoRedoManager

func _can_handle(object: Object) -> bool:
	if object.get_class() in ["MultiNodeEdit","EditorMultiNodeEdit"]:
		return EditorInterface.get_selection().get_selected_nodes().all(func(node): return Properties.read(node,"style") != null)
	if not object is Resource: return false
	var script: Script = object.get_script()
	return script != null and script.resource_path.get_file() in ["mold_style_resource.gd","MoldStyleResource.cs","mold_appearance_resource.gd","MoldAppearanceResource.cs"]
func _parse_begin(object: Object) -> void:
	var panel := AppearancePanel.new()
	if object is Resource: panel.setup(object,undo)
	else:
		var values: Array[Resource] = []
		var nodes: Array[Node] = []
		for node in EditorInterface.get_selection().get_selected_nodes(): values.append(Properties.read(node,"style"));nodes.append(node)
		if values.is_empty(): return
		panel.setup_many(values,nodes,undo)
	add_custom_control(panel)
func _parse_property(_object: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_string: String, _usage: int, _wide: bool) -> bool:
	if not _object is Resource: return false
	return name not in ["resource_name","resource_local_to_scene","script"]

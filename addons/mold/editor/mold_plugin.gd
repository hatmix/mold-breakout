@tool
extends EditorPlugin

const MoldHdrColorInspectorPlugin = preload("inspectors/mold_hdr_color_inspector_plugin.gd")
const MoldGizmoPlugin = preload("res://addons/mold/editor/mold_gizmo_plugin.gd")
var _world_hover
var _ui_editor
var _point_editor
var _gizmo_plugin: EditorNode3DGizmoPlugin
var _appearance_inspector: EditorInspectorPlugin
var _hdr_color_inspector_plugin: EditorInspectorPlugin


func _enter_tree() -> void:
	_ui_editor=preload("ui/mold_ui_editor.gd").new()
	_ui_editor.install(self)
	_appearance_inspector=preload("inspectors/mold_appearance_inspector.gd").new()
	_appearance_inspector.undo=get_undo_redo()
	add_inspector_plugin(_appearance_inspector)
	_point_editor = preload("res://addons/mold/editor/mold_point_editor.gd").new()
	_point_editor.install(self)
	_world_hover=preload("picking/mold_world_hover.gd").new()
	_world_hover.install(self)
	_gizmo_plugin = MoldGizmoPlugin.new()
	_gizmo_plugin.hover_service=_world_hover
	add_node_3d_gizmo_plugin(_gizmo_plugin)
	_hdr_color_inspector_plugin = MoldHdrColorInspectorPlugin.new()
	add_inspector_plugin(_hdr_color_inspector_plugin)


func _exit_tree() -> void:
	if _world_hover:_world_hover.uninstall()
	_world_hover=null
	if _ui_editor:_ui_editor.uninstall()
	_ui_editor=null
	if _appearance_inspector: remove_inspector_plugin(_appearance_inspector)
	_appearance_inspector=null
	if _point_editor:
		_point_editor.uninstall()
		_point_editor = null
	if _hdr_color_inspector_plugin:
		remove_inspector_plugin(_hdr_color_inspector_plugin)
		_hdr_color_inspector_plugin = null
	if _gizmo_plugin:
		remove_node_3d_gizmo_plugin(_gizmo_plugin)
		_gizmo_plugin = null


func _process(_delta: float) -> void:
	if _world_hover:_world_hover.tick(_delta)
	if _point_editor: _point_editor.update_labels()

func _forward_3d_force_draw_over_viewport(control: Control) -> void:
	if _point_editor: _point_editor.draw_indices(control)

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var result: int=_point_editor.forward_input(camera,event) if _point_editor else EditorPlugin.AFTER_GUI_INPUT_PASS
	if _world_hover:_world_hover.forward_input(camera,event,result!=EditorPlugin.AFTER_GUI_INPUT_PASS or (_point_editor!=null and _point_editor.hover_part!=0))
	return result

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	return _ui_editor.forward_input(event) if _ui_editor else false
func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	if _ui_editor:_ui_editor.draw(overlay)

func _handles(object: Object) -> bool:
	return _ui_editor != null and _ui_editor.handles(object)

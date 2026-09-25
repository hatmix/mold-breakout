@tool
extends EditorInspectorPlugin
var state
func _init(editor):state=editor
# Inspect the actual Inspector root, not scene selection: a shared resource must
# keep its world options when opened independently or through a world node.
func ui_shape_owner(object: Object) -> Control:
 var owner:=EditorInterface.get_inspector().get_edited_object()
 if not state.is_ui(owner):return null
 var key: String=state.geometry_property(owner)
 if key.to_snake_case()=="shape" and owner.get(key)==object:return owner
 return null
func _can_handle(object: Object) -> bool:
 return (state.is_ui(object) and not state.geometry_property(object).is_empty()) or ui_shape_owner(object)!=null
func _parse_property(object: Object, _type: Variant.Type, name: String, _hint: PropertyHint, _hint_string: String, _usage: int, _wide: bool) -> bool:
 if ui_shape_owner(object)==null:return false
 if name.to_snake_case()=="billboard_mode":return true
 if name.to_snake_case()=="kind":
  var choices: Dictionary=state.Properties.enum_choices(object,"kind")
  var labels: Array=[]
  var ids: Array=[]
  for id in choices:
   if id>=100:continue
   labels.append(choices[id]);ids.append(id)
  var editor=preload("../inspectors/mold_enum_property.gd").new(labels,func(resource,value):
   var undo=state.host.get_undo_redo()
   undo.create_action("Set Canvas Shape Kind",UndoRedo.MERGE_DISABLE,resource)
   undo.add_do_property(resource,name,value);undo.add_undo_property(resource,name,resource.get(name));undo.commit_action(),ids)
  add_property_editor(name,editor)
  return true
 return false
func _parse_begin(object: Object) -> void:
 if object is Resource:return
 var box:=VBoxContainer.new()
 var hint:=Label.new()
 hint.text="Native canvas graphics • local UI units • +Y down"
 hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 box.add_child(hint)
 var unique:=Button.new()
 unique.text="Make Geometry Unique"
 unique.pressed.connect(func():state.make_unique(object))
 box.add_child(unique)
 if state.geometry_property(object).to_lower()!="shape":
  var toggle:=Button.new()
  toggle.text="Edit Canvas Points / Done"
  toggle.pressed.connect(func():state.toggle(object))
  box.add_child(toggle)
  var snap:=SpinBox.new()
  snap.min_value=.001;snap.max_value=1000;snap.step=.01;snap.value=state.snap_step
  snap.prefix="Ctrl/Cmd snap: "
  snap.value_changed.connect(func(v):state.snap_step=v)
  box.add_child(snap)
 add_custom_control(box)

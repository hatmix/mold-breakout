@tool
extends RefCounted

const Properties = preload("../mold_editor_properties.gd")
const Inspector=preload("mold_ui_inspector.gd")
var picker: Control
var host: EditorPlugin
var inspector: EditorInspectorPlugin
var menu: PopupMenu
var target: Control
var selected: Array[int]=[]
var active:=false
var snap_step:=1.0
var _drag:=false
var _role:=0
var _index:=-1
var _start:=Vector2.ZERO
var _before: Array=[]

static func is_ui(node: Object) -> bool:
 return node is Control and node.get_script() and ("/ui/mold_" in node.get_script().resource_path or "/UI/Mold" in node.get_script().resource_path)
func handles(node: Object) -> bool:
 return is_ui(node)
static func field(object: Object, name: String) -> String:
 return Properties.api_name(object, name)
static func geometry_property(node: Object) -> String:
 for name in ["curve","polyline","polygon","shape"]:
  var key:=field(node,name)
  for p in node.get_property_list():
   if p.name==key:return key
 return ""
func install(plugin: EditorPlugin) -> void:
 host=plugin
 picker=preload("mold_ui_picker.gd").new()
 picker.install(plugin,self)
 inspector=Inspector.new(self)
 host.add_inspector_plugin(inspector)
 menu=PopupMenu.new()
 for name in ["Shape","Polyline","Curve","Polygon"]:menu.add_item(name)
 menu.id_pressed.connect(create_control)
 host.add_tool_submenu_item("Create Mold UI",menu)
 EditorInterface.get_selection().selection_changed.connect(selection_changed)
func uninstall() -> void:
 if is_instance_valid(picker):picker.uninstall()
 picker=null
 finish(true)
 EditorInterface.get_selection().selection_changed.disconnect(selection_changed)
 host.remove_inspector_plugin(inspector)
 inspector=null
 host.remove_tool_menu_item("Create Mold UI")
 menu=null
 target=null
 host=null
func selection_changed() -> void:
 finish(true)
 var nodes:=EditorInterface.get_selection().get_selected_nodes()
 target=nodes[0] if nodes.size()==1 and is_ui(nodes[0]) else null
 selected.clear();active=false
 host.update_overlays()
func toggle(node: Control) -> void:
 if is_instance_valid(picker):picker.set_enabled(false)
 finish(true)
 active=not active if target==node else true
 target=node;selected.clear()
 host.update_overlays()
func create_control(id: int) -> void:
 var scene:=EditorInterface.get_edited_scene_root()
 if not scene:return
 var names:=["Shape","Polyline","Curve","Polygon"]
 var cs: bool=host.get_script().resource_path.ends_with(".cs")
 var path:="res://addons/mold/UI/Mold%sControl.cs"%names[id] if cs else "res://addons/mold/ui/mold_%s_control.gd"%names[id].to_lower()
 var node: Control=load(path).new()
 node.name="Mold"+names[id]
 node.size=Vector2(100,100)
 var parent: Node=scene
 var nodes:=EditorInterface.get_selection().get_selected_nodes()
 if nodes.size()==1:parent=nodes[0]
 var undo:=host.get_undo_redo()
 undo.create_action("Create Mold UI "+names[id],UndoRedo.MERGE_DISABLE,scene)
 undo.add_do_method(parent,"add_child",node)
 undo.add_do_property(node,"owner",scene)
 undo.add_undo_method(parent,"remove_child",node)
 undo.add_do_reference(node)
 undo.commit_action()
 EditorInterface.get_selection().clear()
 EditorInterface.get_selection().add_node(node)
func resource() -> Resource:
 if not is_instance_valid(target):return null
 var key:=geometry_property(target)
 return target.get(key) if not key.is_empty() else null
func points() -> Array:
 var res:=resource()
 if not res:return []
 for p in res.get_property_list():
  if p.name==field(res,"points"):return res.get(p.name)
 return []
func snapshot() -> Array:
 var values: Array=[]
 for point in points():
  var item: Dictionary={}
  for name in ["position","in_offset","out_offset","mode"]:
   var key:=field(point,name)
   for prop in point.get_property_list():
    if prop.name==key:item[key]=point.get(key)
  values.append(item)
 return values
func restore(res: Resource, values: Array) -> void:
 var ps: Array=res.get(field(res,"points"))
 for i in mini(ps.size(),values.size()):
  for key in values[i]:ps[i].set(key,values[i][key])
 host.update_overlays()
func tangent_point(index: int, role: int) -> Vector3:
 var res:=resource()
 return res.call(field(res,"handle_position"),index,role)
func has_tangents() -> bool:
 var res:=resource()
 return res and "curve" in res.get_script().resource_path.to_lower() and res.get(field(res,"kind")) in [0,3]
func draw(overlay: Control) -> void:
 if is_instance_valid(picker):picker.attach(overlay)
 if not active or not is_instance_valid(target):return
 var transform:=target.get_global_transform_with_canvas()
 var ps:=points()
 for i in ps.size():
  var p: Vector3=ps[i].get(field(ps[i],"position"))
  var screen:=transform*Vector2(p.x,p.y)
  overlay.draw_circle(screen,5,Color.ORANGE if i in selected else Color.CYAN)
  overlay.draw_string(ThemeDB.fallback_font,screen+Vector2(8,-7),str(i),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color.WHITE)
  if i in selected and has_tangents():
   for role in [1,2]:
    var t:=tangent_point(i,role)
    var end:=transform*Vector2(t.x,t.y)
    overlay.draw_line(screen,end,Color.ORANGE,1)
    overlay.draw_circle(end,4,Color.YELLOW)
func forward_input(event: InputEvent) -> bool:
 if not active or not is_instance_valid(target):return false
 if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
  if _drag:finish(true)
  else:active=false;host.update_overlays()
  return true
 if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
  if not event.pressed:
   if _drag:finish(false);return true
   return false
  var transform:=target.get_global_transform_with_canvas()
  var ps:=points()
  var hit:=-1
  _role=0
  var distance:=9.0
  for i in ps.size():
   var p: Vector3=ps[i].get(field(ps[i],"position"))
   var d:=(transform*Vector2(p.x,p.y)).distance_to(event.position)
   if d<distance:distance=d;hit=i;_role=0
   if i in selected and has_tangents():
    for role in [1,2]:
     var t:=tangent_point(i,role)
     d=(transform*Vector2(t.x,t.y)).distance_to(event.position)
     if d<distance:distance=d;hit=i;_role=role
  if hit<0:return false
  if event.shift_pressed and _role==0:
   if hit in selected:selected.erase(hit)
   else:selected.append(hit)
  elif hit not in selected:selected=[hit]
  _index=hit;_start=transform.affine_inverse()*event.position;_before=snapshot();_drag=true
  host.update_overlays()
  return true
 if event is InputEventMouseMotion and _drag:
  var local: Vector2=target.get_global_transform_with_canvas().affine_inverse()*event.position
  var delta: Vector2=local-_start
  if event.ctrl_pressed or event.meta_pressed:delta=delta.snapped(Vector2.ONE*maxf(snap_step,.0001))
  var res:=resource()
  restore(res,_before)
  if _role!=0:
   var original:=tangent_point(_index,_role)
   res.call(field(res,"move_handle"),_index,_role,original+Vector3(delta.x,delta.y,0))
  else:
   var ps:=points()
   for index in selected:
    var key:=field(ps[index],"position")
    var value: Vector3=_before[index][key]+Vector3(delta.x,delta.y,0)
    ps[index].set(key,value)
    var peer: Resource=preload("../mold_point_editor.gd").closing_peer(res,ps[index])
    if peer:peer.set(key,value)
  host.update_overlays()
  return true
 return false
func finish(cancel: bool) -> void:
 if not _drag:return
 _drag=false
 var res:=resource()
 if not res:return
 var after:=snapshot()
 restore(res,_before)
 if cancel or after==_before:return
 var undo:=host.get_undo_redo()
 undo.create_action("Move Mold UI Points",UndoRedo.MERGE_DISABLE,res)
 undo.add_do_method(self,"restore",res,after)
 undo.add_undo_method(self,"restore",res,_before)
 undo.commit_action()
func make_unique(node: Control) -> void:
 var key:=geometry_property(node)
 var original: Resource=node.get(key)
 var copy:=original.duplicate(true)
 for p in copy.get_property_list():
  if p.name==field(copy,"points"):
   var ps: Array=copy.get(p.name).duplicate()
   for i in ps.size():ps[i]=ps[i].duplicate(true)
   copy.set(p.name,ps)
 copy.resource_local_to_scene=true
 var undo:=host.get_undo_redo()
 undo.create_action("Make Mold UI Geometry Unique",UndoRedo.MERGE_DISABLE,node)
 undo.add_do_property(node,key,copy)
 undo.add_undo_property(node,key,original)
 undo.commit_action()

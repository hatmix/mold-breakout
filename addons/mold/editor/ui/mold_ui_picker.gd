@tool
extends Control
const SelectionStyle=preload("../picking/mold_selection_style.gd")
## Explicit editor-only selection mode. Never resizes or reparents scene graphics.
const MaskGraphic=preload("mold_ui_pick_mesh.gd")
const CACHE_LIMIT=24
const CACHE_PIXEL_LIMIT=8000000
const ALPHA_THRESHOLD=.002
var host: EditorPlugin
var state
var toolbar: HBoxContainer
var button: Button
var hint: Label
var popup: PopupMenu
var _mode_scene_id:=0
var enabled:=false
var tolerance:=4
var _surface: Control
var _attaching:=false
var _cache: Dictionary={}
var _clock:=0
var _hover: Control
var _popup_nodes: Array[Node]=[]
var _popup_add:=false
var _press:=Vector2.ZERO
var _pressed:=false
var _dragging:=false
var _mouse:=Vector2.ZERO
var _pending:=false
var _busy:=false
var _query_busy:=false
var _elapsed:=0.0
var _epoch:=0
var _mask_shader: Shader
var _outline_shader: Shader
var _outlines: Array[TextureRect]=[]

func install(plugin: EditorPlugin, editor) -> void:
 host=plugin;state=editor
 name="MoldUiPicker";mouse_filter=MOUSE_FILTER_IGNORE;focus_mode=FOCUS_ALL
 toolbar=HBoxContainer.new()
 button=Button.new();button.text="Pick Mold UI: OFF";button.custom_minimum_size.x=180;button.toggle_mode=true
 button.tooltip_text="Select Mold silhouettes. Click selects; Shift toggles; right-click lists overlaps; drag selects a region; Escape exits."
 button.toggled.connect(set_enabled);toolbar.add_child(button)
 var label:=Label.new();label.text="Tolerance";toolbar.add_child(label)
 var width:=SpinBox.new();width.custom_minimum_size.x=84;width.min_value=0;width.max_value=12;width.step=1;width.value=tolerance;width.suffix=" px"
 width.tooltip_text="Screen-space click tolerance for thin strokes; box selection uses exact coverage."
 width.value_changed.connect(func(value):tolerance=int(value));toolbar.add_child(width)
 # Hover names must not change the toolbar's minimum width: the editor can
 # otherwise wrap its toolbar and move the canvas out from under the pointer.
 hint=Label.new();hint.clip_text=true;hint.custom_minimum_size.x=240
 hint.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 hint.tooltip_text=button.tooltip_text;toolbar.add_child(hint)
 host.add_control_to_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU,toolbar)
 popup=PopupMenu.new();popup.id_pressed.connect(_choose_popup);add_child(popup)
 _mask_shader=Shader.new()
 _mask_shader.code='shader_type canvas_item;\nrender_mode unshaded, blend_mix;\n#define MOLD_UI_MATERIAL_PARAMETERS\n#define MOLD_UI_PICK\n#define MOLD_UI_BLEND_MODE 1\n#include "res://addons/mold/ui/rendering/mold_canvas.gdshaderinc"\n'
 _outline_shader=Shader.new()
 _outline_shader.code="""shader_type canvas_item;
 render_mode unshaded;
 uniform float outline_width=1.0;
 uniform vec4 outline_color : source_color=vec4(1.,.7,.15,1.);
 void fragment(){
  float lo=1.;float hi=0.;
  for(int x=-2;x<=2;x++)for(int y=-2;y<=2;y++){
   float a=texture(TEXTURE,UV+vec2(float(x),float(y))*TEXTURE_PIXEL_SIZE*(outline_width/4.0)).a;
   lo=min(lo,a);hi=max(hi,a);
  }
  COLOR=vec4(outline_color.rgb,outline_color.a*clamp(hi-lo,0.,1.));
 }"""
 # The host point-editor service already enables force-draw forwarding.
 host.scene_changed.connect(_scene_changed)
 host.update_overlays()

func _scene_changed(_scene: Node) -> void:
 _epoch+=1;_pressed=false;_dragging=false;_hover=null
 _clear_cache();_clear_outlines();popup.hide();_pending=enabled
 call_deferred("_sync_scene_mode")

func _sync_scene_mode() -> void:
 if not is_instance_valid(host):return
 var scene:=EditorInterface.get_edited_scene_root()
 var id:=scene.get_instance_id() if scene else 0
 if id==_mode_scene_id:return
 _mode_scene_id=id
 var native_ui:=false
 if scene is Control:
  var nodes: Array[Node]=[]
  _collect(scene,nodes)
  for node in nodes:
   if node is Control and (node.has_method("editor_snapshot") or node.has_method("EditorSnapshot")):
    native_ui=true;break
 set_enabled(native_ui)

func attach(surface: Control) -> void:
 if _surface==surface or _attaching:return
 _attaching=true
 call_deferred("_attach",surface)
func _attach(surface: Control) -> void:
 _attaching=false
 if not is_instance_valid(host) or not is_instance_valid(surface):return
 if get_parent():get_parent().remove_child(self)
 _surface=surface;surface.add_child(self)
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _sync_scene_mode()
func uninstall() -> void:
 set_enabled(false)
 if is_instance_valid(host):
  host.scene_changed.disconnect(_scene_changed)
  host.remove_control_from_container(EditorPlugin.CONTAINER_CANVAS_EDITOR_MENU,toolbar)
 toolbar.queue_free();host=null;state=null
 queue_free()
func set_enabled(value: bool) -> void:
 enabled=value;_epoch+=1;_query_busy=false;_busy=false;_pressed=false;_dragging=false;_hover=null
 if is_instance_valid(button):
  button.set_pressed_no_signal(value)
  button.text="Pick Mold UI: ON" if value else "Pick Mold UI: OFF"
 mouse_filter=MOUSE_FILTER_PASS if value else MOUSE_FILTER_IGNORE
 if value:
  state.finish(true);state.active=false
  if is_inside_tree():grab_focus()
  _pending=true
 else:
  _clear_cache();_clear_outlines()
  if is_instance_valid(popup):popup.hide()
 if is_instance_valid(hint):hint.text="Click • Shift add • Right-click overlaps • Drag box • Esc exit" if value else "OFF • Enable to select Mold shapes"
 queue_redraw()
func _clear_cache() -> void:
 for entry in _cache.values():
  if is_instance_valid(entry.viewport):entry.viewport.queue_free()
 _cache.clear()
func _clear_outlines() -> void:
 for outline in _outlines:if is_instance_valid(outline):outline.queue_free()
 _outlines.clear()
func _process(delta: float) -> void:
 if is_instance_valid(_surface):_sync_scene_mode()
 if not enabled or not is_visible_in_tree():return
 for id in _cache.keys():
  var node: Object=_cache[id].node.get_ref()
  if not is_instance_valid(node) or not node.is_inside_tree():
   _cache[id].viewport.queue_free();_cache.erase(id)
 _elapsed+=delta
 if _elapsed>.25:_elapsed=0;_pending=true
 if _pending and not _busy:
  _pending=false
  _update_hover()
func _gui_input(event: InputEvent) -> void:
 if not enabled:return
 if event is InputEventKey:
  if event.pressed and event.keycode==KEY_ESCAPE:set_enabled(false);accept_event()
  return
 if event is InputEventMouseMotion:
  _mouse=event.position;_pending=true
  if _pressed:
   _dragging=_dragging or _mouse.distance_to(_press)>5
   queue_redraw();accept_event()
  return
 if not event is InputEventMouseButton:return
 if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] or event.alt_pressed or Input.is_key_pressed(KEY_SPACE):return
 _mouse=event.position
 if event.button_index==MOUSE_BUTTON_RIGHT:
  if event.pressed:_open_overlap(_mouse,event.shift_pressed)
  accept_event();return
 if event.pressed:
  _press=_mouse;_pressed=true;_dragging=false;grab_focus()
 elif _pressed:
  _pressed=false
  var area:=Rect2(_press,_mouse-_press).abs()
  var box:=_dragging;_dragging=false;queue_redraw()
  _select_at(_mouse,event.shift_pressed,area if box else Rect2())
 accept_event()
func _draw() -> void:
 if enabled and _dragging:
  var rect:=Rect2(_press,_mouse-_press).abs()
  draw_rect(rect,Color(.2,.7,1,.12));draw_rect(rect,Color(.2,.7,1),false,1)

func _snapshot(node: Control) -> Dictionary:
 return node.call("EditorSnapshot" if node.has_method("EditorSnapshot") else "editor_snapshot")
func _node_transform(node: CanvasItem) -> Transform2D:
 # Control sends a pixel-snapped local transform to RenderingServer, while
 # get_global_transform() retains fractional positions. Rebuild the rendered
 # hierarchy: authored HUDs can magnify that difference with large parent scales.
 var viewport:=node.get_viewport()
 var transform:=Transform2D.IDENTITY
 var current: CanvasItem=node
 while current:
  var local:=current.get_transform()
  if current is Control and viewport.is_snap_controls_to_pixels_enabled() and absf(sin(current.rotation*4.0))<.00001:
   local.origin=(local.origin+Vector2(.5,.5)).floor()
  transform=local*transform
  if current.is_set_as_top_level():break
  current=current.get_parent() as CanvasItem
 return viewport.global_canvas_transform*node.get_canvas_transform()*transform
func _screen_bounds(node: Control, bounds: Rect2) -> Rect2:
 var transform:=_node_transform(node)
 var result:=Rect2(transform*bounds.position,Vector2.ZERO)
 for point in [bounds.position+Vector2(bounds.size.x,0),bounds.end,bounds.position+Vector2(0,bounds.size.y)]:result=result.expand(transform*point)
 return result
func _eligible(node: Control) -> bool:
 if not node.is_visible_in_tree() or node.get_viewport()!=EditorInterface.get_editor_viewport_2d():return false
 if absf(_node_transform(node).determinant())<.000001:return false
 var alpha:=node.self_modulate.a
 var current: Node=node
 while current:
  if current.get_meta("_edit_lock_",false):return false
  if current is CanvasItem:alpha*=current.modulate.a
  current=current.get_parent()
 return alpha>.00001
func _clips(node: Control) -> Array:
 var result: Array=[]
 var parent:=node.get_parent()
 while parent and not parent is Viewport:
  if parent is Control and parent.clip_contents:
   result.push_front({"transform":_node_transform(parent),"size":parent.size})
  parent=parent.get_parent()
 return result
func _order(node: CanvasItem) -> Vector2i:
 var z:=node.z_index
 var current:=node
 while current.z_as_relative and current.get_parent() is CanvasItem:
  current=current.get_parent();z+=current.z_index
 var layer:=0
 var parent:=node.get_parent()
 while parent:
  if parent is CanvasLayer:layer=parent.layer;break
  parent=parent.get_parent()
 return Vector2i(layer,clampi(z,-4096,4096))
func _collect(node: Node, result: Array[Node]) -> void:
 for child in node.get_children():
  if child is CanvasItem and child.show_behind_parent:_collect(child,result)
 result.append(node)
 for child in node.get_children():
  if not child is CanvasItem or not child.show_behind_parent:_collect(child,result)
func candidates(area: Rect2) -> Array:
 var result: Array=[]
 var scene:=EditorInterface.get_edited_scene_root()
 if not scene:return result
 var nodes: Array[Node]=[]
 _collect(scene,nodes)
 var serial:=0
 for node in nodes:
  serial+=1
  if not node is Control or not node.has_method("editor_snapshot") and not node.has_method("EditorSnapshot"):continue
  if not _eligible(node):continue
  var snapshot:=_snapshot(node)
  if snapshot.is_empty() or not snapshot.get("mesh"):continue
  var bounds:=_screen_bounds(node,snapshot.bounds)
  if not bounds.grow(tolerance).intersects(area):continue
  var clips:=_clips(node)
  var clipped:=false
  for clip in clips:
   if absf(clip.transform.determinant())<.000001:clipped=true;break
  if clipped:continue
  result.append({"node":node,"snapshot":snapshot,"bounds":bounds,"clips":clips,"order":_order(node),"serial":serial})
 result.sort_custom(func(a,b):return a.order.x>b.order.x or (a.order.x==b.order.x and (a.order.y>b.order.y or (a.order.y==b.order.y and a.serial>b.serial))))
 return result
func selection_target(node: Node) -> Node:
 var scene:=EditorInterface.get_edited_scene_root()
 var result:=node
 while result!=scene and result.owner!=scene and not scene.is_editable_instance(result.owner):
  result=result.get_parent()
  if not result:return node
 var parent:=result.get_parent()
 while parent and parent!=scene.get_parent():
  if parent.get_meta("_edit_group_",false):result=parent
  parent=parent.get_parent()
 return result

func _mask(entry: Dictionary) -> Dictionary:
 var node: Control=entry.node
 var snap: Dictionary=entry.snapshot
 var rect: Rect2=entry.bounds.grow(3).intersection(Rect2(Vector2.ZERO,size))
 rect=Rect2(rect.position.floor(),rect.end.ceil()-rect.position.floor())
 if not rect.has_area():return {}
 var transform:=_node_transform(node)
 var signature:=str([snap.mesh.get_rid(),snap.parameters,snap.vertices_texture,snap.contour_texture,transform,entry.clips,rect])
 var id:=node.get_instance_id()
 _clock+=1
 if _cache.has(id) and _cache[id].signature==signature:
  _cache[id].used=_clock
  return _cache[id]
 if _cache.has(id):_cache[id].viewport.queue_free();_cache.erase(id)
 var viewport:=SubViewport.new();viewport.size=Vector2i(rect.size);viewport.transparent_bg=true
 viewport.disable_3d=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
 add_child(viewport)
 var origin:=Node2D.new();origin.position=-rect.position;viewport.add_child(origin)
 var parent: Node=origin
 var previous:=Transform2D.IDENTITY
 for clip in entry.clips:
  var carrier:=Node2D.new();carrier.transform=previous.affine_inverse()*clip.transform;parent.add_child(carrier)
  var container:=Control.new();container.size=clip.size;container.clip_contents=true;container.mouse_filter=Control.MOUSE_FILTER_IGNORE
  carrier.add_child(container);parent=container;previous=clip.transform
 var graphic:=MaskGraphic.new();graphic.mesh=snap.mesh;graphic.transform=previous.affine_inverse()*transform
 var material:=ShaderMaterial.new();material.shader=_mask_shader
 for key in snap.parameters:material.set_shader_parameter(key,snap.parameters[key])
 if snap.vertices_texture:material.set_shader_parameter("ui_vertices",snap.vertices_texture)
 if snap.contour_texture:
  material.set_shader_parameter("mold_polygon_points",snap.contour_texture)
  material.set_shader_parameter("mold_polygon_count",snap.count)
  material.set_shader_parameter("mold_polygon_aa_quality",snap.aa)
 graphic.material=material;parent.add_child(graphic)
 var cached: Dictionary={"viewport":viewport,"image":null,"rect":rect,"signature":signature,"used":_clock,"node":weakref(node)}
 _cache[id]=cached
 return cached
func _trim_cache() -> void:
 var pixels:=0
 for mask in _cache.values():pixels+=int(mask.rect.size.x*mask.rect.size.y)
 if _cache.size()<=CACHE_LIMIT and pixels<=CACHE_PIXEL_LIMIT:return
 var keys:=_cache.keys();keys.sort_custom(func(a,b):return _cache[a].used<_cache[b].used)
 for key in keys:
  if _cache.size()<=CACHE_LIMIT and pixels<=CACHE_PIXEL_LIMIT:break
  var mask: Dictionary=_cache[key]
  pixels-=int(mask.rect.size.x*mask.rect.size.y)
  mask.viewport.queue_free();_cache.erase(key)
func _sample(mask: Dictionary, point: Vector2, radius: int) -> bool:
 var image: Image=mask.image
 if not image:return false
 var center:=Vector2i((point-mask.rect.position).floor())
 for y in range(-radius,radius+1):
  for x in range(-radius,radius+1):
   if x*x+y*y>radius*radius:continue
   var pixel:=center+Vector2i(x,y)
   if pixel.x>=0 and pixel.y>=0 and pixel.x<image.get_width() and pixel.y<image.get_height() and image.get_pixelv(pixel).a>ALPHA_THRESHOLD:return true
 return false
func hits_at(point: Vector2, area:=Rect2()) -> Array[Control]:
 var epoch:=_epoch
 while _query_busy:
  await get_tree().process_frame
  if epoch!=_epoch:return []
 _query_busy=true
 var hits:=await _hits_at(point,area)
 if epoch==_epoch:_query_busy=false
 return hits
func _hits_at(point: Vector2, area: Rect2) -> Array[Control]:
 var hits: Array[Control]=[]
 var query:=area if area.has_area() else Rect2(point-Vector2.ONE*.5,Vector2.ONE).grow(tolerance)
 var entries:=candidates(query)
 var epoch:=_epoch
 # Limit simultaneous render targets; retained masks avoid repeated readbacks.
 for start in range(0,entries.size(),8):
  var batch: Array=[]
  var pending:=false
  for entry in entries.slice(start,start+8):
   var mask:=_mask(entry)
   if mask.is_empty():continue
   batch.append([entry,mask]);pending=pending or mask.image==null
  if pending:
   await RenderingServer.frame_post_draw
   await RenderingServer.frame_post_draw
   if epoch!=_epoch or not is_inside_tree():return hits
  for pair in batch:
   var entry: Dictionary=pair[0];var mask: Dictionary=pair[1]
   if not is_instance_valid(entry.node):continue
   if not mask.image:
    mask.image=mask.viewport.get_texture().get_image()
    mask.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
   var hit:=false
   if area.has_area():
    var local:=area.intersection(mask.rect)
    if local.has_area():
     var pixels:=Rect2i((local.position-mask.rect.position).floor(),local.size.ceil())
     hit=mask.image.get_region(pixels).get_used_rect().has_area()
   else:hit=_sample(mask,point,tolerance)
   if hit:hits.append(entry.node)
  _trim_cache()
 return hits
func _update_hover() -> void:
 _busy=true
 var epoch:=_epoch
 var hits:=await hits_at(_mouse)
 if epoch==_epoch and enabled:
  _hover=hits[0] if not hits.is_empty() else null
  hint.text=str(_hover.name)+( " • custom material: authored silhouette" if _snapshot(_hover).custom else "") if is_instance_valid(_hover) else "Click • Shift add • Right-click overlaps • Drag box • Esc exit"
  await _show_outlines()
 if epoch==_epoch:_busy=false
func _show_outlines() -> void:
 var epoch:=_epoch
 while _query_busy:
  await get_tree().process_frame
  if epoch!=_epoch:return
 _query_busy=true
 var selected:=EditorInterface.get_selection().get_selected_nodes()
 var outlines: Array=[]
 var entries:=candidates(Rect2(Vector2.ZERO,size))
 for start in range(0,entries.size(),8):
  var batch: Array=[]
  var pending:=false
  for entry in entries.slice(start,start+8):
   var node: Control=entry.node
   var chosen:=selection_target(node) in selected
   for ancestor in selected:
    if ancestor.is_ancestor_of(node):chosen=true
   if node!=_hover and not chosen:continue
   var mask:=_mask(entry)
   if mask.is_empty():continue
   batch.append([mask,chosen]);pending=pending or mask.image==null
  if pending:
   await RenderingServer.frame_post_draw
   await RenderingServer.frame_post_draw
   if epoch!=_epoch:return
  for pair in batch:
   var mask: Dictionary=pair[0]
   if not mask.image:
    mask.image=mask.viewport.get_texture().get_image()
    mask.viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
   if not mask.has("texture"):mask.texture=ImageTexture.create_from_image(mask.image)
   outlines.append([mask.rect,mask.texture,pair[1]])
  _trim_cache()
 _query_busy=false
 _clear_outlines()
 for outline in outlines:
  var view:=TextureRect.new();view.mouse_filter=MOUSE_FILTER_IGNORE
  view.texture_filter=CanvasItem.TEXTURE_FILTER_LINEAR
  view.position=outline[0].position;view.size=outline[0].size;view.texture=outline[1]
  var material:=ShaderMaterial.new();material.shader=_outline_shader
  material.set_shader_parameter("outline_color",SelectionStyle.color(outline[2]))
  material.set_shader_parameter("outline_width",SelectionStyle.width(outline[2]))
  view.material=material;add_child(view);_outlines.append(view)
func _apply_selection(nodes: Array, additive: bool) -> void:
 var selection:=EditorInterface.get_selection()
 if not additive:selection.clear()
 var resolved: Array[Node]=[]
 for node in nodes:
  if not is_instance_valid(node):continue
  var target:=selection_target(node)
  if target in resolved:continue
  resolved.append(target)
  if additive and target in selection.get_selected_nodes():selection.remove_node(target)
  else:selection.add_node(target)
 var current:=selection.get_selected_nodes()
 if current.size()==1:EditorInterface.edit_node(current[0])
 host.update_overlays();_pending=true
func _select_at(point: Vector2, additive: bool, area: Rect2) -> void:
 var epoch:=_epoch
 var hits:=await hits_at(point,area)
 if epoch!=_epoch or not enabled:return
 _apply_selection(hits if area.has_area() else hits.slice(0,1),additive)
func _open_overlap(point: Vector2, additive: bool) -> void:
 var epoch:=_epoch
 var hits:=await hits_at(point)
 if epoch!=_epoch or not enabled:return
 popup.clear();_popup_nodes.clear();_popup_add=additive
 for node in hits:
  var target:=selection_target(node)
  if target in _popup_nodes:continue
  _popup_nodes.append(target)
  popup.add_item(str(EditorInterface.get_edited_scene_root().get_path_to(target)),_popup_nodes.size()-1)
 if _popup_nodes.is_empty():return
 popup.position=Vector2i(get_screen_transform()*point);popup.popup()
func _choose_popup(index: int) -> void:
 if index>=0 and index<_popup_nodes.size():_apply_selection([_popup_nodes[index]],_popup_add)

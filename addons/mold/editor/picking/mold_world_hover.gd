@tool
extends RefCounted
const Contours=preload("mold_contour_mesh.gd")
const Style=preload("mold_selection_style.gd")
const Outline=preload("mold_outline.gdshader")
var host: EditorPlugin
var entries: Dictionary={}
var hover: Node3D
var camera: Camera3D
var mouse:=Vector2.ZERO
var suspended:=false
var elapsed:=0.0
var _selected: Array=[]
var _hover_target: Node3D
var _selected_material: ShaderMaterial
var _hover_material: ShaderMaterial
var _occluder_faces: Dictionary={}

func install(plugin: EditorPlugin) -> void:
 host=plugin
 _selected=EditorInterface.get_selection().get_selected_nodes()
 # The point editor enables input forwarding once for this host.
 host.scene_changed.connect(_scene_changed)
 EditorInterface.get_selection().selection_changed.connect(_selection_changed)

func uninstall() -> void:
 _set_hover(null)
 if host.scene_changed.is_connected(_scene_changed):host.scene_changed.disconnect(_scene_changed)
 if EditorInterface.get_selection().selection_changed.is_connected(_selection_changed):EditorInterface.get_selection().selection_changed.disconnect(_selection_changed)
 entries.clear();_clear_occluders();host=null;camera=null

func _scene_changed(_root: Node) -> void:
 _set_hover(null);camera=null;entries.clear();_clear_occluders()
 host.call_deferred("update_overlays")
 if _root:
  for node in _root.find_children("*","Node3D",true,false):node.update_gizmos()

func _selection_changed() -> void:
 var previous:=_selected
 _selected=EditorInterface.get_selection().get_selected_nodes()
 for entry in entries.values():
  var node=entry.node.get_ref()
  if is_instance_valid(node):node.update_gizmos()
 for node in previous+_selected:
  if is_instance_valid(node) and node is Node3D:node.update_gizmos()

func selected(node: Node3D) -> bool:
 for target in _selected:
  if is_instance_valid(target) and (target==node or target.is_ancestor_of(node)):return true
 return false

func draw_gizmo(gizmo: EditorNode3DGizmo, faces: PackedVector3Array, segments: PackedVector3Array) -> void:
 var node:=gizmo.get_node_3d();var id:=node.get_instance_id()
 var entry: Dictionary=entries.get(id,{})
 if entry.is_empty() or entry.faces!=faces or entry.segments!=segments:
  var bounds:=AABB(faces[0],Vector3.ZERO) if not faces.is_empty() else AABB()
  for vertex in faces:bounds=bounds.expand(vertex)
  entry={"node":weakref(node),"faces":faces,"segments":segments,"bounds":bounds.grow(.00001),"mesh":null}
  entries[id]=entry
 var chosen:=selected(node)
 if not chosen and not hovered(node):
  # The cleared gizmo no longer needs its contour. Cleanup is local to this
  # entry, rather than scanning the entire registry for every shape redraw.
  entry.mesh=null
  return
 if entry.mesh==null:entry.mesh=Contours.build(faces,segments)
 if entry.mesh.get_surface_count()==0:return
 gizmo.add_mesh(entry.mesh,_outline_material(chosen))

func _outline_material(chosen: bool) -> ShaderMaterial:
 var material:=_selected_material if chosen else _hover_material
 if material==null:
  material=ShaderMaterial.new();material.shader=Outline
  material.set_shader_parameter("outline_color",Style.color(chosen))
  material.set_shader_parameter("width_pixels",Style.width(chosen))
  material.set_shader_parameter("hover_only",not chosen)
  if chosen:_selected_material=material
  else:
   _hover_material=material
   _update_hover_camera()
 return material

func _update_hover_camera() -> void:
 if _hover_material!=null and is_instance_valid(camera):
  _hover_material.set_shader_parameter("hover_camera",camera.global_transform)
  _hover_material.set_shader_parameter("hover_projection",camera.get_camera_projection())

func forward_input(view: Camera3D, event: InputEvent, consumed: bool) -> void:
 if event is InputEventMouse:
  if camera!=view:_set_hover(null)
  camera=view;mouse=_viewport_point(view,event.position)
  suspended=consumed or event.button_mask!=0 or event.alt_pressed
  if suspended:_set_hover(null)
  # Mouse events only record the latest position. tick coalesces picking to
  # 20 Hz, including stationary-pointer checks for scene/camera changes.

func tick(delta: float) -> void:
 elapsed+=delta
 if elapsed<0.05:return
 elapsed=0
 if not is_instance_valid(camera) or suspended:return
 var viewport:=camera.get_viewport()
 var container:=viewport.get_parent() as SubViewportContainer
 if not host.get_window().has_focus():
  _set_hover(null);return
 if container:
  var hovered_control:=host.get_viewport().gui_get_hovered_control()
  if hovered_control and not container.get_parent().is_ancestor_of(hovered_control):
   _set_hover(null);return
  var position:=container.get_local_mouse_position()
  if not container.is_visible_in_tree() or not Rect2(Vector2.ZERO,container.size).has_point(position):
   _set_hover(null);return
  mouse=_viewport_point(camera,position)
 _update_hover()

func _set_hover(node: Node3D) -> void:
 var old_target:=_hover_target if is_instance_valid(_hover_target) else null
 var new_target:=selection_target(node) if is_instance_valid(node) else null
 hover=node;_hover_target=new_target
 # Crossing children of one packed scene changes the hit, not its outline.
 if old_target==new_target:return
 for entry in entries.values():
  var candidate=entry.node.get_ref()
  if not is_instance_valid(candidate):continue
  if (old_target and (old_target==candidate or old_target.is_ancestor_of(candidate))) or (new_target and (new_target==candidate or new_target.is_ancestor_of(candidate))):candidate.update_gizmos()

func _update_hover() -> void:
 if not is_instance_valid(camera):return
 _set_hover(hit_at(camera,mouse))
 _update_hover_camera()

func hit_at(view: Camera3D, point: Vector2) -> Node3D:
 var origin:=view.project_ray_origin(point);var direction:=view.project_ray_normal(point)
 var nearest:=INF
 var winner: Node3D
 var root:=EditorInterface.get_edited_scene_root()
 if not root:return null
 for id in entries.keys():
  var entry: Dictionary=entries[id];var node: Node3D=entry.node.get_ref()
  if not is_instance_valid(node):entries.erase(id);continue
  if not node.is_inside_tree() or not node.is_visible_in_tree() or (node!=root and not root.is_ancestor_of(node)):continue
  if selection_target(node)==null:continue
  var cs: bool=node.get_script().resource_path.ends_with(".cs")
  if not node.get("PreviewInEditor" if cs else "preview_in_editor"):continue
  var layers: int=node.get("RenderLayerMask" if cs else "render_layer_mask")
  if (layers & view.cull_mask)==0:continue
  var transform:=node.global_transform
  if absf(transform.basis.determinant())<.000001:continue
  var inverse:=transform.affine_inverse()
  if not entry.faces.is_empty() and entry.bounds.intersects_ray(inverse*origin,inverse.basis*direction)==null:continue
  var distance:=ray_distance(entry.faces,transform,origin,direction)
  for i in range(0,entry.segments.size(),2):
   var a: Vector3=transform*entry.segments[i];var b: Vector3=transform*entry.segments[i+1]
   if view.is_position_behind(a) or view.is_position_behind(b):continue
   var screen:=Geometry2D.get_closest_point_to_segment(point,view.unproject_position(a),view.unproject_position(b))
   if screen.distance_to(point)>6.0*EditorInterface.get_editor_scale():continue
   var pair:=Geometry3D.get_closest_points_between_segments(origin,origin+direction*view.far,a,b)
   distance=minf(distance,origin.distance_to(pair[1]))
  if distance<nearest:
   var hit_depth: float=-(view.global_transform.affine_inverse()*(origin+direction*distance)).z
   if hit_depth>=view.near and hit_depth<=view.far:nearest=distance;winner=node
 # Ordinary mesh occluders need no physics collision body. Mold previews are
 # excluded because their support meshes differ from their rendered geometry.
 if winner:
  for other in root.find_children("*","MeshInstance3D",true,false):
   if not other.is_visible_in_tree() or not other.mesh or other.get_parent().get_instance_id() in entries:continue
   if (other.layers & view.cull_mask)==0:continue
   if absf(other.global_transform.basis.determinant())<.000001:continue
   var inverse: Transform3D=other.global_transform.affine_inverse()
   if other.mesh.get_aabb().intersects_ray(inverse*origin,inverse.basis*direction)==null:continue
   var mesh: Mesh=other.mesh
   var key:=mesh.get_rid()
   if not _occluder_faces.has(key):
    if _occluder_faces.size()>=32:_invalidate_occluder(_occluder_faces.keys()[0])
    var changed:=_invalidate_occluder.bind(key)
    _occluder_faces[key]={"mesh":mesh,"faces":mesh.get_faces(),"changed":changed}
    mesh.changed.connect(changed,CONNECT_ONE_SHOT)
   if ray_distance(_occluder_faces[key].faces,other.global_transform,origin,direction)<nearest-.0001:return null
 return winner

static func ray_distance(faces: PackedVector3Array, transform: Transform3D, origin: Vector3, direction: Vector3) -> float:
 if faces.is_empty() or absf(transform.basis.determinant())<.000001:return INF
 var inverse:=transform.affine_inverse()
 var local_origin:=inverse*origin;var local_direction:=inverse.basis*direction
 var nearest:=INF
 for i in range(0,faces.size(),3):
  var hit=Geometry3D.ray_intersects_triangle(local_origin,local_direction,faces[i],faces[i+1],faces[i+2])
  if hit!=null:nearest=minf(nearest,origin.distance_to(transform*hit))
 return nearest

static func selection_target(node: Node3D) -> Node3D:
 var root:=EditorInterface.get_edited_scene_root()
 if not root or (node!=root and not root.is_ancestor_of(node)):return null
 var target: Node=node
 if target!=root:
  if not target.owner:return null
  while target!=root and target.owner!=root and not (target.owner and root.is_editable_instance(target.owner)):
   target=target.get_parent()
 var ancestor: Node=target
 while ancestor and ancestor!=root.get_parent():
  if ancestor.has_meta("_edit_group_") and ancestor is Node3D:target=ancestor
  ancestor=ancestor.get_parent()
 if target.has_meta("_edit_lock_"):return null
 return target as Node3D

static func _viewport_point(view: Camera3D, position: Vector2) -> Vector2:
 var viewport:=view.get_viewport()
 var container:=viewport.get_parent() as SubViewportContainer
 # Editor input is in Control coordinates, which can differ from the render
 # viewport at reduced resolution or on high-density displays.
 return position*Vector2(viewport.size)/container.size if container and container.size.x>0 and container.size.y>0 else position

func _invalidate_occluder(key: RID) -> void:
 if not _occluder_faces.has(key):return
 var entry: Dictionary=_occluder_faces[key]
 if entry.mesh.changed.is_connected(entry.changed):entry.mesh.changed.disconnect(entry.changed)
 _occluder_faces.erase(key)

func _clear_occluders() -> void:
 for key in _occluder_faces.keys():_invalidate_occluder(key)

func hovered(node: Node3D) -> bool:
 return is_instance_valid(_hover_target) and (_hover_target==node or _hover_target.is_ancestor_of(node))

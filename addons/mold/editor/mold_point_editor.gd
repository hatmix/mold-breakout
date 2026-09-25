@tool
extends RefCounted

# Coordinates point selection, viewport input and Undo actions.
const Properties = preload("mold_editor_properties.gd")
const PointGizmo = preload("gizmos/mold_point_gizmo.gd")
const PointInspector = preload("inspectors/mold_point_inspector.gd")
var _last_field_point: WeakRef
var _last_field_owner: WeakRef
var _last_field_key := ""
var host: EditorPlugin
var gizmo_plugin: EditorNode3DGizmoPlugin
var inspector_plugin: EditorInspectorPlugin
var target: Node3D
var selected_point := -1
var selected_role := 0
var drag_snapshot: Array = []
var hover_part := 0
var drag_part := 0
var drag_before := Vector3.ZERO
var drag_anchor := Vector3.ZERO
var drag_camera: Camera3D
var toggle_buttons: Array[WeakRef] = []
var index_buttons: Array[WeakRef] = []
var show_indices := true

static func shape_property(node: Object) -> String:
	if not node is Node3D or not node.get_script(): return ""
	var path: String = node.get_script().resource_path
	if path.ends_with("/mold_polygon_node_3d.gd"): return "polygon"
	if path.ends_with("/mold_curve_node_3d.gd"): return "polyline"
	if path.ends_with("/MoldCurveNode3D.cs"): return "Polyline"
	if path.ends_with("/mold_polyline_node_3d.gd"): return "polyline"
	if path.ends_with("/MoldPolygonNode3D.cs"): return "Polygon"
	if path.ends_with("/MoldPolylineNode3D.cs"): return "Polyline"
	return ""

static func field(node: Object, gd_name: String, cs_name: String) -> String:
	return Properties.api_name(node, gd_name, cs_name)

static func positions(node: Node3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	var property := shape_property(node)
	var resource: Resource = node.get(property)
	if not resource: return result
	for point in resource.get(field(node,"points","Points")):
		result.append(point.get(field(node,"position","Position")) if point else Vector3.ZERO)
	return result

func install(plugin: EditorPlugin) -> void:
	host = plugin
	show_indices = EditorInterface.get_editor_settings().get_project_metadata("mold","show_point_indices",true)
	host.set_force_draw_over_forwarding_enabled()
	host.set_input_event_forwarding_always_enabled()
	gizmo_plugin = PointGizmo.new(self)
	inspector_plugin = PointInspector.new(self)
	host.add_node_3d_gizmo_plugin(gizmo_plugin)
	host.add_inspector_plugin(inspector_plugin)
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)

func uninstall() -> void:
	set_target(null)
	EditorInterface.get_selection().selection_changed.disconnect(_selection_changed)
	host.remove_inspector_plugin(inspector_plugin)
	host.remove_node_3d_gizmo_plugin(gizmo_plugin)
	inspector_plugin = null
	gizmo_plugin = null
	host = null
	toggle_buttons.clear()
	index_buttons.clear()


func set_show_indices(value: bool) -> void:
	show_indices = value
	EditorInterface.get_editor_settings().set_project_metadata("mold","show_point_indices",value)
	for ref in index_buttons:
		var button = ref.get_ref()
		if is_instance_valid(button): button.set_pressed_no_signal(value)
	host.update_overlays()

func update_labels() -> void:
	# Camera navigation, resource edits, and animated editor previews all repaint.
	if is_instance_valid(target):
		target.update_gizmos()
		host.update_overlays()
	if not show_indices: return
	for node in EditorInterface.get_selection().get_selected_nodes():
		if not shape_property(node).is_empty():
			host.update_overlays()
			return

func overlay_camera(control: Control) -> Camera3D:
	# Match by ancestry rather than viewport size: split views may share a size.
	var parent: Node = control
	while parent:
		for i in 4:
			var viewport := EditorInterface.get_editor_viewport_3d(i)
			if viewport and parent.is_ancestor_of(viewport): return viewport.get_camera_3d()
		parent = parent.get_parent()
	return null

func index_labels(camera: Camera3D, size: Vector2) -> Array:
	var labels := []
	if not show_indices or not camera: return labels
	var viewport_size := camera.get_viewport().get_visible_rect().size
	if viewport_size.x <= 0 or viewport_size.y <= 0: return labels
	for node in EditorInterface.get_selection().get_selected_nodes():
		if shape_property(node).is_empty(): continue
		var vertices := positions(node)
		var resource: Resource = node.get(shape_property(node))
		for i in vertices.size():
			if not vertices[i].is_finite(): continue
			if not resource.get(field(node,"points","Points"))[i]: continue
			var world: Vector3 = node.global_transform * vertices[i]
			if camera.is_position_behind(world): continue
			var screen := camera.unproject_position(world) * size / viewport_size
			if not Rect2(Vector2.ZERO,size).has_point(screen): continue
			labels.append([screen,str(i)])
	return labels

func draw_indices(control: Control) -> void:
	var camera := overlay_camera(control)
	draw_move_gizmo(control,camera)
	var font := EditorInterface.get_editor_theme().get_font("font","Label")
	var scale := EditorInterface.get_editor_scale()
	var font_size := roundi(14*scale)
	for label in index_labels(camera,control.size):
		var position: Vector2 = label[0] + Vector2(8,-8)*scale
		control.draw_string_outline(font,position,label[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,roundi(4*scale),Color.BLACK)
		control.draw_string(font,position,label[1],HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)

# The movement controls are viewport overlays: drawing and picking share exactly
# the same projected geometry, including in split views and under scaled parents.
func spatial_points(node: Node3D) -> bool:
	if not is_instance_valid(node) or shape_property(node).to_lower() != "polyline": return false
	var resource: Resource = node.get(shape_property(node))
	return resource != null and resource.get(field(node,"geometry","Geometry")) == 1

func plane_start(part: int) -> int:
	return 3 if part == 3 else (8 if part == 5 else 12)

func axis_index(part: int) -> int:
	return part-1 if part < 3 else 2

func move_geometry(camera: Camera3D) -> PackedVector2Array:
	if not camera or not is_instance_valid(target) or selected_point < 0: return PackedVector2Array()
	var vertices := positions(target)
	if selected_point >= vertices.size() or not vertices[selected_point].is_finite(): return PackedVector2Array()
	if absf(target.global_basis.determinant()) < 0.0000001: return PackedVector2Array()
	var p := target.to_global(control_position(target,selected_point,selected_role))
	if camera.is_position_behind(p): return PackedVector2Array()
	var pixels := camera.unproject_position(p).distance_to(camera.unproject_position(p+camera.global_basis.x))
	# Unity GetHandleSize represents 80 UI pixels; its move gizmo uses 0.7.
	var length := 56.0*EditorInterface.get_editor_scale()/maxf(pixels,0.001)
	var x := target.global_basis.x.normalized()*length
	var y := target.global_basis.y.normalized()*length
	var result := PackedVector2Array()
	var worlds := [p,p+x,p+y,p+x*0.14+y*0.14,p+x*0.34+y*0.14,p+x*0.34+y*0.34,p+x*0.14+y*0.34]
	if spatial_points(target):
		var z := target.global_basis.z.normalized()*length
		worlds.append_array([p+z,p+x*0.14+z*0.14,p+x*0.34+z*0.14,p+x*0.34+z*0.34,p+x*0.14+z*0.34,p+y*0.14+z*0.14,p+y*0.34+z*0.14,p+y*0.34+z*0.34,p+y*0.14+z*0.34])
	for world in worlds:
		if camera.is_position_behind(world): return PackedVector2Array()
		result.append(camera.unproject_position(world))
	return result

func arrow_head(origin: Vector2, tip: Vector2) -> PackedVector2Array:
	var direction := (tip-origin).normalized()
	var side := Vector2(-direction.y,direction.x)
	var size := minf(12.0*EditorInterface.get_editor_scale(),origin.distance_to(tip)*0.3)
	return PackedVector2Array([tip,tip-direction*size+side*size*0.45,tip-direction*size-side*size*0.45])

func pick_move(camera: Camera3D, cursor: Vector2) -> int:
	var g := move_geometry(camera)
	if g.is_empty(): return 0
	for plane in ([3,5,6] if g.size()>7 else [3]):
		var start := plane_start(plane)
		if Geometry2D.is_point_in_polygon(cursor,PackedVector2Array([g[start],g[start+1],g[start+2],g[start+3]])): return plane
	var best := 8.0*EditorInterface.get_editor_scale()
	var part := 0
	for axis in ([1,2,4] if g.size()>7 else [1,2]):
		var tip_index: int = axis if axis<3 else 7
		if g[0].distance_to(g[tip_index]) < 12.0*EditorInterface.get_editor_scale(): continue
		var start := g[0].lerp(g[tip_index],0.16)
		var distance := cursor.distance_to(Geometry2D.get_closest_point_to_segment(cursor,start,g[tip_index]))
		if Geometry2D.is_point_in_polygon(cursor,arrow_head(g[0],g[tip_index])): distance = 0.0
		if distance < best: best = distance; part = axis
	return part

func draw_move_gizmo(control: Control, camera: Camera3D) -> void:
	var g := move_geometry(camera)
	if g.is_empty(): return
	var ratio := control.size / camera.get_viewport().get_visible_rect().size
	for i in g.size(): g[i] *= ratio
	var active := drag_part if drag_part != 0 else hover_part
	for axis in ([1,2,4] if g.size()>7 else [1,2]):
		var tip_index: int = axis if axis<3 else 7
		if g[0].distance_to(g[tip_index]) < 12.0*EditorInterface.get_editor_scale(): continue
		var color := Color(1,0.25,0.25) if axis == 1 else (Color(0.3,1,0.3) if axis == 2 else Color(0.3,0.6,1))
		if active == axis: color = Color(1,1,0.4)
		control.draw_line(g[0],g[tip_index],color,3.0*EditorInterface.get_editor_scale(),true)
		control.draw_colored_polygon(arrow_head(g[0],g[tip_index]),color)
	for plane in ([3,5,6] if g.size()>7 else [3]):
		var start := plane_start(plane)
		var square := PackedVector2Array([g[start],g[start+1],g[start+2],g[start+3]])
		var color := Color(1,1,0.4) if active == plane else Color(1,0.85,0.15)
		if absf((square[1]-square[0]).cross(square[3]-square[0])) > 0.1:
			control.draw_colored_polygon(square,Color(color,0.45 if active == plane else 0.2))
		square.append(square[0])
		control.draw_polyline(square,color,2.0*EditorInterface.get_editor_scale(),true)

func drag_projection(camera: Camera3D, cursor: Vector2, part: int) -> Variant:
	var inverse := target.global_transform.affine_inverse()
	var origin := inverse*camera.project_ray_origin(cursor)
	var direction := (inverse.basis*camera.project_ray_normal(cursor)).normalized()
	if part in [3,5,6]:
		var normal_axis := 2 if part == 3 else (1 if part == 5 else 0)
		if absf(direction[normal_axis]) < 0.000001: return null
		var distance := (drag_before[normal_axis]-origin[normal_axis])/direction[normal_axis]
		if distance < 0: return null
		return origin+direction*distance
	var axis := Vector3.ZERO
	axis[axis_index(part)] = 1.0
	var dot := axis.dot(direction)
	if 1.0-dot*dot < 0.000001: return null
	var delta := origin-drag_before
	return axis*((axis.dot(delta)-dot*direction.dot(delta))/(1.0-dot*dot))

func finish_drag(cancel: bool) -> void:
	if drag_part == 0: return
	if is_instance_valid(target) and selected_point >= 0 and selected_point < positions(target).size():
		var gizmo := EditorNode3DGizmo.new()
		gizmo.set_node_3d(target)
		gizmo_plugin._commit_handle(gizmo,selected_point*4+selected_role,false,drag_snapshot if is_curve(target) else drag_before,cancel)
		gizmo.clear()
	drag_part = 0
	drag_camera = null
	host.update_overlays()

func forward_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(target): return EditorPlugin.AFTER_GUI_INPUT_PASS
	if drag_part != 0:
		if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
			finish_drag(true)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			finish_drag(false)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		if event is InputEventMouseMotion:
			if camera != drag_camera: return EditorPlugin.AFTER_GUI_INPUT_STOP
			var projection = drag_projection(camera,event.position,drag_part)
			if projection != null:
				var value: Vector3 = drag_before+(projection-drag_anchor)
				if not spatial_points(target): value.z = drag_before.z
				if EditorInterface.is_node_3d_snap_enabled() != Input.is_key_pressed(KEY_CTRL):
					var step := EditorInterface.get_node_3d_translate_snap()
					for axis in 3:
						var allowed: bool = axis == axis_index(drag_part) if drag_part in [1,2,4] else axis != (2 if drag_part == 3 else (1 if drag_part == 5 else 0))
						if allowed: value[axis] = snappedf(value[axis],step)
				if value.is_finite(): set_point(target,selected_point,value)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		hover_part = pick_move(camera,event.position)
		host.update_overlays()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not event.alt_pressed:
		var part := pick_move(camera,event.position)
		if part != 0:
			drag_before = control_position(target,selected_point,selected_role)
			drag_snapshot = control_snapshot(target,selected_point) if is_curve(target) else []
			var anchor = drag_projection(camera,event.position,part)
			if anchor != null:
				drag_anchor = anchor
				drag_part = part
				drag_camera = camera
				return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS

func _selection_changed() -> void:
	host.update_overlays()
	var selected := EditorInterface.get_selection().get_selected_nodes()
	if not is_instance_valid(target) or selected.size() != 1 or selected[0] != target: set_target(null)

func set_target(node: Node3D) -> void:
	if target != node and drag_part != 0: finish_drag(true)
	hover_part = 0
	if target != node: selected_point = -1; selected_role = 0
	var previous := target
	target = node
	if is_instance_valid(previous): previous.update_gizmos()
	if is_instance_valid(target): target.update_gizmos()
	for ref in toggle_buttons:
		var button = ref.get_ref()
		if is_instance_valid(button): button.text = "Done" if button.get_meta("mold_target") == target else "Edit Points"

func refresh(node: Node3D) -> void:
	if not is_instance_valid(node): return
	node.update_gizmos()

static func curve_resource(object: Object) -> bool:
	return object is Resource and object.get_script() and (object.get_script().resource_path.ends_with("/mold_curve_resource.gd") or object.get_script().resource_path.ends_with("/MoldCurveResource.cs"))
func is_curve(node: Node3D) -> bool:
	return is_instance_valid(node) and not shape_property(node).is_empty() and curve_resource(node.get(shape_property(node)))
func has_tangents(node: Node3D) -> bool:
	if not is_curve(node): return false
	var resource: Resource = node.get(shape_property(node))
	return resource.get(resource_field(resource,"kind","Kind")) in [0,3]
func control_position(node: Node3D,index: int,role: int) -> Vector3:
	if not has_tangents(node) or role==0: return positions(node)[index]
	var resource: Resource = node.get(shape_property(node))
	return resource.call(resource_field(resource,"handle_position","HandlePosition"),index,role)
func control_snapshot(node: Node3D,index: int) -> Array:
	var resource: Resource = node.get(shape_property(node))
	var point: Resource = resource.get(field(node,"points","Points"))[index]
	return [point.get(field(node,"position","Position")),point.get(field(node,"in_offset","InOffset")),point.get(field(node,"out_offset","OutOffset")),point.get(field(node,"mode","Mode"))]
func restore_control(node: Node3D,index: int,values: Array) -> void:
	var resource: Resource = node.get(shape_property(node))
	var point: Resource = resource.get(field(node,"points","Points"))[index]
	var names := [field(node,"position","Position"),field(node,"in_offset","InOffset"),field(node,"out_offset","OutOffset"),field(node,"mode","Mode")]
	for i in names.size(): point.set(names[i],values[i])
	var peer := closing_peer(node.get(shape_property(node)),point)
	if peer: peer.set(names[0],values[0])
	refresh(node)

func set_point(node: Node3D, index: int, value: Vector3) -> void:
	var property := shape_property(node)
	var resource: Resource = node.get(property)
	if not resource: return
	var points = resource.get(field(node,"points","Points"))
	if index >= points.size() or not points[index]: return
	if is_curve(node) and selected_role!=0:
		resource.call(resource_field(resource,"move_handle","MoveHandle"),index,selected_role,value)
	else:
		points[index].set(field(node,"position","Position"),value)
		var peer := closing_peer(resource,points[index])
		if peer: peer.set(field(node,"position","Position"),value)
	refresh(node)

func make_unique(node: Node3D) -> void:
	var property := shape_property(node)
	var original: Resource = node.get(property)
	if not original: return
	var copy := original.duplicate(true)
	if property.to_lower() in ["polyline", "polygon"]:
		# Explicitly duplicate nested points, including on Godot versions where
		# Resource.duplicate(true) does not recurse through resource arrays.
		var key := field(node,"points","Points")
		var points = copy.get(key).duplicate()
		for i in points.size():
			if points[i]: points[i] = points[i].duplicate(true)
		copy.set(key,points)
	var undo := host.get_undo_redo()
	undo.create_action("Make Mold Shape Unique",UndoRedo.MERGE_DISABLE,node)
	undo.add_do_property(node,property,copy)
	undo.add_undo_property(node,property,original)
	undo.commit_action()

static func polyline_resource(object: Object) -> bool:
	if not object is Resource or not object.get_script(): return false
	var path: String = object.get_script().resource_path
	return curve_resource(object) or path.ends_with("/mold_polyline_resource.gd") or path.ends_with("/MoldPolylineResource.cs")

static func resource_field(resource: Resource, gd: String, cs: String) -> String:
	return Properties.api_name(resource, gd, cs)

# Closing quadratics adds a segment; the explicit closing endpoint is not an ordinary extra control.
func set_curve_closed(resource: Resource, value: int) -> void:
	var key := resource_field(resource,"closed","Closed")
	var closed := bool(value)
	if resource.get(key)==closed: return
	var points_key := resource_field(resource,"points","Points")
	var position := resource_field(resource,"position","Position")
	var points: Array = resource.get(points_key).duplicate()
	var kind: int = resource.get(resource_field(resource,"kind","Kind"))
	if kind==1 and points.size()>=3:
		if closed and points[0].get(position).distance_to(points[-1].get(position))>0.000001:
			var midpoint: Resource = points[-1].duplicate()
			midpoint.set(position,(points[-1].get(position)+points[0].get(position))*.5)
			points.append(midpoint)
			points.append(points[0].duplicate())
		elif not closed and points.size()>3: points.resize(points.size()-2)
	var undo := host.get_undo_redo()
	undo.create_action("Set Mold Curve Closed",UndoRedo.MERGE_DISABLE,resource)
	undo.add_do_method(resource,"set_block_signals",true)
	undo.add_undo_method(resource,"set_block_signals",true)
	for entry in [[points_key,points],[key,closed]]:
		undo.add_do_property(resource,entry[0],entry[1])
		undo.add_undo_property(resource,entry[0],resource.get(entry[0]))
	if kind in [4,5]:
		var knots := resource_field(resource,"knot_vector","KnotVector")
		undo.add_do_property(resource,knots,PackedFloat32Array())
		undo.add_undo_property(resource,knots,resource.get(knots))
	undo.add_do_method(resource,"set_block_signals",false)
	undo.add_undo_method(resource,"set_block_signals",false)
	undo.add_do_method(resource,"emit_changed")
	undo.add_undo_method(resource,"emit_changed")
	undo.add_do_method(resource,"notify_property_list_changed")
	undo.add_undo_method(resource,"notify_property_list_changed")
	undo.commit_action()

static func closing_peer(resource: Resource, point: Resource) -> Resource:
	if not curve_resource(resource) or resource.get(resource_field(resource,"kind","Kind"))!=1 or not resource.get(resource_field(resource,"closed","Closed")): return null
	var points: Array = resource.get(resource_field(resource,"points","Points"))
	if points.size()<3: return null
	return points[-1] if point==points[0] else points[0] if point==points[-1] else null

func set_curve_kind(resource: Resource, value: int) -> void:
	var kind := resource_field(resource,"kind","Kind")
	var previous: int = resource.get(kind)
	if value == previous: return
	var points_key := resource_field(resource,"points","Points")
	var position := resource_field(resource,"position","Position")
	var degree_key := resource_field(resource,"degree","Degree")
	var knots_key := resource_field(resource,"knot_vector","KnotVector")
	var closed: bool = resource.get(resource_field(resource,"closed","Closed"))
	var original: Array = resource.get(points_key)
	var points := original.duplicate()
	# A closed quadratic stores its closing endpoint explicitly; other kinds do not.
	if previous == 1 and closed and points.size() > 2 and points[0].get(position).distance_to(points[-1].get(position)) <= 0.000001:
		points.remove_at(points.size()-1)
	if value == 2:
		var count := points.size()
		for i in range(count-1,0,-1):
			if points[i].get(position).distance_to(points[i-1].get(position)) <= 0.000001: points.remove_at(i)
		if closed and points.size() > 1 and points[0].get(position).distance_to(points[-1].get(position)) <= 0.000001:
			points.remove_at(points.size()-1)
	var point_script = load(resource.get_script().resource_path.replace("mold_curve_resource.gd","mold_curve_point_resource.gd").replace("MoldCurveResource.cs","MoldCurvePointResource.cs"))
	while points.size() < 2:
		var point: Resource = point_script.new()
		point.set(position,Vector3.ZERO if points.is_empty() else points[0].get(position)+Vector3.RIGHT)
		points.append(point)
	if value == 1:
		if closed and points[0].get(position).distance_to(points[-1].get(position)) > 0.000001:
			points.append(points[0].duplicate(true))
		if points.size() % 2 == 0:
			var midpoint: Resource = point_script.new()
			midpoint.set(position,(points[-2].get(position)+points[-1].get(position))*0.5)
			points.insert(points.size()-1,midpoint)
	var degree: int = resource.get(degree_key)
	var knots: PackedFloat32Array = resource.get(knots_key)
	if value in [4,5]:
		degree = clampi(degree,1,mini(32,points.size()-1))
		if closed or previous not in [4,5] or points.size() != original.size() or degree != resource.get(degree_key):
			knots = PackedFloat32Array()
	# Suppress intermediate notifications: gizmos can rebuild synchronously on a property change.
	var undo := host.get_undo_redo()
	undo.create_action("Set Mold Curve Kind",UndoRedo.MERGE_DISABLE,resource)
	undo.add_do_method(resource,"set_block_signals",true)
	undo.add_undo_method(resource,"set_block_signals",true)
	for entry in [[points_key,points],[degree_key,degree],[knots_key,knots],[kind,value]]:
		undo.add_do_property(resource,entry[0],entry[1])
		undo.add_undo_property(resource,entry[0],resource.get(entry[0]))
	undo.add_do_method(resource,"set_block_signals",false)
	undo.add_undo_method(resource,"set_block_signals",false)
	undo.add_do_method(resource,"emit_changed")
	undo.add_undo_method(resource,"emit_changed")
	undo.add_do_method(resource,"notify_property_list_changed")
	undo.add_undo_method(resource,"notify_property_list_changed")
	undo.commit_action()

func edit_curve_points(resource: Resource, points: Array) -> void:
	var points_key := resource_field(resource,"points","Points")
	var degree_key := resource_field(resource,"degree","Degree")
	var knots_key := resource_field(resource,"knot_vector","KnotVector")
	var degree: int = resource.get(degree_key)
	var knots: PackedFloat32Array = resource.get(knots_key)
	if resource.get(resource_field(resource,"kind","Kind")) in [4,5]:
		degree = clampi(degree,1,mini(32,points.size()-1))
		if points.size() != resource.get(points_key).size(): knots = PackedFloat32Array()
	var undo := host.get_undo_redo()
	undo.create_action("Edit Mold Curve Points",UndoRedo.MERGE_DISABLE,resource)
	undo.add_do_method(resource,"set_block_signals",true)
	undo.add_undo_method(resource,"set_block_signals",true)
	for entry in [[points_key,points],[degree_key,degree],[knots_key,knots]]:
		undo.add_do_property(resource,entry[0],entry[1])
		undo.add_undo_property(resource,entry[0],resource.get(entry[0]))
	undo.add_do_method(resource,"set_block_signals",false)
	undo.add_undo_method(resource,"set_block_signals",false)
	undo.add_do_method(resource,"emit_changed")
	undo.add_undo_method(resource,"emit_changed")
	undo.commit_action()

func set_geometry(resource: Resource, value: int) -> void:
	var geometry := resource_field(resource,"geometry","Geometry")
	var undo := host.get_undo_redo()
	undo.create_action("Set Mold Polyline Geometry",UndoRedo.MERGE_DISABLE,resource)
	undo.add_do_property(resource,geometry,value)
	undo.add_undo_property(resource,geometry,resource.get(geometry))
	if value == 0:
		var position := resource_field(resource,"position","Position")
		for point in resource.get(resource_field(resource,"points","Points")):
			if point:
				undo.add_undo_property(point,position,point.get(position))
				if curve_resource(resource):
					for pair in [["in_offset","InOffset"],["out_offset","OutOffset"]]:
						var key := resource_field(resource,pair[0],pair[1])
						var previous: Vector3 = point.get(key)
						undo.add_undo_property(point,key,previous)
						previous.z=0; undo.add_do_property(point,key,previous)
	undo.commit_action()

func edit_point_field(owner: Resource, point: Resource, key: String, value: Variant) -> void:
	var undo := host.get_undo_redo()
	# MERGE_ENDS keeps the first undo and last do. Only merge updates to the same target.
	var same_target: bool = _last_field_point != null and _last_field_point.get_ref() == point \
		and _last_field_owner != null and _last_field_owner.get_ref() == owner and _last_field_key == key
	undo.create_action("Edit Mold Point "+key,UndoRedo.MERGE_ENDS if same_target else UndoRedo.MERGE_DISABLE,owner)
	_last_field_point = weakref(point)
	_last_field_owner = weakref(owner)
	_last_field_key = key
	undo.add_do_property(point,key,value); undo.add_undo_property(point,key,point.get(key))
	if key.to_snake_case()=="position":
		var peer := closing_peer(owner,point)
		if peer:
			undo.add_do_property(peer,key,value);undo.add_undo_property(peer,key,peer.get(key))
	undo.commit_action()

static func polygon_resource(object: Object) -> bool:
	if not object is Resource or not object.get_script(): return false
	var path: String = object.get_script().resource_path
	return path.ends_with("/mold_polygon_resource.gd") or path.ends_with("/MoldPolygonResource.cs")

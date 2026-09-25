@tool
extends EditorNode3DGizmoPlugin

const MARKER_NAMES = ["mold_point_marker_0","mold_point_marker_1","mold_point_marker_2","mold_point_marker_3"]
var marker_positions: Array[Array] = [[],[],[],[]]
var marker_ids: Array[Array] = [[],[],[],[]]
# Native handles select vertices; viewport input handles axis/plane dragging.
# The ID stride remains stable for Undo and selection callbacks.
var state
func _init(editor):
	state = editor
	create_material("mold_point_edges",Color(0.3,0.9,1.0))
	for marker in 4:
		var texture_image := Image.create(16,16,false,Image.FORMAT_RGBA8)
		texture_image.fill(Color.TRANSPARENT)
		var tint := Color.YELLOW if marker%2==1 else (Color.RED if marker<2 else Color.BLUE)
		for y in 16:
			for x in 16:
				var distance := Vector2(x-7.5,y-7.5).length() if marker<2 else maxf(absf(x-7.5),absf(y-7.5))
				if distance<=6.5:
					texture_image.set_pixel(x,y,Color(tint,clampf(6.5-distance,0,1)))
		create_handle_material(MARKER_NAMES[marker],false,ImageTexture.create_from_image(texture_image))
		# Unity: 80 UI pixels * 0.055 radius * 2. Account for this
		# texture's 13-pixel silhouette inside its 16-pixel canvas.
		get_material(MARKER_NAMES[marker]).point_size = 8.8*EditorInterface.get_editor_scale()*16.0/13.0
func _get_gizmo_name() -> String: return "Mold Points"
func _has_gizmo(node: Node3D) -> bool: return not state.shape_property(node).is_empty()
func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	if state.target != node: return
	var vertices: PackedVector3Array = state.positions(node)
	var handles := marker_positions
	var ids := marker_ids
	for marker in 4: handles[marker].clear(); ids[marker].clear()
	var resource: Resource = node.get(state.shape_property(node))
	if not resource: return
	var polygon: bool = state.shape_property(node).to_lower() == "polygon"
	var vertex_count := vertices.size()
	var points = resource.get(state.field(node,"points","Points"))
	var tangents: bool = state.has_tangents(node)
	for i in vertex_count:
		if not vertices[i].is_finite(): continue
		if not points[i]: continue
		var marker := 1 if state.selected_point==i and state.selected_role==0 else 0
		handles[marker].append(vertices[i]); ids[marker].append(i*4)
		if tangents:
			for role in [1,2]:
				var position: Vector3 = state.control_position(node,i,role)
				var closed_curve: bool = resource.get(state.field(node,"closed","Closed"))
				if position==vertices[i] or (not closed_curve and ((i==0 and role==1) or (i==vertex_count-1 and role==2))): continue
				marker = 3 if state.selected_point==i and state.selected_role==role else 2
				handles[marker].append(position); ids[marker].append(i*4+role)
	var lines := PackedVector3Array()
	var closed: bool = polygon or resource.get(state.field(node,"closed","Closed"))
	for i in vertex_count:
		if i+1 == vertex_count and not closed: break
		var next := (i+1)%vertex_count
		if vertices[i].is_finite() and vertices[next].is_finite(): lines.append(vertices[i]); lines.append(vertices[next])
	if tangents:
		for i in vertex_count:
			for role in [1,2]: lines.append(vertices[i]); lines.append(state.control_position(node,i,role))
	if not lines.is_empty(): gizmo.add_lines(lines,get_material("mold_point_edges",gizmo))
	for marker in 4:
		if not handles[marker].is_empty():
			gizmo.add_handles(PackedVector3Array(handles[marker]),get_material(MARKER_NAMES[marker],gizmo),PackedInt32Array(ids[marker]))
func _begin_handle_action(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> void:
	state.selected_point = id / 4
	state.selected_role = id % 4
	var node := gizmo.get_node_3d()
	node.update_gizmos()
func _get_handle_name(_gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> String:
	if state.is_curve(_gizmo.get_node_3d()): return "Control %d %s" % [id/4,["Anchor","Incoming","Outgoing",""][id%4]]
	return "Point %d %s" % [id/4,["Select","X","Y","XY"][id%4]]
func _get_handle_value(gizmo: EditorNode3DGizmo, id: int, _secondary: bool) -> Variant:
	return state.control_snapshot(gizmo.get_node_3d(),id/4) if state.is_curve(gizmo.get_node_3d()) else state.positions(gizmo.get_node_3d())[id/4]
func _set_handle(_gizmo: EditorNode3DGizmo, _id: int, _secondary: bool, _camera: Camera3D, _screen_pos: Vector2) -> void:
	# Native point handles select only. Viewport input owns movement.
	pass
func _commit_handle(gizmo: EditorNode3DGizmo, id: int, _secondary: bool, restore: Variant, cancel: bool) -> void:
	var node := gizmo.get_node_3d()
	id = id / 4
	if state.is_curve(node):
		if cancel: state.restore_control(node,id,restore); return
		var after: Array = state.control_snapshot(node,id)
		if after==restore: return
		var resource: Resource = node.get(state.shape_property(node))
		var point: Resource = resource.get(state.field(node,"points","Points"))[id]
		var undo: EditorUndoRedoManager = state.host.get_undo_redo()
		undo.create_action("Move Mold Curve Control",UndoRedo.MERGE_DISABLE,node if point.resource_path.is_empty() or point.resource_path.contains("::") else point)
		var names := [state.field(node,"position","Position"),state.field(node,"in_offset","InOffset"),state.field(node,"out_offset","OutOffset"),state.field(node,"mode","Mode")]
		for i in names.size():
			undo.add_do_property(point,names[i],after[i]); undo.add_undo_property(point,names[i],restore[i])
		undo.commit_action(false)
		return
	var current: Vector3 = state.positions(node)[id]
	if cancel:
		state.set_point(node,id,restore)
		return
	if current.is_equal_approx(restore): return
	# Undo belongs to the resource actually edited, including shared resources.
	var resource: Resource = node.get(state.shape_property(node))
	var property: String
	var before: Variant = restore
	var after: Variant = current
	resource = resource.get(state.field(node,"points","Points"))[id]
	property = state.field(node,"position","Position")
	var undo: EditorUndoRedoManager = state.host.get_undo_redo()
	undo.create_action("Move Mold Point",UndoRedo.MERGE_DISABLE,node if resource.resource_path.is_empty() or resource.resource_path.contains("::") else resource)
	undo.add_do_property(resource,property,after)
	undo.add_undo_property(resource,property,before)
	undo.commit_action(false)

@tool
extends EditorNode3DGizmoPlugin
var hover_service
const PickGeometry=preload("picking/mold_pick_geometry.gd")


func _init() -> void:
	create_material("mold_bounds", Color(0.35, 0.95, 1.0, 0.85))


func _has_gizmo(node: Node3D) -> bool:
	return node is MoldNode3D or node is MoldPolylineNode3D or node is MoldPolygonNode3D


func _get_gizmo_name() -> String:
	return "Mold"


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var mold := gizmo.get_node_3d()
	if not mold is MoldNode3D and not mold is MoldPolylineNode3D and not mold is MoldPolygonNode3D: return
	var lines := PickGeometry.bounds_lines(mold.get_mold_aabb())
	if not hover_service:gizmo.add_lines(lines, get_material("mold_bounds", gizmo))
	var faces := get_picking_faces(mold)
	if hover_service:hover_service.draw_gizmo(gizmo,faces,get_picking_segments(mold) if faces.is_empty() else PackedVector3Array())
	if not faces.is_empty():
		var triangles := TriangleMesh.new()
		triangles.create_from_faces(faces)
		gizmo.add_collision_triangles(triangles)
	else:
		gizmo.add_collision_segments(get_picking_segments(mold))


func _is_selectable_when_hidden() -> bool:
	return true


# Collision data belongs to the native gizmo. Never intercept editor clicks or
# replace EditorSelection: that breaks modifier clicks, overlap picking and drags.
func get_picking_faces(node: Node3D) -> PackedVector3Array:
	if node is MoldPolygonNode3D:
		var resource: MoldPolygonResource = node.polygon
		if not resource or resource.points.size() < 3: return PackedVector3Array()
		var contour := PackedVector2Array()
		for point in resource.points:
			if not point or not point.position.is_finite(): return PackedVector3Array()
			contour.append(Vector2(point.position.x, point.position.y))
		if resource.triangulation == MoldPolygon.Triangulation.EAR_CLIPPING and Geometry2D.triangulate_polygon(contour).is_empty():
			return PackedVector3Array()
		var polygon := resource.to_polygon()
		var faces := PackedVector3Array()
		for index in polygon._triangles: faces.append(polygon._vertices[index])
		return faces
	if node is MoldPolylineNode3D:
		if node.polyline.geometry == MoldPolyline.Geometry.BILLBOARD: return PackedVector3Array()
		return PickGeometry.preview_faces(node._preview)
	if node is MoldNode3D:
		if not node.shape.is_valid_for_authoring(): return PackedVector3Array()
		var shape: MoldShape = node._current_shape()
		if shape.is_empty or shape.billboard_mode != MoldShape.BillboardMode.DISABLED: return PackedVector3Array()
		if shape.kind in [MoldShape.Kind.DISC, MoldShape.Kind.DISC_RIM]:
			return PickGeometry.radial_faces(
				shape.rim_inner_radius() if shape.kind == MoldShape.Kind.DISC_RIM else 0.0,
				shape.rim_outer_radius() if shape.kind == MoldShape.Kind.DISC_RIM else shape.radius,
				shape.start_radians, shape.span_radians)
		if shape.is_2d:
			var layout:=MoldShapeLayout.resolve(shape)
			return PickGeometry.planar_faces(layout.custom_data,layout.local_transform,shape.start_radians,shape.span_radians)
		if shape.kind==MoldShape.Kind.TORUS:
			return PickGeometry.torus_faces(shape.radius,shape.thickness,shape.start_radians,shape.span_radians,shape.capped)
		var preview: MeshInstance3D = node._preview
		var offset := shape.height / (shape.radius * 4.0) - 1.0 if shape.kind == MoldShape.Kind.CAPSULE else 0.0
		return PickGeometry.preview_faces(preview, offset, MoldShapeLayout.resolve(shape).custom_data if MoldShapeLayout.deformation_kind(shape)>2 else Vector4.ZERO)
	return PackedVector3Array()


func get_picking_segments(node: Node3D) -> PackedVector3Array:
	if node is MoldPolylineNode3D and node.polyline.geometry == MoldPolyline.Geometry.BILLBOARD:
		var path: MoldPolyline = node._current_polyline()
		var points := path._render_points
		var result := PackedVector3Array()
		for i in range(points.size() if path.closed else points.size() - 1):
			result.append(points[i].position)
			result.append(points[(i + 1) % points.size()].position)
		return result
	return PickGeometry.bounds_lines(node.get_mold_aabb())

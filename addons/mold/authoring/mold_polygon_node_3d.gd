@tool
@icon("res://addons/mold/mold_node.svg")
class_name MoldPolygonNode3D
extends Node3D

@export var polygon := MoldPolygonResource.new():
	set(value):
		_disconnect_resources()
		polygon=value
		_connect_resources()
		refresh()
@export var style := MoldStyleResource.new():
	set(value):
		_disconnect_resources()
		style=value
		_connect_resources()
		refresh()
enum AppearanceMode { FILL, OUTLINE, FILL_AND_OUTLINE }
@export var appearance_mode: AppearanceMode = AppearanceMode.FILL:
	set(value): appearance_mode=value; refresh()
@export_range(.001,1,.001,"or_greater") var outline_width := .08:
	set(value):
		if not is_finite(value): return
		outline_width=maxf(.001,value); refresh()
var _outline: MoldHandle
var _outline_path: MoldPolyline
var _outline_width := -1.0
func _draw_fill() -> bool: return not style or not style.appearance or style.appearance.kind == 0 or appearance_mode != AppearanceMode.OUTLINE
func _draw_outline() -> bool: return style and style.appearance and style.appearance.kind != 0 and appearance_mode != AppearanceMode.FILL
func _sync_outline(geometry_changed: bool, colors_changed: bool) -> void:
	if not _draw_outline():
		if _outline and _outline.is_valid: _outline.release()
		_outline=null; _outline_path=null
		return
	var changed := geometry_changed or colors_changed or _outline_width != outline_width or not _outline_path
	if changed:
		var points: Array[MoldPolylinePoint] = []
		for p in polygon.points: points.append(MoldPolylinePoint.new(p.position,p.color))
		_outline_path=MoldPolyline.new(points,outline_width,true)
		_outline_width=outline_width
	if not _outline or not _outline.is_valid:
		_outline=_context.create_polyline(_outline_path,style.to_style(),_refresh_state,MoldPolylineBackend.Mode.CPU if Engine.is_editor_hint() or backend == MoldPolygonBackend.Mode.CPU else MoldPolylineBackend.Mode.AUTO)
	else:
		if changed: _outline.set_polyline(_outline_path)
		_outline.set_style(style.to_style()); _outline.set_render_state(_refresh_state)
	_outline.set_stroke_backend(MoldPolylineBackend.Mode.CPU if Engine.is_editor_hint() or backend==MoldPolygonBackend.Mode.CPU else MoldPolylineBackend.Mode.AUTO)
	_outline.set_visible(is_visible_in_tree())

@export_group("Rendering")
@export var backend: MoldPolygonBackend.Mode = MoldPolygonBackend.Mode.AUTO:
	set(value): backend=value; refresh()
@export var runtime_enabled := true:
	set(value): runtime_enabled=value; refresh()
@export var preview_in_editor := true:
	set(value): preview_in_editor=value; refresh()
@export_group("Render State")
@export_flags_3d_render var render_layer_mask := 1:
	set(value): render_layer_mask=value; refresh()
## 3D material priority; higher values sort later. Depth testing still applies.
@export_range(-128, 127, 1) var sorting_order := 0:
	set(value): sorting_order=clampi(value, MoldRenderState.MIN_SORTING_ORDER, MoldRenderState.MAX_SORTING_ORDER); refresh()
@export var depth_test: MoldRenderState.DepthTest = MoldRenderState.DepthTest.LESS_EQUAL:
	set(value): depth_test=value; refresh()
@export var depth_write: MoldRenderState.DepthWrite = MoldRenderState.DepthWrite.AUTO:
	set(value): depth_write=value; refresh()
@export var face_cull: MoldRenderState.FaceCull = MoldRenderState.FaceCull.DISABLED:
	set(value): face_cull=value; refresh()
var _renderer: MoldPolygonRenderer
var _cached_polygon: MoldPolygon
var _point_colors := PackedColorArray()
var _refresh_style := MoldStyle.new()
var _refresh_state := MoldRenderState.new()
var _preview_runtime: MoldRuntimeInstance
var _context: MoldContext
var _dirty := true
var _refresh_queued := false
var _preview_viewport: Viewport
var is_allocated: bool:
	get: return _renderer != null and _renderer.is_valid
var is_using_gpu_backend: bool:
	get: return is_allocated and _renderer.is_using_gpu_backend

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_sync_transform()
		if is_inside_tree() and Engine.is_editor_hint(): update_gizmos()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and is_allocated:
		_renderer.set_visible(is_visible_in_tree() and _draw_fill())
		if _outline and _outline.is_valid: _outline.set_visible(is_visible_in_tree())
	elif what == NOTIFICATION_PARENTED and is_inside_tree(): refresh()

func _enter_tree() -> void:
	set_notify_transform(true)
	_connect_resources()
	refresh()
func _exit_tree() -> void:
	_disconnect_resources()
	_disconnect_preview_viewport()
	_release()
	_dirty=true
func _connect_resources() -> void:
	if polygon and not polygon.changed.is_connected(refresh): polygon.changed.connect(refresh)
	if style and not style.changed.is_connected(refresh): style.changed.connect(refresh)
func _disconnect_resources() -> void:
	if polygon and polygon.changed.is_connected(refresh): polygon.changed.disconnect(refresh)
	if style and style.changed.is_connected(refresh): style.changed.disconnect(refresh)
func refresh() -> void:
	_dirty=true
	if not is_inside_tree(): return
	if Engine.is_editor_hint(): update_gizmos()
	if _refresh_queued: return
	_refresh_queued=true
	call_deferred("_flush_refresh")
func _release() -> void:
	if _outline and _outline.is_valid: _outline.release()
	_outline=null; _outline_path=null
	if _renderer: _renderer.dispose()
	_renderer=null
	if _preview_runtime: _preview_runtime.dispose()
	_preview_runtime=null
	_context=null
# Coalesce edits and build outside scene-tree notifications; idle authoring
# nodes need no per-frame callback. The shared runtime still flushes rendering.
func _flush_refresh() -> void:
	_refresh_queued=false
	if not is_inside_tree() or not _dirty: return
	_dirty=false
	_disconnect_preview_viewport()
	if not polygon or not style or not runtime_enabled or (Engine.is_editor_hint() and not preview_in_editor):
		_release()
		return
	var geometry_changed := not polygon.matches_geometry(_cached_polygon)
	if Engine.is_editor_hint() and geometry_changed:
		var contour := PackedVector2Array()
		for point in polygon.points:
			if not point or not point.position.is_finite():
				_release()
				return
			contour.append(Vector2(point.position.x,point.position.y))
		if contour.size() < 3 or (polygon.triangulation == MoldPolygon.Triangulation.EAR_CLIPPING and Geometry2D.triangulate_polygon(contour).is_empty()):
			_release()
			return
	if Engine.is_editor_hint():
		if not _preview_runtime: _preview_runtime=MoldRuntime.create_attached_instance(self)
		_context=_preview_runtime
	else:
		var world = MoldRuntime._world_for(self)
		if not _context or _context._world != world:
			_release()
			_context=MoldContext.new(world)
	if geometry_changed: _cached_polygon=polygon.to_polygon()
	var colors_changed := _point_colors.size() != polygon.points.size()
	if colors_changed: _point_colors.resize(polygon.points.size())
	for i in _point_colors.size():
		var color := polygon.points[i].color
		colors_changed = colors_changed or _point_colors[i] != color
		_point_colors[i]=color
	_refresh_state._init(render_layer_mask,sorting_order,depth_test,depth_write,0,0,0,face_cull)
	var state := _refresh_state
	var selected_backend := MoldPolygonBackend.Mode.CPU if Engine.is_editor_hint() else backend
	if not is_allocated:
		_renderer=_context.create_polygon(_cached_polygon,style.to_style(null,_refresh_style),state,selected_backend)
		if not geometry_changed: _renderer.update_points(_cached_polygon._vertices,_point_colors,false)
	else:
		_renderer.backend=selected_backend
		if geometry_changed: _renderer.set_polygon(_cached_polygon)
		elif colors_changed: _renderer.update_points(_cached_polygon._vertices,_point_colors,false)
		_renderer.configure(style.to_style(null,_refresh_style),state)
	_sync_outline(geometry_changed,colors_changed)
	_sync_transform()
	_renderer.set_visible(is_visible_in_tree() and _draw_fill())
	# Initialize even if the runtime already flushed this frame. The preview
	# world does not process in the editor, so resize signals update its uniforms.
	_renderer._sync()
	if Engine.is_editor_hint() and _outline: _context._world._process(0.0)
	if Engine.is_editor_hint():
		_preview_viewport=get_viewport()
		_preview_viewport.size_changed.connect(_sync_preview_material)

func _sync_transform() -> void:
	if is_inside_tree() and is_allocated:
		var transform: Transform3D = _context._world.global_transform.affine_inverse()*global_transform
		_renderer.set_transform(transform)
		if _outline and _outline.is_valid: _outline.set_transform(transform.origin,transform.basis.get_rotation_quaternion(),transform.basis.get_scale())

func _sync_preview_material() -> void:
	if is_inside_tree() and is_allocated: _renderer._sync()

func _disconnect_preview_viewport() -> void:
	if is_instance_valid(_preview_viewport) and _preview_viewport.size_changed.is_connected(_sync_preview_material):
		_preview_viewport.size_changed.disconnect(_sync_preview_material)
	_preview_viewport=null

func get_mold_aabb() -> AABB:
	var result := AABB()
	if polygon and not polygon.points.is_empty():
		result=AABB(polygon.points[0].position,Vector3.ZERO)
		for point in polygon.points: result=result.expand(point.position)
	return result

func _validate_property(property: Dictionary) -> void:
	if property.name in ["appearance_mode","outline_width"]: property.usage &= ~PROPERTY_USAGE_EDITOR

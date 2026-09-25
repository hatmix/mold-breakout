@tool
@icon("res://addons/mold/mold_node.svg")
class_name MoldPolylineNode3D
extends Node3D

const PREVIEW_MARKER := &"_mold_polyline_editor_preview"
const PREVIEW_NODE_NAME := "MoldPolylineEditorPreview"

@export var polyline := MoldPolylineResource.new():
	set(value):
		_disconnect_resources()
		polyline = value if value else MoldPolylineResource.new()
		_cached_polyline = null
		_connect_resources()
		_on_polyline_resource_changed()
@export var style := MoldStyleResource.new():
	set(value):
		_disconnect_resources()
		style = value if value else MoldStyleResource.new()
		_connect_resources()
		_on_style_resource_changed()
## Auto uses GPU vertex expansion when supported, with CPU fallback when the
## backend is unavailable or incompatible.
@export_group("Rendering")
@export var backend: MoldPolylineBackend.Mode = MoldPolylineBackend.Mode.AUTO:
	set(value):
		var next := value if value in [MoldPolylineBackend.Mode.AUTO, MoldPolylineBackend.Mode.CPU] \
			else MoldPolylineBackend.Mode.AUTO
		if backend == next: return
		backend = next
		_backend_changed()
@export var runtime_enabled := true:
	set(value):
		runtime_enabled = value
		if value: _attach_runtime()
		else: _detach_runtime()
@export var preview_in_editor := true:
	set(value): preview_in_editor = value; _refresh_preview()

@export_group("Render State")
@export_flags_3d_render var render_layer_mask := 1:
	set(value):
		var next := value if value != 0 else 1
		if render_layer_mask == next: return
		render_layer_mask = next
		_render_state_changed()
## 3D material priority; higher values sort later. Depth testing still applies.
@export_range(-128, 127, 1) var sorting_order := 0:
	set(value):
		var next := clampi(value, MoldRenderState.MIN_SORTING_ORDER, MoldRenderState.MAX_SORTING_ORDER)
		if sorting_order == next: return
		sorting_order = next
		_render_state_changed()
@export var depth_test: MoldRenderState.DepthTest = MoldRenderState.DepthTest.LESS_EQUAL:
	set(value):
		if depth_test == value: return
		depth_test = value
		_render_state_changed()
@export var depth_write: MoldRenderState.DepthWrite = MoldRenderState.DepthWrite.AUTO:
	set(value):
		if depth_write == value: return
		depth_write = value
		_render_state_changed()
@export var face_cull: MoldRenderState.FaceCull = MoldRenderState.FaceCull.DISABLED:
	set(value):
		if face_cull == value: return
		face_cull = value
		_render_state_changed()
@export_flags("Read:1", "Write:2", "Write on depth fail:4") var stencil_flags := 0:
	set(value):
		var next := value & 7
		if stencil_flags == next: return
		stencil_flags = next
		notify_property_list_changed()
		_render_state_changed()
@export var stencil_compare: MoldRenderState.StencilCompare = MoldRenderState.StencilCompare.ALWAYS:
	set(value):
		if stencil_compare == value: return
		stencil_compare = value
		_render_state_changed()
@export_range(0, 255, 1) var stencil_reference := 0:
	set(value):
		var next := clampi(value, 0, 255)
		if stencil_reference == next: return
		stencil_reference = next
		_render_state_changed()

var _cached_polyline: MoldPolyline
var handle: MoldHandle:
	get: return _handle
var _handle: MoldHandle
var _custom_material_handle: MoldMaterialHandle
var _registered_custom_material: ShaderMaterial
var _preview: MeshInstance3D
var _preview_viewport: Viewport
var _preview_cache := MoldMeshCache.new()

var is_allocated: bool:
	get: return _handle != null and _handle.is_valid
var is_using_gpu_backend: bool:
	get: return _handle != null and _handle.is_valid and _handle._required_world().is_using_gpu_backend(_handle)


func _enter_tree() -> void:
	set_notify_transform(true)
	_connect_resources()
	call_deferred("_initialize_authoring")


func _initialize_authoring() -> void:
	if not is_inside_tree(): return
	_connect_preview_viewport()
	if Engine.is_editor_hint(): _refresh_preview()
	else: _attach_runtime()


func _exit_tree() -> void:
	_disconnect_resources()
	_disconnect_preview_viewport()
	_detach_runtime()
	_preview = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_sync_runtime_transform()
		if Engine.is_editor_hint():
			update_gizmos()
			_refresh_preview_bounds()
	elif what == NOTIFICATION_VISIBILITY_CHANGED:
		var visible := is_visible_in_tree()
		if _handle and _handle.is_valid: _handle.set_visible(visible)
		if is_instance_valid(_preview): _preview.visible = visible and preview_in_editor
	elif what == NOTIFICATION_PARENTED and is_inside_tree():
		if Engine.is_editor_hint(): call_deferred("_connect_preview_viewport")
		else: call_deferred("_attach_runtime")


func _connect_preview_viewport() -> void:
	# The editor viewport can be resized without touching a single Mold property,
	# so the baked pixel size has to follow the viewport instead of the refresh.
	if not Engine.is_editor_hint() or not is_inside_tree(): return
	var viewport := get_viewport()
	if _preview_viewport != viewport: _disconnect_preview_viewport()
	_preview_viewport = viewport
	if viewport and not viewport.size_changed.is_connected(_on_preview_viewport_resized):
		viewport.size_changed.connect(_on_preview_viewport_resized)


func _disconnect_preview_viewport() -> void:
	if is_instance_valid(_preview_viewport) \
			and _preview_viewport.size_changed.is_connected(_on_preview_viewport_resized):
		_preview_viewport.size_changed.disconnect(_on_preview_viewport_resized)
	_preview_viewport = null


func _on_preview_viewport_resized() -> void:
	if not is_instance_valid(_preview): return
	var material := _preview.material_override as ShaderMaterial
	if is_instance_valid(material):
		material.set_shader_parameter("mold_viewport_size", _viewport_size())
		material.set_shader_parameter("mold_msaa_enabled", get_viewport().msaa_3d != Viewport.MSAA_DISABLED)


func _viewport_size() -> Vector2:
	var viewport := get_viewport()
	return viewport.get_visible_rect().size if viewport else Vector2.ONE


func _current_polyline() -> MoldPolyline:
	if not _cached_polyline: _cached_polyline = polyline.to_polyline()
	return _cached_polyline


func _connect_resources() -> void:
	if not is_inside_tree(): return
	if polyline and not polyline.changed.is_connected(_on_polyline_resource_changed):
		polyline.changed.connect(_on_polyline_resource_changed)
	if style and not style.changed.is_connected(_on_style_resource_changed):
		style.changed.connect(_on_style_resource_changed)


func _disconnect_resources() -> void:
	if polyline and polyline.changed.is_connected(_on_polyline_resource_changed):
		polyline.changed.disconnect(_on_polyline_resource_changed)
	if style and style.changed.is_connected(_on_style_resource_changed):
		style.changed.disconnect(_on_style_resource_changed)


func _on_polyline_resource_changed() -> void:
	_cached_polyline = null
	_normalize_style()
	if Engine.is_editor_hint(): _refresh_preview()
	elif _handle and _handle.is_valid: _handle.set_polyline(_current_polyline())
	if is_inside_tree(): update_gizmos()


func _on_style_resource_changed() -> void:
	_normalize_style()
	if Engine.is_editor_hint(): _refresh_preview_material()
	elif not _has_valid_custom_material(): _detach_runtime()
	elif _handle and _handle.is_valid: _handle.set_style(_current_style(_handle._world))
	else: _attach_runtime()


func _backend_changed() -> void:
	if _handle and _handle.is_valid: _handle.set_stroke_backend(backend)
	else: _attach_runtime()
	_refresh_preview()


func _has_valid_custom_material() -> bool:
	return style.mode != MoldStyle.BlendMode.CUSTOM or (is_instance_valid(style.custom_material) and is_instance_valid(style.custom_material.shader))


func _normalize_style() -> void:
	if style.mode == MoldStyle.BlendMode.CUSTOM:
		if style.color_mode != MoldStyle.ColorMode.SINGLE: style.color_mode = MoldStyle.ColorMode.SINGLE
		return
	if style.color_mode not in [MoldStyle.ColorMode.SINGLE, MoldStyle.ColorMode.DUAL_DIRECTIONAL]:
		style.color_mode = MoldStyle.ColorMode.SINGLE


func _render_state_changed() -> void:
	if _handle and _handle.is_valid: _handle.set_render_state(_render_state())
	if is_instance_valid(_preview): _preview.layers = render_layer_mask
	_refresh_preview_material()


func _get_configuration_warnings() -> PackedStringArray:
	if not polyline or polyline.points.size() < (3 if polyline.closed else 2): return PackedStringArray(["Add enough points to form the polyline."])
	for point in polyline.points:
		if not point: return PackedStringArray(["A polyline point is missing."])
		if polyline.geometry == MoldPolyline.Geometry.FLAT_2D and absf(point.position.z-polyline.points[0].position.z)>0.00001:
			return PackedStringArray(["Flat 2D requires a common local Z. Reselect Flat 2D to reset point depths to zero, or select Billboard."])
	return PackedStringArray()

func _refresh_preview_bounds() -> void:
	if not is_instance_valid(_preview) or not _cached_polyline: return
	_preview.custom_aabb = MoldPolyline.billboard_local_bounds(_cached_polyline.bounds,global_basis) if _cached_polyline.geometry == MoldPolyline.Geometry.BILLBOARD else _cached_polyline.bounds

func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree(): return
	update_configuration_warnings()
	if not _get_configuration_warnings().is_empty():
		if is_instance_valid(_preview): _preview.visible=false
		return
	if not preview_in_editor:
		if is_instance_valid(_preview): _preview.visible = false
		return
	_preview = _ensure_preview_node()
	_preview.mesh = _preview_cache.get_polyline_mesh(_current_polyline())
	_refresh_preview_bounds()
	_preview.transform = Transform3D.IDENTITY
	_preview.layers = render_layer_mask
	_preview.visible = is_visible_in_tree()
	_refresh_preview_material()


func _ensure_preview_node() -> MeshInstance3D:
	if is_instance_valid(_preview) and _preview.get_parent() == self:
		_remove_stale_preview_children(_preview)
		return _preview
	var existing: MeshInstance3D
	for child in get_children(true):
		if not child is MeshInstance3D or not _is_preview_child(child): continue
		if not existing:
			existing = child
			existing.set_meta(PREVIEW_MARKER, true)
		else:
			child.visible = false
			child.queue_free()
	if existing: return existing
	var created := MeshInstance3D.new()
	created.name = PREVIEW_NODE_NAME
	created.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	created.ignore_occlusion_culling = true
	created.set_meta(PREVIEW_MARKER, true)
	add_child(created, false, Node.INTERNAL_MODE_BACK)
	return created


func _remove_stale_preview_children(retained: MeshInstance3D) -> void:
	for child in get_children(true):
		if child != retained and child is MeshInstance3D and _is_preview_child(child):
			child.visible = false
			child.queue_free()


func _is_preview_child(candidate: MeshInstance3D) -> bool:
	return candidate.has_meta(PREVIEW_MARKER)


func _refresh_preview_material() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree() or not preview_in_editor: return
	if not is_instance_valid(_preview) or _preview.get_parent() != self:
		_refresh_preview()
		return
	var value_polyline := _current_polyline()
	var state := _render_state()
	if style.mode == MoldStyle.BlendMode.CUSTOM:
		if not is_instance_valid(style.custom_material) or not is_instance_valid(style.custom_material.shader):
			_preview.visible = false
			return
		_preview.visible = is_visible_in_tree()
		var custom := MoldPreviewMaterial.create_custom_polyline(style.custom_material, style.color, style.shader_data, state, style.shader_data_2)
		custom.set_shader_parameter("mold_viewport_size", _viewport_size())
		_preview.material_override = custom
		return
	_preview.visible = is_visible_in_tree()
	var material := MoldPreviewMaterial.update_polyline(_preview.material_override as ShaderMaterial, value_polyline, style.to_style(), state)
	material.set_shader_parameter("mold_viewport_size", _viewport_size())
	material.set_shader_parameter("mold_msaa_enabled", get_viewport().msaa_3d != Viewport.MSAA_DISABLED)
	if _preview.material_override != material: _preview.material_override = material


func _attach_runtime() -> void:
	if Engine.is_editor_hint() or not runtime_enabled or not is_inside_tree() or not _has_valid_custom_material(): return
	var target = MoldRuntime._world_for(self)
	if _handle and _handle.is_valid and _handle._world == target: return
	_detach_runtime()
	var local: Transform3D = target.global_transform.affine_inverse() * global_transform
	var value_style := _current_style(target)
	if not value_style: return
	_handle = target.create_polyline_transformed(_current_polyline(), local.origin,
		local.basis.get_rotation_quaternion(), local.basis.get_scale(), value_style, _render_state(), backend)
	_handle.set_visible(is_visible_in_tree())


func _detach_runtime() -> void:
	if _handle and _handle.is_valid: _handle.release()
	_handle = null
	_release_custom_material()


func _current_style(target) -> MoldStyle:
	if style.mode != MoldStyle.BlendMode.CUSTOM:
		_release_custom_material()
		return style.to_style()
	if not is_instance_valid(style.custom_material):
		push_error("Custom mode requires a ShaderMaterial.")
		return null
	if not _custom_material_handle or not _custom_material_handle.is_valid or _registered_custom_material != style.custom_material:
		_release_custom_material()
		_custom_material_handle = target.register_material(style.custom_material)
		_registered_custom_material = style.custom_material
	return style.to_style(_custom_material_handle)


func _release_custom_material() -> void:
	if _custom_material_handle and is_instance_valid(_custom_material_handle._world):
		_custom_material_handle._world._unregister_material(_custom_material_handle)
	_custom_material_handle = null
	_registered_custom_material = null


func _sync_runtime_transform() -> void:
	if not _handle or not _handle.is_valid: return
	var target = _handle._world
	if not target: return
	var local: Transform3D = target.global_transform.affine_inverse() * global_transform
	_handle.set_transform(local.origin, local.basis.get_rotation_quaternion(), local.basis.get_scale())


func _render_state() -> MoldRenderState:
	return MoldRenderState.new(render_layer_mask, sorting_order, depth_test, depth_write,
		stencil_flags, stencil_compare, stencil_reference, face_cull)


func get_mold_aabb() -> AABB:
	return _current_polyline().bounds


## Retain this immutable geometry for repeated sampling; reacquire after edits.
func get_geometry() -> MoldPolyline:
	return _current_polyline()

func evaluate(t: float) -> Vector3:
	return get_geometry().evaluate(t)

func evaluate_world(t: float) -> Vector3:
	return to_global(evaluate(t))

func evaluate_tangent(t: float, incoming := false) -> Vector3:
	return get_geometry().evaluate_tangent(t, incoming)

func evaluate_world_tangent(t: float, incoming := false) -> Vector3:
	return (global_transform.basis * get_geometry().evaluate_derivative(t, incoming)).normalized()

func bake_distance_table(tolerance := 0.001, max_depth := 20) -> MoldCurveDistanceTable:
	return get_geometry().bake_distance_table(tolerance, max_depth)

func _validate_property(property: Dictionary) -> void:
	if property.name == "stencil_compare" and not (stencil_flags & 1):
		property.usage &= ~PROPERTY_USAGE_EDITOR
	elif property.name == "stencil_reference" and stencil_flags == 0:
		property.usage &= ~PROPERTY_USAGE_EDITOR

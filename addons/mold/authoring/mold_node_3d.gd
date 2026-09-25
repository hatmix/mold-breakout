@tool
@icon("res://addons/mold/mold_node.svg")
class_name MoldNode3D
extends Node3D

const PREVIEW_MARKER := &"_mold_editor_preview"
const PREVIEW_NODE_NAME := "MoldEditorPreview"

@export var shape := MoldShapeResource.new():
	set(value):
		_disconnect_resources()
		shape = value if value else MoldShapeResource.new()
		_connect_resources()
		_on_shape_resource_changed()
@export var style := MoldStyleResource.new():
	set(value):
		_disconnect_resources()
		style = value if value else MoldStyleResource.new()
		_connect_resources()
		_on_style_resource_changed()
@export_group("Rendering")
@export var runtime_enabled := true:
	set(value):
		runtime_enabled = value
		if value: _attach_runtime()
		else: _detach_runtime()
@export var preview_in_editor := true:
	set(value):
		preview_in_editor = value
		_refresh()

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

var _bound_runtime: MoldContext
var _bound_material: MoldMaterialHandle
var _bound_material_resource: ShaderMaterial
var handle: MoldHandle:
	get: return _handle

## Bind to a caller-owned runtime. The optional shared material registration is borrowed.
func bind_runtime(runtime: MoldContext, material: MoldMaterialHandle = null) -> void:
	assert(runtime != null and runtime.is_valid)
	if _bound_runtime != runtime or _bound_material != material: _detach_runtime()
	_bound_runtime = runtime
	_bound_material = material
	_bound_material_resource = style.custom_material
	runtime_enabled = true
	_attach_runtime()

var _handle: MoldHandle
var _custom_material_handle: MoldMaterialHandle
var _registered_custom_material: ShaderMaterial
var _preview: MeshInstance3D
var _preview_viewport: Viewport
var _preview_cache := MoldMeshCache.new()
var _cached_shape: MoldShape


func _enter_tree() -> void:
	_cached_shape = null
	set_notify_transform(true)
	_connect_resources()


func _ready() -> void:
	# Tool-script reloads can replace this script instance while the node remains
	# in the edited scene. Re-establish resource callbacks on every ready pass.
	_connect_resources()
	_connect_preview_viewport()
	_refresh()
	if not Engine.is_editor_hint(): call_deferred("_attach_runtime")


func _exit_tree() -> void:
	_disconnect_resources()
	_disconnect_preview_viewport()
	_detach_runtime()
	# Ready must run again when pooled nodes or editor scene tabs re-enter.
	request_ready()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if _handle and _handle.is_valid: _handle.set_visible(is_visible_in_tree())
		if is_instance_valid(_preview): _refresh_preview_material()
	elif what == NOTIFICATION_TRANSFORM_CHANGED and _handle and _handle.is_valid:
		var target = _handle._world
		if target:
			var local: Transform3D = target.global_transform.affine_inverse() * global_transform
			_handle.set_transform(local.origin, local.basis.get_rotation_quaternion(), local.basis.get_scale())
	elif what == NOTIFICATION_PARENTED and is_inside_tree():
		# Reparenting can cross SubViewport or independently managed scene
		# boundaries without a full tree exit.
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


func _viewport_size() -> Vector2:
	var viewport := get_viewport()
	return viewport.get_visible_rect().size if viewport else Vector2.ONE


func _connect_resources() -> void:
	if not is_inside_tree(): return
	if shape and not shape.changed.is_connected(_on_shape_resource_changed): shape.changed.connect(_on_shape_resource_changed)
	if style and not style.changed.is_connected(_on_style_resource_changed): style.changed.connect(_on_style_resource_changed)


func _disconnect_resources() -> void:
	if shape and shape.changed.is_connected(_on_shape_resource_changed): shape.changed.disconnect(_on_shape_resource_changed)
	if style and style.changed.is_connected(_on_style_resource_changed): style.changed.disconnect(_on_style_resource_changed)


func _on_shape_resource_changed() -> void:
	_cached_shape = null
	if not shape.is_valid_for_authoring():
		if is_instance_valid(_preview): _preview.visible = false
		return
	_reset_invalid_color_mode()
	if Engine.is_editor_hint():
		_refresh_preview()
	elif _handle and _handle.is_valid:
		_handle.set_shape(_current_shape())


func _on_style_resource_changed() -> void:
	_reset_invalid_color_mode()
	if Engine.is_editor_hint():
		_refresh_preview_material()
	elif not _has_valid_custom_material():
		_detach_runtime()
	elif _handle and _handle.is_valid:
		_handle.set_style(_current_style(_handle._world))
	else:
		_attach_runtime()


func _has_valid_custom_material() -> bool:
	return style.mode != MoldStyle.BlendMode.CUSTOM or (is_instance_valid(style.custom_material) and is_instance_valid(style.custom_material.shader))


func _refresh() -> void:
	if not is_inside_tree(): return
	if not shape.is_valid_for_authoring():
		if is_instance_valid(_preview): _preview.visible = false
		return
	_reset_invalid_color_mode()
	if Engine.is_editor_hint(): _refresh_preview()
	elif _handle and _handle.is_valid:
		_handle.set_shape(_current_shape())
		_handle.set_style(_current_style(_handle._world))
		_handle.set_render_state(_render_state())


func _reset_invalid_color_mode() -> void:
	if not shape.is_valid_for_authoring(): return
	if style.mode == MoldStyle.BlendMode.CUSTOM:
		if style.color_mode != MoldStyle.ColorMode.SINGLE: style.color_mode = MoldStyle.ColorMode.SINGLE
		return
	var value_shape := _current_shape()
	var valid := style.color_mode == MoldStyle.ColorMode.SINGLE or style.color_mode == MoldStyle.ColorMode.DUAL_DIRECTIONAL or (style.color_mode in [MoldStyle.ColorMode.DUAL_RADIAL, MoldStyle.ColorMode.DUAL_RADIAL_BOUNDS, MoldStyle.ColorMode.DUAL_ANGULAR] and not value_shape.is_line)
	if not valid: style.color_mode = MoldStyle.ColorMode.SINGLE


func _refresh_preview() -> void:
	if is_inside_tree(): update_gizmos()
	if not preview_in_editor:
		if is_instance_valid(_preview): _preview.visible = false
		return
	if not shape.is_valid_for_authoring():
		if is_instance_valid(_preview): _preview.visible = false
		return
	_preview = _ensure_preview_node()
	var value_shape := _current_shape()
	if value_shape.is_empty:
		_preview.visible = false
		return
	_preview.visible = is_visible_in_tree()
	var layout := MoldShapeLayout.resolve(value_shape)
	_preview.mesh = _preview_cache.get_mesh(value_shape)
	_preview.transform = layout.local_transform
	_preview.layers = render_layer_mask
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
			# Internal children are not serialized, but they can survive a
			# GDScript tool reload after this script's fields have been reset.
			# Retire extras so an old material cannot cover the live preview.
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
	if not shape.is_valid_for_authoring() or _current_shape().is_empty:
		if is_instance_valid(_preview): _preview.visible = false
		return
	if not is_instance_valid(_preview) or _preview.get_parent() != self:
		_refresh_preview()
		return
	var value_shape := _current_shape()
	var state := _render_state()
	if style.mode == MoldStyle.BlendMode.CUSTOM:
		if not is_instance_valid(style.custom_material) or not is_instance_valid(style.custom_material.shader):
			_preview.visible = false
			return
		_preview.visible = is_visible_in_tree()
		var custom := MoldPreviewMaterial.create_custom_shape(style.custom_material, value_shape, style.color, style.shader_data, state, style.shader_data_2)
		custom.set_shader_parameter("mold_viewport_size", _viewport_size())
		_preview.material_override = custom
		return
	_preview.visible = is_visible_in_tree()
	var material := MoldPreviewMaterial.update_shape(_preview.material_override as ShaderMaterial, value_shape, style.to_style(), state)
	material.set_shader_parameter("mold_viewport_size", _viewport_size())
	if _preview.material_override != material: _preview.material_override = material



func _render_state_changed() -> void:
	if _handle and _handle.is_valid: _handle.set_render_state(_render_state())
	if is_instance_valid(_preview): _preview.layers = render_layer_mask
	_refresh_preview_material()


func _current_shape() -> MoldShape:
	if not _cached_shape: _cached_shape = shape.to_shape()
	return _cached_shape


func _attach_runtime() -> void:
	if Engine.is_editor_hint() or not runtime_enabled or not is_inside_tree() or not _has_valid_custom_material(): return
	if not shape.is_valid_for_authoring(): return
	var target = _bound_runtime._world if _bound_runtime else MoldRuntime._world_for(self)
	if _handle and _handle.is_valid and _handle._world == target: return
	_detach_runtime()
	var local: Transform3D = target.global_transform.affine_inverse() * global_transform
	var value_style := _current_style(target)
	if not value_style: return
	_handle = target.create_transformed(_current_shape(), local.origin, local.basis.get_rotation_quaternion(), local.basis.get_scale(), value_style, _render_state())
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
	if _bound_material and _bound_material.is_valid and _bound_material_resource == style.custom_material:
		_release_custom_material()
		return style.to_style(_bound_material)
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


func _render_state() -> MoldRenderState:
	return MoldRenderState.new(render_layer_mask, sorting_order, depth_test, depth_write, stencil_flags, stencil_compare, stencil_reference, face_cull)


func get_mold_aabb() -> AABB:
	if not shape.is_valid_for_authoring(): return AABB(Vector3.ZERO, Vector3.ONE * 0.001)
	var value_shape := _current_shape()
	if value_shape.is_empty: return AABB(Vector3.ZERO, Vector3.ONE * 0.001)
	var layout := MoldShapeLayout.resolve(value_shape)
	if value_shape.is_line and value_shape.billboard_mode == MoldShape.BillboardMode.FACE_CAMERA:
		var half_width := value_shape.thickness * 0.5
		var minimum := Vector3(
			minf(value_shape.start_position.x, value_shape.end_position.x),
			minf(value_shape.start_position.y, value_shape.end_position.y),
			minf(value_shape.start_position.z, value_shape.end_position.z)) - Vector3.ONE * half_width
		var maximum := Vector3(
			maxf(value_shape.start_position.x, value_shape.end_position.x),
			maxf(value_shape.start_position.y, value_shape.end_position.y),
			maxf(value_shape.start_position.z, value_shape.end_position.z)) + Vector3.ONE * half_width
		return AABB(minimum, maximum - minimum)
	if value_shape.kind == MoldShape.Kind.TORUS:
		var outer_radius := value_shape.radius + value_shape.thickness * 0.5
		return AABB(Vector3(-outer_radius, -value_shape.thickness * 0.5, -outer_radius), Vector3(outer_radius * 2.0, value_shape.thickness, outer_radius * 2.0))
	if value_shape.billboard_mode != MoldShape.BillboardMode.DISABLED:
		var radius := Vector2(layout.scale.x, layout.scale.y).length() * 0.5
		return AABB(Vector3.ONE * -radius, Vector3.ONE * radius * 2.0)
	var mesh := _preview_cache.get_mesh(value_shape)
	return _transform_aabb(mesh.get_aabb(), layout.local_transform)


static func _transform_aabb(bounds: AABB, transform: Transform3D) -> AABB:
	var minimum := bounds.position
	var maximum := bounds.end
	var result := AABB(transform * minimum, Vector3.ZERO)
	for point in [
		Vector3(maximum.x, minimum.y, minimum.z), Vector3(minimum.x, maximum.y, minimum.z),
		Vector3(maximum.x, maximum.y, minimum.z), Vector3(minimum.x, minimum.y, maximum.z),
		Vector3(maximum.x, minimum.y, maximum.z), Vector3(minimum.x, maximum.y, maximum.z), maximum,
	]: result = result.expand(transform * point)
	return result

func _validate_property(property: Dictionary) -> void:
	if property.name == "stencil_compare" and not (stencil_flags & 1):
		property.usage &= ~PROPERTY_USAGE_EDITOR
	elif property.name == "stencil_reference" and stencil_flags == 0:
		property.usage &= ~PROPERTY_USAGE_EDITOR

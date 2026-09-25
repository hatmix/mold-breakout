extends Node3D

const DENSE_TRANSFORM_DIVISOR := 4
const RETAINED_BATCH_SHARD_SIZE := 16384
const BATCH_SHARD_SHIFT := 26
# Bit 30 of the packed mesh x coordinate is unused by MoldMeshKey. Reserve it
# only in batch lookup keys so coverage-output and hard-opaque instances cannot
# accidentally share a material variant while still sharing the cached mesh.
const BATCH_COVERAGE_BIT := 1 << 30

var performance_metrics := MoldPerformanceMetrics.new()
var transparent_ordering_mode: MoldWorldSettings.TransparentOrderingMode:
	get:
		_ensure_initialized()
		return _active_settings.transparent_ordering_mode
	set(value):
		_ensure_initialized()
		_active_settings.transparent_ordering_mode = value if value >= 0 and value <= 3 else MoldWorldSettings.TransparentOrderingMode.NATIVE_COMPATIBLE
var settings: MoldWorldSettings
var _world_id: int

var statistics: MoldStatistics:
	get:
		var result := MoldStatistics.new()
		statistics_into(result)
		return result

## Reuse a caller-owned snapshot for per-frame diagnostics.
func statistics_into(result: MoldStatistics) -> void:
	_ensure_initialized()
	var immediate_batches := _active_immediate_batch_count()
	var polygon_draws := 0
	for polygon in _polygon_renderers:
		if polygon.is_visible: polygon_draws += 1
	result.active_mold_count = _active_count + _polygon_renderers.size()
	result.batch_count = _active_retained_batch_count() + immediate_batches + _gpu_batch_count() + polygon_draws
	result.cached_mesh_count = _mesh_cache.count
	result.mesh_cache_hits = _mesh_cache.hits
	result.mesh_cache_misses = _mesh_cache.misses
	result.immediate_command_count = _immediate_command_count
	result.immediate_batch_count = immediate_batches
	result.lod_minimal_count = 0; result.lod_low_count = 0; result.lod_medium_count = 0
	result.lod_high_count = 0; result.lod_extreme_count = 0; result.lod_transition_count = 0
	result.gpu_lod_source_count = 0
	for index in _alive.size():
		if _alive[index] == 0 or _polylines[index] or _shapes[index].is_empty or _local_scales[index] == Vector3.ZERO: continue
		if _gpu_lod_flags[index] != 0:
			result.gpu_lod_source_count += 1
			continue
		match clampi(_resolved_details[index],0,4):
			0: result.lod_minimal_count += 1
			1: result.lod_low_count += 1
			2: result.lod_medium_count += 1
			3: result.lod_high_count += 1
			4: result.lod_extreme_count += 1
		if _has_secondary_lod[index] != 0: result.lod_transition_count += 1
	result.last_lod_rebind_count = _last_lod_rebind_count

var _active_settings: MoldWorldSettings
var _mesh_cache: MoldMeshCache
var _renderer: MoldMultiMeshRenderer
var _polygon_renderers: Array[MoldPolygonRenderer] = []
var _gpu_polyline_renderers: Array[MoldGpuPolylineRenderer] = []
var _gpu_entries: Dictionary = {}
var _polyline_policies: Dictionary = {}


func create_polygon(polygon: MoldPolygon, style: MoldStyle = null, state: MoldRenderState = null, backend: MoldPolygonBackend.Mode = MoldPolygonBackend.Mode.AUTO) -> MoldPolygonRenderer:
	_ensure_initialized()
	var renderer := MoldPolygonRenderer.new(self, _active_settings.local_aa_quality)
	renderer.backend = backend
	renderer.set_polygon(polygon)
	renderer.configure(style if style else MoldStyle.transparent(Color.WHITE), state)
	_polygon_renderers.append(renderer)
	return renderer

func release_polygon_renderer(renderer: MoldPolygonRenderer) -> void:
	_polygon_renderers.erase(renderer)
	renderer._dispose_from_world()

func create_gpu_polyline_renderer() -> MoldGpuPolylineRenderer:
	_ensure_initialized()
	var renderer := MoldGpuPolylineRenderer.new(self, _active_settings.local_aa_quality)
	_gpu_polyline_renderers.append(renderer)
	return renderer

func release_gpu_polyline_renderer(renderer: MoldGpuPolylineRenderer) -> void:
	_gpu_polyline_renderers.erase(renderer)
	renderer._dispose_from_world()

func is_using_gpu_backend(handle: MoldHandle) -> bool:
	return is_handle_valid(handle) and _gpu_entries.has(handle._index)

func _can_use_gpu_polyline(index: int) -> bool:
	return _polyline_policies.get(index, MoldPolylineBackend.Mode.CPU) == MoldPolylineBackend.Mode.AUTO and MoldGpuPolylineRenderer.is_supported() and _polylines[index]._render_points.size() <= MoldGpuPolylineRenderer.MAX_TEXELS/2 and _polylines[index]._render_points.size()-(0 if _polylines[index].closed else 1) <= MoldGpuPolylineRenderer.MAX_TEXELS/3 and _color_modes[index] in [MoldStyle.ColorMode.SINGLE, MoldStyle.ColorMode.DUAL_DIRECTIONAL] and (_style_modes[index] != MoldStyle.BlendMode.CUSTOM or MoldGpuPolylineRenderer.is_material_compatible(_resolve_custom_material(_style_for(index))))

func _sync_gpu_polylines(viewport_size: Vector2, msaa: bool) -> void:
	for key in _polyline_policies:
		var index: int = key
		var use_gpu := _can_use_gpu_polyline(index)
		if use_gpu and not _gpu_entries.has(index):
			_unbind(index)
			if _meshes[index]: _mesh_cache.release(_mesh_keys[index])
			_meshes[index] = null
			var renderer := create_gpu_polyline_renderer()
			renderer.set_polyline(_polylines[index])
			_gpu_entries[index] = renderer
		elif not use_gpu and _gpu_entries.has(index):
			_gpu_entries[index].dispose()
			_gpu_entries.erase(index)
			_meshes[index] = _mesh_cache.acquire(_mesh_keys[index])
			_bind(index)
		if not _gpu_entries.has(index): continue
		var gpu: MoldGpuPolylineRenderer = _gpu_entries[index]
		gpu.configure(_style_for(index), _render_states[index])
		gpu._reveal=1.0-_dash_data[index].x
		gpu.set_material(_resolve_custom_material(_style_for(index)) if _style_modes[index] == MoldStyle.BlendMode.CUSTOM else null)
		gpu.set_transform(_transform_for(index))
		gpu.set_visible(_visible[index] != 0 and _local_scales[index] != Vector3.ZERO and _polylines[index].length > 0.00000001)
		gpu.local_aa_quality = _local_aa_quality[index]
	for renderer in _gpu_polyline_renderers: renderer._sync(viewport_size, msaa)

func _gpu_batch_count() -> int:
	var count := 0
	for renderer in _gpu_polyline_renderers:
		if renderer._visible and renderer.segment_count > 0: count += 1
	return count


# Stable handle slots. Each array is one column of the retained mold record.
var _alive := PackedByteArray()
var _gpu_lod_flags := PackedByteArray()
var _generations := PackedInt64Array()
var _free_indices: Array[int] = []
var _shapes: Array[MoldShape] = []
var _polylines: Array[MoldPolyline] = []
var _render_states: Array[MoldRenderState] = []
var _mesh_keys: Array = []
var _meshes: Array[Mesh] = []
var _secondary_mesh_keys: Array = []
var _secondary_meshes: Array[Mesh] = []
var _resolved_details := PackedInt32Array()
var _secondary_details := PackedInt32Array()
var _lod_blends := PackedFloat32Array()
var _has_secondary_lod := PackedByteArray()
var _positions := PackedVector3Array()
var _position_offsets := PackedVector3Array()
var _shape_has_offset := PackedByteArray()
var _lod_diameters := PackedFloat32Array()
var _lod_diameter_valid := PackedByteArray()
var _rotations: Array[Quaternion] = []
var _local_scales := PackedVector3Array()
var _shape_transforms: Array[Transform3D] = []
var _style_modes := PackedInt32Array()
var _appearances: Array[MoldAppearanceSnapshot] = []
var _appearance_ids: Dictionary = {}
var _appearance_retirement_pending := false
var _appearance_live_epochs: Dictionary = {}
var _appearance_epoch := 0
# Keep scratch slots at their high-water size; clearing an Array would release storage.
var _retire_layer_keys: Array = []
var _retire_order_keys: Array = []
var _retire_material_keys: Array = []
var _retire_batch_keys: Array = []
var _retire_appearance_keys: Array = []
var _next_appearance_id := -1
var _style_materials: Array[MoldMaterialHandle] = []
var _colors := PackedColorArray()
var _secondary_colors := PackedColorArray()
var _emissions := PackedFloat32Array()
var _shader_data := PackedVector4Array()
var _shader_data_2 := PackedVector4Array()
var _color_modes := PackedInt32Array()
var _color_interpolations := PackedInt32Array()
var _gradient_spaces := PackedInt32Array()
var _gradient_directions := PackedVector3Array()
var _custom_data := PackedVector4Array()
var _dash_data := PackedVector4Array()
var _local_aa_quality := PackedByteArray()
var _visible := PackedByteArray()
var _slot_batches: Array[MoldBatch] = []
var _batch_indices := PackedInt32Array()
var _secondary_slot_batches: Array[MoldBatch] = []
var _secondary_batch_indices := PackedInt32Array()

var _batches: Dictionary = {}
# Flat traversal order for renderer synchronization; key dictionaries still own lookup.
var _render_batches: Array[MoldBatch] = []
var _immediate_batches: Dictionary = {}
var _retired_batches: Array[MoldBatch] = []
# Reused by bulk transform updates so animation loops do not create temporary
# containers every frame. These remain separate from the SoA mold columns.
var _bulk_updated_slots := PackedInt32Array()
var _bulk_batch_counts: Dictionary = {}
var _bulk_dense_batches: Dictionary = {}
class ImmediateTemplate:
	var shape: MoldShape
	var generation := 0
	var previous_shape_match := false
	var layout := {"scale": Vector3.ONE, "custom_data": Vector4.ZERO, "local_transform": Transform3D.IDENTITY}
	var miss_layout := {"scale": Vector3.ONE, "custom_data": Vector4.ZERO, "local_transform": Transform3D.IDENTITY}
	var dash_data := Vector4.ZERO
	var mesh_key
	var detail := -1
	var batch: MoldBatch
	var material_id := -1
	var diameter_valid := false
	var diameter_basis := Basis.IDENTITY
	var diameter := 0.0
	var bounds_valid := false
	var bounds_basis := Basis.IDENTITY
	var relative_bounds := AABB()
	var properties_valid := false
	var color_mode := -1
	var interpolation := -1
	var color := Color()
	var secondary := Color()
	var packed_color := Color()
	var packed_secondary := Color()
	var gradient_space := -1
	var gradient_direction := Vector3.ZERO
	var gradient_data := Vector4.ZERO
	var emission := -1.0
	var flags := Vector4.ZERO

	# Reuse the snapshot storage: a cache miss must not allocate two RefCounted objects.
	func capture(value: MoldShape) -> void:
		if not shape: shape = MoldShape.new()
		shape.kind = value.kind
		shape.size = value.size
		shape.radius = value.radius
		shape.height = value.height
		shape.thickness = value.thickness
		shape.roundness = value.roundness
		shape.rectangle_roundness_mode = value.rectangle_roundness_mode
		shape.start_radians = value.start_radians
		shape.span_radians = value.span_radians
		shape.sides = value.sides
		shape.detail = value.detail
		shape.capped = value.capped
		shape.line_enabled = value.line_enabled
		shape.start_position = value.start_position
		shape.end_position = value.end_position
		shape.billboard_mode = value.billboard_mode
		shape.dash.mode = value.dash.mode
		shape.dash.snap = value.dash.snap
		shape.dash.count = value.dash.count
		shape.dash.spacing = value.dash.spacing
		shape.dash.offset = value.dash.offset
		shape.dash.type = value.dash.type
		shape.dash.modifier = value.dash.modifier
		shape.dash.dash_length = value.dash.dash_length

var _gradient_layout := {"scale": Vector3.ONE, "custom_data": Vector4.ZERO, "local_transform": Transform3D.IDENTITY}
var _immediate_templates: Array[ImmediateTemplate] = []
var _immediate_generation := 0
var _immediate_command_count := 0
var _active_count := 0
var _lod_evaluation_cursor := 0
var _last_lod_rebind_count := 0
var _lod_view_active := false
var _lod_view_orthographic := false
var _lod_view_height := 1.0
var _lod_view_size := 1.0
var _lod_view_origin := Vector3.ZERO
var _lod_view_forward := Vector3.FORWARD
var _lod_view_span := 1.0
var _lod_view_mask := 0
var _lod_view_id := 0
var _orthographic_camera_id := 0
var _orthographic_viewport_height := -1.0
var _orthographic_size := -1.0
var _orthographic_cull_mask := 0
var _orthographic_lod_remaining := 0
var _shape_snapshots: Dictionary = {}
var _render_state_snapshots: Dictionary = {}
var _custom_materials: Dictionary = {}
var _next_custom_material_id := 1
var _shutdown_requested := false
var _cleaned := false
var _pending_attach := false


func _init() -> void:
	_world_id = MoldHandle._register_world(self)


func _ready() -> void:
	_pending_attach = false
	top_level = true
	global_transform = Transform3D.IDENTITY
	process_priority = 1000
	_ensure_initialized()
	_renderer = MoldMultiMeshRenderer.new(self, _active_settings)


func _validate_requested_settings(requested: MoldWorldSettings) -> void:
	if not requested: return
	_ensure_initialized()
	var value := requested.validated_copy()
	if _active_settings.transparent_ordering_mode != value.transparent_ordering_mode or _active_settings.capacity != value.capacity or _active_settings.retained_unused_mesh_count != value.retained_unused_mesh_count or _active_settings.local_aa_quality != value.local_aa_quality or _active_settings.culling_mode != value.culling_mode or not is_equal_approx(_active_settings.culling_bounds_padding, value.culling_bounds_padding) or _active_settings.lod_backend != value.lod_backend or _active_settings.lod_mode != value.lod_mode or not is_equal_approx(_active_settings.lod_bias, value.lod_bias) or _active_settings.lod_threshold_pixels != value.lod_threshold_pixels or not is_equal_approx(_active_settings.lod_hysteresis, value.lod_hysteresis) or not is_equal_approx(_active_settings.lod_transition_width, value.lod_transition_width) or _active_settings.lod_evaluation_budget != value.lod_evaluation_budget:
		var message := "A Mold context already exists for this scene or SubViewport with different settings. Configure it before creating molds in that rendering context."
		push_error(message)
		assert(false, message)


func _process(_delta: float) -> void:
	if _shutdown_requested or not _renderer: return
	var render_start := performance_metrics.begin_render()
	var viewport := get_viewport()
	var viewport_size := viewport.get_visible_rect().size
	var msaa := viewport.msaa_3d != Viewport.MSAA_DISABLED
	_sync_gpu_polylines(viewport_size, msaa)
	for polygon in _polygon_renderers: polygon._sync(viewport_size, msaa)
	_renderer.update_gpu_camera(viewport.get_camera_3d())
	_evaluate_retained_lod(viewport.get_camera_3d())
	performance_metrics.end_lod(render_start)
	if _appearance_retirement_pending: _retire_empty_appearances()
	_renderer.sync(_render_batches, _retired_batches, viewport_size, msaa)
	_retired_batches.clear()
	performance_metrics.end_render(render_start)


func _exit_tree() -> void:
	_shutdown_requested = true
	_cleanup()


func _is_available() -> bool:
	return not _shutdown_requested and (is_inside_tree() or _pending_attach)


func _begin_pending_attach() -> void:
	_pending_attach = true


func _shutdown() -> void:
	if _shutdown_requested: return
	_shutdown_requested = true
	process_mode = Node.PROCESS_MODE_DISABLED
	_cleanup()
	if is_inside_tree(): queue_free()


func _cleanup() -> void:
	if _cleaned: return
	_cleaned = true
	MoldHandle._unregister_world(_world_id, self)
	_clear_immediate()
	for renderer in _gpu_polyline_renderers: renderer._dispose_from_world()
	_gpu_polyline_renderers.clear()
	for polygon in _polygon_renderers: polygon._dispose_from_world()
	_polygon_renderers.clear()
	_gpu_entries.clear()
	_polyline_policies.clear()
	if _renderer: _renderer.dispose()
	for layer in _batches:
		var layer_batches: Dictionary = _batches[layer]
		for order in layer_batches:
			var order_batches: Dictionary = layer_batches[order]
			for material_id in order_batches:
				var material_batches: Dictionary = order_batches[material_id]
				for key in material_batches:
					(material_batches[key] as MoldBatch).slots.clear()
	_batches.clear()
	_render_batches.clear()
	for layer in _immediate_batches:
		var layer_batches: Dictionary = _immediate_batches[layer]
		for order in layer_batches:
			var order_batches: Dictionary = layer_batches[order]
			for material_id in order_batches:
				var material_batches: Dictionary = order_batches[material_id]
				for key in material_batches:
					var batch: MoldBatch = material_batches[key]
					if batch.owns_mesh: _mesh_cache.release(batch.mesh_key)
	_immediate_batches.clear()
	_immediate_templates.clear()
	_retired_batches.clear()
	_custom_materials.clear()
	_clear_columns()
	_mesh_cache = null
	_renderer = null


func _begin_immediate_generation() -> int:
	if not _is_available(): return 0
	_clear_immediate()
	_immediate_generation += 1
	return _immediate_generation


func _clear_immediate() -> void:
	for layer in _immediate_batches:
		var layer_batches: Dictionary = _immediate_batches[layer]
		for order in layer_batches:
			var order_batches: Dictionary = layer_batches[order]
			for material_id in order_batches:
				var material_batches: Dictionary = order_batches[material_id]
				for key in material_batches:
					(material_batches[key] as MoldBatch).clear_immediate()
					if material_batches[key].appearance: _appearance_retirement_pending=true
	_immediate_command_count = 0


func _record_immediate(generation: int, shape: MoldShape, position: Vector3, rotation: Quaternion, scale: Vector3, style: MoldStyle, render_state: MoldRenderState) -> void:
	_ensure_initialized()
	if generation <= 0 or generation != _immediate_generation:
		push_error("This immediate frame was replaced by a newer recorder.begin() call.")
		return
	if not shape: return
	if shape.is_empty or scale == Vector3.ZERO: return
	style = style if style else MoldStyle.opaque(Color.WHITE)
	render_state = render_state if render_state else MoldRenderState.new()
	if not style.validate_for_shape(shape): return
	var custom_material := _resolve_custom_material(style)
	if style.mode == MoldStyle.BlendMode.CUSTOM and not custom_material: return
	if _immediate_templates.is_empty(): _immediate_templates.resize(int(MoldShape.Kind.values().max()) + 1)
	var template := _immediate_templates[shape.kind]
	if not template:
		template = ImmediateTemplate.new()
		_immediate_templates[shape.kind] = template
	# Animated line endpoints are the most common early miss; avoid walking all
	# unrelated shape and dash fields before discovering a different segment.
	var shape_match := template.shape != null
	if shape_match and shape.line_enabled:
		shape_match = template.shape.start_position == shape.start_position and template.shape.end_position == shape.end_position
	if shape_match: shape_match = template.shape.equals(shape)
	var layout: Dictionary
	var dash_data: Vector4
	if shape_match:
		layout = template.layout
		dash_data = template.dash_data
	else:
		layout = template.layout if template.generation != _immediate_generation else template.miss_layout
		MoldShapeLayout.resolve_into(shape, layout)
		dash_data = shape.dash.to_gpu_data(shape.dash_path_length())
		# Refresh at most once per kind/frame. Interpreted snapshot writes on every
		# animated command cost more than resolving its layout directly.
		if template.generation != _immediate_generation:
			template.capture(shape)
			template.layout = layout
			template.dash_data = dash_data
			template.detail = -1
			template.generation = _immediate_generation
			shape_match = true
			template.previous_shape_match = false
	if not shape_match or not template.previous_shape_match:
		template.diameter_valid = false
		template.bounds_valid = false
		template.properties_valid = false
	template.previous_shape_match = shape_match
	var shape_transform: Transform3D = layout.local_transform
	var custom_data: Vector4 = layout.custom_data
	var transform := shape_transform
	if rotation == Quaternion.IDENTITY and scale == Vector3.ONE:
		transform.origin += position
	else:
		transform = compose_transform(position, rotation.normalized(), scale) * shape_transform
	if _active_settings.lod_mode == MoldWorldSettings.LodMode.MANUAL:
		var manual_key
		if shape_match and template.detail == shape.detail:
			manual_key = template.mesh_key
		else:
			manual_key = _mesh_cache.resolve_key(shape, shape.detail)
			if shape_match:
				template.mesh_key = manual_key
				template.detail = shape.detail
		_add_immediate_shape(shape, style, render_state, manual_key, transform, custom_data,
			_angular_lod_data(shape, Vector4(1.0, 0.0, 0.0, 0.0)), template, dash_data, shape_match)
		_immediate_command_count += 1
		return
	var selection := _select_immediate_lod(shape, transform, get_viewport().get_camera_3d(), custom_data, template)
	var primary: int = int(selection[0])
	var mesh_key
	if shape_match:
		if template.detail != primary:
			template.mesh_key = _mesh_cache.resolve_key(shape, primary)
			template.detail = primary
		mesh_key = template.mesh_key
	else:
		mesh_key = _mesh_cache.resolve_key(shape, primary)
	var has_secondary: bool = selection[3] > 0.5
	_add_immediate_shape(shape, style, render_state, mesh_key, transform, custom_data,
		_angular_lod_data(shape, Vector4(1.0 - selection[2], 0.0, 0.0, 0.0)
			if has_secondary else Vector4(1.0, 0.0, 0.0, 0.0)), template, dash_data, shape_match)
	if has_secondary:
		_add_immediate_shape(shape, style, render_state,
			_mesh_cache.resolve_key(shape, int(selection[1])), transform, custom_data,
			_angular_lod_data(shape, Vector4(selection[2], 1.0, 0.0, 0.0)), template, dash_data, shape_match)
	_immediate_command_count += 1


func _add_immediate_shape(shape: MoldShape, style: MoldStyle, render_state: MoldRenderState, mesh_key, transform: Transform3D, custom_data: Vector4, lod_data: Vector4, template: ImmediateTemplate, dash_data: Vector4, prepared: bool) -> void:
	style = style.with_appearance(MoldAppearanceSnapshot.for_geometry(style.appearance, shape)) if style.appearance else style
	var custom_material := _resolve_custom_material(style)
	var material_id := _material_id_for(style)
	var coverage_output := _uses_coverage_output(style.mode, shape.is_2d or shape.is_line)
	var batch := template.batch
	if batch and (batch.mode != style.mode or not batch.render_state.equals(render_state)
			or batch.custom_material != custom_material or template.material_id != material_id
			or batch.coverage_output != coverage_output):
		batch = null
	if batch and batch.mesh_key != mesh_key:
		var mesh: Vector3i = mesh_key.packed_key()
		if Vector3i(batch.key.x & ~BATCH_COVERAGE_BIT, batch.key.y, batch.key.z) != mesh: batch = null
	var batches: Dictionary
	var key := Vector4i.ZERO
	if not batch:
		key = _batch_key_for(mesh_key, style.mode, render_state, _active_settings.local_aa_quality, 0, coverage_output)
		batches = _batch_bucket(_immediate_batches, render_state, material_id)
		batch = batches.get(key)
	if not batch:
		batch = MoldBatch.new()
		_render_batches.append(batch)
		batch.configure_immediate(key, mesh_key, _mesh_cache.acquire(mesh_key), style.mode, custom_material, render_state, shape.is_2d, _active_settings.local_aa_quality, coverage_output, style.appearance)
		batches[key] = batch
	template.batch = batch
	template.material_id = material_id
	# Interpreted dependency checks cost more than direct packing on a geometry
	# miss. Keep the bounded template for hits; stream changing geometry directly.
	if not prepared:
		batch.add_immediate(
			MoldMultiMeshRenderer.immediate_aabb(shape, custom_data, transform), transform,
			MoldMultiMeshRenderer.pack_color(style.color, style.color_mode, style.color_interpolation),
			MoldMultiMeshRenderer.pack_color(style.secondary_color, style.color_mode, style.color_interpolation),
			custom_data, dash_data,
			_property_flags_for(shape, style.emission_strength, _active_settings.local_aa_quality),
			_gradient_data_for(shape, style.color_mode, style.color_interpolation, style.gradient_space, style.gradient_direction), style.shader_data, lod_data, style.shader_data_2)
		return
	if not template.bounds_valid or template.bounds_basis != transform.basis:
		template.relative_bounds = MoldMultiMeshRenderer.immediate_aabb(shape, custom_data, Transform3D(transform.basis, Vector3.ZERO))
		template.bounds_basis = transform.basis
		template.bounds_valid = true
	var encoding_changed := template.color_mode != style.color_mode or template.interpolation != style.color_interpolation
	if encoding_changed or template.color != style.color:
		template.packed_color = MoldMultiMeshRenderer.pack_color(style.color, style.color_mode, style.color_interpolation)
		template.color = style.color
	if encoding_changed or template.secondary != style.secondary_color:
		template.packed_secondary = MoldMultiMeshRenderer.pack_color(style.secondary_color, style.color_mode, style.color_interpolation)
		template.secondary = style.secondary_color
	if not template.properties_valid or template.emission != style.emission_strength:
		template.flags = _property_flags_for(shape, style.emission_strength, _active_settings.local_aa_quality)
		template.emission = style.emission_strength
	if not template.properties_valid or encoding_changed or template.gradient_space != style.gradient_space or template.gradient_direction != style.gradient_direction:
		template.gradient_data = _gradient_data_for(shape, style.color_mode, style.color_interpolation, style.gradient_space, style.gradient_direction)
		template.gradient_space = style.gradient_space
		template.gradient_direction = style.gradient_direction
	template.properties_valid = true
	template.color_mode = style.color_mode
	template.interpolation = style.color_interpolation
	batch.add_immediate(
		AABB(template.relative_bounds.position + transform.origin, template.relative_bounds.size),
		transform, template.packed_color, template.packed_secondary, custom_data,
		dash_data, template.flags, template.gradient_data, style.shader_data, lod_data, style.shader_data_2)



func _record_immediate_polyline(generation: int, polyline: MoldPolyline, position: Vector3, rotation: Quaternion, scale: Vector3, style: MoldStyle, render_state: MoldRenderState) -> void:
	_ensure_initialized()
	if generation <= 0 or generation != _immediate_generation:
		push_error("This immediate frame was replaced by a newer recorder.begin() call.")
		return
	if not polyline: return
	if scale == Vector3.ZERO: return
	style = style if style else MoldStyle.opaque(Color.WHITE)
	if not style.validate_for_polyline(): return
	if style.appearance: style=style.with_appearance(style.appearance.resolve(polyline.length))
	render_state = render_state if render_state else MoldRenderState.new()
	var custom_material := _resolve_custom_material(style)
	if style.mode == MoldStyle.BlendMode.CUSTOM and not custom_material: return
	var mesh_key = _mesh_cache.resolve_polyline_key(polyline)
	var coverage_output := _uses_coverage_output(style.mode, true)
	var key := _batch_key_for(mesh_key, style.mode, render_state, _active_settings.local_aa_quality, 0, coverage_output)
	var batches := _batch_bucket(_immediate_batches, render_state, _material_id_for(style))
	var batch: MoldBatch = batches.get(key)
	if not batch:
		batch = MoldBatch.new()
		_render_batches.append(batch)
		batch.configure_immediate(key, mesh_key, _mesh_cache.acquire(mesh_key), style.mode, custom_material, render_state, false, _active_settings.local_aa_quality, coverage_output, style.appearance)
		batches[key] = batch
	var transform := compose_transform(position, rotation.normalized(), scale)
	batch.add_immediate(
		MoldMultiMeshRenderer.immediate_polyline_aabb(polyline, transform),
		transform,
		MoldMultiMeshRenderer.pack_color(style.color, style.color_mode, style.color_interpolation),
		MoldMultiMeshRenderer.pack_color(style.secondary_color, style.color_mode, style.color_interpolation),
		Vector4.ZERO,
		Vector4.ZERO,
		_property_flags_for_polyline(style.emission_strength, _active_settings.local_aa_quality),
		_gradient_data_for_polyline(style.color_mode, style.color_interpolation, style.gradient_space, style.gradient_direction),
		style.shader_data,
		Vector4(1.0, 0.0, 0.0, 0.0), style.shader_data_2,
	)
	_immediate_command_count += 1


func create(shape: MoldShape, style: MoldStyle = null, render_state: MoldRenderState = null) -> MoldHandle:
	return _create_internal(shape, style, render_state, Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE)


func create_polyline(polyline: MoldPolyline, style: MoldStyle = null, render_state: MoldRenderState = null, backend: MoldPolylineBackend.Mode = MoldPolylineBackend.Mode.AUTO) -> MoldHandle:
	return _create_polyline_internal(polyline, style, render_state, Vector3.ZERO, Quaternion.IDENTITY, Vector3.ONE, backend)


func create_polyline_transformed(polyline: MoldPolyline, position: Vector3, rotation: Quaternion, scale: Vector3, style: MoldStyle = null, render_state: MoldRenderState = null, backend: MoldPolylineBackend.Mode = MoldPolylineBackend.Mode.AUTO) -> MoldHandle:
	return _create_polyline_internal(polyline, style, render_state, position, rotation.normalized(), scale, backend)


func create_transformed(shape: MoldShape, position: Vector3, rotation: Quaternion, scale: Vector3, style: MoldStyle = null, render_state: MoldRenderState = null) -> MoldHandle:
	return _create_internal(shape, style, render_state, position, rotation.normalized(), scale)


func _create_internal(shape: MoldShape, style: MoldStyle, render_state: MoldRenderState, position: Vector3, rotation: Quaternion, scale: Vector3) -> MoldHandle:
	_ensure_initialized()
	if not shape:
		push_error("MoldWorld.create requires a shape.")
		return null
	if _active_count >= _active_settings.capacity:
		push_error("MoldWorld capacity of %d has been exhausted." % _active_settings.capacity)
		return null
	style = style if style else MoldStyle.opaque(Color.WHITE)
	if not style.validate_for_shape(shape): return null
	if style.mode == MoldStyle.BlendMode.CUSTOM and not _resolve_custom_material(style): return null
	render_state = render_state if render_state else MoldRenderState.new()
	var index: int
	if _free_indices.is_empty():
		index = _append_slot()
	else:
		index = _free_indices.pop_back()
	_alive[index] = 1
	_gpu_lod_flags[index] = 0
	_shapes[index] = _snapshot_shape(shape)
	_polylines[index] = null
	_render_states[index] = _snapshot_render_state(render_state)
	_positions[index] = position
	_rotations[index] = rotation
	_local_scales[index] = scale
	_style_modes[index] = style.mode
	_appearances[index] = MoldAppearanceSnapshot.for_geometry(style.appearance, _shapes[index], _polylines[index])
	_style_materials[index] = style.custom_material
	_colors[index] = style.color
	_secondary_colors[index] = style.secondary_color
	_emissions[index] = style.emission_strength
	_shader_data[index] = style.shader_data
	_shader_data_2[index] = style.shader_data_2
	_color_modes[index] = style.color_mode
	_color_interpolations[index] = style.color_interpolation
	_gradient_spaces[index] = style.gradient_space
	_gradient_directions[index] = style.gradient_direction
	_local_aa_quality[index] = _active_settings.local_aa_quality
	_visible[index] = 1
	_slot_batches[index] = null
	_batch_indices[index] = -1
	_secondary_slot_batches[index] = null
	_secondary_batch_indices[index] = -1
	if shape.is_empty:
		_configure_empty_shape(index)
	else:
		_configure_shape(index)
		_meshes[index] = _mesh_cache.acquire(_mesh_keys[index])
	_active_count += 1
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport else null
	if not shape.is_empty and scale != Vector3.ZERO \
			and camera and _camera_renders(index, camera):
		_evaluate_lod(index, camera)
	if not _slot_batches[index]: _bind(index)
	return MoldHandle.new(self, index, _generations[index])


func _create_polyline_internal(polyline: MoldPolyline, style: MoldStyle, render_state: MoldRenderState, position: Vector3, rotation: Quaternion, scale: Vector3, backend: MoldPolylineBackend.Mode) -> MoldHandle:
	_ensure_initialized()
	# Backend resolution and lifetime belong to the world.
	if backend not in [MoldPolylineBackend.Mode.AUTO, MoldPolylineBackend.Mode.CPU]:
		backend = MoldPolylineBackend.Mode.AUTO
	if not polyline:
		push_error("MoldWorld.create_polyline requires a path.")
		return null
	if _active_count >= _active_settings.capacity:
		push_error("MoldWorld capacity of %d has been exhausted." % _active_settings.capacity)
		return null
	style = style if style else MoldStyle.opaque(Color.WHITE)
	if not style.validate_for_polyline(): return null
	if style.mode == MoldStyle.BlendMode.CUSTOM and not _resolve_custom_material(style): return null
	render_state = render_state if render_state else MoldRenderState.new()
	var index: int
	if _free_indices.is_empty(): index = _append_slot()
	else: index = _free_indices.pop_back()
	_alive[index] = 1
	_gpu_lod_flags[index] = 0
	_shapes[index] = null
	_polylines[index] = polyline
	_render_states[index] = _snapshot_render_state(render_state)
	_positions[index] = position; _rotations[index] = rotation; _local_scales[index] = scale
	_style_modes[index] = style.mode; _appearances[index] = MoldAppearanceSnapshot.for_geometry(style.appearance, _shapes[index], _polylines[index])
	_style_materials[index] = style.custom_material; _colors[index] = style.color; _secondary_colors[index] = style.secondary_color
	_emissions[index] = style.emission_strength; _shader_data[index] = style.shader_data; _shader_data_2[index] = style.shader_data_2; _color_modes[index] = style.color_mode
	_color_interpolations[index] = style.color_interpolation; _gradient_spaces[index] = style.gradient_space
	_gradient_directions[index] = style.gradient_direction; _local_aa_quality[index] = _active_settings.local_aa_quality
	_visible[index] = 1; _slot_batches[index] = null; _batch_indices[index] = -1
	_secondary_slot_batches[index] = null; _secondary_batch_indices[index] = -1
	_configure_polyline(index)
	_polyline_policies[index] = backend
	if _can_use_gpu_polyline(index):
		var renderer := create_gpu_polyline_renderer()
		renderer.set_polyline(polyline)
		_gpu_entries[index] = renderer
	else:
		_meshes[index] = _mesh_cache.acquire(_mesh_keys[index])
	_active_count += 1
	_bind(index)
	return MoldHandle.new(self, index, _generations[index])


func release(handle: MoldHandle) -> void:
	var index := _required_index(handle)
	if index < 0: return
	_unbind(index)
	if _gpu_entries.has(index):
		_gpu_entries[index].dispose()
		_gpu_entries.erase(index)
	_polyline_policies.erase(index)
	if _meshes[index]: _mesh_cache.release(_mesh_keys[index])
	_release_secondary_mesh(index)
	_alive[index] = 0
	_generations[index] += 1
	_shapes[index] = null
	_appearances[index] = null
	_polylines[index] = null
	_render_states[index] = null
	_mesh_keys[index] = null
	_meshes[index] = null
	_secondary_mesh_keys[index] = null
	_secondary_meshes[index] = null
	_free_indices.append(index)
	_active_count -= 1


func is_handle_valid(handle: MoldHandle) -> bool:
	return not _shutdown_requested and handle != null and handle._world_id == _world_id and handle._index >= 0 and handle._index < _alive.size() and _alive[handle._index] != 0 and _generations[handle._index] == handle._generation


func update_shape(handle: MoldHandle, shape: MoldShape) -> void:
	var index := _required_index(handle)
	if index < 0 or not shape: return
	if _polylines[index]:
		push_error("A polyline handle cannot be changed into a MoldShape.")
		return
	if _shapes[index].equals(shape): return
	if not _style_for(index).validate_for_shape(shape): return
	var previous := _shapes[index]
	if not previous.is_empty and not shape.is_empty and previous.kind == shape.kind and previous.detail == shape.detail and previous.is_line == shape.is_line and previous.billboard_mode == shape.billboard_mode:
		_update_shape_geometry(index, _snapshot_shape(shape))
		_write_transform(index)
		_write_properties(index)
		_evaluate_current_lod(index)
		return
	_unbind(index)
	if _mesh_keys[index]: _mesh_cache.release(_mesh_keys[index])
	_release_secondary_mesh(index)
	_shapes[index] = _snapshot_shape(shape)
	if shape.is_empty:
		_configure_empty_shape(index)
	else:
		_configure_shape(index)
		_meshes[index] = _mesh_cache.acquire(_mesh_keys[index])
		_evaluate_current_lod(index)
	if not _slot_batches[index]: _bind(index)


func update_style(handle: MoldHandle, style: MoldStyle) -> void:
	var index := _required_index(handle)
	if index < 0 or not style: return
	if not _polylines[index] and not style.validate_for_shape(_shapes[index]): return
	if _polylines[index] and not style.validate_for_polyline(): return
	if style.mode == MoldStyle.BlendMode.CUSTOM and not _resolve_custom_material(style): return
	var resolved_appearance := MoldAppearanceSnapshot.for_geometry(style.appearance, _shapes[index], _polylines[index])
	var appearance_changed := (resolved_appearance.key if resolved_appearance else "") != (_appearances[index].key if _appearances[index] else "")
	var material_changed := appearance_changed or _style_modes[index] != style.mode or not _material_handles_equal(_style_materials[index], style.custom_material)
	if material_changed: _unbind(index)
	_style_modes[index] = style.mode
	_appearances[index] = resolved_appearance
	_style_materials[index] = style.custom_material
	_colors[index] = style.color
	_secondary_colors[index] = style.secondary_color
	_emissions[index] = style.emission_strength
	_shader_data[index] = style.shader_data
	_shader_data_2[index] = style.shader_data_2
	_color_modes[index] = style.color_mode
	_color_interpolations[index] = style.color_interpolation
	_gradient_spaces[index] = style.gradient_space
	_gradient_directions[index] = style.gradient_direction
	if material_changed and _visible[index] != 0: _bind(index)
	else: _write_properties(index)


func update_polyline_reveal(handle: MoldHandle, fraction: float) -> void:
	var index := _required_index(handle)
	if index < 0: return
	assert(_polylines[index] != null, "This handle does not contain a polyline.")
	assert(is_finite(fraction), "Reveal fraction must be finite.")
	var data := Vector4(1.0-clampf(fraction,0.0,1.0),0,0,0)
	if _dash_data[index] == data: return
	_dash_data[index]=data
	_write_properties(index)


func update_dash(handle: MoldHandle, dash: MoldDash) -> void:
	var index := _required_index(handle)
	if index < 0: return
	if _polylines[index]:
		update_polyline(handle, _polylines[index].with_dash(dash))
		return
	var shape := _shapes[index].with_dash(dash)
	if not shape: return
	_shapes[index] = shape
	_dash_data[index] = dash.to_gpu_data(_shapes[index].dash_path_length())
	_write_properties(index)


func update_color(handle: MoldHandle, color: Color) -> void:
	var index := _required_index(handle)
	if index < 0: return
	_colors[index] = color
	_write_color(index, false)


func update_secondary_color(handle: MoldHandle, color: Color) -> void:
	var index := _required_index(handle)
	if index < 0: return
	_secondary_colors[index] = color
	_write_color(index, true)


func update_shader_data(handle: MoldHandle, value: Vector4) -> void:
	var index := _required_index(handle)
	if index < 0 or _shader_data[index] == value: return
	_shader_data[index] = value
	_write_properties(index)


func update_shader_data_2(handle: MoldHandle, value: Vector4) -> void:
	var index := _required_index(handle)
	if index < 0 or _shader_data_2[index] == value: return
	_shader_data_2[index] = value
	_write_properties(index)


func update_shader_data_bulk(handles: Array[MoldHandle], values: Array[Vector4]) -> int:
	if handles.size() != values.size():
		push_error("Handles and shader data must have the same length.")
		return 0
	var updated := 0
	for item_index in handles.size():
		var handle := handles[item_index]
		if not is_handle_valid(handle): continue
		var index := handle._index
		_shader_data[index] = values[item_index]
		_write_properties(index)
		updated += 1
	return updated


func update_shader_data_2_bulk(handles: Array[MoldHandle], values: Array[Vector4]) -> int:
	if handles.size() != values.size():
		push_error("Handles and shader data must have the same length.")
		return 0
	var updated := 0
	for item_index in handles.size():
		var handle := handles[item_index]
		if not is_handle_valid(handle): continue
		var index := handle._index
		_shader_data_2[index] = values[item_index]
		_write_properties(index)
		updated += 1
	return updated


func update_position(handle: MoldHandle, position: Vector3) -> void:
	var index := _required_index(handle)
	if index < 0: return
	_positions[index] = position
	_write_position(index)


func update_rotation(handle: MoldHandle, rotation: Quaternion) -> void:
	var index := _required_index(handle)
	if index < 0: return
	_rotations[index] = rotation.normalized()
	_write_transform(index)


func update_scale(handle: MoldHandle, scale: Vector3) -> void:
	var index := _required_index(handle)
	if index < 0: return
	var was_zero := _local_scales[index] == Vector3.ZERO
	var is_zero := scale == Vector3.ZERO
	if not was_zero and is_zero: _unbind(index)
	_local_scales[index] = scale
	_write_transform(index)
	if was_zero and not is_zero:
		_evaluate_current_lod(index)
		_bind(index)
	_invalidate_orthographic_lod()


func update_line_positions(handle: MoldHandle, start: Vector3, end: Vector3) -> void:
	var index := _required_index(handle)
	if index < 0: return
	if _polylines[index]:
		push_error("Polyline points must be changed with set_polyline_point or set_polyline_points.")
		return
	var shape := _shapes[index].with_line_positions(start, end)
	if not shape: return
	_update_shape_geometry(index, shape)
	_write_properties(index)
	_write_transform(index)


func update_polyline(handle: MoldHandle, polyline: MoldPolyline) -> void:
	var index := _required_index(handle)
	if index < 0 or not polyline: return
	if not _polylines[index]:
		push_error("This handle does not contain a polyline.")
		return
	if _polylines[index] == polyline: return
	_unbind(index)
	if _meshes[index]: _mesh_cache.release(_mesh_keys[index])
	var reveal := _dash_data[index]
	_polylines[index] = polyline
	_configure_polyline(index)
	_dash_data[index] = reveal
	if _gpu_entries.has(index) and not _can_use_gpu_polyline(index):
		_gpu_entries[index].dispose()
		_gpu_entries.erase(index)
	if _gpu_entries.has(index): _gpu_entries[index].set_polyline(polyline)
	else: _meshes[index] = _mesh_cache.acquire(_mesh_keys[index])
	_bind(index)


func update_polyline_point(handle: MoldHandle, index: int, point: MoldPolylinePoint) -> void:
	var slot := _required_index(handle)
	if slot < 0 or not _polylines[slot]: return
	update_polyline(handle, _polylines[slot].with_point(index, point))


func update_polyline_points(handle: MoldHandle, points: Array[MoldPolylinePoint]) -> void:
	var slot := _required_index(handle)
	if slot < 0 or not _polylines[slot]: return
	update_polyline(handle, _polylines[slot].with_points(points))


func update_line_positions_bulk(handles: Array[MoldHandle], starts: PackedVector3Array, ends: PackedVector3Array) -> int:
	var count := handles.size()
	if count != starts.size() or count != ends.size():
		push_error("Handle and line position counts must match.")
		return 0
	var updated := 0
	for array_index in count:
		var handle := handles[array_index]
		if not is_handle_valid(handle): continue
		var slot := handle._index
		if _polylines[slot] or not _shapes[slot].is_line: continue
		var shape := _shapes[slot].with_line_positions(starts[array_index], ends[array_index])
		if not shape: continue
		_update_shape_geometry(slot, shape)
		_write_properties(slot)
		_write_transform(slot)
		updated += 1
	return updated


func _update_shape_geometry(index: int, shape: MoldShape) -> void:
	if shape.is_empty or _shapes[index].is_empty:
		_unbind(index)
		if _mesh_keys[index]: _mesh_cache.release(_mesh_keys[index])
		_release_secondary_mesh(index)
		_shapes[index] = shape
		if shape.is_empty:
			_configure_empty_shape(index)
		else:
			_configure_shape(index)
			_meshes[index] = _mesh_cache.acquire(_mesh_keys[index])
			_evaluate_current_lod(index)
		_bind(index)
		return
	var primary_key := _mesh_cache.resolve_key(shape, _resolved_details[index])
	var topology_changed: bool = not _mesh_keys[index].equals(primary_key)
	if _has_secondary_lod[index] != 0:
		var secondary_key := _mesh_cache.resolve_key(shape, _secondary_details[index])
		topology_changed = topology_changed or not _secondary_mesh_keys[index].equals(secondary_key)
	if topology_changed:
		_unbind(index)
		_mesh_cache.release(_mesh_keys[index])
		_release_secondary_mesh(index)
		_shapes[index] = shape
		_configure_shape(index)
		_meshes[index] = _mesh_cache.acquire(_mesh_keys[index])
		_evaluate_current_lod(index)
		if not _slot_batches[index]: _bind(index)
	else:
		var previous_appearance := _appearances[index].key if _appearances[index] else ""
		_shapes[index] = shape
		_configure_shape(index, false)
		if previous_appearance != (_appearances[index].key if _appearances[index] else ""):
			_unbind(index)
			_bind(index)


func update_transform(handle: MoldHandle, position: Vector3, rotation: Quaternion, scale: Vector3) -> void:
	var index := _required_index(handle)
	if index < 0: return
	var was_zero := _local_scales[index] == Vector3.ZERO
	var is_zero := scale == Vector3.ZERO
	if not was_zero and is_zero: _unbind(index)
	_positions[index] = position
	_rotations[index] = rotation.normalized()
	_local_scales[index] = scale
	_write_transform(index)
	if was_zero and not is_zero:
		_evaluate_current_lod(index)
		_bind(index)
	_invalidate_orthographic_lod()


func update_positions_bulk(handles: Array[MoldHandle], positions: PackedVector3Array) -> int:
	var count := handles.size()
	if count != positions.size():
		push_error("Handle and position counts must match.")
		return 0
	var updated := 0
	var slot_count := _alive.size()
	for array_index in count:
		var handle := handles[array_index]
		if handle == null: continue
		# Read the RefCounted handle's slot once, rather than resolving it for
		# every validation column and again for the write.
		var slot := handle._index
		if handle._world_id != _world_id or slot < 0 or slot >= slot_count or _alive[slot] == 0 or _generations[slot] != handle._generation: continue
		var position := positions[array_index]
		_positions[slot] = position
		var origin := position + _position_offsets[slot]
		var batch := _slot_batches[slot]
		if batch: batch.store_position(_batch_indices[slot], origin)
		var secondary := _secondary_slot_batches[slot]
		if secondary: secondary.store_position(_secondary_batch_indices[slot], origin)
		updated += 1
	return updated

func update_transforms_bulk(handles: Array[MoldHandle], positions: PackedVector3Array, rotations: Array[Quaternion], scales: PackedVector3Array) -> int:
	var count := handles.size()
	if count != positions.size() or count != rotations.size() or count != scales.size():
		push_error("Handle and transform counts must match.")
		return 0
	_bulk_batch_counts.clear()
	var invalidate_lod := _active_settings.lod_mode != MoldWorldSettings.LodMode.MANUAL
	if _bulk_updated_slots.size() < count: _bulk_updated_slots.resize(count)
	var updated := 0
	for array_index in count:
		var handle := handles[array_index]
		if handle == null or handle._world_id != _world_id or handle._index < 0 or handle._index >= _alive.size() or _alive[handle._index] == 0 or _generations[handle._index] != handle._generation: continue
		var slot := handle._index
		var was_zero := _local_scales[slot] == Vector3.ZERO
		var is_zero := scales[array_index] == Vector3.ZERO
		if not was_zero and is_zero: _unbind(slot)
		_positions[slot] = positions[array_index]
		_rotations[slot] = rotations[array_index].normalized()
		_local_scales[slot] = scales[array_index]
		if invalidate_lod: _lod_diameter_valid[slot] = 0
		if _shape_has_offset[slot] != 0: _refresh_position_offset(slot)
		if was_zero and not is_zero:
			_evaluate_current_lod(slot)
			_bind(slot)
		_bulk_updated_slots[updated] = slot
		updated += 1
		var batch := _slot_batches[slot]
		if batch: _bulk_batch_counts[batch] = int(_bulk_batch_counts.get(batch, 0)) + 1
	_flush_bulk_transform_updates(updated)
	if updated > 0: _invalidate_orthographic_lod()
	return updated


func update_colors_bulk(handles: Array[MoldHandle], colors: PackedColorArray) -> int:
	var count := handles.size()
	if count != colors.size():
		push_error("Handle and color counts must match.")
		return 0
	var updated := 0
	for array_index in count:
		var handle := handles[array_index]
		if not is_handle_valid(handle): continue
		var slot := handle._index
		_colors[slot] = colors[array_index]
		var packed := MoldMultiMeshRenderer.pack_color(colors[array_index], _color_modes[slot], _color_interpolations[slot])
		var batch := _slot_batches[slot]
		if batch: batch.write_color(_batch_indices[slot], packed, false)
		var secondary := _secondary_slot_batches[slot]
		if secondary: secondary.write_color(_secondary_batch_indices[slot], packed, false)
		updated += 1
	return updated


func update_render_state(handle: MoldHandle, state: MoldRenderState) -> void:
	var index := _required_index(handle)
	if index < 0 or not state: return
	if _render_states[index].equals(state): return
	_unbind(index)
	_render_states[index] = _snapshot_render_state(state)
	_evaluate_current_lod(index)
	if not _slot_batches[index]: _bind(index)


func update_visibility(handle: MoldHandle, visible: bool) -> void:
	var index := _required_index(handle)
	if index < 0 or (_visible[index] != 0) == visible: return
	_visible[index] = int(visible)
	if visible:
		_evaluate_current_lod(index)
		if not _slot_batches[index]: _bind(index)
	else: _unbind(index)


func prewarm(shapes: Array) -> void:
	_ensure_initialized()
	_mesh_cache.prewarm(shapes)


func clear_unused_meshes() -> void:
	_ensure_initialized()
	_mesh_cache.clear_unused()


func register_material(material: ShaderMaterial) -> MoldMaterialHandle:
	_ensure_initialized()
	if not is_instance_valid(material) or not is_instance_valid(material.shader):
		push_error("Custom mold materials must be valid ShaderMaterials with an assigned Shader.")
		return null
	var id := _next_custom_material_id
	_next_custom_material_id += 1
	_custom_materials[id] = material
	return MoldMaterialHandle.new(self, id)


func _is_material_handle_valid(handle: MoldMaterialHandle) -> bool:
	if _shutdown_requested or not handle or handle._world != self: return false
	var material := _custom_materials.get(handle._id) as ShaderMaterial
	return is_instance_valid(material) and is_instance_valid(material.shader)


func _unregister_material(handle: MoldMaterialHandle) -> void:
	if handle and handle._world == self: _custom_materials.erase(handle._id)


func _resolve_custom_material(style: MoldStyle) -> ShaderMaterial:
	if style.mode != MoldStyle.BlendMode.CUSTOM: return null
	var handle := style.custom_material
	if not handle or handle._world != self:
		push_error("The custom material handle is not registered with this Mold world.")
		return null
	var material := _custom_materials.get(handle._id) as ShaderMaterial
	if not is_instance_valid(material) or not is_instance_valid(material.shader):
		push_error("The ShaderMaterial registered by this custom material handle is no longer valid.")
		return null
	return material


func _material_id_for(style: MoldStyle) -> int:
	if style.mode != MoldStyle.BlendMode.CUSTOM and style.appearance:
		if not _appearance_ids.has(style.appearance.key):
			_appearance_ids[style.appearance.key]=_next_appearance_id
			_appearance_live_epochs[style.appearance.key]=0
			_next_appearance_id-=1
		return _appearance_ids[style.appearance.key]
	return style.custom_material._id if style.mode == MoldStyle.BlendMode.CUSTOM and style.custom_material else 0


static func _material_handles_equal(left: MoldMaterialHandle, right: MoldMaterialHandle) -> bool:
	if left == null or right == null: return left == right
	return left.equals(right)


func _ensure_initialized() -> void:
	assert(not _shutdown_requested, "This Mold runtime has been disposed.")
	if _mesh_cache: return
	_active_settings = settings.validated_copy() if settings else MoldWorldSettings.new()
	_mesh_cache = MoldMeshCache.new(_active_settings.retained_unused_mesh_count)


func _snapshot_shape(source: MoldShape) -> MoldShape:
	var snapshot: MoldShape = _shape_snapshots.get(source)
	if snapshot and snapshot.equals(source): return snapshot
	snapshot = source.duplicate_shape()
	_shape_snapshots[source] = snapshot
	return snapshot


func _snapshot_render_state(source: MoldRenderState) -> MoldRenderState:
	var snapshot: MoldRenderState = _render_state_snapshots.get(source)
	if snapshot and snapshot.equals(source): return snapshot
	snapshot = source.duplicate_state()
	_render_state_snapshots[source] = snapshot
	return snapshot


func _append_slot() -> int:
	var index := _alive.size()
	_alive.append(0)
	_gpu_lod_flags.append(0)
	_generations.append(1)
	_shapes.append(null)
	_polylines.append(null)
	_render_states.append(null)
	_mesh_keys.append(null)
	_meshes.append(null)
	_secondary_mesh_keys.append(null)
	_secondary_meshes.append(null)
	_resolved_details.append(MoldShape.Detail.MINIMAL)
	_secondary_details.append(MoldShape.Detail.MINIMAL)
	_lod_blends.append(0.0)
	_has_secondary_lod.append(0)
	_positions.append(Vector3.ZERO)
	_position_offsets.append(Vector3.ZERO)
	_shape_has_offset.append(0)
	_lod_diameters.append(0)
	_lod_diameter_valid.append(0)
	_rotations.append(Quaternion.IDENTITY)
	_local_scales.append(Vector3.ONE)
	_shape_transforms.append(Transform3D.IDENTITY)
	_style_modes.append(MoldStyle.BlendMode.OPAQUE)
	_style_materials.append(null)
	_appearances.append(null)
	_colors.append(Color.WHITE)
	_secondary_colors.append(Color.TRANSPARENT)
	_emissions.append(0.0)
	_shader_data.append(Vector4.ZERO)
	_shader_data_2.append(Vector4.ZERO)
	_color_modes.append(MoldStyle.ColorMode.SINGLE)
	_color_interpolations.append(MoldStyle.ColorInterpolation.LINEAR_RGB)
	_gradient_spaces.append(MoldStyle.GradientSpace.WORLD)
	_gradient_directions.append(Vector3.UP)
	_custom_data.append(Vector4.ZERO)
	_dash_data.append(Vector4.ZERO)
	_local_aa_quality.append(MoldWorldSettings.LocalAaQuality.HIGH)
	_visible.append(0)
	_slot_batches.append(null)
	_batch_indices.append(-1)
	_secondary_slot_batches.append(null)
	_secondary_batch_indices.append(-1)
	return index


func _configure_shape(index: int, reset_lod := true) -> void:
	_appearances[index]=MoldAppearanceSnapshot.for_geometry(_appearances[index],_shapes[index])
	var shape := _shapes[index]
	if reset_lod:
		_resolved_details[index] = shape.detail
		_secondary_details[index] = shape.detail
		_lod_blends[index] = 0.0
		_has_secondary_lod[index] = 0
		_secondary_mesh_keys[index] = null
		_secondary_meshes[index] = null
		_mesh_keys[index] = _mesh_cache.resolve_key(shape)
	var layout := MoldShapeLayout.resolve(shape)
	_shape_transforms[index] = layout.local_transform
	_shape_has_offset[index] = int(layout.local_transform.origin != Vector3.ZERO)
	_refresh_position_offset(index)
	_custom_data[index] = layout.custom_data
	_dash_data[index] = shape.dash.to_gpu_data(shape.dash_path_length())


func _configure_empty_shape(index: int) -> void:
	var shape := _shapes[index]
	_resolved_details[index] = shape.detail
	_secondary_details[index] = shape.detail
	_lod_blends[index] = 0.0
	_has_secondary_lod[index] = 0
	_mesh_keys[index] = null
	_meshes[index] = null
	_secondary_mesh_keys[index] = null
	_secondary_meshes[index] = null
	_shape_transforms[index] = Transform3D.IDENTITY
	_shape_has_offset[index] = 0
	_position_offsets[index] = Vector3.ZERO
	_lod_diameter_valid[index] = 0
	_custom_data[index] = Vector4.ZERO
	_dash_data[index] = Vector4.ZERO


func _configure_polyline(index: int) -> void:
	_appearances[index]=MoldAppearanceSnapshot.for_geometry(_appearances[index],null,_polylines[index])
	_resolved_details[index] = MoldShape.Detail.MINIMAL
	_secondary_details[index] = MoldShape.Detail.MINIMAL
	_lod_blends[index] = 0.0
	_has_secondary_lod[index] = 0
	_secondary_mesh_keys[index] = null
	_secondary_meshes[index] = null
	_mesh_keys[index] = _mesh_cache.resolve_polyline_key(_polylines[index])
	_shape_transforms[index] = Transform3D.IDENTITY
	_shape_has_offset[index] = 0
	_position_offsets[index] = Vector3.ZERO
	_lod_diameter_valid[index] = 0
	_custom_data[index] = Vector4.ZERO
	_dash_data[index] = Vector4.ZERO


func _transform_for(index: int) -> Transform3D:
	return compose_transform(_positions[index], _rotations[index], _local_scales[index]) * _shape_transforms[index]


static func compose_transform(position: Vector3, rotation: Quaternion, local_scale: Vector3) -> Transform3D:
	return Transform3D(Basis(rotation).scaled_local(local_scale), position)


func _batch_key(index: int, secondary := false) -> Vector4i:
	var state := _render_states[index]
	var mode := _style_modes[index]
	var mesh_key = _secondary_mesh_keys[index] if secondary else _mesh_keys[index]
	return _batch_key_for(mesh_key, mode, state, _local_aa_quality[index],
		index / RETAINED_BATCH_SHARD_SIZE, _uses_coverage_output(mode, _polylines[index] != null or _shapes[index].is_2d or _shapes[index].is_line))


func _batch_key_for(mesh_key, mode: MoldStyle.BlendMode, state: MoldRenderState, local_aa_quality: MoldWorldSettings.LocalAaQuality, shard := 0, coverage_output := false) -> Vector4i:
	var mesh: Vector3i = mesh_key.packed_key()
	if coverage_output: mesh.x |= BATCH_COVERAGE_BIT
	return Vector4i(mesh.x, mesh.y, mesh.z, state.shader_key(mode) |
		(int(local_aa_quality) << 24) | (shard << BATCH_SHARD_SHIFT))


static func _uses_coverage_output(mode: MoldStyle.BlendMode, has_analytic_coverage: bool) -> bool:
	return mode == MoldStyle.BlendMode.OPAQUE and has_analytic_coverage


func _batch_bucket(root: Dictionary, state: MoldRenderState, material_id: int) -> Dictionary:
	var layer_batches = root.get(state.render_layer_mask)
	if layer_batches == null:
		layer_batches = {}
		root[state.render_layer_mask] = layer_batches
	var order_batches = layer_batches.get(state.sorting_order)
	if order_batches == null:
		order_batches = {}
		layer_batches[state.sorting_order] = order_batches
	var material_batches = order_batches.get(material_id)
	if material_batches == null:
		material_batches = {}
		order_batches[material_id] = material_batches
	return material_batches


func _bind(index: int) -> void:
	if _gpu_entries.has(index): return
	if _visible[index] == 0 or _local_scales[index] == Vector3.ZERO \
			or _slot_batches[index] != null \
			or (_shapes[index] and _shapes[index].is_empty) or (_polylines[index] and _polylines[index].length <= 0.00000001): return
	_bind_one(index, false)
	if _has_secondary_lod[index] != 0: _bind_one(index, true)


func _bind_one(index: int, secondary: bool) -> void:
	var key := _batch_key(index, secondary)
	var material_id := _material_id_for(_style_for(index))
	var batches := _batch_bucket(_batches, _render_states[index], material_id)
	var batch: MoldBatch = batches.get(key)
	if not batch:
		batch = MoldBatch.new()
		_render_batches.append(batch)
		var mesh: Mesh = _secondary_meshes[index] if secondary else _meshes[index]
		var custom_material := _custom_materials.get(material_id) as ShaderMaterial
		var coverage_output := _uses_coverage_output(_style_modes[index], _polylines[index] != null or _shapes[index].is_2d or _shapes[index].is_line)
		batch.configure(key, mesh, _style_modes[index], custom_material, _render_states[index], not _polylines[index] and _shapes[index].is_2d, _local_aa_quality[index], coverage_output, _appearances[index])
		batches[key] = batch
	var lod_data := _angular_lod_data(_shapes[index],
		Vector4(_lod_blends[index], 1.0, 0.0, 0.0) if secondary else
		(Vector4(1.0 - _lod_blends[index], 0.0, 0.0, 0.0)
			if _has_secondary_lod[index] != 0 else Vector4(1.0, 0.0, 0.0, 0.0)))
	var batch_index := batch.add_item(
		index,
		_transform_for(index),
		MoldMultiMeshRenderer.pack_color(_colors[index], _color_modes[index], _color_interpolations[index]),
		MoldMultiMeshRenderer.pack_color(_secondary_colors[index], _color_modes[index], _color_interpolations[index]),
		_custom_data[index],
		_dash_data[index],
		_property_flags(index),
		_gradient_data(index),
		_shader_data[index],
		lod_data,
		secondary,
		_shader_data_2[index],
	)
	if secondary:
		_secondary_slot_batches[index] = batch
		_secondary_batch_indices[index] = batch_index
	else:
		_slot_batches[index] = batch
		_batch_indices[index] = batch_index


func _unbind(index: int) -> void:
	_unbind_one(index, true)
	_unbind_one(index, false)


func _unbind_one(index: int, secondary: bool) -> void:
	var batch := _secondary_slot_batches[index] if secondary else _slot_batches[index]
	if not batch: return
	var old_index := _secondary_batch_indices[index] if secondary else _batch_indices[index]
	var swapped := batch.remove_item(old_index)
	if batch.appearance: _appearance_retirement_pending=true
	if swapped.x >= 0:
		if swapped.y != 0: _secondary_batch_indices[swapped.x] = old_index
		else: _batch_indices[swapped.x] = old_index
	if secondary:
		_secondary_slot_batches[index] = null
		_secondary_batch_indices[index] = -1
	else:
		_slot_batches[index] = null
		_batch_indices[index] = -1
	# Empty batches stay resident and are reused. Removing and recreating their
	# nested dictionary entries would reintroduce allocation churn during LOD or
	# style changes; the renderer simply hides a zero-count batch.


func _write_position(index: int) -> void:
	var batch := _slot_batches[index]
	var secondary_batch := _secondary_slot_batches[index]
	if not batch and not secondary_batch: return
	var origin := _positions[index] + _position_offsets[index]
	if batch: batch.write_position(_batch_indices[index], origin)
	if secondary_batch: secondary_batch.write_position(_secondary_batch_indices[index], origin)


func _refresh_position_offset(index: int) -> void:
	_lod_diameter_valid[index] = 0
	var shape_origin := _shape_transforms[index].origin
	_position_offsets[index] = Vector3.ZERO if shape_origin == Vector3.ZERO else Basis(_rotations[index]).scaled_local(_local_scales[index]) * shape_origin


func _write_transform(index: int) -> void:
	_refresh_position_offset(index)
	var transform := _transform_for(index)
	var batch := _slot_batches[index]
	if batch: batch.write_transform(_batch_indices[index], transform)
	var secondary_batch := _secondary_slot_batches[index]
	if secondary_batch: secondary_batch.write_transform(_secondary_batch_indices[index], transform)


func _flush_bulk_transform_updates(updated_count: int) -> void:
	_bulk_dense_batches.clear()
	for value in _bulk_batch_counts:
		var batch: MoldBatch = value
		if int(_bulk_batch_counts[batch]) * DENSE_TRANSFORM_DIVISOR >= batch.count():
			batch.rebuild_transforms(_positions, _rotations, _local_scales, _shape_transforms)
			_bulk_dense_batches[batch] = true
	for updated_index in updated_count:
		var slot := _bulk_updated_slots[updated_index]
		var batch := _slot_batches[slot]
		if batch and not _bulk_dense_batches.has(batch):
			batch.write_transform(_batch_indices[slot], _transform_for(slot))
		var secondary_batch := _secondary_slot_batches[slot]
		if secondary_batch: secondary_batch.write_transform(_secondary_batch_indices[slot], _transform_for(slot))


func _write_color(index: int, secondary: bool) -> void:
	var color := _secondary_colors[index] if secondary else _colors[index]
	var packed := MoldMultiMeshRenderer.pack_color(color, _color_modes[index], _color_interpolations[index])
	var batch := _slot_batches[index]
	if batch: batch.write_color(_batch_indices[index], packed, secondary)
	var secondary_batch := _secondary_slot_batches[index]
	if secondary_batch: secondary_batch.write_color(_secondary_batch_indices[index], packed, secondary)


func _write_properties(index: int) -> void:
	var batch := _slot_batches[index]
	if batch: _write_properties_one(index, batch, _batch_indices[index], false)
	var secondary_batch := _secondary_slot_batches[index]
	if secondary_batch: _write_properties_one(index, secondary_batch, _secondary_batch_indices[index], true)


func _write_properties_one(index: int, batch: MoldBatch, batch_index: int, secondary: bool) -> void:
	var lod_data := _angular_lod_data(_shapes[index],
		Vector4(_lod_blends[index], 1.0, 0.0, 0.0) if secondary else
		(Vector4(1.0 - _lod_blends[index], 0.0, 0.0, 0.0)
			if _has_secondary_lod[index] != 0 else Vector4(1.0, 0.0, 0.0, 0.0)))
	batch.write_properties(
		batch_index,
		MoldMultiMeshRenderer.pack_color(_colors[index], _color_modes[index], _color_interpolations[index]),
		MoldMultiMeshRenderer.pack_color(_secondary_colors[index], _color_modes[index], _color_interpolations[index]),
		_custom_data[index],
		_dash_data[index],
		_property_flags(index),
		_gradient_data(index),
		_shader_data[index],
		lod_data,
		_shader_data_2[index],
	)


func _angular_lod_data(shape: MoldShape, lod_data: Vector4) -> Vector4:
	if shape and not shape.is_line and (shape.kind == MoldShape.Kind.RECTANGLE
			or shape.kind == MoldShape.Kind.RECTANGLE_RIM or shape.kind == MoldShape.Kind.REGULAR_POLYGON
			or shape.kind == MoldShape.Kind.REGULAR_POLYGON_RIM or shape.kind == MoldShape.Kind.ELLIPSE_RIM):
		lod_data.z = shape.start_radians
		lod_data.w = shape.span_radians
	else:
		lod_data.z = 0.0
		lod_data.w = TAU
	return lod_data


func _release_secondary_mesh(index: int) -> void:
	if _secondary_mesh_keys[index]: _mesh_cache.release(_secondary_mesh_keys[index])
	_secondary_mesh_keys[index] = null
	_secondary_meshes[index] = null
	_has_secondary_lod[index] = 0
	_lod_blends[index] = 0.0


func _evaluate_retained_lod(camera: Camera3D) -> void:
	_last_lod_rebind_count = 0
	if _active_settings.lod_mode == MoldWorldSettings.LodMode.MANUAL or not camera or _active_count == 0: return
	_capture_lod_camera(camera)
	var orthographic := _lod_view_orthographic
	if orthographic:
		var viewport_height := _lod_view_height
		var camera_id := _lod_view_id
		if _orthographic_camera_id != camera_id or not is_equal_approx(_orthographic_viewport_height, viewport_height) or not is_equal_approx(_orthographic_size, _lod_view_size) or _orthographic_cull_mask != _lod_view_mask:
			_orthographic_camera_id = camera_id
			_orthographic_viewport_height = viewport_height
			_orthographic_size = _lod_view_size
			_orthographic_cull_mask = _lod_view_mask
			_orthographic_lod_remaining = _active_count
		if _orthographic_lod_remaining <= 0: return
	var budget := mini(_active_settings.lod_evaluation_budget,
		_orthographic_lod_remaining if orthographic else _active_count)
	var evaluated := 0
	var scanned := 0
	_lod_view_active = true
	var entry_count := _alive.size()
	while evaluated < budget and scanned < entry_count:
		var index := _lod_evaluation_cursor
		_lod_evaluation_cursor = (_lod_evaluation_cursor + 1) % entry_count
		scanned += 1
		if _alive[index] == 0 or _polylines[index]: continue
		evaluated += 1
		if orthographic: _orthographic_lod_remaining -= 1
		if _shapes[index].is_empty or _local_scales[index] == Vector3.ZERO: continue
		if _visible[index] == 0 or (_render_states[index].render_layer_mask & _lod_view_mask) == 0: continue
		_evaluate_lod(index, camera)
	_lod_view_active = false


func _evaluate_current_lod(index: int) -> void:
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport else null
	if camera and not _polylines[index] and not _shapes[index].is_empty \
			and _local_scales[index] != Vector3.ZERO \
			and _camera_renders(index, camera):
		_evaluate_lod(index, camera)


func _invalidate_orthographic_lod() -> void:
	_orthographic_lod_remaining = _active_count


func _camera_renders(index: int, camera: Camera3D) -> bool:
	return _visible[index] != 0 and (_render_states[index].render_layer_mask & camera.cull_mask) != 0


func _uses_gpu_lod(index: int) -> bool:
	return (_active_settings.lod_backend == MoldWorldSettings.LodBackend.AUTO or _active_settings.lod_backend == MoldWorldSettings.LodBackend.GPU) and _active_settings.lod_mode != MoldWorldSettings.LodMode.MANUAL and _renderer != null and _renderer.gpu_ready and _polylines[index] == null and _is_lod_eligible(_shapes[index]) and (_style_modes[index] == MoldStyle.BlendMode.OPAQUE or _style_modes[index] == MoldStyle.BlendMode.DITHER)


func _evaluate_lod(index: int, camera: Camera3D) -> void:
	var shape := _shapes[index]
	if shape.is_empty or _local_scales[index] == Vector3.ZERO: return
	var gpu_lod := _uses_gpu_lod(index)
	if _gpu_lod_flags[index] != int(gpu_lod):
		_gpu_lod_flags[index] = int(gpu_lod)
		_write_properties(index)
	var primary: int = shape.detail
	var secondary: int = shape.detail
	var blend := 0.0
	var has_secondary := false
	if _active_settings.lod_mode != MoldWorldSettings.LodMode.MANUAL and _active_settings.lod_backend != MoldWorldSettings.LodBackend.GPU and _is_lod_eligible(shape) and not gpu_lod:
		if _lod_diameter_valid[index] == 0:
			_lod_diameters[index] = _lod_world_diameter(_transform_for(index), shape, _custom_data[index])
			_lod_diameter_valid[index] = 1
		var pixels := _projected_diameter(_lod_diameters[index], _positions[index] + _position_offsets[index], camera) * _active_settings.lod_bias
		var cap: int = shape.detail
		if _active_settings.lod_mode == MoldWorldSettings.LodMode.DISCREET:
			var level := clampi(_resolved_details[index], 0, cap)
			while level < cap and pixels >= _lod_threshold(level) * (1.0 + _active_settings.lod_hysteresis): level += 1
			while level > 0 and pixels < _lod_threshold(level - 1) * (1.0 - _active_settings.lod_hysteresis): level -= 1
			primary = level
		else:
			var level := cap
			for boundary in cap:
				var threshold := _lod_threshold(boundary)
				var low := threshold * (1.0 - _active_settings.lod_transition_width)
				var high := threshold * (1.0 + _active_settings.lod_transition_width)
				if pixels < low:
					level = boundary
					break
				if pixels <= high:
					primary = boundary
					secondary = boundary + 1
					var t := clampf((pixels - low) / maxf(high - low, 0.0001), 0.0, 1.0)
					blend = t * t * (3.0 - 2.0 * t)
					has_secondary = blend > 0.001 and blend < 0.999
					if not has_secondary and blend >= 0.999: primary = secondary
					level = -1
					break
			if level >= 0: primary = level
	var primary_key = _mesh_cache.resolve_key(shape, primary)
	var secondary_key = _mesh_cache.resolve_key(shape, secondary) if has_secondary else null
	var topology_matches: bool = _resolved_details[index] == primary and _secondary_details[index] == secondary and _mesh_keys[index].equals(primary_key) and ((_has_secondary_lod[index] == 0 and not has_secondary) or (_has_secondary_lod[index] != 0 and has_secondary and _secondary_mesh_keys[index].equals(secondary_key)))
	if topology_matches:
		if is_equal_approx(_lod_blends[index], blend): return
		_lod_blends[index] = blend
		_write_properties(index)
		return
	_unbind(index)
	_last_lod_rebind_count += 1
	_mesh_cache.release(_mesh_keys[index])
	_release_secondary_mesh(index)
	_resolved_details[index] = primary
	_secondary_details[index] = secondary
	_mesh_keys[index] = primary_key
	_meshes[index] = _mesh_cache.acquire(primary_key)
	_has_secondary_lod[index] = int(has_secondary)
	_lod_blends[index] = blend
	if has_secondary:
		_secondary_mesh_keys[index] = secondary_key
		_secondary_meshes[index] = _mesh_cache.acquire(secondary_key)
	if _visible[index] != 0: _bind(index)


func _select_immediate_lod(shape: MoldShape, transform: Transform3D, camera: Camera3D, custom_data: Vector4, template: ImmediateTemplate) -> Vector4:
	var primary: int = shape.detail
	var secondary: int = shape.detail
	var blend := 0.0
	var has_secondary := false
	if _active_settings.lod_backend == MoldWorldSettings.LodBackend.GPU or _active_settings.lod_mode == MoldWorldSettings.LodMode.MANUAL or not camera or not _is_lod_eligible(shape):
		return Vector4(primary, secondary, blend, 1.0 if has_secondary else 0.0)
	if not template.diameter_valid or template.diameter_basis != transform.basis:
		template.diameter = _lod_world_diameter(transform, shape, custom_data)
		template.diameter_basis = transform.basis
		template.diameter_valid = true
	var pixels := _projected_diameter(template.diameter, transform.origin, camera) * _active_settings.lod_bias
	var cap: int = shape.detail
	if _active_settings.lod_mode == MoldWorldSettings.LodMode.DISCREET:
		primary = 0
		while primary < cap and pixels >= _lod_threshold(primary): primary += 1
		return Vector4(primary, secondary, blend, 1.0 if has_secondary else 0.0)
	var selected := cap
	for boundary in cap:
		var threshold := _lod_threshold(boundary)
		var low := threshold * (1.0 - _active_settings.lod_transition_width)
		var high := threshold * (1.0 + _active_settings.lod_transition_width)
		if pixels < low:
			selected = boundary
			break
		if pixels > high: continue
		primary = boundary
		secondary = boundary + 1
		var t := clampf((pixels - low) / maxf(high - low, 0.0001), 0.0, 1.0)
		blend = t * t * (3.0 - 2.0 * t)
		has_secondary = blend > 0.001 and blend < 0.999
		if not has_secondary and blend >= 0.999: primary = secondary
		selected = -1
		break
	if selected >= 0: primary = selected
	return Vector4(primary, secondary, blend, 1.0 if has_secondary else 0.0)


func _lod_threshold(boundary: int) -> float:
	var thresholds := _active_settings.lod_threshold_pixels
	match boundary:
		0: return thresholds.x
		1: return thresholds.y
		2: return thresholds.z
	return thresholds.w


static func _is_lod_eligible(shape: MoldShape) -> bool:
	return not shape.is_empty and not shape.is_2d and not (shape.kind == MoldShape.Kind.CUBOID and shape.roundness <= 0.0) and not (shape.kind == MoldShape.Kind.REGULAR_PRISM and shape.roundness <= 0.0) and not (shape.kind == MoldShape.Kind.PYRAMID and shape.roundness <= 0.0)


func _capture_lod_camera(camera: Camera3D) -> void:
	_lod_view_orthographic = camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	_lod_view_height = maxf(camera.get_viewport().get_visible_rect().size.y, 1.0)
	_lod_view_size = camera.size
	var transform := camera.global_transform
	_lod_view_origin = transform.origin
	_lod_view_forward = -transform.basis.z.normalized()
	_lod_view_span = 2.0 * tan(deg_to_rad(camera.fov) * 0.5)
	_lod_view_mask = camera.cull_mask
	_lod_view_id = camera.get_instance_id()


func _projected_diameter_pixels(transform: Transform3D, camera: Camera3D, shape: MoldShape, custom_data: Vector4) -> float:
	return _projected_diameter(_lod_world_diameter(transform, shape, custom_data), transform.origin, camera)


func _projected_diameter(diameter: float, origin: Vector3, camera: Camera3D) -> float:
	if not _lod_view_active: _capture_lod_camera(camera)
	if _lod_view_orthographic:
		return diameter * _lod_view_height / maxf(_lod_view_size, 0.0001)
	var depth := (origin - _lod_view_origin).dot(_lod_view_forward)
	if depth <= 0.0001: return 0.0
	return diameter * _lod_view_height / maxf(depth * _lod_view_span, 0.0001)


static func _lod_world_diameter(transform: Transform3D, shape: MoldShape, custom_data: Vector4) -> float:
	var x := transform.basis.x.length()
	var y := transform.basis.y.length()
	var z := transform.basis.z.length()
	var radial := maxf(x, z)
	var diameter: float
	match shape.kind:
		MoldShape.Kind.ELLIPSOID, MoldShape.Kind.SPHERE, MoldShape.Kind.HEMISPHERE, MoldShape.Kind.TORUS:
			diameter = maxf(radial, y)
		MoldShape.Kind.CAPSULE:
			diameter = maxf(radial, y * maxf(2.0 * (1.0 + custom_data.y), 1.0))
		MoldShape.Kind.CUBOID:
			diameter = sqrt(x * x + y * y + z * z)
		_:
			diameter = sqrt(radial * radial + y * y)
	return maxf(diameter, 0.0001)


func _property_flags(index: int) -> Vector4:
	return _property_flags_for_polyline(_emissions[index], _local_aa_quality[index]) if _polylines[index] else _property_flags_for(_shapes[index], _emissions[index], _local_aa_quality[index])


func _property_flags_for(shape: MoldShape, emission: float, local_aa_quality: MoldWorldSettings.LocalAaQuality) -> Vector4:
	var deformation := MoldShapeLayout.deformation_kind(shape)
	var packed_flags := _packed_aa_flags(local_aa_quality) \
		+ 2 * int(shape.billboard_mode != MoldShape.BillboardMode.DISABLED) \
		+ 4 * int(shape.is_line) \
		+ 16 * int(shape.billboard_mode == MoldShape.BillboardMode.FACE_CAMERA_Y)
	return Vector4(emission, float(shape.is_2d), deformation, float(packed_flags))


func _property_flags_for_polyline(emission: float, local_aa_quality: MoldWorldSettings.LocalAaQuality) -> Vector4:
	return Vector4(emission, 0.0, 0.0, float(_packed_aa_flags(local_aa_quality) + 4 + 8))


static func _packed_aa_flags(quality: MoldWorldSettings.LocalAaQuality) -> int:
	if quality == MoldWorldSettings.LocalAaQuality.OFF: return 0
	return 33 if quality == MoldWorldSettings.LocalAaQuality.HIGH else 1


func _gradient_data(index: int) -> Vector4:
	return _gradient_data_for_polyline(_color_modes[index], _color_interpolations[index], _gradient_spaces[index], _gradient_directions[index]) if _polylines[index] else _gradient_data_for(_shapes[index], _color_modes[index], _color_interpolations[index], _gradient_spaces[index], _gradient_directions[index])


func _gradient_data_for(shape: MoldShape, color_mode: MoldStyle.ColorMode, color_interpolation: MoldStyle.ColorInterpolation, gradient_space: MoldStyle.GradientSpace, gradient_direction: Vector3) -> Vector4:
	var direction := gradient_direction
	if color_mode == MoldStyle.ColorMode.DUAL_RADIAL:
		if (shape.kind == MoldShape.Kind.RECTANGLE or shape.kind == MoldShape.Kind.RECTANGLE_RIM): direction = Vector3(shape.size.x, shape.size.y, 0.0)
		elif (shape.kind == MoldShape.Kind.REGULAR_POLYGON or shape.kind == MoldShape.Kind.REGULAR_POLYGON_RIM or shape.kind == MoldShape.Kind.ELLIPSE_RIM):
			MoldShapeLayout.resolve_into(shape, _gradient_layout)
			direction = Vector3(_gradient_layout.scale.x, _gradient_layout.scale.y, 0.0)
	if not shape.is_2d and (color_mode == MoldStyle.ColorMode.DUAL_RADIAL or color_mode == MoldStyle.ColorMode.DUAL_RADIAL_BOUNDS):
		MoldShapeLayout.resolve_into(shape, _gradient_layout)
		direction = _gradient_layout.scale
	var packed := color_mode + 8 * color_interpolation + 16 * gradient_space + 32 * shape.kind
	return Vector4(direction.x, direction.y, direction.z, float(packed))


func _gradient_data_for_polyline(color_mode: MoldStyle.ColorMode, color_interpolation: MoldStyle.ColorInterpolation, gradient_space: MoldStyle.GradientSpace, gradient_direction: Vector3) -> Vector4:
	var packed := color_mode + 8 * color_interpolation + 16 * gradient_space
	return Vector4(gradient_direction.x, gradient_direction.y, gradient_direction.z, float(packed))


func _active_immediate_batch_count() -> int:
	var result := 0
	for layer in _immediate_batches:
		var layer_batches: Dictionary = _immediate_batches[layer]
		for order in layer_batches:
			var order_batches: Dictionary = layer_batches[order]
			for material_id in order_batches:
				var material_batches: Dictionary = order_batches[material_id]
				for key in material_batches:
					if (material_batches[key] as MoldBatch).count() > 0: result += 1
	return result


func _active_retained_batch_count() -> int:
	var result := 0
	for layer in _batches:
		var layer_batches: Dictionary = _batches[layer]
		for order in layer_batches:
			var order_batches: Dictionary = layer_batches[order]
			for material_id in order_batches:
				var material_batches: Dictionary = order_batches[material_id]
				for key in material_batches:
					if (material_batches[key] as MoldBatch).count() > 0: result += 1
	return result


func _style_for(index: int) -> MoldStyle:
	return MoldStyle.new(_style_modes[index], _colors[index], _secondary_colors[index], _emissions[index], _color_modes[index], _color_interpolations[index], _gradient_spaces[index], _gradient_directions[index], _style_materials[index], _appearances[index], _shader_data[index], _shader_data_2[index])


func _required_index(handle: MoldHandle) -> int:
	if is_handle_valid(handle): return handle._index
	push_error("Mold handle is stale or belongs to another world.")
	return -1


func _clear_columns() -> void:
	_alive.clear()
	_gpu_lod_flags.clear()
	_generations.clear()
	_free_indices.clear()
	_shapes.clear()
	_polylines.clear()
	_render_states.clear()
	_mesh_keys.clear()
	_meshes.clear()
	_secondary_mesh_keys.clear()
	_secondary_meshes.clear()
	_resolved_details.clear()
	_secondary_details.clear()
	_lod_blends.clear()
	_has_secondary_lod.clear()
	_positions.clear()
	_position_offsets.clear()
	_shape_has_offset.clear()
	_lod_diameters.clear()
	_lod_diameter_valid.clear()
	_rotations.clear()
	_local_scales.clear()
	_shape_transforms.clear()
	_style_modes.clear()
	_style_materials.clear()
	_appearances.clear()
	_appearance_ids.clear()
	_appearance_live_epochs.clear()
	_colors.clear()
	_secondary_colors.clear()
	_emissions.clear()
	_shader_data.clear()
	_shader_data_2.clear()
	_color_modes.clear()
	_color_interpolations.clear()
	_gradient_spaces.clear()
	_gradient_directions.clear()
	_custom_data.clear()
	_dash_data.clear()
	_local_aa_quality.clear()
	_visible.clear()
	_slot_batches.clear()
	_batch_indices.clear()
	_secondary_slot_batches.clear()
	_secondary_batch_indices.clear()
	_shape_snapshots.clear()
	_render_state_snapshots.clear()
	_active_count = 0

func get_stroke(handle: MoldHandle) -> MoldPolyline:
	var index := _required_index(handle)
	return _polylines[index] if index>=0 else null
func set_stroke_backend(handle: MoldHandle,backend: int) -> void:
	var index := _required_index(handle)
	if index<0 or not _polylines[index]: return
	if backend not in [MoldPolylineBackend.Mode.AUTO,MoldPolylineBackend.Mode.CPU]: push_error("Invalid backend."); return
	_polyline_policies[index]=backend

# Appearance values are unbounded, unlike warmed built-in render-state variants.
# Retire only unused effect batches after all same-frame rebindings finish.
func _retire_empty_appearances() -> void:
	if not _appearance_retirement_pending: return
	_appearance_retirement_pending=false
	_appearance_epoch+=1
	_retire_appearance_table(_batches)
	_retire_appearance_table(_immediate_batches)
	var count := 0
	for key in _appearance_ids:
		if _appearance_live_epochs[key] != _appearance_epoch:
			_remember_retirement_key(_retire_appearance_keys,count,key)
			count+=1
	for index in count:
		var key: String = _retire_appearance_keys[index]
		_appearance_ids.erase(key)
		_appearance_live_epochs.erase(key)
		_retire_appearance_keys[index]=null

func _retire_appearance_table(root: Dictionary) -> void:
	var layer_count := 0
	for layer in root:
		var orders: Dictionary = root[layer]
		var order_count := 0
		for order in orders:
			var materials: Dictionary = orders[order]
			var material_count := 0
			for material_id in materials:
				if material_id >= 0: continue
				var bucket: Dictionary = materials[material_id]
				var batch_count := 0
				for key in bucket:
					var batch: MoldBatch = bucket[key]
					if batch.count()==0:
						_retired_batches.append(batch)
						if batch.owns_mesh: _mesh_cache.release(batch.mesh_key)
						_remember_retirement_key(_retire_batch_keys,batch_count,key)
						batch_count+=1
					else: _appearance_live_epochs[batch.appearance.key]=_appearance_epoch
				_erase_retirement_keys(bucket,_retire_batch_keys,batch_count)
				if bucket.is_empty():
					_remember_retirement_key(_retire_material_keys,material_count,material_id)
					material_count+=1
			_erase_retirement_keys(materials,_retire_material_keys,material_count)
			if materials.is_empty():
				_remember_retirement_key(_retire_order_keys,order_count,order)
				order_count+=1
		_erase_retirement_keys(orders,_retire_order_keys,order_count)
		if orders.is_empty():
			_remember_retirement_key(_retire_layer_keys,layer_count,layer)
			layer_count+=1
	_erase_retirement_keys(root,_retire_layer_keys,layer_count)

static func _remember_retirement_key(keys: Array, index: int, key: Variant) -> void:
	if index == keys.size(): keys.append(key)
	else: keys[index]=key

static func _erase_retirement_keys(table: Dictionary, keys: Array, count: int) -> void:
	for index in count:
		table.erase(keys[index])
		keys[index]=null

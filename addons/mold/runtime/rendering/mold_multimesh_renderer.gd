class_name MoldMultiMeshRenderer
extends RefCounted

const DATA_TEXELS_PER_INSTANCE := 7
const DATA_TEXTURE_WIDTH := 1024
const CULLING_EXTENT := 1000000.0

class BatchState:
	extends RefCounted
	var gpu_eligibility_revision := -1
	var gpu_eligibility_count := -1
	var gpu_eligibility_select_lod := false
	var gpu_eligible := false
	var native_instances: Array[RID] = []
	var native_meshes: Array[MultiMesh] = []
	var native_transforms: Array[Transform3D] = []
	var native_bounds: Array[AABB] = []
	var native_mode := false
	var native_visible_count := 0
	var oit_mode := false
	var native_transforms_pending := false
	var native_properties_pending := false
	var node: MultiMeshInstance3D
	var multimesh: MultiMesh
	var material: ShaderMaterial
	var data_image: Image
	var data_texture: ImageTexture
	var custom_data_image: Image
	var custom_data_image_2: Image
	var custom_data_texture: ImageTexture
	var custom_data_texture_2: ImageTexture
	var transform_buffer := PackedFloat32Array()
	var property_buffer := PackedByteArray()
	var custom_data_buffer := PackedByteArray()
	var custom_data_buffer_2 := PackedByteArray()
	var custom_data_width := 1
	var capacity := 0
	var visible_count := -1
	var transform_revision := 0
	var property_revision := 0
	var upload_revision := 0
	var viewport_size := Vector2.ZERO
	var msaa_enabled := false

var gpu_lod: RefCounted
var gpu_ready := false
var _gpu_capacities: Dictionary = {}
var _gpu_mesh_keys: Array = []

var _scenario := RID()
var _world_transform := Transform3D.IDENTITY
var _world_visible := false
var _world_changed := false
var _world_identity := true

# Provisional crossover: see docs/culling-auto-benchmark.md.
# Standalone compaction threshold; fused GPU LOD bypasses it.
const AUTO_GPU_CULLING_MINIMUM_INSTANCES := 2048

var _viewport_size := Vector2.ZERO
var _viewport_changed := false
var _msaa_enabled := false
var _world
var _settings: MoldWorldSettings
var _states: Dictionary = {}


func _init(world, settings: MoldWorldSettings) -> void:
	_world = world
	_settings = settings
	_world.visibility_changed.connect(_sync_visibility)
	if (((settings.lod_backend == MoldWorldSettings.LodBackend.AUTO or settings.lod_backend == MoldWorldSettings.LodBackend.GPU) and settings.lod_mode != MoldWorldSettings.LodMode.MANUAL) or (settings.culling_mode == MoldWorldSettings.CullingMode.FRUSTUM_GPU or settings.culling_mode == MoldWorldSettings.CullingMode.AUTO)) and DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() != "gl_compatibility":
		gpu_lod = load("res://addons/mold/gpu_lod/mold_gpu_lod.gd").new(settings.capacity,settings.lod_bias,settings.lod_threshold_pixels,settings.lod_hysteresis,settings.lod_transition_width,settings.lod_mode,settings.culling_mode == MoldWorldSettings.CullingMode.AUTO)


func _sync_visibility() -> void:
	_world_visible = _world.is_visible_in_tree()
	for key in _states:
		var state: BatchState = _states[key]
		_set_native_visible_count(state, state.visible_count if state.native_mode and _world_visible else 0)


static func _set_native_visible_count(state: BatchState, count: int) -> void:
	count = clampi(count, 0, state.native_instances.size())
	for i in range(mini(count, state.native_visible_count), maxi(count, state.native_visible_count)):
		RenderingServer.instance_set_visible(state.native_instances[i], i < count)
	state.native_visible_count = count


static func _free_native_instances(state: BatchState) -> void:
	for instance in state.native_instances: RenderingServer.free_rid(instance)
	state.native_instances.clear()
	state.native_meshes.clear()
	state.native_transforms.clear()
	state.native_bounds.clear()
	state.native_visible_count = 0


func sync(batches: Array[MoldBatch], retired_batches: Array[MoldBatch], size: Vector2, msaa_enabled: bool) -> void:
	var scenario: RID = _world.get_world_3d().scenario
	var world_transform: Transform3D = _world.global_transform
	_world_changed = scenario != _scenario or world_transform != _world_transform
	if scenario != _scenario:
		for key in _states:
			var state: BatchState = _states[key]
			for instance in state.native_instances: RenderingServer.instance_set_scenario(instance, scenario)
	_scenario = scenario
	_world_transform = world_transform
	_world_identity = world_transform == Transform3D.IDENTITY
	if _world_visible != _world.is_visible_in_tree(): _sync_visibility()
	_viewport_changed = size != _viewport_size or msaa_enabled != _msaa_enabled
	_msaa_enabled = msaa_enabled
	_viewport_size = size
	for batch in retired_batches:
		_remove(batch)
		batches.erase(batch)
	var viewport: Viewport = _world.get_viewport()
	if _settings.transparent_ordering_mode >= MoldWorldSettings.TransparentOrderingMode.WEIGHTED_BLENDED and not viewport.has_meta("mold_oit_camera"):
		MoldRuntime.enable_oit(viewport)
	var oit = viewport.get_meta("mold_oit_camera") if viewport.has_meta("mold_oit_camera") else null
	var oit_status: String = oit.status() if is_instance_valid(oit) else "Initializing OIT"
	var available: bool = oit_status == "OIT available"
	var initializing := "initializ" in oit_status.to_lower()
	for batch in batches:
		var rs: MoldRenderState = batch.render_state
		var eligible: bool = batch.mode == MoldStyle.BlendMode.TRANSPARENT and not rs.effective_depth_write(batch.mode) and rs.depth_test == MoldRenderState.DepthTest.LESS_EQUAL and rs.stencil_flags == 0 and rs.sorting_order == 0
		var native: bool = (_settings.transparent_ordering_mode == MoldWorldSettings.TransparentOrderingMode.NATIVE_COMPATIBLE or (_settings.transparent_ordering_mode >= MoldWorldSettings.TransparentOrderingMode.WEIGHTED_BLENDED and ((not available and not initializing) or not eligible))) and batch.mode not in [MoldStyle.BlendMode.OPAQUE,MoldStyle.BlendMode.DITHER,MoldStyle.BlendMode.CUSTOM]
		var oit_mode: bool = available and eligible and _settings.transparent_ordering_mode >= MoldWorldSettings.TransparentOrderingMode.WEIGHTED_BLENDED
		var changed: bool = _states.has(batch) and (_states[batch].native_mode != native or _states[batch].oit_mode != oit_mode)
		if batch.transform_pending or batch.property_pending or _viewport_changed or changed or _world_changed:
			_sync(batch, native, oit_mode)
	var requested_backend := false
	for batch in _states:
		var state: BatchState = _states[batch]
		if _sync_gpu_lod(batch,state): continue
		if state.native_mode:
			state.node.visible = false
			continue
		if is_instance_valid(oit):
			var rs: MoldRenderState = batch.render_state
			var eligible: bool = _settings.transparent_ordering_mode >= MoldWorldSettings.TransparentOrderingMode.WEIGHTED_BLENDED and batch.mode == MoldStyle.BlendMode.TRANSPARENT and not rs.effective_depth_write(batch.mode) and rs.depth_test == MoldRenderState.DepthTest.LESS_EQUAL and rs.stencil_flags == 0 and rs.sorting_order == 0
			var camera: Camera3D = _world.get_viewport().get_camera_3d()
			if not requested_backend and eligible and state.visible_count > 0 and _world.is_visible_in_tree() and camera != null and (rs.render_layer_mask & camera.cull_mask) != 0:
				oit.request_backend(_settings.transparent_ordering_mode - 2)
				requested_backend = true
			if not oit.submit_cached_batch(state.node,state.upload_revision,rs.face_cull,eligible):
				var upload_start: int = _world.performance_metrics.begin_upload()
				oit.submit_batch(state.node,state.transform_buffer,state.property_buffer,rs.face_cull,state.upload_revision)
				_world.performance_metrics.end_upload(upload_start, 0 if state.node.visible else 80 + state.visible_count * 160)
		else: state.node.visible = true
		if state.node.visible:
			_flush_native_transforms(state)
			_flush_native_properties(state)


func _sync(batch: MoldBatch, native: bool, oit_mode: bool) -> void:
	var count := batch.count()
	var state: BatchState = _states.get(batch)
	if not state:
		if count == 0:
			batch.acknowledge_changes()
			return
		state = _create(batch)
		_states[batch] = state
	state.oit_mode = oit_mode
	if oit_mode and not state.native_instances.is_empty():
		_free_native_instances(state)
	if state.native_mode != native:
		state.native_mode = native
		state.transform_revision = -1
		_set_native_visible_count(state, 0)
	if count == 0:
		_set_native_visible_count(state, 0)
		if state.visible_count != 0: state.multimesh.visible_instance_count = 0
		state.visible_count = 0
		batch.acknowledge_changes()
		return
	if state.native_mode:
		_batch_aabb(batch)
		while state.native_instances.size() < count:
			# One MultiMesh per sorted object carries its property index without
			# allocating from Godot's hardware-limited instance-uniform buffer.
			var native_mesh := MultiMesh.new()
			native_mesh.transform_format = MultiMesh.TRANSFORM_3D
			native_mesh.use_custom_data = true
			native_mesh.use_colors = true
			native_mesh.mesh = batch.mesh
			native_mesh.instance_count = 1
			native_mesh.set_instance_transform(0, Transform3D.IDENTITY)
			native_mesh.set_instance_color(0, Color.WHITE)
			var index := state.native_instances.size()
			native_mesh.set_instance_custom_data(0, Color(index % 1024, index / 1024, 1, 0))
			state.native_meshes.append(native_mesh)
			var instance := RenderingServer.instance_create2(native_mesh.get_rid(), _scenario)
			RenderingServer.instance_set_visible(instance, false)
			RenderingServer.instance_geometry_set_material_override(instance, state.material.get_rid())
			RenderingServer.instance_set_layer_mask(instance, batch.render_state.render_layer_mask)
			RenderingServer.instance_set_pivot_data(instance, 0.0, true)
			state.native_instances.append(instance)
			state.native_transforms.append(Transform3D.IDENTITY)
			state.native_bounds.append(AABB())
			# Also initialize an identity transform and its bounds on first use.
			state.transform_revision = -1
		_set_native_visible_count(state, count if _world_visible else 0)
		for i in count:
			var instance := state.native_instances[i]
			var transform := batch.transform_at(i)
			var previous := state.native_transforms[i]
			if previous != transform or _world_changed or state.transform_revision == -1:
				RenderingServer.instance_set_transform(instance, transform if _world_identity else _world_transform * transform)
				state.native_transforms[i] = transform
			var bounds: AABB = batch.immediate_bounds[i] if batch.is_immediate else batch.relative_bounds[i]
			if batch.is_immediate: bounds.position -= transform.origin
			if (previous.basis != transform.basis or state.native_bounds[i] != bounds or state.transform_revision == -1) and absf(transform.basis.determinant()) > 0.000001:
				RenderingServer.instance_set_custom_aabb(instance, Transform3D(transform.basis.inverse(), Vector3.ZERO) * bounds)
				state.native_bounds[i] = bounds

	_sync_batch(batch, state, count)
	if native: _flush_native_properties(state)


func dispose() -> void:
	_world.visibility_changed.disconnect(_sync_visibility)
	if gpu_lod:
		gpu_lod.dispose()
		gpu_lod = null
	for key in _gpu_mesh_keys: _world._mesh_cache.release(key)
	_gpu_mesh_keys.clear()
	_gpu_capacities.clear()
	for key in _states:
		var state: BatchState = _states[key]
		_free_native_instances(state)
		if is_instance_valid(state.node): state.node.free()
	_states.clear()


func _create(batch: MoldBatch) -> BatchState:
	var material: ShaderMaterial
	if batch.mode == MoldStyle.BlendMode.CUSTOM:
		if not is_instance_valid(batch.custom_material):
			push_error("A custom Mold batch lost its registered ShaderMaterial.")
			material = ShaderMaterial.new()
		else:
			material = batch.custom_material.duplicate() as ShaderMaterial
	else:
		var coverage_output := batch.coverage_output
		var shader := MoldShader.get_shader(batch.mode, batch.render_state, MoldShader.Backend.MULTIMESH, coverage_output, batch.appearance)
		material = ShaderMaterial.new()
		material.shader = shader
		if batch.appearance: batch.appearance.apply(material)
	material.render_priority = clampi(batch.render_state.sorting_order, -128, 127)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = batch.mesh
	multimesh.custom_aabb = _unculled_aabb()
	var node := MultiMeshInstance3D.new()
	node.multimesh = multimesh
	node.material_override = material
	node.layers = batch.render_state.render_layer_mask
	_world.add_child(node, false, Node.INTERNAL_MODE_BACK)
	var state := BatchState.new()
	state.node = node
	state.multimesh = multimesh
	state.material = material
	return state


func _sync_batch(batch: MoldBatch, state: BatchState, count: int) -> void:
	if _viewport_size != state.viewport_size or _msaa_enabled != state.msaa_enabled:
		state.material.set_shader_parameter("mold_viewport_size", _viewport_size)
		state.viewport_size = _viewport_size
		state.material.set_shader_parameter("mold_msaa_enabled", _msaa_enabled)
		state.msaa_enabled = _msaa_enabled
	var required_capacity := _next_power_of_two(count)
	var resized := state.capacity < required_capacity
	if resized:
		state.multimesh.instance_count = 0
		state.multimesh.instance_count = required_capacity
		state.capacity = required_capacity
		state.transform_revision = 0
		state.property_revision = 0
	if state.visible_count != count:
		state.multimesh.visible_instance_count = count
		state.visible_count = count
	if state.transform_revision != batch.transform_revision:
		_sync_transforms(batch, state)
		state.transform_revision = batch.transform_revision
	if state.property_revision != batch.property_revision:
		_sync_properties(batch, state)
		state.property_revision = batch.property_revision
	batch.acknowledge_changes()


func _sync_transforms(batch: MoldBatch, state: BatchState) -> void:
	var required := state.capacity * 12
	# Store the native MultiMesh layout directly; translation writes only three floats.
	state.transform_buffer = batch.transform_buffer if batch.transform_buffer.size() == required else batch.transform_buffer.slice(0, required)
	if not state.native_mode:
		state.native_transforms_pending = true
		if not state.oit_mode: _flush_native_transforms(state)
	state.upload_revision += 1
	state.multimesh.custom_aabb = _unculled_aabb() if (_settings.culling_mode != MoldWorldSettings.CullingMode.BATCH_BOUNDS and _settings.culling_mode != MoldWorldSettings.CullingMode.AUTO) else _batch_aabb(batch)


static func _unculled_aabb() -> AABB:
	return AABB(Vector3.ONE * -CULLING_EXTENT, Vector3.ONE * CULLING_EXTENT * 2.0)



func _batch_aabb(batch: MoldBatch) -> AABB:
	var count := batch.count()
	if count == 0: return AABB(Vector3.ZERO, Vector3.ONE * 0.001)
	var block_count := (count + MoldBatch.BOUNDS_BLOCK_SIZE - 1) / MoldBatch.BOUNDS_BLOCK_SIZE
	var result := AABB()
	for block in block_count:
		if batch.bounds_dirty[block] != 0:
			var first := block * MoldBatch.BOUNDS_BLOCK_SIZE
			batch.bounds_blocks[block] = _uncached_block_aabb(batch, first, mini(first + MoldBatch.BOUNDS_BLOCK_SIZE, count)) if batch.full_bounds_rebuild else _block_aabb(batch, first, mini(first + MoldBatch.BOUNDS_BLOCK_SIZE, count))
			batch.bounds_dirty[block] = 0
		result = batch.bounds_blocks[block] if block == 0 else result.merge(batch.bounds_blocks[block])
	batch.full_bounds_rebuild = false
	var padding := _settings.culling_bounds_padding
	if padding > 0.0:
		result.position -= Vector3.ONE * padding
		result.size += Vector3.ONE * padding * 2.0
	return result


func _block_aabb(batch: MoldBatch, first: int, end: int) -> AABB:
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var transforms := batch.transform_buffer
	for index in range(first, end):
		var transformed: AABB
		if batch.is_immediate:
			transformed = batch.immediate_bounds[index]
		else:
			if batch.bounds_valid[index] == 0:
				var slot: int = batch.slots[index]
				var transform := batch.transform_at(index)
				transform.origin = Vector3.ZERO
				var polyline: MoldPolyline = _world._polylines[slot]
				if polyline:
					batch.relative_bounds[index] = immediate_polyline_aabb(polyline, transform)
				else:
					var shape: MoldShape = _world._shapes[slot]
					batch.relative_bounds[index] = _instance_aabb(shape, _local_aabb(shape, batch.custom_data_at(index)), transform)
				batch.bounds_valid[index] = 1
			transformed = batch.relative_bounds[index]
			var offset := index * MoldBatch.TRANSFORM_FLOATS_PER_INSTANCE
			transformed.position += Vector3(transforms[offset + 3], transforms[offset + 7], transforms[offset + 11])
		minimum = minimum.min(transformed.position)
		maximum = maximum.max(transformed.end)
	return AABB(minimum, maximum - minimum)


static func _instance_aabb(shape: MoldShape, local: AABB, transform: Transform3D) -> AABB:
	if shape.is_line and shape.billboard_mode == MoldShape.BillboardMode.FACE_CAMERA:
		var half_tangent := transform.basis.x * 0.5
		var first := transform.origin - half_tangent
		var second := transform.origin + half_tangent
		var half_width := transform.basis.y.length() * 0.5
		var minimum := Vector3(
			minf(first.x, second.x),
			minf(first.y, second.y),
			minf(first.z, second.z)) - Vector3.ONE * half_width
		var maximum := Vector3(
			maxf(first.x, second.x),
			maxf(first.y, second.y),
			maxf(first.z, second.z)) + Vector3.ONE * half_width
		return AABB(minimum, maximum - minimum)
	return _transform_aabb(local, transform)


static func immediate_aabb(shape: MoldShape, custom: Vector4, transform: Transform3D) -> AABB:
	return _instance_aabb(shape, _local_aabb(shape, custom), transform)


static func immediate_polyline_aabb(polyline: MoldPolyline, transform: Transform3D) -> AABB:
	if polyline.geometry == MoldPolyline.Geometry.BILLBOARD:
		var radius := polyline.bounds.size.length()*0.5*maxf(transform.basis.x.length(),maxf(transform.basis.y.length(),transform.basis.z.length()))
		return AABB(transform*polyline.bounds.get_center()-Vector3.ONE*radius,Vector3.ONE*radius*2)
	return _transform_aabb(polyline.bounds, transform)


static func _local_aabb(shape: MoldShape, custom: Vector4) -> AABB:
	if shape.billboard_mode != MoldShape.BillboardMode.DISABLED:
		var radius := sqrt(0.5)
		return AABB(Vector3.ONE * -radius, Vector3.ONE * radius * 2.0)
	if shape.kind == MoldShape.Kind.CAPSULE:
		var half_height := 0.5 + custom.y
		return AABB(Vector3(-0.5, -half_height, -0.5), Vector3(1.0, half_height * 2.0, 1.0))
	if shape.kind == MoldShape.Kind.TORUS:
		return AABB(Vector3(-0.5, -custom.y, -0.5), Vector3(1.0, custom.y * 2.0, 1.0))
	if shape.kind == MoldShape.Kind.HEMISPHERE:
		return AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 0.5, 1.0))
	if shape.is_2d:
		return AABB(Vector3(-0.5, -0.5, -0.01), Vector3(1.0, 1.0, 0.02))
	return AABB(Vector3.ONE * -0.5, Vector3.ONE)


static func _transform_aabb(source: AABB, transform: Transform3D) -> AABB:
	return transform * source


func _sync_properties(batch: MoldBatch, state: BatchState) -> void:
	var texel_count := state.capacity * DATA_TEXELS_PER_INSTANCE
	var height := maxi(1, ceili(float(texel_count) / DATA_TEXTURE_WIDTH))
	var byte_count := DATA_TEXTURE_WIDTH * height * 16
	var active_texel_count := batch.count() * DATA_TEXELS_PER_INSTANCE
	if state.property_buffer.size() != byte_count: state.property_buffer.resize(byte_count)
	for row in active_texel_count:
		var value := batch.property_texels[row]
		if not batch.is_immediate and row % 7 == 6:
			var slot := batch.slots[row / 7]
			if _world._gpu_lod_flags[slot] != 0:
				var generation: int = _world._generations[slot]
				value = Vector4((generation & 65535)+1,generation >> 16,slot,0)
		var offset := row*16
		state.property_buffer.encode_float(offset,value.x)
		state.property_buffer.encode_float(offset+4,value.y)
		state.property_buffer.encode_float(offset+8,value.z)
		state.property_buffer.encode_float(offset+12,value.w)
	if batch.mode == MoldStyle.BlendMode.CUSTOM:
		state.custom_data_width = mini(DATA_TEXTURE_WIDTH, _next_power_of_two(maxi(1, state.capacity)))
		var custom_height := maxi(1, ceili(float(state.capacity) / state.custom_data_width))
		state.custom_data_buffer = batch.shader_data.slice(0, batch.count()).to_byte_array()
		state.custom_data_buffer.resize(state.custom_data_width * custom_height * 16)
		state.custom_data_buffer_2 = batch.shader_data_2.slice(0, batch.count()).to_byte_array()
		state.custom_data_buffer_2.resize(state.custom_data_width * custom_height * 16)
	state.native_properties_pending = true
	if not state.oit_mode: _flush_native_properties(state)
	state.upload_revision += 1

func _flush_native_transforms(state: BatchState) -> void:
	if not state.native_transforms_pending: return
	var start: int = _world.performance_metrics.begin_upload()
	RenderingServer.multimesh_set_buffer(state.multimesh.get_rid(), state.transform_buffer)
	state.native_transforms_pending = false
	_world.performance_metrics.end_upload(start, state.transform_buffer.size() * 4)

func _flush_native_properties(state: BatchState) -> void:
	if not state.native_properties_pending: return
	var height := state.property_buffer.size() / (DATA_TEXTURE_WIDTH * 16)
	var start: int = _world.performance_metrics.begin_upload()
	if not state.data_image or state.data_image.get_height() != height:
		state.data_image = Image.create_from_data(DATA_TEXTURE_WIDTH, height, false, Image.FORMAT_RGBAF, state.property_buffer)
		state.data_texture = ImageTexture.create_from_image(state.data_image)
		state.material.set_shader_parameter("mold_instance_data", state.data_texture)
	else:
		state.data_image.set_data(DATA_TEXTURE_WIDTH, height, false, Image.FORMAT_RGBAF, state.property_buffer)
		state.data_texture.update(state.data_image)
	_world.performance_metrics.end_upload(start, state.property_buffer.size())
	if not state.custom_data_buffer.is_empty():
		var custom_start: int = _world.performance_metrics.begin_upload()
		var custom_height := state.custom_data_buffer.size() / (state.custom_data_width * 16)
		if not state.custom_data_image or state.custom_data_image.get_width() != state.custom_data_width or state.custom_data_image.get_height() != custom_height:
			state.custom_data_image = Image.create_from_data(state.custom_data_width, custom_height, false, Image.FORMAT_RGBAF, state.custom_data_buffer)
			state.custom_data_texture = ImageTexture.create_from_image(state.custom_data_image)
			state.material.set_shader_parameter("mold_custom_instance_data", state.custom_data_texture)
		else:
			state.custom_data_image.set_data(state.custom_data_width, custom_height, false, Image.FORMAT_RGBAF, state.custom_data_buffer)
			state.custom_data_texture.update(state.custom_data_image)
		_world.performance_metrics.end_upload(custom_start, state.custom_data_buffer.size())
	if not state.custom_data_buffer_2.is_empty():
		var custom_start: int = _world.performance_metrics.begin_upload()
		var custom_height := state.custom_data_buffer_2.size() / (state.custom_data_width * 16)
		if not state.custom_data_image_2 or state.custom_data_image_2.get_width() != state.custom_data_width or state.custom_data_image_2.get_height() != custom_height:
			state.custom_data_image_2 = Image.create_from_data(state.custom_data_width, custom_height, false, Image.FORMAT_RGBAF, state.custom_data_buffer_2)
			state.custom_data_texture_2 = ImageTexture.create_from_image(state.custom_data_image_2)
			state.material.set_shader_parameter("mold_custom_instance_data_2", state.custom_data_texture_2)
		else:
			state.custom_data_image_2.set_data(state.custom_data_width, custom_height, false, Image.FORMAT_RGBAF, state.custom_data_buffer_2)
			state.custom_data_texture_2.update(state.custom_data_image_2)
		_world.performance_metrics.end_upload(custom_start, state.custom_data_buffer_2.size())
	state.native_properties_pending = false


static func instance_texture_color(value: Color) -> Color:
	var linear := value.srgb_to_linear()
	linear.a = value.a
	return linear


static func pack_color(value: Color, color_mode: MoldStyle.ColorMode, interpolation: MoldStyle.ColorInterpolation) -> Color:
	var linear := instance_texture_color(value)
	if color_mode == MoldStyle.ColorMode.SINGLE or interpolation == MoldStyle.ColorInterpolation.LINEAR_RGB:
		return linear
	var l := _signed_cbrt(0.4122214708 * linear.r + 0.5363325363 * linear.g + 0.0514459929 * linear.b)
	var m := _signed_cbrt(0.2119034982 * linear.r + 0.6806995451 * linear.g + 0.1073969566 * linear.b)
	var s := _signed_cbrt(0.0883024619 * linear.r + 0.2817188376 * linear.g + 0.6299787005 * linear.b)
	return Color(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s,
		linear.a,
	)


static func pack_color_vector(value: Color, color_mode: MoldStyle.ColorMode, interpolation: MoldStyle.ColorInterpolation) -> Vector4:
	var packed := pack_color(value, color_mode, interpolation)
	return Vector4(packed.r, packed.g, packed.b, packed.a)


static func create_single_instance_texture(primary_color: Color, shape_data: Vector4,
		dash_data: Vector4, flags: Vector4, gradient_data: Vector4,
		lod_data := Vector4(1.0, 0.0, 0.0, 0.0)) -> ImageTexture:
	var primary := instance_texture_color(primary_color)
	var texels := PackedVector4Array([
		Vector4(primary.r, primary.g, primary.b, primary.a),
		Vector4.ZERO,
		shape_data,
		dash_data,
		flags,
		gradient_data,
		lod_data,
	])
	var bytes := texels.to_byte_array()
	bytes.resize(DATA_TEXTURE_WIDTH * 16)
	var image := Image.create_from_data(DATA_TEXTURE_WIDTH, 1, false, Image.FORMAT_RGBAF, bytes)
	return ImageTexture.create_from_image(image)


static func create_single_custom_data_texture(data: Vector4) -> ImageTexture:
	var image := Image.create_from_data(1, 1, false, Image.FORMAT_RGBAF,
		PackedVector4Array([data]).to_byte_array())
	return ImageTexture.create_from_image(image)


static func _signed_cbrt(value: float) -> float:
	return signf(value) * pow(absf(value), 1.0 / 3.0)


func _remove(batch: MoldBatch) -> void:
	var state: BatchState = _states.get(batch)
	if not state: return
	if gpu_lod and _gpu_capacities.has(batch):
		gpu_lod.remove(state.node)
		_gpu_capacities.erase(batch)
	_states.erase(batch)
	_free_native_instances(state)
	if is_instance_valid(state.node): state.node.queue_free()


static func _next_power_of_two(value: int) -> int:
	var result := 1
	while result < value: result <<= 1
	return result


# Dense TRS changes invalidate every relative cache each frame. Compute their
# bounds directly; populate relative caches lazily when translation-only updates resume.
func _uncached_block_aabb(batch: MoldBatch, first: int, end: int) -> AABB:
	var result := AABB()
	for index in range(first, end):
		var slot: int = batch.slots[index]
		var polyline: MoldPolyline = _world._polylines[slot]
		var transform := batch.transform_at(index)
		var bounds: AABB
		if polyline:
			bounds = immediate_polyline_aabb(polyline, transform)
		else:
			var shape: MoldShape = _world._shapes[slot]
			bounds = _instance_aabb(shape, _local_aabb(shape, batch.custom_data_at(index)), transform)
		result = bounds if index == first else result.merge(bounds)
	return result


func update_gpu_camera(camera: Camera3D) -> void:
	var was_ready := gpu_ready
	gpu_ready = gpu_lod != null and gpu_lod.ready and camera != null and not camera.get_viewport().use_xr
	if was_ready != gpu_ready: _world._invalidate_orthographic_lod()
	if gpu_lod == null: return
	var ortho := camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	gpu_lod.camera(camera.global_position if camera else Vector3.ZERO,-camera.global_basis.z.normalized() if camera else Vector3.FORWARD,
		(camera.size if ortho else 2*tan(deg_to_rad(camera.fov)*0.5)) if camera else 1.0,
		maxf(camera.get_viewport().get_visible_rect().size.y,1.0) if camera else 1.0,ortho,gpu_ready)

	if (_settings.culling_mode == MoldWorldSettings.CullingMode.FRUSTUM_GPU or _settings.culling_mode == MoldWorldSettings.CullingMode.AUTO):
		var view := camera.get_camera_projection()*Projection(camera.global_transform.affine_inverse()) if camera else Projection.IDENTITY
		gpu_lod.frustum(view.x,view.y,view.z,view.w,_settings.culling_bounds_padding,gpu_ready)


func _sync_gpu_lod(batch: MoldBatch, state: BatchState) -> bool:
	if gpu_lod == null or batch.is_immediate: return false
	var count := batch.count()
	var eligible := gpu_ready and count > 0
	var select_lod: bool = count > 0 and _world._gpu_lod_flags[batch.slots[0]] != 0
	if not select_lod and _settings.culling_mode == MoldWorldSettings.CullingMode.AUTO:
		eligible = eligible and count >= AUTO_GPU_CULLING_MINIMUM_INSTANCES
	# Cache shape/material eligibility until membership or property metadata changes.
	if eligible and (state.gpu_eligibility_revision != batch.property_revision or state.gpu_eligibility_count != count or state.gpu_eligibility_select_lod != select_lod):
		state.gpu_eligible = true
		for i in count:
			var slot := batch.slots[i]
			if select_lod:
				state.gpu_eligible = _world._gpu_lod_flags[slot] != 0 and batch.secondary_memberships[i] == 0
			else:
				state.gpu_eligible = (_settings.culling_mode == MoldWorldSettings.CullingMode.FRUSTUM_GPU or _settings.culling_mode == MoldWorldSettings.CullingMode.AUTO) and _world._gpu_lod_flags[slot] == 0 and _world._polylines[slot] == null and _world._is_lod_eligible(_world._shapes[slot]) and (_world._style_modes[slot] == MoldStyle.BlendMode.OPAQUE or _world._style_modes[slot] == MoldStyle.BlendMode.DITHER)
			if not state.gpu_eligible: break
		state.gpu_eligibility_revision = batch.property_revision
		state.gpu_eligibility_count = count
		state.gpu_eligibility_select_lod = select_lod
	eligible = eligible and state.gpu_eligible
	if not eligible:
		if _gpu_capacities.has(batch): gpu_lod.update(state.node,state.data_texture,0)
		return false
	_flush_native_transforms(state)
	_flush_native_properties(state)
	var signature: int = state.capacity if select_lod else -state.capacity
	if _gpu_capacities.get(batch,0) != signature:
		if _gpu_capacities.has(batch): gpu_lod.remove(state.node)
		var source_key: MoldMeshCache.MeshKey = _world._mesh_keys[batch.slots[0]]
		var meshes: Array = []
		meshes.resize(source_key.detail+1)
		for detail in range(0 if select_lod else source_key.detail,source_key.detail+1):
			var key := MoldMeshCache.MeshKey.new(source_key.kind,detail,source_key.sides,source_key.capped)
			meshes[detail] = _world._mesh_cache.acquire(key)
			_gpu_mesh_keys.append(key)
		gpu_lod.add(state.node,meshes,source_key.kind,source_key.detail,state.capacity,select_lod)
		_gpu_capacities[batch]=signature
	var active: bool = gpu_lod.update(state.node,state.data_texture,count if _world.is_visible_in_tree() else 0,select_lod)
	state.node.visible = not active
	return active

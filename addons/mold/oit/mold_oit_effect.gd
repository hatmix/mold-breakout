extends CompositorEffect
## Internal RenderingDevice backend. SceneTree data is published as immutable snapshots.
const PREPARE_TRANSFORMS_SHADER = preload("shaders/mold_oit_prepare_transforms.glsl")
const AdaptiveVoxel = preload("mold_oit_adaptive_voxel.gd")
const WEIGHTED_SHADER = preload("shaders/mold_oit_weighted.glsl")
const WEIGHTED_MSAA_SHADER = preload("shaders/mold_oit_weighted_msaa.glsl")
const COMPOSITE_SHADER = preload("shaders/mold_oit_composite.glsl")
const COMPOSITE_MSAA_SHADER = preload("shaders/mold_oit_composite_msaa.glsl")
const APPEARANCE_SHADERS = {
 "weighted_paint_stroke_gpu_polyline": preload("shaders/mold_oit_weighted_paint_stroke_gpu_polyline.glsl"),
 "weighted_msaa_paint_stroke_gpu_polyline": preload("shaders/mold_oit_weighted_msaa_paint_stroke_gpu_polyline.glsl"),
 "adaptive_voxel_occupy_paint_stroke_gpu_polyline": preload("shaders/mold_oit_adaptive_voxel_occupy_paint_stroke_gpu_polyline.glsl"),
 "adaptive_voxel_splat_paint_stroke_gpu_polyline": preload("shaders/mold_oit_adaptive_voxel_splat_paint_stroke_gpu_polyline.glsl"),
 "adaptive_voxel_shade_paint_stroke_gpu_polyline": preload("shaders/mold_oit_adaptive_voxel_shade_paint_stroke_gpu_polyline.glsl"),
 "weighted_paint_stroke_polygon": preload("shaders/mold_oit_weighted_paint_stroke_polygon.glsl"),
 "weighted_msaa_paint_stroke_polygon": preload("shaders/mold_oit_weighted_msaa_paint_stroke_polygon.glsl"),
 "adaptive_voxel_occupy_paint_stroke_polygon": preload("shaders/mold_oit_adaptive_voxel_occupy_paint_stroke_polygon.glsl"),
 "adaptive_voxel_splat_paint_stroke_polygon": preload("shaders/mold_oit_adaptive_voxel_splat_paint_stroke_polygon.glsl"),
 "adaptive_voxel_shade_paint_stroke_polygon": preload("shaders/mold_oit_adaptive_voxel_shade_paint_stroke_polygon.glsl"),
 "weighted_pencil_stroke_gpu_polyline": preload("shaders/mold_oit_weighted_pencil_stroke_gpu_polyline.glsl"),
 "weighted_msaa_pencil_stroke_gpu_polyline": preload("shaders/mold_oit_weighted_msaa_pencil_stroke_gpu_polyline.glsl"),
 "adaptive_voxel_occupy_pencil_stroke_gpu_polyline": preload("shaders/mold_oit_adaptive_voxel_occupy_pencil_stroke_gpu_polyline.glsl"),
 "adaptive_voxel_splat_pencil_stroke_gpu_polyline": preload("shaders/mold_oit_adaptive_voxel_splat_pencil_stroke_gpu_polyline.glsl"),
 "adaptive_voxel_shade_pencil_stroke_gpu_polyline": preload("shaders/mold_oit_adaptive_voxel_shade_pencil_stroke_gpu_polyline.glsl"),
 "weighted_pencil_stroke_polygon": preload("shaders/mold_oit_weighted_pencil_stroke_polygon.glsl"),
 "weighted_msaa_pencil_stroke_polygon": preload("shaders/mold_oit_weighted_msaa_pencil_stroke_polygon.glsl"),
 "adaptive_voxel_occupy_pencil_stroke_polygon": preload("shaders/mold_oit_adaptive_voxel_occupy_pencil_stroke_polygon.glsl"),
 "adaptive_voxel_splat_pencil_stroke_polygon": preload("shaders/mold_oit_adaptive_voxel_splat_pencil_stroke_polygon.glsl"),
 "adaptive_voxel_shade_pencil_stroke_polygon": preload("shaders/mold_oit_adaptive_voxel_shade_pencil_stroke_polygon.glsl"),

 "weighted_paint_stroke": preload("shaders/mold_oit_weighted_paint_stroke.glsl"),
 "weighted_msaa_paint_stroke": preload("shaders/mold_oit_weighted_msaa_paint_stroke.glsl"),
 "adaptive_voxel_occupy_paint_stroke": preload("shaders/mold_oit_adaptive_voxel_occupy_paint_stroke.glsl"),
 "adaptive_voxel_splat_paint_stroke": preload("shaders/mold_oit_adaptive_voxel_splat_paint_stroke.glsl"),
 "adaptive_voxel_shade_paint_stroke": preload("shaders/mold_oit_adaptive_voxel_shade_paint_stroke.glsl"),
 "weighted_paint_surface": preload("shaders/mold_oit_weighted_paint_surface.glsl"),
 "weighted_msaa_paint_surface": preload("shaders/mold_oit_weighted_msaa_paint_surface.glsl"),
 "adaptive_voxel_occupy_paint_surface": preload("shaders/mold_oit_adaptive_voxel_occupy_paint_surface.glsl"),
 "adaptive_voxel_splat_paint_surface": preload("shaders/mold_oit_adaptive_voxel_splat_paint_surface.glsl"),
 "adaptive_voxel_shade_paint_surface": preload("shaders/mold_oit_adaptive_voxel_shade_paint_surface.glsl"),
 "weighted_pencil_stroke": preload("shaders/mold_oit_weighted_pencil_stroke.glsl"),
 "weighted_msaa_pencil_stroke": preload("shaders/mold_oit_weighted_msaa_pencil_stroke.glsl"),
 "adaptive_voxel_occupy_pencil_stroke": preload("shaders/mold_oit_adaptive_voxel_occupy_pencil_stroke.glsl"),
 "adaptive_voxel_splat_pencil_stroke": preload("shaders/mold_oit_adaptive_voxel_splat_pencil_stroke.glsl"),
 "adaptive_voxel_shade_pencil_stroke": preload("shaders/mold_oit_adaptive_voxel_shade_pencil_stroke.glsl"),
 "weighted_pencil_surface": preload("shaders/mold_oit_weighted_pencil_surface.glsl"),
 "weighted_msaa_pencil_surface": preload("shaders/mold_oit_weighted_msaa_pencil_surface.glsl"),
 "adaptive_voxel_occupy_pencil_surface": preload("shaders/mold_oit_adaptive_voxel_occupy_pencil_surface.glsl"),
 "adaptive_voxel_splat_pencil_surface": preload("shaders/mold_oit_adaptive_voxel_splat_pencil_surface.glsl"),
 "adaptive_voxel_shade_pencil_surface": preload("shaders/mold_oit_adaptive_voxel_shade_pencil_surface.glsl"),
}
var _appearance_shaders: Dictionary = {}
var _appearance_pipelines: Dictionary = {}
var mutex := Mutex.new()
var packets: Array = []
var _render_packets: Array = []
var _camera_bytes := PackedByteArray()
var _push_bytes := PackedByteArray()
var _sets: Array[RID] = []
var _seen_instances: Dictionary = {}
var _seen_meshes: Dictionary = {}
var _stale: Array = []
var _serial := 0
var _target_color := RID()
var _format_color := RID()
var _color_format := 0
var _color_samples := 0
var _target_framebuffer := RID()
const CLEAR_ONE = [Color(0,0,0,0)]
var clear_one := PackedColorArray(CLEAR_ONE)
var clear_two := PackedColorArray([Color(0,0,0,0),Color.WHITE])
class SetState:
	var shader := RID()
	var index := 0
	var rid := RID()
	var uniforms: Array[RDUniform] = []
	var first: Array[RID] = []
	var second: Array[RID] = []
var _set_pool: Array[SetState] = []
var _set_cursor := 0
var _binding_cursor := 0
var _building: SetState
var _set_changed := false
var backend := 0
var _adaptive_voxel = AdaptiveVoxel.new()
var depth_far := 1000.0
var _av_far := 1000.0
var _active_mode := -1
var _reported_mode := 0
var _ordering_status := "WeightedBlended"
var ready := false
var failure := "Initializing OIT"
var last_draw_count := 0
var last_sample_count := 0
var _samples := RenderingDevice.TEXTURE_SAMPLES_1
var _depth := RID()
var _rd: RenderingDevice
var _shader := RID()
var _shader_msaa := RID()
var _composite_shader_msaa := RID()
var _composite_shader := RID()
var _composite_pipelines: Dictionary = {}
var _camera_buffer := RID()
var _prepare_shader := RID()
var _prepare_pipeline := RID()
var _prepare_sets: Array[RID] = []
var _sampler := RID()
var _surface_sampler := RID()
var _white := RID()
var _accum := RID()
var _reveal := RID()
var _framebuffer := RID()
var _size := Vector2i.ZERO
var _pipelines: Array[RID] = []
var _meshes: Dictionary = {}
var _instances: Dictionary = {}
var _index_buffers: Dictionary = {}
var _index_arrays: Dictionary = {}
var _stopped := false

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	access_resolved_depth = false
	access_resolved_color = false

func publish(value: Array, mode := 0, far_plane := 1000.0, count := -1) -> void:
	mutex.lock()
	if count < 0: count = value.size()
	packets.resize(count)
	for i in count: packets[i] = value[i]
	backend = mode
	depth_far = far_plane
	mutex.unlock()

func get_status() -> String:
	mutex.lock()
	var result := failure
	mutex.unlock()
	return result

func get_effective_backend() -> int:
	mutex.lock()
	var result := _reported_mode
	mutex.unlock()
	return result

func get_ordering_status() -> String:
	mutex.lock()
	var result := _ordering_status
	mutex.unlock()
	return result

func get_draw_count() -> int:
	mutex.lock()
	var result := last_draw_count
	mutex.unlock()
	return result

func get_sample_count() -> int:
	mutex.lock()
	var result := last_sample_count
	mutex.unlock()
	return result

func _status(message: String) -> void:
	mutex.lock()
	failure = message
	mutex.unlock()

func _count(value: int) -> void:
	mutex.lock()
	last_draw_count = value
	last_sample_count = (1 << _samples) if value > 0 else 0
	mutex.unlock()

# Each call position owns its bindings and set. Stable frames only compare RIDs.
func _begin_set(shader: RID, index: int) -> void:
	if _set_cursor == _set_pool.size(): _set_pool.append(SetState.new())
	_building = _set_pool[_set_cursor]
	_set_cursor += 1
	_binding_cursor = 0
	_set_changed = _building.shader != shader or _building.index != index
	_building.shader = shader
	_building.index = index

func _bind(kind: int, binding: int, first: RID, second := RID()) -> void:
	var i := _binding_cursor
	_binding_cursor += 1
	if i == _building.uniforms.size():
		_building.uniforms.append(RDUniform.new())
		_building.first.append(RID())
		_building.second.append(RID())
		_set_changed = true
	var uniform := _building.uniforms[i]
	if uniform.uniform_type != kind or uniform.binding != binding or _building.first[i] != first or _building.second[i] != second:
		uniform.uniform_type = kind
		uniform.binding = binding
		uniform.clear_ids()
		uniform.add_id(first)
		if second.is_valid(): uniform.add_id(second)
		_building.first[i] = first
		_building.second[i] = second
		_set_changed = true

func _end_set() -> RID:
	if _building.uniforms.size() != _binding_cursor:
		_building.uniforms.resize(_binding_cursor)
		_building.first.resize(_binding_cursor)
		_building.second.resize(_binding_cursor)
		_set_changed = true
	if _set_changed or not _rd.uniform_set_is_valid(_building.rid):
		if _rd.uniform_set_is_valid(_building.rid): _rd.free_rid(_building.rid)
		_building.rid = _rd.uniform_set_create(_building.uniforms,_building.shader,_building.index)
	return _building.rid

func _write_matrix(p: Projection, offset: int) -> void:
	for column in 4:
		for row in 4: _camera_bytes.encode_float(offset+(column*4+row)*4,p[column][row])

func push_data(x: float, y := 0.0, z := 0.0, w := 0.0) -> PackedByteArray:
	_push_bytes.resize(16)
	_push_bytes.encode_float(0,x); _push_bytes.encode_float(4,y)
	_push_bytes.encode_float(8,z); _push_bytes.encode_float(12,w)
	return _push_bytes

func _create_shader(shader_file: RDShaderFile) -> RID:
	var error := shader_file.base_error
	var spirv := shader_file.get_spirv()
	if error.is_empty() and spirv != null:
		for stage in [RenderingDevice.SHADER_STAGE_VERTEX, RenderingDevice.SHADER_STAGE_FRAGMENT, RenderingDevice.SHADER_STAGE_COMPUTE]:
			error = spirv.get_stage_compile_error(stage)
			if not error.is_empty(): break
	if spirv == null and error.is_empty(): error = "Missing imported SPIR-V"
	if not error.is_empty():
		_status(error)
		push_error("Mold OIT shader: " + error)
		return RID()
	return _rd.shader_create_from_spirv(spirv)

func _initialize() -> bool:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null: return false
	_shader = _create_shader(WEIGHTED_SHADER)
	if not _shader.is_valid(): return false
	_composite_shader = _create_shader(COMPOSITE_SHADER)
	if not _composite_shader.is_valid(): return false
	_shader_msaa = _create_shader(WEIGHTED_MSAA_SHADER)
	if not _shader_msaa.is_valid(): return false
	_composite_shader_msaa = _create_shader(COMPOSITE_MSAA_SHADER)
	if not _composite_shader_msaa.is_valid(): return false
	_prepare_shader = _create_shader(PREPARE_TRANSFORMS_SHADER)
	if not _prepare_shader.is_valid(): return false
	_prepare_pipeline = _rd.compute_pipeline_create(_prepare_shader)
	if not _prepare_pipeline.is_valid(): return false
	_camera_buffer = _rd.uniform_buffer_create(208)
	_sampler = _rd.sampler_create(RDSamplerState.new())
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_surface_sampler = _rd.sampler_create(sampler_state)
	var format := RDTextureFormat.new()
	format.width = 1; format.height = 1
	format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	_white = _rd.texture_create(format, RDTextureView.new(), [PackedByteArray([255,255,255,255])])
	return true

func _target(size: Vector2i, format: int, samples := RenderingDevice.TEXTURE_SAMPLES_1) -> RID:
	var f := RDTextureFormat.new()
	f.width = size.x
	f.height = size.y
	f.format = format
	f.samples = samples
	f.usage_bits = RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	return _rd.texture_create(f,RDTextureView.new())

func _targets(size: Vector2i) -> void:
	if size == _size and _accum.is_valid(): return
	_free_weighted_targets()
	_accum = _target(size,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,_samples)
	_reveal = _target(size,RenderingDevice.DATA_FORMAT_R16_SFLOAT,_samples)
	_framebuffer = _rd.framebuffer_create([_accum,_reveal,_depth] if _samples > RenderingDevice.TEXTURE_SAMPLES_1 else [_accum,_reveal])
	_size = size
	if not _pipelines.is_empty(): return
	var blend := RDPipelineColorBlendState.new()
	var a := RDPipelineColorBlendStateAttachment.new()
	a.enable_blend = true
	a.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	a.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	a.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	a.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
	var r := RDPipelineColorBlendStateAttachment.new()
	r.enable_blend = true
	r.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ZERO
	r.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_COLOR
	blend.attachments = [a,r]
	var multisample := RDPipelineMultisampleState.new()
	multisample.sample_count = _samples
	var depth_state := RDPipelineDepthStencilState.new()
	depth_state.enable_depth_test = _samples > RenderingDevice.TEXTURE_SAMPLES_1
	depth_state.depth_compare_operator = RenderingDevice.COMPARE_OP_GREATER_OR_EQUAL
	# Opaque depth is read-only. Hardware testing preserves each covered sample.
	var shader := _shader_msaa if depth_state.enable_depth_test else _shader
	for cull in [RenderingDevice.POLYGON_CULL_DISABLED,RenderingDevice.POLYGON_CULL_BACK,RenderingDevice.POLYGON_CULL_FRONT]:
		var raster := RDPipelineRasterizationState.new()
		raster.cull_mode = cull
		raster.front_face = RenderingDevice.POLYGON_FRONT_FACE_CLOCKWISE
		_pipelines.append(_rd.render_pipeline_create(shader,_rd.framebuffer_get_format(_framebuffer),-1,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,multisample,depth_state,blend))

static func matrix_data(p: Projection) -> PackedFloat32Array:
	return PackedFloat32Array([p.x.x,p.x.y,p.x.z,p.x.w,p.y.x,p.y.y,p.y.z,p.y.w,p.z.x,p.z.y,p.z.z,p.z.w,p.w.x,p.w.y,p.w.z,p.w.w])

func _render_callback(_type: int, render_data: RenderData) -> void:
	if _stopped: return
	if _rd == null and not _initialize():
		_stopped = true
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null or buffers.get_view_count() != 1: return
	var msaa := buffers.get_msaa_3d() != RenderingServer.VIEWPORT_MSAA_DISABLED
	var color := buffers.get_color_layer(0,msaa)
	var depth := buffers.get_depth_layer(0,msaa)
	if color != _format_color:
		var color_description := _rd.texture_get_format(color)
		_color_samples = color_description.samples
		_color_format = color_description.format
		_format_color = color
	var samples := _color_samples
	var new_size := buffers.get_internal_size()
	ready = true
	mutex.lock()
	_render_packets.resize(packets.size())
	for i in packets.size(): _render_packets[i] = packets[i]
	var frame := _render_packets
	var mode := backend
	_av_far = depth_far
	mutex.unlock()
	_count(0)
	# The weighted path supports multisample targets and remains available after
	# an AdaptiveVoxel-specific initialization failure.
	var requested := mode
	if msaa or not _adaptive_voxel.failure.is_empty(): mode = 0
	mutex.lock()
	_reported_mode = mode
	_ordering_status = "AdaptiveVoxel" if mode == 1 else ("Weighted fallback: MSAA or AdaptiveVoxel unavailable" if requested == 1 else "WeightedBlended")
	mutex.unlock()
	_status("OIT available")
	_set_cursor = 0
	_serial += 1
	for packet in frame:
		_seen_instances[packet.id] = _serial
		_seen_meshes[packet.mesh_id] = _serial
	_stale.clear()
	for key in _meshes:
		if _seen_meshes.get(key,0) != _serial: _stale.append(key)
	for key in _stale:
		_rd.free_rid(_meshes[key]); _meshes.erase(key); _seen_meshes.erase(key)
		if _index_buffers.has(key):
			_rd.free_rid(_index_buffers[key]); _index_buffers.erase(key); _index_arrays.erase(key)
	_stale.clear()
	for key in _instances:
		if _seen_instances.get(key,0) != _serial: _stale.append(key)
	for key in _stale:
		if _instances[key].get("geometry",RID()).is_valid(): _rd.free_rid(_instances[key].geometry)
		if _instances[key].get("appearance",RID()).is_valid(): _rd.free_rid(_instances[key].appearance)
		_rd.free_rid(_instances[key].rid); _rd.free_rid(_instances[key].matrices); _instances.erase(key); _seen_instances.erase(key)
	if mode != _active_mode or new_size != _size or samples != _samples or (msaa and depth != _depth):
		_free_weighted_targets()
		_adaptive_voxel.release_targets(_rd)
		_active_mode = mode
	_size = new_size
	_samples = samples
	_depth = depth
	if frame.is_empty(): return
	if mode == 0: _targets(_size)
	var scene := render_data.get_render_scene_data()
	# RenderSceneData already supplies the GPU projection (Y flipped, reverse Z).
	var projection := scene.get_cam_projection()
	_camera_bytes.resize(208)
	_write_matrix(projection,0)
	_write_matrix(Projection(scene.get_cam_transform().affine_inverse()),64)
	_write_matrix(Projection(scene.get_cam_transform()),128)
	_camera_bytes.encode_float(192,_size.x); _camera_bytes.encode_float(196,_size.y)
	_rd.buffer_update(_camera_buffer,0,208,_camera_bytes)
	_sets.resize(frame.size())
	for i in frame.size():
		var packet: Dictionary = frame[i]
		if not _meshes.has(packet.mesh_id):
			_meshes[packet.mesh_id] = _rd.storage_buffer_create(packet.vertices.size(),packet.vertices)
			if not packet.indices.is_empty():
				var indices := _rd.index_buffer_create(packet.element_count,RenderingDevice.INDEX_BUFFER_FORMAT_UINT32,packet.indices)
				_index_buffers[packet.mesh_id] = indices
				_index_arrays[packet.mesh_id] = _rd.index_array_create(indices,0,packet.element_count)
		if not _instances.has(packet.id):
			_instances[packet.id] = {"version":packet.version,"size":packet.instances.size(),"rid":_rd.storage_buffer_create(packet.instances.size(),packet.instances),"matrices":_rd.storage_buffer_create(packet.count*128)}
		var cached: Dictionary = _instances[packet.id]
		if packet.has("appearance_data"):
			if not cached.has("appearance"): cached.appearance=_rd.uniform_buffer_create(128,packet.appearance_data)
			elif cached.version != packet.version: _rd.buffer_update(cached.appearance,0,128,packet.appearance_data)

		if packet.has("geometry_data"):
			if not cached.has("geometry"): cached.geometry=_rd.uniform_buffer_create(64,packet.geometry_data)
			elif cached.version != packet.version: _rd.buffer_update(cached.geometry,0,64,packet.geometry_data)
		if cached.version != packet.version:
			if cached.size == packet.instances.size():
				_rd.buffer_update(cached.rid,0,cached.size,packet.instances)
			else:
				_rd.free_rid(cached.matrices)
				cached.matrices = _rd.storage_buffer_create(packet.count*128)
				_rd.free_rid(cached.rid)
				cached.rid = _rd.storage_buffer_create(packet.instances.size(),packet.instances)
				cached.size = packet.instances.size()
			cached.version = packet.version
		if mode != 0: continue
		_weighted_pipeline(packet.get("appearance",""),packet.cull)
		_begin_set(_effect_shader("weighted_msaa" if msaa else "weighted",packet.get("appearance","")),0)
		_bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,0,_meshes[packet.mesh_id])
		_bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,1,cached.rid)
		_bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,5,cached.matrices)
		_bind(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,2,_camera_buffer)
		if not msaa: _bind(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,3,_sampler,depth)
		_bind(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,4,_surface_sampler,_surface_texture(packet))
		if packet.has("appearance"): _bind(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,6,cached.appearance)
		_bind_stream(packet,cached)
		_sets[i] = _end_set()
	_prepare_transforms(frame)
	var composite_accum := _accum
	var composite_reveal := _reveal
	if mode == 1:
		composite_accum = _adaptive_voxel.render(self,frame,buffers.get_depth_layer(0))
		if not composite_accum.is_valid():
			_render_callback(_type, render_data)
			return
		composite_reveal = _adaptive_voxel.reveal
		_count(frame.size()*3)
	else:
		var draw := _rd.draw_list_begin(_framebuffer,RenderingDevice.DRAW_CLEAR_COLOR_0 | RenderingDevice.DRAW_CLEAR_COLOR_1,clear_two)
		for i in frame.size():
			var packet: Dictionary = frame[i]
			_rd.draw_list_bind_render_pipeline(draw,_weighted_pipeline(packet.get("appearance",""),packet.cull))
			_rd.draw_list_bind_uniform_set(draw,_sets[i],0)
			_draw_packet(draw,packet)

		_rd.draw_list_end()
		_count(frame.size())
	var composite_shader := _composite_shader_msaa if msaa else _composite_shader
	_begin_set(composite_shader,0)
	_bind(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,0,_sampler,composite_accum)
	_bind(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,1,_sampler,composite_reveal)
	var composite_set := _end_set()
	if color != _target_color or not _rd.framebuffer_is_valid(_target_framebuffer):
		if _rd.framebuffer_is_valid(_target_framebuffer): _rd.free_rid(_target_framebuffer)
		_target_color = color
		_target_framebuffer = _rd.framebuffer_create([color])
	var target := _target_framebuffer
	var format := _rd.framebuffer_get_format(target)
	var scale := 1.0 if _color_format == RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT else 0.5
	var composite := _rd.draw_list_begin(target)
	var key := format
	if not _composite_pipelines.has(key):
		var blend := RDPipelineColorBlendState.new()
		var attachment := RDPipelineColorBlendStateAttachment.new()
		attachment.enable_blend = true
		attachment.src_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.dst_color_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
		attachment.src_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE
		attachment.dst_alpha_blend_factor = RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
		blend.attachments = [attachment]
		var multisample := RDPipelineMultisampleState.new()
		multisample.sample_count = _samples
		multisample.enable_sample_shading = msaa
		multisample.min_sample_shading = 1.0 if msaa else 0.0
		_composite_pipelines[key] = _rd.render_pipeline_create(composite_shader,format,-1,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,RDPipelineRasterizationState.new(),multisample,RDPipelineDepthStencilState.new(),blend)
	_rd.draw_list_bind_render_pipeline(composite,_composite_pipelines[key])
	_rd.draw_list_bind_uniform_set(composite,composite_set,0)
	_rd.draw_list_set_push_constant(composite,push_data(scale,0,0),16)
	_rd.draw_list_draw(composite,false,1,3)
	_rd.draw_list_end()
	# Mobile's post-transparent callback runs after the engine's normal resolve.
	# Resolve the final composited scene, never the raw accumulation textures.
	if msaa and _type == EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		_rd.texture_resolve_multisample(color,buffers.get_color_layer(0))

func _free_weighted_targets() -> void:
	for pipeline in _appearance_pipelines.values(): _rd.free_rid(pipeline)
	_appearance_pipelines.clear()
	for pipeline in _pipelines: _rd.free_rid(pipeline)
	_pipelines.clear()
	# Godot invalidates dependent framebuffers when it replaces viewport depth.
	if _rd.framebuffer_is_valid(_framebuffer): _rd.free_rid(_framebuffer)
	for id in [_accum,_reveal]:
		if id.is_valid(): _rd.free_rid(id)
	_framebuffer = RID()
	_accum = RID()
	_reveal = RID()

func _prepare_transforms(frame: Array) -> void:
	_prepare_sets.resize(frame.size())
	for i in frame.size():
		var cached: Dictionary = _instances[frame[i].id]
		_begin_set(_prepare_shader,0)
		_bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,0,cached.rid)
		_bind(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,1,_camera_buffer)
		_bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,cached.matrices)
		_prepare_sets[i] = _end_set()
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list,_prepare_pipeline)
	for i in frame.size():
		_rd.compute_list_bind_uniform_set(list,_prepare_sets[i],0)
		_rd.compute_list_dispatch(list,ceili(frame[i].count/64.0),1,1)
	_rd.compute_list_end()

func _draw_packet(draw: int, packet: Dictionary) -> void:
	var indexed := _index_arrays.has(packet.mesh_id)
	if indexed: _rd.draw_list_bind_index_array(draw,_index_arrays[packet.mesh_id])
	_rd.draw_list_draw(draw,indexed,packet.count,0 if indexed else packet.element_count)

func shutdown() -> void:
	_stopped = true
	_render_packets.clear()
	mutex.lock()
	packets.clear()
	mutex.unlock()
	ready = false
	if _rd == null: return
	for state in _set_pool:
		if _rd.uniform_set_is_valid(state.rid): _rd.free_rid(state.rid)
	_set_pool.clear()
	if _rd.framebuffer_is_valid(_target_framebuffer): _rd.free_rid(_target_framebuffer)
	_adaptive_voxel.shutdown(_rd)
	for item in _instances.values():
		if item.get("geometry",RID()).is_valid(): _rd.free_rid(item.geometry)
		if item.get("appearance",RID()).is_valid(): _rd.free_rid(item.appearance)
		_rd.free_rid(item.rid)
		_rd.free_rid(item.matrices)
	for id in _meshes.values(): _rd.free_rid(id)
	for id in _index_buffers.values(): _rd.free_rid(id)
	_index_buffers.clear()
	_index_arrays.clear()
	_free_weighted_targets()
	for pipeline in _composite_pipelines.values(): _rd.free_rid(pipeline)
	_pipelines.clear()
	_composite_pipelines.clear()
	for id in [_prepare_pipeline,_prepare_shader,_camera_buffer,_sampler,_surface_sampler,_white,_shader,_shader_msaa,_composite_shader,_composite_shader_msaa]:
		if id.is_valid(): _rd.free_rid(id)
	for shader in _appearance_shaders.values(): _rd.free_rid(shader)
	_appearance_shaders.clear()
	_instances.clear()
	_meshes.clear()

func _surface_texture(packet: Dictionary) -> RID:
	var texture: Texture2D = packet.get("texture")
	if texture == null: return _white
	var rid := RenderingServer.texture_get_rd_texture(texture.get_rid(), true)
	return rid if rid.is_valid() else _white

func _effect_shader(stage: String, variant: String) -> RID:
	if variant.is_empty(): return _shader_msaa if stage == "weighted_msaa" else _shader
	var key := stage+"_"+variant
	if not _appearance_shaders.has(key): _appearance_shaders[key]=_create_shader(APPEARANCE_SHADERS[key])
	return _appearance_shaders[key]
func _weighted_pipeline(variant: String, cull: int) -> RID:
	if variant.is_empty(): return _pipelines[cull]
	var key := variant+str(cull)
	if _appearance_pipelines.has(key): return _appearance_pipelines[key]
	var raster := RDPipelineRasterizationState.new()
	raster.cull_mode=cull; raster.front_face=RenderingDevice.POLYGON_FRONT_FACE_CLOCKWISE
	var multi := RDPipelineMultisampleState.new();multi.sample_count=_samples
	var depth := RDPipelineDepthStencilState.new();depth.enable_depth_test=_samples>RenderingDevice.TEXTURE_SAMPLES_1;depth.depth_compare_operator=RenderingDevice.COMPARE_OP_GREATER_OR_EQUAL
	var blend := RDPipelineColorBlendState.new()
	var a := RDPipelineColorBlendStateAttachment.new();a.enable_blend=true
	a.src_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE;a.dst_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
	a.src_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ONE;a.dst_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
	var r := RDPipelineColorBlendStateAttachment.new();r.enable_blend=true;r.src_color_blend_factor=RenderingDevice.BLEND_FACTOR_ZERO;r.dst_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_COLOR
	blend.attachments=[a,r]
	var shader := _effect_shader("weighted_msaa" if depth.enable_depth_test else "weighted",variant)
	var pipeline := _rd.render_pipeline_create(shader,_rd.framebuffer_get_format(_framebuffer),-1,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,multi,depth,blend)
	_appearance_pipelines[key]=pipeline
	return pipeline

func _bind_stream(packet: Dictionary, cached: Dictionary) -> void:
	if not packet.has("geometry_data"): return
	_bind(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,7,cached.geometry)
	_bind(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,8,_sampler,RenderingServer.texture_get_rd_texture(packet.points.get_rid(),false))
	if packet.get("segments") != null:
		_bind(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,9,_sampler,RenderingServer.texture_get_rd_texture(packet.segments.get_rid(),false))

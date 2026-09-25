# Shared by both ports. A mutex protects camera snapshots and batch lifetime across threads.
extends RefCounted

class Draw:
	var node: MultiMeshInstance3D
	var multimesh: MultiMesh
	var texture: Texture2DRD
	var image := RID()
	var uniform := RID()
	var args := RID()
	var args_guard := RID()
class Batch:
	var source: MultiMeshInstance3D
	var properties: Texture2D
	var capacity := 0
	var count := 0
	var kind := 0
	var cap := 0
	var mode := 0
	var first_detail := 0
	var culled := false
	var draws: Array[Draw] = []
	var selection := RID()
	var source_buffer := RID()
	var source_texture := RID()
	var ready := false
	var removed := false

var ready := false
var _auto_culling := false
var _planes: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO]
var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()
var _history := RID()
var _sampler := RID()
var _guard_texture := RID()
var _capacity := 0
var _mode := 0
var _frustum := RID()
var _frustum_bytes := PackedByteArray()
var _mutex := Mutex.new()
var _batches: Dictionary = {}
var _retired: Array[Batch] = []
var _push := PackedByteArray()
var _camera_valid := false
var _stopped := false
var _dispatch_callable: Callable
var _release_callable: Callable

func _init(capacity: int, bias: float, thresholds: Vector4, hysteresis: float, width: float, mode: int, auto_culling: bool = false) -> void:
	_auto_culling = auto_culling
	_capacity = capacity
	_mode = mode
	_frustum_bytes.resize(80)
	_push.resize(96)
	_vec(32, thresholds)
	_vec(48, Vector4(bias,hysteresis,width,1))
	_push.encode_u32(92,mode)
	_dispatch_callable = _dispatch
	_release_callable = _release
	RenderingServer.call_on_render_thread(_initialize)
	RenderingServer.frame_pre_draw.connect(_submit)

func _vec(offset: int, value: Vector4) -> void:
	_push.encode_float(offset,value.x)
	_push.encode_float(offset+4,value.y)
	_push.encode_float(offset+8,value.z)
	_push.encode_float(offset+12,value.w)

func _initialize() -> void:
	_rd = RenderingServer.get_rendering_device()
	if _rd == null: return
	var file: RDShaderFile = load("res://addons/mold/gpu_lod/mold_lod.glsl")
	if file == null: return
	var spirv := file.get_spirv()
	if spirv == null or not spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE).is_empty(): return
	_shader = _rd.shader_create_from_spirv(spirv)
	if not _shader.is_valid(): return
	_pipeline = _rd.compute_pipeline_create(_shader)
	if not _pipeline.is_valid(): return
	var zeros := PackedByteArray()
	zeros.resize(_capacity*8)
	_history = _rd.storage_buffer_create(zeros.size(),zeros)
	_frustum = _rd.storage_buffer_create(80,_frustum_bytes)
	_sampler = _rd.sampler_create(RDSamplerState.new())
	var guard_format := RDTextureFormat.new()
	guard_format.width=1;guard_format.height=1
	guard_format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	guard_format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	_guard_texture=_rd.texture_create(guard_format,RDTextureView.new())
	ready = true

func camera(origin: Vector3, forward: Vector3, span: float, height: float, orthographic: bool, valid: bool) -> void:
	_mutex.lock()
	_vec(0,Vector4(origin.x,origin.y,origin.z,1 if orthographic else 0))
	_vec(16,Vector4(forward.x,forward.y,forward.z,span))
	_push.encode_float(60,height)
	_camera_valid = valid
	_mutex.unlock()

func frustum(x: Vector4, y: Vector4, z: Vector4, w: Vector4, padding: float, enabled: bool) -> void:
	_mutex.lock()
	var row_x := Vector4(x.x,y.x,z.x,w.x)
	var row_y := Vector4(x.y,y.y,z.y,w.y)
	var row_z := Vector4(x.z,y.z,z.z,w.z)
	var row_w := Vector4(x.w,y.w,z.w,w.w)
	_planes[0]=row_w+row_x;_planes[1]=row_w-row_x
	_planes[2]=row_w+row_y;_planes[3]=row_w-row_y
	_planes[4]=row_w+row_z;_planes[5]=row_w-row_z
	_frustum_vec(0,x);_frustum_vec(16,y);_frustum_vec(32,z);_frustum_vec(48,w)
	_frustum_bytes.encode_float(64,padding)
	_frustum_bytes.encode_float(68,1.0 if enabled else 0.0)
	_mutex.unlock()

func _frustum_vec(offset: int, value: Vector4) -> void:
	_frustum_bytes.encode_float(offset,value.x);_frustum_bytes.encode_float(offset+4,value.y)
	_frustum_bytes.encode_float(offset+8,value.z);_frustum_bytes.encode_float(offset+12,value.w)

func add(source: MultiMeshInstance3D, meshes: Array, kind: int, cap: int, capacity: int, select_lod: bool) -> void:
	var batch := Batch.new()
	batch.source=source;batch.kind=kind;batch.cap=cap;batch.capacity=capacity
	batch.mode=_mode if select_lod else 0
	batch.first_detail=0 if select_lod else cap
	for detail in range(batch.first_detail,cap+1):
		var draw := Draw.new()
		var multimesh := MultiMesh.new()
		RenderingServer.multimesh_allocate_data(multimesh.get_rid(),capacity,RenderingServer.MULTIMESH_TRANSFORM_3D,false,false,true)
		multimesh.mesh=meshes[detail]
		draw.multimesh=multimesh
		draw.node=MultiMeshInstance3D.new()
		draw.node.multimesh=multimesh
		draw.node.material_override=source.material_override.duplicate()
		draw.node.layers=source.layers
		draw.node.visible=false
		source.get_parent().add_child(draw.node,false,Node.INTERNAL_MODE_BACK)
		batch.draws.append(draw)
	_mutex.lock()
	_batches[source.get_instance_id()]=batch
	_mutex.unlock()
	RenderingServer.call_on_render_thread(_track_args.bind(batch))

func update(source: MultiMeshInstance3D, properties: Texture2D, count: int, select_lod: bool = false) -> bool:
	_mutex.lock()
	var batch: Batch = _batches.get(source.get_instance_id())
	if batch == null:
		_mutex.unlock()
		return false
	batch.properties=properties;batch.count=count
	batch.mode=_mode if select_lod else 0
	var active := batch.ready and _camera_valid
	# Test the same conservative world bounds used by native visibility. Keep the
	# source hidden while skipped; otherwise it would draw stale indirect data.
	batch.culled = _auto_culling and not _intersects_bounds(source.global_transform * source.multimesh.custom_aabb)
	for draw in batch.draws:
		draw.node.visible=active and count>0 and not batch.culled
		draw.node.multimesh.custom_aabb=source.multimesh.custom_aabb
		draw.node.transform=source.transform
		# Viewport-dependent AA uniforms remain synchronized without creating materials.
		draw.node.material_override.set_shader_parameter(&"mold_viewport_size",source.material_override.get_shader_parameter(&"mold_viewport_size"))
		draw.node.material_override.set_shader_parameter(&"mold_msaa_enabled",source.material_override.get_shader_parameter(&"mold_msaa_enabled"))
	_mutex.unlock()
	return active

func _intersects_bounds(bounds: AABB) -> bool:
	var center := bounds.get_center()
	var extent := bounds.size * 0.5
	for i in 6:
		var plane := _planes[i]
		var radius := absf(plane.x)*extent.x + absf(plane.y)*extent.y + absf(plane.z)*extent.z
		if plane.x*center.x + plane.y*center.y + plane.z*center.z + plane.w < -radius:
			return false
	return true

func remove(source: MultiMeshInstance3D) -> void:
	_mutex.lock()
	var batch: Batch = _batches.get(source.get_instance_id())
	if batch:
		batch.removed=true
		for draw in batch.draws:
			draw.node.visible=false
			draw.node.free()
		_batches.erase(source.get_instance_id())
		_retired.append(batch)
	_mutex.unlock()

func _uniform(type: int, binding: int, rid: RID, extra := RID()) -> RDUniform:
	var value := RDUniform.new()
	value.uniform_type=type;value.binding=binding;value.add_id(rid)
	if extra.is_valid(): value.add_id(extra)
	return value

func _track_args(batch: Batch) -> void:
	if _rd == null: return
	for draw in batch.draws:
		if not draw.args_guard.is_valid():
			var args := RenderingServer.multimesh_get_command_buffer_rd_rid(draw.multimesh.get_rid())
			draw.args=args
			# Godot 4.7 may leave the indirect command buffer alive after MultiMesh disposal.
			# This unused set tracks ONLY that buffer and context-owned resources, so a
			# future engine that frees it automatically cannot cause a double free.
			var guard: Array[RDUniform] = [
				_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,0,_history),
				_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,1,_sampler,_guard_texture),
				_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,_history),
				_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,3,_history),
				_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,4,_history),
				_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,5,_guard_texture),
				_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,6,args),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,7,_frustum)]
			draw.args_guard=_rd.uniform_set_create(guard,_shader,0)

func _prepare(batch: Batch) -> void:
	var source_buffer := RenderingServer.multimesh_get_buffer_rd_rid(batch.source.multimesh.get_rid())
	var source_texture := RenderingServer.texture_get_rd_texture(batch.properties.get_rid())
	if not source_buffer.is_valid() or not source_texture.is_valid(): return
	if batch.ready and source_buffer==batch.source_buffer and source_texture==batch.source_texture: return
	batch.source_buffer=source_buffer;batch.source_texture=source_texture
	if not batch.selection.is_valid(): batch.selection=_rd.storage_buffer_create(batch.capacity*16)
	for draw in batch.draws:
		if draw.uniform.is_valid() and _rd.uniform_set_is_valid(draw.uniform): _rd.free_rid(draw.uniform)
		if not draw.image.is_valid():
			var format := RDTextureFormat.new()
			format.width=1024;format.height=maxi(1,(batch.capacity*7+1023)/1024)
			format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
			format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			draw.image=_rd.texture_create(format,RDTextureView.new())
			draw.texture=Texture2DRD.new();draw.texture.texture_rd_rid=draw.image
			draw.node.material_override.set_shader_parameter(&"mold_instance_data",draw.texture)
		var output := RenderingServer.multimesh_get_buffer_rd_rid(draw.node.multimesh.get_rid())
		var args := RenderingServer.multimesh_get_command_buffer_rd_rid(draw.node.multimesh.get_rid())
		if not output.is_valid() or not args.is_valid():
			ready=false
			return
		var uniforms: Array[RDUniform] = [
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,0,source_buffer),
			_uniform(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,1,_sampler,source_texture),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,_history),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,3,batch.selection),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,4,output),
			_uniform(RenderingDevice.UNIFORM_TYPE_IMAGE,5,draw.image),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,6,args),
			_uniform(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,7,_frustum)]
		draw.uniform=_rd.uniform_set_create(uniforms,_shader,0)
		if not draw.uniform.is_valid():
			ready=false
			return
	batch.ready=true

func _submit() -> void:
	if not _stopped: RenderingServer.call_on_render_thread(_dispatch_callable)

func _dispatch() -> void:
	if not ready or _stopped: return
	_mutex.lock()
	for batch in _retired: _free_batch(batch)
	_retired.clear()
	_rd.buffer_update(_frustum,0,80,_frustum_bytes)
	for key in _batches:
		var batch: Batch = _batches[key]
		if batch.removed or batch.culled: continue
		if batch.properties == null or batch.count==0 or not _camera_valid: continue
		_prepare(batch)
		if not batch.ready: continue
		_push.encode_u32(92,batch.mode)
		_push.encode_u32(68,batch.count);_push.encode_u32(76,batch.cap)
		_push.encode_u32(80,batch.kind);_push.encode_u32(84,1024)
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list,_pipeline)
		_rd.compute_list_bind_uniform_set(list,batch.draws[0].uniform,0)
		_push.encode_u32(64,0)
		_rd.compute_list_set_push_constant(list,_push,96)
		_rd.compute_list_dispatch(list,(batch.count+63)/64,1,1)
		_rd.compute_list_add_barrier(list)
		var levels := batch.draws.size()
		for detail in levels:
			_rd.compute_list_bind_uniform_set(list,batch.draws[detail].uniform,0)
			_push.encode_u32(72,detail+batch.first_detail);_push.encode_u32(64,1)
			_rd.compute_list_set_push_constant(list,_push,96)
			_rd.compute_list_dispatch(list,1,1,1)
			_rd.compute_list_add_barrier(list)
			_push.encode_u32(64,2)
			_rd.compute_list_set_push_constant(list,_push,96)
			_rd.compute_list_dispatch(list,(batch.count+63)/64,1,1)
			_rd.compute_list_add_barrier(list)
		_rd.compute_list_end()
	_mutex.unlock()

func dispose() -> void:
	_mutex.lock()
	_stopped=true
	RenderingServer.frame_pre_draw.disconnect(_submit)
	for key in _batches:
		var batch: Batch = _batches[key]
		if not batch.removed:
			for draw in batch.draws:
				draw.node.visible=false
				draw.node.free()
	_mutex.unlock()
	RenderingServer.call_on_render_thread(_release_callable)

func _release() -> void:
	if _rd == null: return
	for key in _batches:
		var batch: Batch = _batches[key]
		_free_batch(batch)
	_batches.clear()
	for batch in _retired: _free_batch(batch)
	_retired.clear()
	for rid in [_frustum,_guard_texture,_history,_sampler,_pipeline,_shader]:
		if rid.is_valid(): _rd.free_rid(rid)

func _free_batch(batch: Batch) -> void:
	_track_args(batch)
	for draw in batch.draws:
		draw.multimesh=null
		if draw.uniform.is_valid() and _rd.uniform_set_is_valid(draw.uniform): _rd.free_rid(draw.uniform)
		if draw.args_guard.is_valid() and _rd.uniform_set_is_valid(draw.args_guard): _rd.free_rid(draw.args)
		if draw.texture: draw.texture.texture_rd_rid=RID()
		if draw.image.is_valid(): _rd.free_rid(draw.image)
	if batch.selection.is_valid(): _rd.free_rid(batch.selection)

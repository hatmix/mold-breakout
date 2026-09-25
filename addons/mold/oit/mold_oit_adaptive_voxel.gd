extends RefCounted
var sets: Array[RID] = []
var compute_sets: Array[RID] = []
# Experimental scalar adaptive voxel OIT. Occupancy is collected from actual fragments.
const RASTER_SHADERS = [
	preload("shaders/mold_oit_adaptive_voxel_occupy.glsl"),
	preload("shaders/mold_oit_adaptive_voxel_splat.glsl"),
	preload("shaders/mold_oit_adaptive_voxel_shade.glsl"),
]
const COMPUTE_SHADERS = [
	preload("shaders/mold_oit_adaptive_voxel_clear.glsl"),
	preload("shaders/mold_oit_adaptive_voxel_map.glsl"),
	preload("shaders/mold_oit_adaptive_voxel_clear_volume.glsl"),
	preload("shaders/mold_oit_adaptive_voxel_integrate.glsl"),
]
var failure := ""
var shaders: Array[RID] = []
var kernels: Array[RID] = []
var compute_pipelines: Array[RID] = []
var pipelines: Array = []
var appearance_pipelines: Dictionary = {}
var textures: Array[RID] = []
var buffers: Array[RID] = []
var targets: Array[RID] = []
var reveal := RID()
var size := Vector2i.ZERO

func render(e, frame: Array, opaque_depth: RID) -> RID:
	var rd: RenderingDevice = e._rd
	if shaders.is_empty():
		for shader_file in RASTER_SHADERS:
			var shader: RID = e._create_shader(shader_file)
			if not shader.is_valid():
				failure = "Native fallback: AdaptiveVoxel shader compilation failed"
				return RID()
			shaders.append(shader)
		for shader_file in COMPUTE_SHADERS:
			var shader: RID = e._create_shader(shader_file)
			if not shader.is_valid():
				failure = "Native fallback: AdaptiveVoxel compute compilation failed"
				return RID()
			kernels.append(shader)
			var pipeline := rd.compute_pipeline_create(shader)
			if not pipeline.is_valid():
				failure = "Native fallback: AdaptiveVoxel compute is unsupported"
				return RID()
			compute_pipelines.append(pipeline)
	if size != e._size:
		release_targets(rd)
		size = e._size
		var cells := ceili(size.x/8.0)*ceili(size.y/8.0)
		buffers = [rd.storage_buffer_create((16388+cells)*4),rd.storage_buffer_create(cells*129*4),rd.storage_buffer_create(cells*128*4),rd.uniform_buffer_create(16)]
		textures = [e._target(size,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT),e._target(size,RenderingDevice.DATA_FORMAT_R16_SFLOAT)]
		for id in buffers+textures:
			if not id.is_valid():
				failure = "Native fallback: AdaptiveVoxel allocation failed"
				return RID()
		reveal = textures[1]
		targets = [rd.framebuffer_create([textures[0]]),rd.framebuffer_create(textures)]
		for id in targets:
			if not id.is_valid():
				failure = "Native fallback: AdaptiveVoxel framebuffer is unsupported"
				return RID()
	if pipelines.is_empty():
		for stage in 3:
			var blend := RDPipelineColorBlendState.new()
			var a := RDPipelineColorBlendStateAttachment.new()
			if stage==2:
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
			else:
				a.write_r = false
				a.write_g = false
				a.write_b = false
				a.write_a = false
				blend.attachments = [a]
			var variants: Array[RID] = []
			for cull in [RenderingDevice.POLYGON_CULL_DISABLED,RenderingDevice.POLYGON_CULL_BACK,RenderingDevice.POLYGON_CULL_FRONT]:
				var raster := RDPipelineRasterizationState.new()
				raster.cull_mode = cull
				raster.front_face = RenderingDevice.POLYGON_FRONT_FACE_CLOCKWISE
				variants.append(rd.render_pipeline_create(shaders[stage],rd.framebuffer_get_format(targets[1 if stage==2 else 0]),-1,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend))
			pipelines.append(variants)
			for id in variants:
				if not id.is_valid():
					failure = "Native fallback: AdaptiveVoxel fragment writes are unsupported"
					return RID()
	rd.buffer_update(buffers[3],0,16,e.push_data(size.x,size.y,1.0/(log(1.0+maxf(e._av_far,0.01))/log(2.0)),0))
	compute_sets.resize(kernels.size())
	for kernel_index in kernels.size():
		var shader: RID = kernels[kernel_index]
		e._begin_set(shader,0)
		e._bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,0,buffers[0])
		e._bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,1,buffers[1])
		e._bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,2,buffers[2])
		e._bind(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,3,buffers[3])
		compute_sets[kernel_index] = e._end_set()
	var cells := ceili(size.x/8.0)*ceili(size.y/8.0)
	_dispatch(rd,0,compute_sets[0],ceili((cells+16388)/64.0))
	for stage in 3:
		e._begin_set(shaders[stage],1)
		e._bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,0,buffers[0])
		e._bind(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,3,buffers[3])
		if stage>0: e._bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,stage,buffers[stage])
		var extra: RID = e._end_set()
		sets.resize(frame.size())
		for packet_index in frame.size():
			var packet: Dictionary = frame[packet_index]
			var variant: String = packet.get("appearance","")
			_variant_pipeline(e,stage,packet.cull,variant)
			e._begin_set(shaders[stage] if variant.is_empty() else e._effect_shader(["adaptive_voxel_occupy","adaptive_voxel_splat","adaptive_voxel_shade"][stage],variant),0)
			e._bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,0,e._meshes[packet.mesh_id])
			e._bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,1,e._instances[packet.id].rid)
			e._bind(RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER,5,e._instances[packet.id].matrices)
			e._bind(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,2,e._camera_buffer)
			e._bind(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,3,e._sampler,opaque_depth)
			e._bind(RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE,4,e._surface_sampler,e._surface_texture(packet))
			if not variant.is_empty(): e._bind(RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER,6,e._instances[packet.id].appearance)
			e._bind_stream(packet,e._instances[packet.id])
			sets[packet_index] = e._end_set()
		var target := targets[1 if stage==2 else 0]
		var clear: PackedColorArray = e.clear_two if stage==2 else e.clear_one
		var flags := RenderingDevice.DRAW_CLEAR_COLOR_0 | RenderingDevice.DRAW_CLEAR_COLOR_1 if stage==2 else RenderingDevice.DRAW_CLEAR_COLOR_0
		var draw := rd.draw_list_begin(target,flags,clear)
		for i in frame.size():
			var packet: Dictionary = frame[i]
			rd.draw_list_bind_render_pipeline(draw,_variant_pipeline(e,stage,packet.cull,packet.get("appearance","")))
			rd.draw_list_bind_uniform_set(draw,sets[i],0)
			rd.draw_list_bind_uniform_set(draw,extra,1)
			e._draw_packet(draw,packet)
		rd.draw_list_end()
		if stage==0:
			_dispatch(rd,1,compute_sets[1],1)
			_dispatch(rd,2,compute_sets[2],ceili(cells/64.0))
		elif stage==1: _dispatch(rd,3,compute_sets[3],ceili(cells/64.0))
	return textures[0]

func _dispatch(rd: RenderingDevice, stage: int, uniform: RID, groups: int) -> void:
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,compute_pipelines[stage])
	rd.compute_list_bind_uniform_set(list,uniform,0)
	rd.compute_list_dispatch(list,groups,1,1)
	rd.compute_list_end()

func release_targets(rd: RenderingDevice) -> void:
	for pipeline in appearance_pipelines.values(): rd.free_rid(pipeline)
	appearance_pipelines.clear()
	for id in targets+textures+buffers:
		if id.is_valid(): rd.free_rid(id)
	targets.clear()
	textures.clear()
	buffers.clear()
	reveal = RID()
	size = Vector2i.ZERO

func shutdown(rd: RenderingDevice) -> void:
	release_targets(rd)
	for id in shaders+kernels:
		if id.is_valid(): rd.free_rid(id)
	shaders.clear()
	kernels.clear()
	pipelines.clear()
	compute_pipelines.clear()

func _variant_pipeline(e, stage: int, cull: int, variant: String) -> RID:
	if variant.is_empty(): return pipelines[stage][cull]
	var key := variant+str(stage)+str(cull)
	if appearance_pipelines.has(key): return appearance_pipelines[key]
	var rd: RenderingDevice = e._rd
	var shader: RID = e._effect_shader(["adaptive_voxel_occupy","adaptive_voxel_splat","adaptive_voxel_shade"][stage],variant)
	var raster := RDPipelineRasterizationState.new();raster.cull_mode=cull;raster.front_face=RenderingDevice.POLYGON_FRONT_FACE_CLOCKWISE
	var blend := RDPipelineColorBlendState.new()
	var a := RDPipelineColorBlendStateAttachment.new()
	if stage==2:
		a.enable_blend=true;a.src_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE;a.dst_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
		a.src_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ONE;a.dst_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
		var r := RDPipelineColorBlendStateAttachment.new();r.enable_blend=true;r.src_color_blend_factor=RenderingDevice.BLEND_FACTOR_ZERO;r.dst_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_COLOR
		blend.attachments=[a,r]
	else:
		a.write_r=false;a.write_g=false;a.write_b=false;a.write_a=false;blend.attachments=[a]
	var result := rd.render_pipeline_create(shader,rd.framebuffer_get_format(targets[1 if stage==2 else 0]),-1,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend)
	appearance_pipelines[key]=result
	return result

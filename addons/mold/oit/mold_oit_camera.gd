class_name MoldOitCamera
extends Node
## Managed by MoldRuntime.enable_oit(). Manual Camera3D children remain supported.
const Effect = preload("mold_oit_effect.gd")
enum Backend { WEIGHTED_BLENDED, ADAPTIVE_VOXEL }
enum RenderTiming { AUTO, BEFORE_TRANSPARENTS, AFTER_TRANSPARENTS }
## Places the complete OIT layer relative to normal transparency, before post-processing.
@export var render_timing: RenderTiming = RenderTiming.AUTO
@export var oit_enabled := true
@export var backend: Backend = Backend.WEIGHTED_BLENDED
var effect: CompositorEffect
var _camera: Camera3D
var _previous: Compositor
var _installed: Compositor
var _cache: Dictionary = {}
var _meshes: Dictionary = {}
var _frame: Array = []
var _frame_count := 0
var _stale: Array = []
var _live_meshes: Dictionary = {}
var _prune_serial := 0
var _empty_frame: Array = []
var _surfaces: Array[WeakRef] = []
var _surface_packets: Array = []
var _requested_backend := -1
var _effective_backend := 0
var _shared_world_frame := -1
var _shared_world := false
var _viewports: Array[WeakRef] = []
var _viewports_dirty := true

func _viewport_changed(node: Node) -> void:
	if node is Viewport: _viewports_dirty = true

func request_backend(value: int) -> void:
	_requested_backend = maxi(_requested_backend, clampi(value, 0, 1))

func effective_render_timing() -> RenderTiming:
	# Mobile currently requires the post-transparent target/resolve path.
	if RenderingServer.get_current_rendering_method() == "mobile": return RenderTiming.AFTER_TRANSPARENTS
	return RenderTiming.AFTER_TRANSPARENTS if render_timing == RenderTiming.AFTER_TRANSPARENTS else RenderTiming.BEFORE_TRANSPARENTS

func timing_status() -> String:
	if render_timing == RenderTiming.BEFORE_TRANSPARENTS and effective_render_timing() == RenderTiming.AFTER_TRANSPARENTS:
		return "AfterTransparents fallback: Mobile requires post-transparent OIT"
	return "AfterTransparents" if effective_render_timing() == RenderTiming.AFTER_TRANSPARENTS else "BeforeTransparents"

func effective_backend() -> Backend:
	return effect.get_effective_backend() as Backend if effect != null else Backend.WEIGHTED_BLENDED

func ordering_status() -> String:
	var current := status()
	return effect.get_ordering_status() if current == "OIT available" else current

# Managed controllers belong to the viewport and follow its active camera.
var _automatic := false
var _pending_viewport: WeakRef

static func enable_for(viewport: Viewport) -> MoldOitCamera:
	assert(viewport != null and viewport.is_inside_tree(), "OIT requires a viewport in the scene tree")
	var existing = viewport.get_meta("mold_oit_camera") if viewport.has_meta("mold_oit_camera") else null
	if is_instance_valid(existing):
		existing.oit_enabled = true
		return existing
	var controller := MoldOitCamera.new()
	controller._schedule_mount(viewport)
	return controller

static func disable_for(viewport: Viewport) -> void:
	var controller = viewport.get_meta("mold_oit_camera") if viewport.has_meta("mold_oit_camera") else null
	if is_instance_valid(controller):
		viewport.remove_meta("mold_oit_camera")
		controller.free()

func _schedule_mount(viewport: Viewport) -> void:
	_automatic = true
	name = "__Mold OIT"
	_pending_viewport = weakref(viewport)
	viewport.set_meta("mold_oit_camera",self)
	viewport.set_meta("mold_oit_camera_id",get_instance_id())
	_mount.call_deferred()

func _mount() -> void:
	var viewport = _pending_viewport.get_ref()
	_pending_viewport = null
	if not is_instance_valid(viewport) or not viewport.is_inside_tree():
		if is_instance_valid(viewport): viewport.remove_meta("mold_oit_camera")
		queue_free()
		return
	viewport.add_child(self)

func _ready() -> void:
	process_priority = 10000
	get_tree().node_added.connect(_viewport_changed)
	get_tree().node_removed.connect(_viewport_changed)
	effect = Effect.new()
	_update_render_timing()
	if _automatic:
		_attach_camera(get_viewport().get_camera_3d())
	else:
		_attach_camera(get_parent() as Camera3D)
		if _camera == null: push_error("MoldOitCamera must be a child of Camera3D")
	get_viewport().set_meta("mold_oit_camera",self)
	get_viewport().set_meta("mold_oit_camera_id",get_instance_id())

func _attach_camera(camera: Camera3D) -> void:
	if is_instance_valid(_camera) and _camera.compositor == _installed:
		_camera.compositor = _previous
	_camera = camera
	_previous = null
	_installed = null
	if _camera == null: return
	_previous = _camera.compositor
	_installed = Compositor.new()
	var inherited := _previous
	if inherited == null:
		# A camera compositor overrides the WorldEnvironment compositor. Preserve its effects.
		for environment in get_tree().root.find_children("*","WorldEnvironment",true,false):
			if environment.get_viewport().find_world_3d() == _camera.get_world_3d() and environment.compositor != null:
				inherited = environment.compositor
				break
	if inherited: _installed.compositor_effects = inherited.compositor_effects.duplicate()
	var effects: Array[CompositorEffect] = _installed.compositor_effects
	effects.append(effect)
	_installed.compositor_effects = effects
	_camera.compositor = _installed

func _sync_camera() -> void:
	if not _automatic or effect == null or not is_inside_tree(): return
	var current := get_viewport().get_camera_3d()
	if (not is_instance_valid(_camera) and current != null) or (is_instance_valid(_camera) and _camera != current):
		_attach_camera(current)

func status() -> String:
	if _pending_viewport != null:
		var viewport = _pending_viewport.get_ref()
		if viewport != null and viewport.get_camera_3d() != null: return "Initializing OIT"
	_sync_camera()
	# Scene visibility is shared by cameras in the same World3D. Until a per-view
	# submission path exists, keep these objects in the native renderer for every view.
	if is_inside_tree() and _shared_world_frame != Engine.get_process_frames():
		_shared_world_frame = Engine.get_process_frames()
		_shared_world = false
		if _viewports_dirty:
			_viewports.clear()
			for viewport in get_tree().root.find_children("*", "SubViewport", true, false): _viewports.append(weakref(viewport))
			_viewports_dirty = false
		for reference in _viewports:
			var viewport = reference.get_ref()
			if viewport != null and viewport != get_viewport() and viewport.find_world_3d() == get_viewport().find_world_3d(): _shared_world = true
		if get_viewport() != get_tree().root and get_tree().root.find_world_3d() == get_viewport().find_world_3d(): _shared_world = true
	if _shared_world: return "Native fallback: shared World3D views require native ordering"
	if not oit_enabled: return "Native fallback: OIT is disabled"
	if not is_instance_valid(_camera) or not _camera.is_current() or _camera.compositor != _installed:
		return "Native fallback: OIT camera is not active"
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" or DisplayServer.get_name() == "headless":
		return "Native fallback: Forward+ or Mobile required"
	if get_viewport().use_xr: return "Native fallback: XR is not supported"
	if effect == null: return "Native fallback: OIT is initializing"
	if not effect.enabled or not _installed.compositor_effects.has(effect): return "Native fallback: OIT effect is disabled"
	return effect.get_status()

func last_draw_count() -> int:
	return effect.get_draw_count() if effect != null and status() == "OIT available" else 0

func last_sample_count() -> int:
	return effect.get_sample_count() if effect != null and status() == "OIT available" else 0

# A cache hit avoids passing packed arrays across the C# boundary, slicing, and hashing.
var _packet_version := 0

# Integer identity avoids allocating an object Variant in the C# render loop.
func submit_cached_batch_id(id: int, revision: int, cull: int, eligible: bool) -> bool:
	return submit_cached_batch(instance_from_id(id),revision,cull,eligible)

func submit_cached_batch(node: MultiMeshInstance3D, revision: int, cull: int, eligible: bool) -> bool:
	node.visible = true
	if not eligible or status() != "OIT available" or not node.is_visible_in_tree() or (node.layers & _camera.cull_mask) == 0: return true
	var count := node.multimesh.visible_instance_count
	if count <= 0: return true
	var mesh := node.multimesh.mesh
	if not (mesh is ArrayMesh) or mesh.get_surface_count() != 1 or mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES: return true
	var id := node.get_instance_id()
	if not _cache.has(id): return false
	var entry: Dictionary = _cache[id]
	if entry.revision != revision or entry.transform != node.global_transform or entry.count != count or entry.mesh_id != mesh.get_instance_id() or entry.cull != cull:
		return false
	_append_packet(entry)
	node.visible = false
	return true

# Called immediately after a cache miss. Revisions include uploads caused by sorting/resizing.
func submit_batch_id(id: int, transforms: PackedFloat32Array, properties: PackedByteArray, cull: int, revision: int) -> void:
	submit_batch(instance_from_id(id),transforms,properties,cull,revision)

func submit_batch(node: MultiMeshInstance3D, transforms: PackedFloat32Array, properties: PackedByteArray, cull: int, revision: int) -> void:
	var count := node.multimesh.visible_instance_count
	var mesh := node.multimesh.mesh
	var mesh_id := mesh.get_instance_id()
	if not _meshes.has(mesh_id): _meshes[mesh_id] = _pack_mesh(mesh)
	var geometry: Dictionary = _meshes[mesh_id]
	if geometry.is_empty(): return
	var id := node.get_instance_id()
	var global := node.global_transform
	var data := _pack_instances(global, transforms, properties, count)
	_packet_version += 1
	var entry := {"id":id,"node":weakref(node),"version":_packet_version,"revision":revision,"transform":global,"instances":data,"mesh_id":mesh_id,"vertices":geometry.data,"indices":geometry.indices,"element_count":geometry.count,"count":count,"cull":cull}
	var appearance_material := node.material_override as ShaderMaterial
	if appearance_material and appearance_material.has_meta("mold_appearance_variant"):
		entry["appearance"]=appearance_material.get_meta("mold_appearance_variant")
		entry["appearance_data"]=appearance_material.get_meta("mold_appearance_data")
	_cache[id] = entry
	_append_packet(entry)
	node.visible = false

# Retained GPU paths and polygon carriers keep their GPU point textures. No CPU expansion.
func release_stream(instance: RID) -> void:
	# A C# disposed Resource may retain a native reference through another packet.
	# Remove by instance identity rather than waiting for a weak material to expire.
	_cache.erase(-instance.get_id())

func submit_stream(owner: Node3D, instance: RID, mesh: Mesh, material: ShaderMaterial, transform: Transform3D, layers: int, visible: bool, ordering: int, cull: int, eligible: bool, flags: Vector4, geometry_kind: String) -> void:
	RenderingServer.instance_set_visible(instance, visible and owner.is_visible_in_tree())
	if not eligible or ordering < 2 or not visible or not owner.is_visible_in_tree():
		_cache.erase(-instance.get_id());return
	request_backend(ordering - 2)
	if status() != "OIT available" or (layers & _camera.cull_mask) == 0 or not material.has_meta("mold_appearance_variant"): return
	var props := PackedFloat32Array()
	for name in ["primary_color", "secondary_color", "shape_data", "dash_data"]:
		var value = material.get_shader_parameter(name)
		var v: Vector4 = value if value is Vector4 else Vector4.ZERO
		props.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
	props.append_array(PackedFloat32Array([flags.x,flags.y,flags.z,flags.w]))
	var gradient: Vector4 = material.get_shader_parameter("gradient_data")
	props.append_array(PackedFloat32Array([gradient.x,gradient.y,gradient.z,gradient.w,1,0,0,TAU]))
	var geometry := PackedFloat32Array()
	var points: Texture2D
	var segments: Texture2D
	if geometry_kind == "gpu_polyline":
		for name in ["mold_gpu_geometry","mold_gpu_vertices_per_segment","mold_gpu_join","mold_gpu_cap","mold_gpu_miter_limit"]: geometry.append(float(material.get_shader_parameter(name)))
		geometry.append(float(material.get_shader_parameter("mold_gpu_dash_cap")))
		var active: int = material.get_shader_parameter("mold_gpu_active_segments")
		# Keep the unbounded sentinel exact when transported in a float buffer.
		geometry.append(-1.0 if active==2147483647 else float(active))
		geometry.resize(8)
		var dash: Vector4 = material.get_shader_parameter("mold_gpu_dash")
		geometry.append_array(PackedFloat32Array([dash.x,dash.y,dash.z,dash.w]))
		points = material.get_shader_parameter("mold_gpu_points")
		segments = material.get_shader_parameter("mold_gpu_segments")
	else:
		for name in ["mold_polygon_count","mold_polygon_aa_quality","mold_polygon_gpu","mold_polygon_uniform_color"]: geometry.append(float(material.get_shader_parameter(name)))
		for name in ["mold_polygon_constant_color","mold_polygon_bounds"]:
			var v: Vector4 = material.get_shader_parameter(name)
			geometry.append_array(PackedFloat32Array([v.x,v.y,v.z,v.w]))
		points = material.get_shader_parameter("mold_polygon_points")
	if points == null or (geometry_kind == "gpu_polyline" and segments == null): return
	if geometry_kind == "polygon": geometry[2]=1.0 # Both carriers retain point indices in UV2.
	geometry.resize(16)
	var id := -instance.get_id()
	var global := owner.global_transform * transform
	var variant: String = material.get_meta("mold_appearance_variant") + "_" + geometry_kind
	var data: PackedByteArray = material.get_meta("mold_appearance_data")
	var mesh_id := mesh.get_instance_id()
	var entry: Dictionary = _cache.get(id,{})
	if entry.is_empty() or entry.transform != global or entry.mesh_id != mesh_id or entry.props != props or entry.geometry_data != geometry.to_byte_array() or entry.appearance_data != data or entry.appearance != variant or entry.cull != cull or entry.points != points or entry.get("segments") != segments:
		if not _meshes.has(mesh_id): _meshes[mesh_id] = _pack_mesh(mesh)
		var packed: Dictionary = _meshes[mesh_id]
		if packed.is_empty(): return
		_packet_version += 1
		entry = {"id":id,"node":weakref(material),"version":_packet_version,"transform":global,"instances":_pack_instances(global,PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0]),props.to_byte_array(),1),"props":props,"stream_instance":instance,"owner":weakref(owner),"stream_visible":visible,"mesh_id":mesh_id,"vertices":packed.data,"indices":packed.indices,"element_count":packed.count,"count":1,"cull":cull,"appearance":variant,"appearance_data":data,"geometry_data":geometry.to_byte_array(),"points":points,"segments":segments}
		_cache[id] = entry
	_append_packet(entry)
	RenderingServer.instance_set_visible(instance, false)

static func _pack_instances(global: Transform3D, transforms: PackedFloat32Array, properties: PackedByteArray, count: int) -> PackedByteArray:
	# Header: world matrix and instance count; then native transform and property blocks.
	var header := Effect.matrix_data(Projection(global))
	header.append_array(PackedFloat32Array([count, 0, 0, 0]))
	var data := header.to_byte_array()
	data.append_array(transforms.slice(0, count * 12).to_byte_array())
	data.append_array(properties.slice(0, count * 112))
	return data

func _append_packet(packet: Dictionary) -> void:
	if _frame_count == _frame.size(): _frame.append(packet)
	else: _frame[_frame_count] = packet
	_frame_count += 1

func _update_render_timing() -> void:
	if effect == null: return
	var callback := CompositorEffect.EFFECT_CALLBACK_TYPE_POST_TRANSPARENT if effective_render_timing() == RenderTiming.AFTER_TRANSPARENTS else CompositorEffect.EFFECT_CALLBACK_TYPE_PRE_TRANSPARENT
	if effect.effect_callback_type != callback: effect.effect_callback_type = callback

func _process(_delta: float) -> void:
	_update_render_timing()
	for reference in _surfaces:
		var node = reference.get_ref()
		if node != null: RenderingServer.instance_set_visible(node.get_instance(), node.is_visible_in_tree())
	_surfaces.clear()
	if status() == "OIT available":
		for node in get_tree().get_nodes_in_group("mold_transparent_objects"):
			if node.get_viewport() == get_viewport(): _submit_mesh(node)
	if effect == null: return
	_sync_camera()
	if not is_instance_valid(_camera):
		effect.publish(_empty_frame)
		_frame_count = 0
		return
	_effective_backend = _requested_backend if _requested_backend >= 0 else backend
	_requested_backend = -1
	effect.publish(_frame,_effective_backend,_camera.far,_frame_count)
	for i in range(_frame_count,_frame.size()): _frame[i] = null
	_frame_count = 0
	_stale.clear()
	_prune_serial += 1
	for id in _cache:
		if _cache[id].node.get_ref() == null: _stale.append(id)
		else: _live_meshes[_cache[id].mesh_id] = _prune_serial
	for id in _stale: _cache.erase(id)
	_stale.clear()
	for id in _meshes:
		if _live_meshes.get(id,0) != _prune_serial: _stale.append(id)
	for id in _stale:
		_meshes.erase(id)
		_live_meshes.erase(id)

func _exit_tree() -> void:
	for reference in _surfaces:
		var node = reference.get_ref()
		if node != null: RenderingServer.instance_set_visible(node.get_instance(), node.is_visible_in_tree())
	if get_viewport().get_meta("mold_oit_camera_id",0) == get_instance_id(): get_viewport().remove_meta("mold_oit_camera_id")
	for item in _cache.values():
		var node = item.node.get_ref()
		if node != null:
			if item.has("stream_instance"):
				var owner = item.owner.get_ref()
				if owner != null: RenderingServer.instance_set_visible(item.stream_instance,item.stream_visible and owner.is_visible_in_tree())
			elif node is Node3D: node.visible = true
	if is_instance_valid(_camera) and _camera.compositor == _installed: _camera.compositor = _previous
	if get_viewport().has_meta("mold_oit_camera") and get_viewport().get_meta("mold_oit_camera") == self: get_viewport().remove_meta("mold_oit_camera")
	_cache.clear()
	_frame.clear()
	if effect != null:
		effect.publish(_empty_frame)
		RenderingServer.call_on_render_thread(effect.shutdown)

func _pack_mesh(mesh: Mesh, surface := 0) -> Dictionary:
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var custom: Array = []
	for slot in 4:
		var bytes = arrays[Mesh.ARRAY_CUSTOM0+slot]
		if bytes != null and bytes.size() > 0:
			if ((mesh.surface_get_format(surface) >> (Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT+slot*Mesh.ARRAY_FORMAT_CUSTOM_BITS)) & Mesh.ARRAY_FORMAT_CUSTOM_MASK) != Mesh.ARRAY_CUSTOM_RGBA_FLOAT: return {}
			custom.append(bytes if bytes is PackedFloat32Array else bytes.to_float32_array())
		else: custom.append(PackedFloat32Array())
	var data := PackedFloat32Array()
	var count := indices.size() if not indices.is_empty() else vertices.size()
	for i in vertices.size():
		var v := vertices[i]
		data.append_array(PackedFloat32Array([v.x,v.y,v.z,1]))
		var n: Vector3 = arrays[Mesh.ARRAY_NORMAL][i] if arrays[Mesh.ARRAY_NORMAL] != null and arrays[Mesh.ARRAY_NORMAL].size() > i else Vector3.FORWARD
		data.append_array(PackedFloat32Array([n.x,n.y,n.z,0]))
		for slot in [Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
			var uv: Vector2 = arrays[slot][i] if arrays[slot] != null and arrays[slot].size() > i else Vector2.ZERO
			data.append_array(PackedFloat32Array([uv.x,uv.y]))
		var color: Color = arrays[Mesh.ARRAY_COLOR][i] if arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_COLOR].size() > i else Color.WHITE
		data.append_array(PackedFloat32Array([color.r,color.g,color.b,color.a]))
		for slot in 4:
			data.append_array(custom[slot].slice(i*4,i*4+4) if not custom[slot].is_empty() else PackedFloat32Array([0,0,0,0]))
	return {"data":data.to_byte_array(),"indices":indices.to_byte_array(),"count":count}

func _submit_mesh(node: MeshInstance3D) -> void:
	if node.transparent_ordering_mode < 2 or not node.is_visible_in_tree() or (node.layers & _camera.cull_mask) == 0: return
	var mesh := node.mesh
	if mesh == null or mesh.get_surface_count() == 0 or node.material_overlay != null or node.skin != null or node.get_node_or_null(node.skeleton) is Skeleton3D: return
	if mesh is ArrayMesh and mesh.get_blend_shape_count() > 0: return
	# Keep the entire native renderer if any surface cannot participate.
	for surface in mesh.get_surface_count():
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: return
		var material = node.get_active_material(surface)
		if not material is MoldOitMaterial or material.shader != MoldOitMaterial.SURFACE or material.next_pass != null or material.render_priority != 0: return
	_surface_packets.clear()
	for surface in mesh.get_surface_count():
		var material: MoldOitMaterial = node.get_active_material(surface)
		var id := str(node.get_instance_id()) + ":" + str(surface)
		var mesh_id := str(mesh.get_instance_id()) + ":" + str(node.geometry_revision) + ":" + str(surface)
		var transform := node.global_transform
		var color: Color = material.color.srgb_to_linear()
		var texture: Texture2D = material.texture
		var entry: Dictionary = _cache.get(id,{})
		if entry.is_empty() or entry.transform != transform or entry.color != color or entry.texture != texture or entry.mesh_id != mesh_id:
			if not _meshes.has(mesh_id): _meshes[mesh_id] = _pack_mesh(mesh,surface)
			var geometry: Dictionary = _meshes[mesh_id]
			if geometry.is_empty(): return
			var properties := PackedByteArray()
			properties.resize(112)
			properties.encode_float(0,color.r); properties.encode_float(4,color.g); properties.encode_float(8,color.b); properties.encode_float(12,color.a)
			properties.encode_float(76,4096.0)
			properties.encode_float(96,1.0); properties.encode_float(108,TAU)
			var data := _pack_instances(transform, PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0]), properties, 1)
			_packet_version += 1
			entry = {"id":id,"node":weakref(node),"version":_packet_version,"transform":transform,"color":color,"texture":texture,"instances":data,"mesh_id":mesh_id,"vertices":geometry.data,"indices":geometry.indices,"element_count":geometry.count,"count":1,"cull":0}
			_cache[id] = entry
		_surface_packets.append(entry)
	request_backend(node.transparent_ordering_mode - 2)
	for entry in _surface_packets: _append_packet(entry)
	_surface_packets.clear()
	_surfaces.append(weakref(node))
	RenderingServer.instance_set_visible(node.get_instance(),false)

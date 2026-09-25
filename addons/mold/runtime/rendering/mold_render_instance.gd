class_name MoldRenderInstance
extends RefCounted

## Retains a stream's RenderingServer instance and its resource references.
## The owning renderer must call dispose before releasing its world.
var instance := RID()
var _owner: WeakRef
var _scenario := RID()
var _appearance_oit_active := false
var _owner_transform := Transform3D.IDENTITY
var mesh: Mesh:
	set(value):
		if mesh == value: return
		mesh = value
		RenderingServer.instance_set_base(instance, mesh.get_rid() if mesh else RID())
var material_override: Material:
	set(value):
		if material_override == value: return
		material_override = value
		RenderingServer.instance_geometry_set_material_override(instance, value.get_rid() if value else RID())
var transform := Transform3D.IDENTITY:
	set(value):
		if transform == value: return
		transform = value
		RenderingServer.instance_set_transform(instance, _owner_transform * transform)
var global_basis: Basis:
	get: return (_owner_transform * transform).basis
var visible := true:
	set(value):
		if visible == value: return
		visible = value
		_sync_visibility()
var layers := 1:
	set(value):
		if layers == value: return
		layers = value
		RenderingServer.instance_set_layer_mask(instance, value)
var custom_aabb := AABB():
	set(value):
		if custom_aabb == value: return
		custom_aabb = value
		RenderingServer.instance_set_custom_aabb(instance, value)


func _init(owner: Node3D) -> void:
	_owner = weakref(owner)
	instance = RenderingServer.instance_create()
	RenderingServer.instance_geometry_set_cast_shadows_setting(instance, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	RenderingServer.instance_set_pivot_data(instance, 0.0, true)
	owner.visibility_changed.connect(_sync_visibility)
	sync_environment()
	# The default identity must also be submitted on first use.
	RenderingServer.instance_set_transform(instance, _owner_transform * transform)
	_sync_visibility()


func _sync_visibility() -> void:
	var owner: Node3D = _owner.get_ref()
	RenderingServer.instance_set_visible(instance, visible and is_instance_valid(owner) and owner.is_visible_in_tree())


func sync_environment() -> void:
	var owner: Node3D = _owner.get_ref()
	if not owner.is_inside_tree(): return
	var scenario := owner.get_world_3d().scenario
	if scenario != _scenario:
		_scenario = scenario
		RenderingServer.instance_set_scenario(instance, scenario)
	var value := owner.global_transform
	if _owner_transform != value:
		_owner_transform = value
		RenderingServer.instance_set_transform(instance, value * transform)


func dispose() -> void:
	if not instance.is_valid(): return
	var owner: Node3D = _owner.get_ref()
	if is_instance_valid(owner):
		if _appearance_oit_active and owner.is_inside_tree():
			var viewport := owner.get_viewport()
			if viewport.has_meta("mold_oit_camera"): viewport.get_meta("mold_oit_camera").release_stream(instance)
		owner.visibility_changed.disconnect(_sync_visibility)
	mesh = null
	material_override = null
	RenderingServer.free_rid(instance)
	instance = RID()

func sync_oit(style: MoldStyle, state: MoldRenderState, aa: int, geometry_kind: String) -> void:
	if not style.appearance and not _appearance_oit_active: return
	_appearance_oit_active=style.appearance != null
	var owner: Node3D = _owner.get_ref()
	_sync_visibility()
	var viewport := owner.get_viewport()
	if not viewport.has_meta("mold_oit_camera") or not material_override is ShaderMaterial or mesh == null: return
	var controller = viewport.get_meta("mold_oit_camera")
	var eligible := style.appearance != null and style.mode == MoldStyle.BlendMode.TRANSPARENT and not state.effective_depth_write(style.mode) and state.depth_test == MoldRenderState.DepthTest.LESS_EQUAL and state.stencil_flags == 0 and state.sorting_order == 0
	var flags := Vector4(style.emission_strength,0,0,(0 if aa == 0 else (1 if aa == 1 else 33)) + (12 if geometry_kind == "gpu_polyline" else 0))
	controller.submit_stream(owner,instance,mesh,material_override,transform,layers,visible,owner.transparent_ordering_mode,state.face_cull,eligible,flags,geometry_kind)

class_name MoldRuntime
extends RefCounted

const WORLD_SCRIPT = preload("res://addons/mold/runtime/core/mold_world.gd")
const RUNTIME_MARKER := &"_mold_runtime_host"
const SHARED_MARKER := &"_mold_shared_runtime_host"
const ATTACHED_MARKER := &"_mold_attached_runtime_host"
const RUNTIME_NAME := "__Mold Runtime"
const SHARED_RUNTIME_NAME := "__Mold Shared Runtime"
const OWNED_RUNTIME_NAME := "__Mold Owned Runtime"
static var _shared_instance


## Enable OIT for all eligible Mold batches in this viewport. Follows camera changes.
static func enable_oit(viewport: Viewport) -> MoldOitCamera:
	return MoldOitCamera.enable_for(viewport)

## Restore native rendering and remove the viewport's OIT controller.
static func disable_oit(viewport: Viewport) -> void:
	MoldOitCamera.disable_for(viewport)


static func shared() -> MoldContext:
	return MoldContext.new(_shared_world())


static func configure_shared(settings: MoldWorldSettings) -> void:
	_shared_world(settings)


static func create(shape: MoldShape, style: MoldStyle = null, render_state: MoldRenderState = null) -> MoldHandle:
	return _shared_world().create(shape, style, render_state)


static func create_polygon(polygon: MoldPolygon, style: MoldStyle = null, render_state: MoldRenderState = null, backend: MoldPolygonBackend.Mode = MoldPolygonBackend.Mode.AUTO) -> MoldPolygonRenderer:
	return _shared_world().create_polygon(polygon, style, render_state, backend)


static func create_polyline(polyline: MoldPolyline, style: MoldStyle = null, render_state: MoldRenderState = null) -> MoldHandle:
	return _shared_world().create_polyline(polyline, style, render_state)


static func create_instance(owner: Node, settings: MoldWorldSettings = null) -> MoldRuntimeInstance:
	_validate_owner(owner, "create_instance")
	var world = _create_world(_lifecycle_container(owner), OWNED_RUNTIME_NAME, settings, &"")
	return MoldRuntimeInstance.new(world)


# Internal systems with an owner-scoped render lifetime use this so tool-script
# reloads also reclaim the world's native rendering children.
static func create_attached_instance(owner: Node, settings: MoldWorldSettings = null) -> MoldRuntimeInstance:
	_validate_owner(owner, "create_attached_instance")
	for child in owner.get_children(true):
		if not child.has_meta(ATTACHED_MARKER): continue
		if child is Node3D: child.visible = false
		child.queue_free()
	return MoldRuntimeInstance.new(_create_world(owner, OWNED_RUNTIME_NAME, settings, ATTACHED_MARKER))


static func for_node(owner: Node, settings: MoldWorldSettings = null) -> MoldContext:
	return MoldContext.new(_world_for(owner, settings))


static func _world_for(owner: Node, settings: MoldWorldSettings = null):
	_validate_owner(owner, "for_node")
	var container := _lifecycle_container(owner)
	for i in container.get_child_count(true):
		var child := container.get_child(i,true)
		if child.get_script() == WORLD_SCRIPT and child.has_meta(RUNTIME_MARKER):
			child._validate_requested_settings(settings)
			return child

	return _create_world(container, RUNTIME_NAME, settings, RUNTIME_MARKER)


static func _shared_world(settings: MoldWorldSettings = null):
	assert(not Engine.is_editor_hint(), "The shared Mold runtime is available while the game is running.")
	var tree := Engine.get_main_loop() as SceneTree
	assert(tree and tree.root and tree.root.is_inside_tree(), "The shared Mold runtime requires an active SceneTree.")
	if is_instance_valid(_shared_instance) and _shared_instance._is_available():
		_shared_instance._validate_requested_settings(settings)
		return _shared_instance
	_shared_instance = null
	for child in tree.root.get_children(true):
		if child.get_script() == WORLD_SCRIPT and child.has_meta(SHARED_MARKER):
			child._validate_requested_settings(settings)
			_shared_instance = child
			return child
	_shared_instance = _create_world(tree.root, SHARED_RUNTIME_NAME, settings, SHARED_MARKER, true)
	return _shared_instance


static func _create_world(container: Node, runtime_name: String, settings: MoldWorldSettings, marker: StringName, deferred_attach := false):
	var world = WORLD_SCRIPT.new()
	world.name = runtime_name
	world.settings = settings.validated_copy() if settings else null
	if not marker.is_empty(): world.set_meta(marker, true)
	if deferred_attach:
		# Godot will not let us add to the root while it is setting up a scene.
		# Shapes work right away; the renderer joins the tree on the next tick.
		world._begin_pending_attach()
		container.add_child.call_deferred(world, false, Node.INTERNAL_MODE_BACK)
	else:
		container.add_child(world, false, Node.INTERNAL_MODE_BACK)
	return world


static func _validate_owner(owner: Node, method: String) -> void:
	assert(is_instance_valid(owner) and owner.is_inside_tree(), "MoldRuntime.%s requires a node that is inside the SceneTree." % method)


static func _lifecycle_container(owner: Node) -> Node:
	var tree := owner.get_tree()
	var viewport := owner.get_viewport()
	if viewport != tree.root:
		return viewport
	var current := tree.current_scene
	if current and (owner == current or current.is_ancestor_of(owner)):
		return current
	var cursor := owner
	while cursor.get_parent() and cursor.get_parent() != viewport:
		cursor = cursor.get_parent()
	return owner if cursor == viewport else cursor

static func create_curve(curve: MoldCurve, stroke: MoldStroke = null, style: MoldStyle = null, render_state: MoldRenderState = null, backend: MoldPolylineBackend.Mode = MoldPolylineBackend.Mode.AUTO, sampling: MoldCurveSampling = null) -> MoldHandle:
	return shared().create_curve(curve,stroke,style,render_state,backend,sampling)

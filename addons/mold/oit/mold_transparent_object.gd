class_name MoldTransparentObject
extends MeshInstance3D
## Attach this script to an ordinary mesh using MoldOitMaterial to opt into OIT.
enum TransparentOrderingMode { NATIVE_COMPATIBLE, BATCHED, WEIGHTED_BLENDED, ADAPTIVE_VOXEL }
@export var transparent_ordering_mode: TransparentOrderingMode = TransparentOrderingMode.WEIGHTED_BLENDED
func _enter_tree() -> void:
	add_to_group("mold_transparent_objects")
var geometry_revision := 0
var _observed_mesh: Mesh
func _geometry_changed() -> void:
	geometry_revision += 1
func _process(_delta: float) -> void:
	if mesh != _observed_mesh:
		if _observed_mesh != null: _observed_mesh.changed.disconnect(_geometry_changed)
		_observed_mesh = mesh
		if mesh != null: mesh.changed.connect(_geometry_changed)
		geometry_revision += 1
	if transparent_ordering_mode < TransparentOrderingMode.WEIGHTED_BLENDED: return
	var viewport := get_viewport()
	if not viewport.has_meta("mold_oit_camera"): MoldOitCamera.enable_for(viewport)

func _exit_tree() -> void:
	RenderingServer.instance_set_visible(get_instance(), visible)

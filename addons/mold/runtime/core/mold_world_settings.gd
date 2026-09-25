@tool
class_name MoldWorldSettings
extends Resource

enum TransparentOrderingMode { NATIVE_COMPATIBLE, BATCHED, WEIGHTED_BLENDED, ADAPTIVE_VOXEL }
@export var transparent_ordering_mode: TransparentOrderingMode = TransparentOrderingMode.NATIVE_COMPATIBLE

enum CullingMode { NONE, BATCH_BOUNDS, FRUSTUM_GPU, AUTO }
enum LodBackend { AUTO, CPU, OFF, GPU }
enum LodMode { MANUAL, DISCREET, CONTINUOUS }
enum LocalAaQuality { OFF, MEDIUM, HIGH }

@export_range(1, 1048576, 1) var capacity := 65536
@export_range(0, 4096, 1) var retained_unused_mesh_count := 64
@export var local_aa_quality: LocalAaQuality = LocalAaQuality.HIGH
@export var culling_mode: CullingMode = CullingMode.AUTO
@export_range(0.0, 100000.0, 0.001, "or_greater") var culling_bounds_padding := 0.0
@export var lod_backend: LodBackend = LodBackend.AUTO:
	set(value):
		if lod_backend == value: return
		lod_backend = value; notify_property_list_changed()
@export var lod_mode: LodMode = LodMode.CONTINUOUS:
	set(value):
		if lod_mode == value: return
		lod_mode = value; notify_property_list_changed()
@export_range(0.01, 16.0, 0.01, "or_greater") var lod_bias := 1.0
@export var lod_threshold_pixels := Vector4(16.0, 32.0, 64.0, 128.0)
@export_range(0.0, 0.49, 0.01) var lod_hysteresis := 0.15
@export_range(0.01, 0.49, 0.01) var lod_transition_width := 0.15
@export_range(1, 1048576, 1) var lod_evaluation_budget := 4096


func validated_copy() -> MoldWorldSettings:
	var result := MoldWorldSettings.new()
	result.transparent_ordering_mode = transparent_ordering_mode if transparent_ordering_mode >= TransparentOrderingMode.NATIVE_COMPATIBLE and transparent_ordering_mode <= TransparentOrderingMode.ADAPTIVE_VOXEL else TransparentOrderingMode.NATIVE_COMPATIBLE
	result.capacity = maxi(1, capacity)
	result.retained_unused_mesh_count = maxi(0, retained_unused_mesh_count)
	result.local_aa_quality = local_aa_quality if local_aa_quality >= LocalAaQuality.OFF and local_aa_quality <= LocalAaQuality.HIGH else LocalAaQuality.HIGH
	result.culling_mode = culling_mode if culling_mode >= CullingMode.NONE and culling_mode <= CullingMode.AUTO else CullingMode.AUTO
	result.culling_bounds_padding = maxf(culling_bounds_padding, 0.0) if is_finite(culling_bounds_padding) else 0.0
	result.lod_backend = lod_backend if lod_backend >= LodBackend.AUTO and lod_backend <= LodBackend.GPU else LodBackend.AUTO
	result.lod_mode = LodMode.MANUAL if lod_backend == LodBackend.OFF else lod_mode if lod_mode >= LodMode.MANUAL and lod_mode <= LodMode.CONTINUOUS else LodMode.CONTINUOUS
	result.lod_bias = maxf(lod_bias, 0.01) if is_finite(lod_bias) else 1.0
	var x := _finite_positive(lod_threshold_pixels.x, 16.0)
	var y := maxf(_finite_positive(lod_threshold_pixels.y, 32.0), x + 0.01)
	var z := maxf(_finite_positive(lod_threshold_pixels.z, 64.0), y + 0.01)
	var w := maxf(_finite_positive(lod_threshold_pixels.w, 128.0), z + 0.01)
	result.lod_threshold_pixels = Vector4(x, y, z, w)
	result.lod_hysteresis = clampf(lod_hysteresis, 0.0, 0.49) if is_finite(lod_hysteresis) else 0.15
	result.lod_transition_width = clampf(lod_transition_width, 0.01, 0.49) if is_finite(lod_transition_width) else 0.15
	result.lod_evaluation_budget = maxi(1, lod_evaluation_budget)
	return result


static func _finite_positive(value: float, fallback: float) -> float:
	return maxf(value, 0.01) if is_finite(value) else fallback

func _validate_property(property: Dictionary) -> void:
	var automatic := lod_backend != LodBackend.OFF and lod_mode != LodMode.MANUAL
	var visible := true
	match str(property.name):
		"lod_mode": visible = lod_backend != LodBackend.OFF
		"lod_bias", "lod_threshold_pixels", "lod_hysteresis", "lod_evaluation_budget": visible = automatic
		"lod_transition_width": visible = automatic and lod_mode == LodMode.CONTINUOUS
	if not visible: property.usage &= ~PROPERTY_USAGE_EDITOR

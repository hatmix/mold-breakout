class_name MoldStatistics
extends RefCounted

var active_mold_count: int
var batch_count: int
var cached_mesh_count: int
var mesh_cache_hits: int
var mesh_cache_misses: int
var immediate_command_count: int
var immediate_batch_count: int
var lod_minimal_count: int
var lod_low_count: int
var lod_medium_count: int
var lod_high_count: int
var lod_extreme_count: int
var lod_transition_count: int
var last_lod_rebind_count: int
var gpu_lod_source_count: int


func _init(active: int = 0, batches: int = 0, meshes: int = 0, hits: int = 0, misses: int = 0, immediate_commands: int = 0, immediate_batches: int = 0, lod_minimal: int = 0, lod_low: int = 0, lod_medium: int = 0, lod_high: int = 0, lod_extreme: int = 0, lod_transitions: int = 0, lod_rebinds: int = 0) -> void:
	active_mold_count = active
	batch_count = batches
	cached_mesh_count = meshes
	mesh_cache_hits = hits
	mesh_cache_misses = misses
	immediate_command_count = immediate_commands
	immediate_batch_count = immediate_batches
	lod_minimal_count = lod_minimal
	lod_low_count = lod_low
	lod_medium_count = lod_medium
	lod_high_count = lod_high
	lod_extreme_count = lod_extreme
	lod_transition_count = lod_transitions
	last_lod_rebind_count = lod_rebinds

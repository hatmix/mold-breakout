class_name MoldGpuPolylineRange
extends RefCounted

var start_index: int
var point_count: int
var closed: bool

func _init(start := 0, count := 0, is_closed := false) -> void:
	start_index = start
	point_count = count
	closed = is_closed

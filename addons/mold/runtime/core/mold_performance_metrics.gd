class_name MoldPerformanceMetrics
extends RefCounted
## Opt-in CPU metrics for the last renderer sync, not GPU execution time.
## Upload bytes are submitted instance/visibility payload, including padding.

var enabled := false
var render_sequence := 0
var render_cpu_milliseconds := 0.0
var lod_cpu_milliseconds := 0.0
var upload_cpu_milliseconds := 0.0
var upload_bytes := 0
var upload_calls := 0
var _collecting := false


func begin_render() -> int:
	_collecting = enabled
	if not _collecting: return 0
	render_cpu_milliseconds = 0.0
	lod_cpu_milliseconds = 0.0
	upload_cpu_milliseconds = 0.0
	upload_bytes = 0
	upload_calls = 0
	return Time.get_ticks_usec()


func end_lod(start: int) -> void:
	if _collecting: lod_cpu_milliseconds = (Time.get_ticks_usec() - start) / 1000.0


func begin_upload() -> int:
	return Time.get_ticks_usec() if _collecting else 0


func end_upload(start: int, bytes: int) -> void:
	if not _collecting: return
	upload_cpu_milliseconds += (Time.get_ticks_usec() - start) / 1000.0
	upload_bytes += bytes
	upload_calls += 1


func end_render(start: int) -> void:
	if not _collecting: return
	render_cpu_milliseconds = (Time.get_ticks_usec() - start) / 1000.0
	render_sequence += 1
	_collecting = false

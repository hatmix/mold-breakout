class_name MoldCurveSampling
extends RefCounted
var _subdivisions := 8
var _tolerance := 0.0
var _max_depth := 0
var _max_points := 1048576
var subdivisions: int:
	get: return _subdivisions
var tolerance: float:
	get: return _tolerance
var max_depth: int:
	get: return _max_depth
var max_points: int:
	get: return _max_points
var is_adaptive: bool:
	get: return _tolerance>0
static func fixed(steps := 8,max_samples := 1048576) -> MoldCurveSampling:
	if steps<1 or steps>65536 or max_samples<3: push_error("Invalid sampling limits."); return null
	var result := MoldCurveSampling.new(); result._subdivisions=steps; result._max_points=max_samples; return result
static func adaptive(error := 0.001,depth := 16,max_samples := 1048576) -> MoldCurveSampling:
	if not is_finite(error) or error<=0 or depth<1 or depth>24 or max_samples<3: push_error("Invalid adaptive limits."); return null
	var result := MoldCurveSampling.new(); result._tolerance=error; result._max_depth=depth; result._max_points=max_samples; return result
func equals(other: MoldCurveSampling) -> bool:
	return subdivisions==other.subdivisions and tolerance==other.tolerance and max_depth==other.max_depth and max_points==other.max_points

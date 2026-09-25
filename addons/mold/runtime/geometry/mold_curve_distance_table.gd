class_name MoldCurveDistanceTable
extends RefCounted
var _curve: MoldCurve
var _parameters := PackedFloat32Array()
var _distances := PackedFloat32Array()
var length: float:
	get: return _distances[-1]
func _init(curve: MoldCurve,samples: Array) -> void:
	_curve=curve
	var samples_count_1 := samples.size()
	for i in samples_count_1:
		_parameters.append(samples[i][1])
		_distances.append(0.0 if i==0 else _distances[-1]+samples[i][0].distance_to(samples[i-1][0]))
func parameter_at_distance(distance: float) -> float:
	if not is_finite(distance): push_error("Distance must be finite."); return 0
	if length<=0.00000001 or distance<=0: return 0
	if distance>=length: return 1
	var i := _distances.bsearch(distance)
	var f := (distance-_distances[i-1])/maxf(_distances[i]-_distances[i-1],0.000000000001)
	return lerpf(_parameters[i-1],_parameters[i],f)
func evaluate_at_distance(distance: float) -> Vector3:
	return _curve.evaluate(parameter_at_distance(distance))

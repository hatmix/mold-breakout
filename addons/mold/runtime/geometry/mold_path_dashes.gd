class_name MoldPathDashes
extends RefCounted

const MAX_RUNS := 65536

static func validate(dash: MoldDash, length: float, closed: bool) -> bool:
	if not dash.is_enabled: return true
	if dash.type == MoldDash.Type.CHEVRON or dash.modifier != 0:
		push_error("Path dashes support Normal and Rounded with zero modifier.")
		return false
	var data := resolve(dash, length, closed)
	if not is_finite(data.x) or data.x > MAX_RUNS - 2:
		push_error("Path dash pattern exceeds the 65,536 run budget.")
		return false
	return true

static func resolve(dash: MoldDash, length: float, closed: bool) -> Vector4:
	var data := dash.to_gpu_data(length)
	var phase := dash.offset-floorf(dash.offset)
	data.w=phase
	if dash.is_enabled and dash.mode == MoldDash.Mode.LENGTH and dash.snap == MoldDash.Snap.TILING:
		data.x=maxf(1,floorf(length/maxf(dash.dash_length+dash.spacing,0.00001)+0.5))
		data.w-=data.z*0.5
	if closed and dash.is_enabled:
		if dash.mode == MoldDash.Mode.FIXED_COUNT: data.x = dash.count
		elif dash.snap != MoldDash.Snap.OFF:
			data.x = maxf(1, floorf(length / (dash.dash_length + dash.spacing) + 0.5))
		if dash.mode == MoldDash.Mode.FIXED_COUNT or dash.snap != MoldDash.Snap.OFF:
			data.w = phase + (1.0 - data.z) * 0.5
	return data

static func split(path: MoldPolyline) -> Array:
	var result: Array = []
	var data := resolve(path._dash, path.length, path.closed)
	var length := path.length
	if length <= 0.00000001 or data.x <= 0: return result
	if data.z <= 0: return [{"path": path.with_dash(null), "origin": 0.0}]
	if data.z >= 1: return result
	var period := length / data.x
	var on := period * (1.0 - data.z)
	var phase := data.w - floorf(data.w)
	var intervals: Array[PackedFloat64Array] = []
	for k in range(-1, ceili(data.x) + 2):
		var start := (k - phase) * period
		var end := minf(length, start + on)
		start = maxf(0, start)
		if end - start > length * 0.0000000001: intervals.append(PackedFloat64Array([start, end]))
	if path.closed and intervals.size() > 1 and intervals[0][0] == 0 and intervals[-1][1] == length:
		var first := intervals[0]
		var last := intervals[-1]
		intervals.remove_at(intervals.size() - 1)
		intervals.remove_at(0)
		intervals.append(PackedFloat64Array([last[0], length + first[1]]))
	var points := path._render_points
	var segments := points.size() if path.closed else points.size() - 1
	var distances := PackedFloat64Array([0.0])
	for i in segments:
		distances.append(distances[-1] + points[i].position.distance_to(points[(i+1)%points.size()].position))
	var scale := length / maxf(distances[-1], 1e-30)
	for i in range(1, distances.size()): distances[i] *= scale
	for interval in intervals:
		var run: Array[MoldPolylinePoint] = [_at(path, distances, interval[0])]
		var first := distances.bsearch(interval[0], false)
		for i in range(first, distances.size()):
			if distances[i] >= interval[1]: break
			if distances[i] > interval[0]: run.append(points[i%points.size()])
		if interval[1] > length:
			for i in range(1, distances.size()):
				if length + distances[i] >= interval[1]: break
				run.append(points[i%points.size()])
		run.append(_at(path, distances, interval[1]))
		for i in range(run.size()-1, 0, -1):
			if run[i].position.distance_squared_to(run[i-1].position) <= 1e-20: run.remove_at(i)
		if run.size() < 2: continue
		var cap := MoldPolyline.Cap.ROUND if path._dash.type == MoldDash.Type.ROUNDED else path.cap
		var piece := MoldPolyline.new(run, path.thickness, false, path.join, cap, path.miter_limit, path.geometry, true)
		result.append({"path": piece, "origin": interval[0]})
	return result

static func _at(path: MoldPolyline, distances: PackedFloat64Array, distance: float) -> MoldPolylinePoint:
	var points := path._render_points
	if distance >= path.length and not path.closed: return points[-1]
	var local := distance - path.length if distance >= path.length else distance
	var index := distances.bsearch(local)
	if index < distances.size() and distances[index] == local: return points[index%points.size()]
	index = clampi(index - 1, 0, distances.size() - 2)
	var t := (local - distances[index]) / maxf(distances[index+1]-distances[index], 1e-30)
	var a := points[index]
	var b := points[(index+1)%points.size()]
	return MoldPolylinePoint.new(a.position.lerp(b.position,t),a.color.lerp(b.color,t),lerpf(a.thickness,b.thickness,t))

static func origin(value: float, start: float, end: float, total: float) -> float:
	return value - floorf((value + (start+end)*0.5) / total)*total

class_name MoldPolylineMeshGenerator
extends RefCounted

# Each segment side shares its inner miter with its neighbor. Only the outer
# wedge belongs to the join. CUSTOM1/2 carry analytic coordinates/extrusion deltas.
static func generate(data: MoldMeshCache.MeshBuffers, path: MoldPolyline) -> void:
	if not path._dash.is_enabled:
		_generate_solid(data, path)
		return
	for run in MoldPathDashes.split(path):
		_generate_solid(data, run.path, run.origin, path.length)
	if path.geometry == MoldPolyline.Geometry.BILLBOARD: data.billboard_bounds = path.bounds
	if data.vertices.is_empty():
		data.uses_extrusion = true
		data.add_vertex(Vector3.ZERO, Vector3.BACK, Vector2.ZERO)
		data.polyline_coordinates.append_array(PackedFloat32Array([0,0,0,0]))
		data.polyline_changes.append_array(PackedFloat32Array([0,0,0,0]))
		data.add_triangle(0, 0, 0)

static func _generate_solid(data: MoldMeshCache.MeshBuffers, path: MoldPolyline, origin := 0.0, full_length := 0.0) -> void:
	data.uses_extrusion = true
	if path.geometry == MoldPolyline.Geometry.BILLBOARD:
		_generate_billboard(data,path,origin,full_length)
		return
	var count := path._render_points.size()
	var segments := count if path.closed else count - 1
	var directions := PackedVector2Array()
	var normals := PackedVector2Array()
	var distances := PackedFloat32Array([0.0])
	for index in range(segments):
		var delta := path._render_points[(index + 1) % count].position - path._render_points[index].position
		var length := Vector2(delta.x, delta.y).length()
		var direction := Vector2(delta.x, delta.y) / maxf(length, 0.000000000001)
		directions.append(direction)
		normals.append(Vector2(-direction.y, direction.x))
		distances.append(distances[index] + length)
	var total := maxf(full_length if full_length > 0 else distances[segments], 0.00001)
	for index in range(segments):
		var next := (index + 1) % count
		var direction := directions[index]
		var normal := normals[index]
		var radius_a := path.thickness * path._render_points[index].thickness * 0.5
		var radius_b := path.thickness * path._render_points[next].thickness * 0.5
		var first := not path.closed and index == 0
		var last := not path.closed and index == segments - 1
		var a := path._render_points[index].position
		var b := path._render_points[next].position
		if path.cap == MoldPolyline.Cap.SQUARE:
			if first: a -= _v3(direction * radius_a)
			if last: b += _v3(direction * radius_b)
		var start_cap := first and path.cap != MoldPolyline.Cap.ROUND
		var end_cap := last and path.cap != MoldPolyline.Cap.ROUND
		var length := Vector2(b.x - a.x, b.y - a.y).dot(direction)
		var branch := MoldPathDashes.origin(origin, distances[index], distances[index+1], total)
		var start_progress := (branch + distances[index]) / total
		var end_progress := (branch + distances[index+1]) / total
		for side: int in [-1, 1]:
			var offset_a := _outline(path, index, index, side, directions, normals, distances)
			var offset_b := _outline(path, next, index, side, directions, normals, distances)
			var root := data.vertices.size()
			_add_segment_vertex(data, path._render_points[index], a, Vector2.ZERO, radius_a, direction, normal,
				start_progress, start_progress, end_progress, 1.0 / total,
				0.0, length, start_cap, end_cap, -direction * radius_a if start_cap else Vector2.ZERO)
			_add_segment_vertex(data, path._render_points[index], a, offset_a, radius_a, direction, normal,
				start_progress, start_progress, end_progress, 1.0 / total,
				0.0, length, start_cap, end_cap, -direction * radius_a if start_cap else Vector2.ZERO)
			_add_segment_vertex(data, path._render_points[next], b, offset_b, radius_b, direction, normal,
				end_progress, start_progress, end_progress, 1.0 / total,
				length, length, start_cap, end_cap, direction * radius_b if end_cap else Vector2.ZERO)
			_add_segment_vertex(data, path._render_points[next], b, Vector2.ZERO, radius_b, direction, normal,
				end_progress, start_progress, end_progress, 1.0 / total,
				length, length, start_cap, end_cap, direction * radius_b if end_cap else Vector2.ZERO)
			_triangle(data, root, root + 1, root + 2)
			_triangle(data, root, root + 2, root + 3)
	if path.join != MoldPolyline.Join.MITER:
		for index in range(0 if path.closed else 1, count if path.closed else count - 1):
			var previous := (index - 1 + segments) % segments
			var next := index % segments
			var cross := directions[previous].cross(directions[next])
			if absf(cross) < 0.00001: continue
			var side := -1.0 if cross > 0.0 else 1.0
			var from := normals[previous] * side
			var to := normals[next] * side
			var radius := path.thickness * path._render_points[index].thickness * 0.5
			var u := fposmod(origin + distances[index], total) / total
			var dash_normal := normals[next]
			if path.join == MoldPolyline.Join.ROUND:
				_add_arc(data, path._render_points[index], from, to, radius, u, cross > 0.0, dash_normal)
			else:
				var axis := (from + to).normalized()
				var height := maxf(axis.dot(from), 0.00001)
				var root := data.vertices.size()
				_add_join_vertex(data, path._render_points[index], Vector2.ZERO, radius, u, 1, axis / height, dash_normal)
				_add_join_vertex(data, path._render_points[index], from, radius, u, 1, axis / height, dash_normal)
				_add_join_vertex(data, path._render_points[index], to, radius, u, 1, axis / height, dash_normal)
				_triangle(data, root, root + 1, root + 2)
	if not path.closed and path.cap == MoldPolyline.Cap.ROUND:
		var last_progress := clampf((MoldPathDashes.origin(origin, distances[segments-1], distances[segments], total) + distances[segments]) / total, 0, 1)
		_add_arc(data, path._render_points[0], normals[0], -normals[0], path.thickness * path._render_points[0].thickness * 0.5, origin / total, true, normals[0])
		_add_arc(data, path._render_points[count - 1], -normals[segments - 1], normals[segments - 1], path.thickness * path._render_points[count - 1].thickness * 0.5, last_progress, true, normals[segments - 1])


static func _outline(path: MoldPolyline, point: int, segment: int, side: int,
		directions: PackedVector2Array, normals: PackedVector2Array, distances: PackedFloat32Array) -> Vector2:
	var radius := path.thickness * path._render_points[point].thickness * 0.5
	if not path.closed and (point == 0 or point == path._render_points.size() - 1):
		return normals[segment] * (side * radius)
	var previous := (point - 1 + directions.size()) % directions.size()
	var next := point % directions.size()
	var cross := directions[previous].cross(directions[next])
	if path.join != MoldPolyline.Join.MITER and cross * side < 0.0:
		return normals[segment] * (side * radius)
	var sum := normals[previous] + normals[next]
	var denominator := sum.dot(normals[next])
	if absf(denominator) < 0.00001: return normals[segment] * (side * radius)
	var offset := sum * (side * radius / denominator)
	var neighbor := minf(distances[previous + 1] - distances[previous], distances[next + 1] - distances[next])
	var limit := minf(radius * path.miter_limit, neighbor * 0.5 + radius)
	return offset.normalized() * limit if offset.length() > limit else offset


static func _add_segment_vertex(data: MoldMeshCache.MeshBuffers, point: MoldPolylinePoint,
		center: Vector3, offset: Vector2, radius: float, direction: Vector2, normal: Vector2,
		u: float, start_progress: float, end_progress: float, inverse_path_length: float,
		along: float, length: float, start_cap: bool, end_cap: bool, endpoint_extrusion: Vector2) -> void:
	var inverse_radius := 1.0 / maxf(radius, 0.00001)
	var extrusion := offset + endpoint_extrusion
	var x := along + offset.dot(direction)
	var y := offset.dot(normal) * inverse_radius
	var dash_progress := clampf(u + offset.dot(direction) * inverse_path_length,
		start_progress, end_progress)
	var coordinate := Vector4(normal.x, y, 1.0 - x * inverse_radius if start_cap else 0.0,
		1.0 - (length - x) * inverse_radius if end_cap else 0.0)
	var change := Vector4(normal.y, extrusion.dot(normal) * inverse_radius,
		-extrusion.dot(direction) * inverse_radius if start_cap else 0.0,
		extrusion.dot(direction) * inverse_radius if end_cap else 0.0)
	_add_vertex(data, center + _v3(offset), point.color, Vector2(dash_progress, 0.5 - y * 0.5), extrusion, radius, 0, coordinate, change)


static func _add_arc(data: MoldMeshCache.MeshBuffers, point: MoldPolylinePoint,
		from: Vector2, to: Vector2, radius: float, u: float, counter_clockwise: bool,
		dash_normal: Vector2) -> void:
	var start := atan2(from.y, from.x)
	var delta := wrapf(atan2(to.y, to.x) - start, -PI, PI)
	if counter_clockwise and delta < 0.0: delta += TAU
	if not counter_clockwise and delta > 0.0: delta -= TAU
	var steps := maxi(1, ceili(absf(delta) / (PI * 0.5) - 0.00001))
	# Circumscribed wedges contain the analytic circle at every detail level.
	for index in range(steps):
		var a := start + delta * index / steps
		var b := start + delta * (index + 1) / steps
		var first := from if index == 0 else Vector2(cos(a), sin(a))
		var last := to if index == steps - 1 else Vector2(cos(b), sin(b))
		var mid := (a + b) * 0.5
		var corner := Vector2(cos(mid), sin(mid)) / cos((b - a) * 0.5)
		var root := data.vertices.size()
		_add_join_vertex(data, point, Vector2.ZERO, radius, u, 2, Vector2.ZERO, dash_normal)
		_add_join_vertex(data, point, first, radius, u, 2, Vector2.ZERO, dash_normal)
		_add_join_vertex(data, point, corner, radius, u, 2, Vector2.ZERO, dash_normal)
		_add_join_vertex(data, point, last, radius, u, 2, Vector2.ZERO, dash_normal)
		_triangle(data, root, root + 1, root + 2)
		_triangle(data, root, root + 2, root + 3)


static func _add_join_vertex(data: MoldMeshCache.MeshBuffers, point: MoldPolylinePoint,
		normalized_offset: Vector2, radius: float, u: float, kind: int, bevel_axis: Vector2,
		dash_normal: Vector2) -> void:
	var offset := normalized_offset * radius
	var edge := normalized_offset if kind == 2 else Vector2(0.0, normalized_offset.dot(bevel_axis))
	var coordinate := Vector4(edge.x, edge.y, 0.0, 0.0)
	var dash_across := normalized_offset.normalized().dot(dash_normal) \
		if normalized_offset.length_squared() > 0.0000000001 else 0.0
	_add_vertex(data, point.position + _v3(offset), point.color,
		Vector2(u, clampf(0.5 - dash_across * 0.5, 0.0, 1.0)), offset, radius, kind, coordinate, coordinate)


static func _add_vertex(data: MoldMeshCache.MeshBuffers, position: Vector3, color: Color, uv: Vector2,
		extrusion: Vector2, radius: float, kind: int, coordinate: Vector4, change: Vector4) -> void:
	data.add_vertex(position, Vector3.BACK, uv, color, Vector4(extrusion.x, extrusion.y, kind, radius))
	data.polyline_coordinates.append(coordinate.x); data.polyline_coordinates.append(coordinate.y)
	data.polyline_coordinates.append(coordinate.z); data.polyline_coordinates.append(coordinate.w)
	data.polyline_changes.append(change.x); data.polyline_changes.append(change.y)
	data.polyline_changes.append(change.z); data.polyline_changes.append(change.w)


static func _v3(value: Vector2) -> Vector3:
	return Vector3(value.x, value.y, 0.0)


static func _triangle(data: MoldMeshCache.MeshBuffers, a: int, b: int, c: int) -> void:
	var cross := (data.vertices[b] - data.vertices[a]).cross(data.vertices[c] - data.vertices[a]).z
	if absf(cross) < 0.000000000001: return
	if cross < 0.0: data.add_triangle(a, b, c)
	else: data.add_triangle(a, c, b)

static func _generate_billboard(data, path: MoldPolyline, origin: float, full_length: float) -> void:
	var points := path._render_points
	var count := points.size()
	var segments := count if path.closed else count-1
	var distance := 0.0
	var total := maxf(full_length if full_length > 0 else path.length, 0.00001)
	data.billboard_bounds = path.bounds
	for i in segments:
		var j := (i+1)%count
		var a := points[i]; var b := points[j]
		var previous := points[(count-1 if path.closed else i) if i==0 else i-1]
		var next := points[(0 if path.closed else j) if j==count-1 else j+1]
		var end := distance+a.position.distance_to(b.position)
		var branch := MoldPathDashes.origin(origin, distance, end, total)
		var flags := 0 if path.closed else (1 if i==0 else 0)+(2 if i==segments-1 else 0)
		for id in 36:
			var corner := id%6
			if id>=6 and id<12:
				if corner%3==1: corner+=1
				elif corner%3==2: corner-=1
			var start: bool = [0,1,2,0,2,3][corner]<2 if id<12 else id<24
			var p := a if start else b
			# Keep CUSTOM3 free for float RGBA: VERTEX holds the previous point,
			# CUSTOM0.xyz the next point, and UV.x packs config * 64 + vertex ID.
			data.add_vertex(previous.position,Vector3.BACK,Vector2(id+64*(128+flags+path.join*4+path.cap*16),branch+distance),p.color,Vector4(next.position.x,next.position.y,next.position.z,a.thickness*path.thickness))
			data.polyline_coordinates.append_array(PackedFloat32Array([a.position.x,a.position.y,a.position.z,b.thickness*path.thickness]))
			data.polyline_changes.append_array(PackedFloat32Array([b.position.x,b.position.y,b.position.z,path.miter_limit]))
			data.billboard_metrics.append(Vector2(branch+end,total))
			data.indices.append(data.vertices.size()-1)
		distance=end

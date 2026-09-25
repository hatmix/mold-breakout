@tool
extends RefCounted
## Collision geometry used by gizmo picking and selection outlines.
## It does not handle editor input or Canvas UI coverage.

static func preview_faces(preview: MeshInstance3D, capsule_offset := 0.0, deformation:=Vector4.ZERO) -> PackedVector3Array:
	if not preview or not preview.mesh or not preview.visible: return PackedVector3Array()
	if deformation.x>2.5:return _rounded_preview_faces(preview,deformation)
	var faces := preview.mesh.get_faces()
	for i in faces.size():
		var point := faces[i]
		point.y += signf(point.y) * capsule_offset
		faces[i] = preview.transform * point
	return faces


static func radial_faces(inner: float, outer: float, start: float, span: float) -> PackedVector3Array:
	var faces := PackedVector3Array()
	# C# angles arrive as float32. Do not turn a full turn into 65 segments
	# merely because its float representation is slightly greater than TAU.
	var steps := maxi(1, ceili(64.0 * span / TAU - 0.00001))
	for i in steps:
		var a := start + span * i / steps
		var b := start + span * (i + 1) / steps
		var first := Vector3(sin(a), cos(a), 0)
		var last := Vector3(sin(b), cos(b), 0)
		faces.append_array(PackedVector3Array([first * inner, first * outer, last * outer]))
		if inner > 0.0:
			faces.append_array(PackedVector3Array([first * inner, last * outer, last * inner]))
	return faces


static func bounds_lines(bounds: AABB) -> PackedVector3Array:
	var minimum := bounds.position
	var maximum := bounds.end
	var points := [
		Vector3(minimum.x, minimum.y, minimum.z), Vector3(maximum.x, minimum.y, minimum.z),
		Vector3(maximum.x, maximum.y, minimum.z), Vector3(minimum.x, maximum.y, minimum.z),
		Vector3(minimum.x, minimum.y, maximum.z), Vector3(maximum.x, minimum.y, maximum.z),
		Vector3(maximum.x, maximum.y, maximum.z), Vector3(minimum.x, maximum.y, maximum.z),
	]
	var edges := [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
	var result := PackedVector3Array()
	for index in edges: result.append(points[index])
	return result

# Planar shaders clip their support quad. Build a radial strip between the
# actual outer/inner contours, so interiors work without filling rim holes.
# Distances follow mold_evaluation.gdshaderinc; selection ignores dash grain.
static var _planar_cache: Dictionary={}

static func planar_faces(shape: Vector4, local: Transform3D, start: float, span: float) -> PackedVector3Array:
	if span<=.00001:return PackedVector3Array()
	var key:=str([shape,local,start,span])
	if _planar_cache.has(key):return _planar_cache[key].duplicate()
	var angles: Array[float]=[0.0,span]
	var steps:=maxi(1,ceili(128.0*span/TAU-.00001))
	for i in range(1,steps):angles.append(span*i/steps)
	# Preserve sharp corners exactly instead of cutting them off with a chord.
	var corners:=4 if shape.x<4.5 else maxi(3,int(shape.y)) if shape.x>6.5 and shape.x<10.5 else 0
	for i in corners:
		var angle:=PI/4+i*TAU/4 if shape.x<4.5 else PI-PI/corners-i*TAU/corners
		var progress:=fposmod(angle-start,TAU)
		if progress>0 and progress<span:angles.append(progress)
	angles.sort()
	var faces:=PackedVector3Array()
	var previous_outer:=Vector3.ZERO
	var previous_inner:=Vector3.ZERO
	var rim:=int(shape.x) in [3,4,6,9,10,11]
	for i in angles.size():
		var angle:=start+angles[i]
		var direction:=Vector2(sin(angle),cos(angle))
		if shape.x>10.5:
			var radii:=Vector2(shape.y,shape.z)
			direction=(direction*radii/(radii+Vector2.ONE*shape.w)).normalized()
		var outer:=_contour_radius(direction,shape,false)
		var inner:=minf(outer,_contour_radius(direction,shape,true)) if rim else 0.0
		var out_vertex:=local*Vector3(direction.x*outer*.5,direction.y*outer*.5,0)
		var in_vertex:=local*Vector3(direction.x*inner*.5,direction.y*inner*.5,0)
		if i>0:
			faces.append_array(PackedVector3Array([previous_inner,previous_outer,out_vertex]))
			if rim:faces.append_array(PackedVector3Array([previous_inner,out_vertex,in_vertex]))
		previous_outer=out_vertex;previous_inner=in_vertex
	if _planar_cache.size()>=128:_planar_cache.erase(_planar_cache.keys()[0])
	_planar_cache[key]=faces
	return faces.duplicate()

static func _contour_radius(direction: Vector2, shape: Vector4, inner: bool) -> float:
	if _contour_distance(Vector2.ZERO,shape,inner)>=0:return 0.0
	var lo:=0.0
	var hi:=2.0
	for i in 24:
		var mid:=(lo+hi)*.5
		if _contour_distance(direction*mid,shape,inner)<=0:lo=mid
		else:hi=mid
	return (lo+hi)*.5

static func _rounded_box(p: Vector2, extent: Vector2, radius: float) -> float:
	var q:=p.abs()-(extent-Vector2.ONE*radius)
	return q.max(Vector2.ZERO).length()+minf(maxf(q.x,q.y),0)-radius

static func _polygon_distance(p: Vector2, sides: float, roundness: float) -> float:
	var count:=maxf(3,floorf(sides))
	var sector:=TAU/count
	var half:=sector*.5
	if roundness<=.00001:
		var angle:=atan2(p.x,-p.y)
		return cos(floorf(.5+angle/sector)*sector-angle)*p.length()/cos(half)-1.0
	var diagonal:=1.0/cos(half)
	var chamfer:=maxf(clampf(roundness,0,1)*half,.00001)
	var remaining:=half-chamfer
	var center:=Vector2(cos(half),sin(half))*tan(remaining)/tan(half)*diagonal
	var a:=center.length()
	var b:=1.0-center.x
	p*=diagonal
	var angle:=absf(fposmod(atan2(p.y,p.x)+PI*2.5+half,sector)-half)
	var ratio:=1.0-(angle-remaining)/chamfer
	var distance:=sqrt(maxf(0,a*a+b*b-2*a*b*cos(PI-half*ratio)))
	return p.length()/maxf(distance,.00001)-1.0 if half-angle<chamfer else cos(angle)*p.length()-1.0

static func _contour_distance(p: Vector2, shape: Vector4, inner: bool) -> float:
	var kind:=int(shape.x)
	if kind==5: return p.length()-1.0
	if kind==6: return p.length()-(maxf(1.0-shape.z,0.0) if inner else 1.0)
	if kind==11:
		var radii:=Vector2(shape.y,shape.z)
		return MoldEllipseGeometry.nearest(p*(radii+Vector2.ONE*shape.w),radii).x+(shape.w if inner else -shape.w)
	if kind<=4:
		var radius:=shape.z if kind==2 else shape.w if kind==4 else 0.0
		if shape.y<0:
			var aspect:=maxf(-shape.y,.00001)
			var extent:=Vector2(aspect,1) if aspect>=1 else Vector2(1,1/aspect)
			return _rounded_box(p*extent,extent,radius)+(shape.z*2 if inner else 0.0)
		if inner:
			var extent:=(Vector2.ONE-Vector2(shape.y,shape.z).clamp(Vector2.ONE*.00001,Vector2.ONE*.5)*2).max(Vector2.ONE*.00001)
			return _rounded_box(p/extent,Vector2.ONE,clampf(radius/minf(extent.x,extent.y),0,1))
		return _rounded_box(p,Vector2.ONE,radius)
	var scale:=maxf(1.0-shape.z,.00001) if inner else 1.0
	var roundness:=shape.z if kind==8 else shape.w if kind==10 else 0.0
	return _polygon_distance(p/scale,shape.y,clampf(roundness/scale,0,1))

static func torus_faces(radius: float, thickness: float, start: float, span: float, capped: bool) -> PackedVector3Array:
	if radius<=0 or thickness<=0 or span<=0:return PackedVector3Array()
	var faces:=PackedVector3Array()
	var steps:=maxi(1,ceili(64.0*span/TAU-.00001))
	var tube:=thickness*.5
	for i in steps:
		var a:=start+span*i/steps
		var b:=start+span*(i+1)/steps
		for j in 16:
			var u:=TAU*j/16
			var v:=TAU*(j+1)/16
			var p:=_torus_point(radius,tube,a,u)
			var q:=_torus_point(radius,tube,b,u)
			var r:=_torus_point(radius,tube,b,v)
			var s:=_torus_point(radius,tube,a,v)
			faces.append_array(PackedVector3Array([p,q,r,p,r,s]))
	if capped and span<TAU-.00001:
		for angle in [start,start+span]:
			var center:=Vector3(cos(angle)*radius,0,sin(angle)*radius)
			for j in 16:
				faces.append_array(PackedVector3Array([center,_torus_point(radius,tube,angle,TAU*j/16),_torus_point(radius,tube,angle,TAU*(j+1)/16)]))
	return faces

static func _torus_point(radius: float, tube: float, angle: float, cross_angle: float) -> Vector3:
	var distance:=radius+tube*cos(cross_angle)
	return Vector3(cos(angle)*distance,tube*sin(cross_angle),sin(angle)*distance)

# Match vertex deformation from mold_rounded_primitive.gdshaderinc. The
# support mesh is a template, not the actual rounded collision surface.
static func _rounded_preview_faces(preview: MeshInstance3D, shape: Vector4) -> PackedVector3Array:
	var key:=str(["rounded",preview.mesh.get_rid(),preview.transform,shape])
	if _planar_cache.has(key):return _planar_cache[key].duplicate()
	var faces:=PackedVector3Array()
	for surface in preview.mesh.get_surface_count():
		var arrays:=preview.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var data=arrays[Mesh.ARRAY_CUSTOM0]
		for i in vertices.size():
			var direction:=Vector3.ZERO
			if data is PackedFloat32Array:direction=Vector3(data[i*4],data[i*4+1],data[i*4+2])
			elif data is PackedByteArray:direction=Vector3(data.decode_float(i*16),data.decode_float(i*16+4),data.decode_float(i*16+8))
			else:direction=arrays[Mesh.ARRAY_NORMAL][i]
			var vertex:=vertices[i]
			if shape.x>3.5:
				var aspect:=maxf(shape.z,1e-20)
				var apothem:=.5*shape.w
				var height:=apothem/(Vector2(aspect,apothem).length()+apothem)
				var support:=vertex*2-direction*.5
				var normal:=(direction/Vector3(1,aspect,1)).normalized()
				vertex=support.lerp(Vector3(0,-.5+height,0),shape.y)+normal*Vector3(aspect*height,height,aspect*height)*shape.y
			else:
				var radii:=Vector3(shape.y,shape.z,shape.w)
				vertex=(vertex-direction*.25)*(Vector3.ONE*2-radii*4)+direction*radii
			vertices[i]=preview.transform*vertex
		if indices.is_empty():faces.append_array(vertices)
		else:
			for index in indices:faces.append(vertices[index])
	if _planar_cache.size()>=128:_planar_cache.erase(_planar_cache.keys()[0])
	_planar_cache[key]=faces
	return faces.duplicate()

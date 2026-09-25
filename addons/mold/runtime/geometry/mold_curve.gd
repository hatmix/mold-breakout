class_name MoldCurve
extends RefCounted
## Immutable mathematical path. t is normalized parameter, not distance.
enum Parameterization { UNIFORM, CENTRIPETAL, CHORDAL }
var _spans: Array = []
var _closed := false
var _kind := ""
var _controls := PackedVector3Array()
var _bezier_knots: Array[MoldBezierKnot] = []
var _in_derivatives := PackedVector3Array()
var _out_derivatives := PackedVector3Array()
var _weights := PackedFloat32Array()
var _knots := PackedFloat32Array()
var _degree := 3
var _parameterization := Parameterization.CENTRIPETAL
var _bakes: Array = []
var closed: bool:
	get: return _closed
var span_count: int:
	get: return _spans.size()
var controls: PackedVector3Array:
	get: return _controls.duplicate()
var weights: PackedFloat32Array:
	get: return _weights.duplicate()
var knot_vector: PackedFloat32Array:
	get: return _knots.duplicate()
var incoming_derivatives: PackedVector3Array:
	get: return _in_derivatives.duplicate()
var outgoing_derivatives: PackedVector3Array:
	get: return _out_derivatives.duplicate()
var degree: int:
	get: return _degree

static func _error(message: String) -> MoldCurve:
	push_error(message)
	return null

static func _h(p: Vector3, weight := 1.0) -> Vector4:
	return Vector4(p.x*weight,p.y*weight,p.z*weight,weight)
static func _project(p: Vector4) -> Vector3:
	return Vector3(p.x,p.y,p.z)/p.w
static func _span(c: PackedVector4Array, a: float, b: float) -> Dictionary:
	return {"controls":c,"start":a,"end":b}
static func _cubic(a: Vector3,b: Vector3,c: Vector3,d: Vector3,start: float,end: float) -> Dictionary:
	return _span(PackedVector4Array([_h(a),_h(b),_h(c),_h(d)]),start,end)
static func _finite(points: PackedVector3Array) -> bool:
	for p in points:
		if not p.is_finite(): return false
	return true

static func bezier(knots: Array[MoldBezierKnot], is_closed := false) -> MoldCurve:
	if knots.size()<2: return _error("A Bezier curve requires two anchors.")
	var curve := MoldCurve.new()
	curve._kind="bezier"; curve._closed=is_closed
	for k in knots:
		if not k or not k.position.is_finite() or not k.in_offset.is_finite() or not k.out_offset.is_finite(): return _error("Bezier controls must be finite.")
		curve._bezier_knots.append(MoldBezierKnot.new(k.position,k.in_offset,k.out_offset))
	var count := knots.size() if is_closed else knots.size()-1
	for i in count:
		var a := knots[i]; var b := knots[(i+1)%knots.size()]
		curve._spans.append(_cubic(a.position,a.position+a.out_offset,b.position+b.in_offset,b.position,float(i)/count,float(i+1)/count))
	return curve

static func linear(points: PackedVector3Array,is_closed := false) -> MoldCurve:
	if points.size()<2 or not _finite(points): return _error("Linear controls require two finite points.")
	var knots: Array[MoldBezierKnot] = []
	var points_count_1 := points.size()
	for i in points_count_1:
		var before := points[i-1] if i>0 else (points[-1] if is_closed else points[i])
		var after := points[i+1] if i+1<points.size() else (points[0] if is_closed else points[i])
		knots.append(MoldBezierKnot.new(points[i],(before-points[i])/3.0,(after-points[i])/3.0))
	return bezier(knots,is_closed)

static func quadratic_bezier(points: PackedVector3Array,is_closed := false) -> MoldCurve:
	if points.size()<3 or points.size()%2==0 or not _finite(points): return _error("Quadratic controls are anchor, control, anchor...")
	if is_closed and points[0].distance_to(points[-1])>0.000001: return _error("Closed quadratic endpoints must meet.")
	var curve := MoldCurve.new(); curve._kind="quadratic"; curve._closed=is_closed; curve._controls=points.duplicate()
	var count := (points.size()-1)/2
	for i in count:
		curve._spans.append(_span(PackedVector4Array([_h(points[i*2]),_h(points[i*2+1]),_h(points[i*2+2])]),float(i)/count,float(i+1)/count))
	return curve

static func hermite(points: PackedVector3Array,incoming: PackedVector3Array,outgoing: PackedVector3Array,is_closed := false) -> MoldCurve:
	if points.size()<2 or points.size()!=incoming.size() or points.size()!=outgoing.size() or not _finite(points) or not _finite(incoming) or not _finite(outgoing): return _error("Hermite positions and derivatives must be finite and have equal counts.")
	var curve := MoldCurve.new(); curve._kind="hermite"; curve._closed=is_closed
	curve._controls=points.duplicate(); curve._in_derivatives=incoming.duplicate(); curve._out_derivatives=outgoing.duplicate()
	var count := points.size() if is_closed else points.size()-1
	for i in count:
		var j := (i+1)%points.size()
		curve._spans.append(_cubic(points[i],points[i]+outgoing[i]/3,points[j]-incoming[j]/3,points[j],float(i)/count,float(i+1)/count))
	return curve

static func catmull_rom(points: PackedVector3Array,is_closed := false,parameterization := Parameterization.CENTRIPETAL) -> MoldCurve:
	if points.size()<2 or not _finite(points) or parameterization not in [0,1,2]: return _error("Invalid Catmull-Rom controls.")
	var curve := MoldCurve.new(); curve._kind="catmull"; curve._closed=is_closed; curve._controls=points.duplicate(); curve._parameterization=parameterization
	var count := points.size() if is_closed else points.size()-1
	for i in count:
		var a := points[i]; var b := points[(i+1)%points.size()]
		var before := points[i-1] if i>0 else (points[-1] if is_closed else 2*a-b)
		var after := points[i+2] if i+2<points.size() else (points[(i+2)%points.size()] if is_closed else 2*b-a)
		var d0 := before.distance_to(a); var d1 := a.distance_to(b); var d2 := b.distance_to(after)
		if minf(d0,minf(d1,d2))<=0.000001: return _error("Adjacent Catmull-Rom anchors must be distinct.")
		curve._spans.append({"controls":_catmull_controls(before,a,b,after,parameterization),"start":float(i)/count,"end":float(i+1)/count})
	return curve

static func _catmull_controls(before: Vector3,a: Vector3,b: Vector3,after: Vector3,parameterization: int,controls := PackedVector4Array()) -> PackedVector4Array:
	var d0 := before.distance_to(a); var d1 := a.distance_to(b); var d2 := b.distance_to(after)
	if parameterization==Parameterization.UNIFORM: d0=1; d1=1; d2=1
	elif parameterization==Parameterization.CENTRIPETAL: d0=sqrt(d0); d1=sqrt(d1); d2=sqrt(d2)
	var m1 := d1*((a-before)/d0-(b-before)/(d0+d1)+(b-a)/d1)
	var m2 := d1*((b-a)/d1-(after-a)/(d1+d2)+(after-b)/d2)
	controls.resize(4)
	controls[0]=_h(a);controls[1]=_h(a+m1/3);controls[2]=_h(b-m2/3);controls[3]=_h(b)
	return controls

static func _default_knots(count: int, spline_degree: int, periodic: bool) -> PackedFloat32Array:
	var n := count+(spline_degree if periodic else 0)
	var result := PackedFloat32Array(); result.resize(n+spline_degree+1)
	var result_count_2 := result.size()
	for i in result_count_2: result[i]=float(i) if periodic else (0.0 if i<=spline_degree else (1.0 if i>=n else float(i-spline_degree)/(n-spline_degree)))
	return result

static func bspline(points: PackedVector3Array,spline_degree := 3,knots := PackedFloat32Array(),periodic := false) -> MoldCurve:
	var w := PackedFloat32Array(); w.resize(points.size()); w.fill(1)
	var result := nurbs(points,w,spline_degree,knots,periodic)
	if result: result._kind="bspline"
	return result

static func nurbs(points: PackedVector3Array,point_weights: PackedFloat32Array,spline_degree := 3,knots := PackedFloat32Array(),periodic := false) -> MoldCurve:
	if spline_degree<1 or spline_degree>32 or points.size()<=spline_degree or points.size()!=point_weights.size() or not _finite(points): return _error("Spline degree must be 1..32 with more controls than degree.")
	if periodic and not knots.is_empty(): return _error("Periodic splines generate their knot vector.")
	for w in point_weights:
		if not is_finite(w) or w<=0: return _error("NURBS weights must be positive and finite.")
	var curve := MoldCurve.new(); curve._kind="nurbs"; curve._closed=periodic; curve._degree=spline_degree; curve._controls=points.duplicate(); curve._weights=point_weights.duplicate()
	var k := knots.duplicate() if not knots.is_empty() else _default_knots(points.size(),spline_degree,periodic)
	curve._knots=k.duplicate()
	var p := PackedVector4Array()
	var points_count_3 := points.size()
	for i in points_count_3+(spline_degree if periodic else 0): p.append(_h(points[i%points_count_3],point_weights[i%points_count_3]))
	if k.size()!=p.size()+spline_degree+1: return _error("Knot count must equal control count + degree + 1.")
	var k_count_4 := k.size()
	for i in k_count_4:
		if not is_finite(k[i]) or (i>0 and k[i]<k[i-1]): return _error("Knots must be finite and nondecreasing.")
	var a := k[spline_degree]; var b := k[p.size()]
	if b<=a: return _error("Spline domain must have positive width.")
	var boundaries := PackedFloat32Array()
	for v in k:
		if v>=a and v<=b and (boundaries.is_empty() or v!=boundaries[-1]): boundaries.append(v)
	for v in boundaries:
		var multiplicity := k.count(v)
		if v>a and v<b and multiplicity>spline_degree: return _error("Discontinuous interior knots are unsupported.")
		while multiplicity<spline_degree:
			var inserted := _insert(p,k,spline_degree,v); p=inserted[0]; k=inserted[1]; multiplicity+=1
	var p_count_5 := p.size()
	for i in range(spline_degree,p_count_5):
		if k[i]>=a and k[i+1]<=b and k[i+1]>k[i]: curve._spans.append(_span(p.slice(i-spline_degree,i+1),(k[i]-a)/(b-a),(k[i+1]-a)/(b-a)))
	return curve

static func _insert(p: PackedVector4Array,knots: PackedFloat32Array,d: int,u: float) -> Array:
	var n := p.size()-1; var k := d
	var knots_count_6 := knots.size()
	while k+1<knots_count_6 and knots[k+1]<=u: k+=1
	k=mini(k,n+1)
	var s := knots.count(u); var q := PackedVector4Array(); q.resize(p.size()+1)
	for i in k-d+1: q[i]=p[i]
	for i in range(k-s,n+1): q[i+1]=p[i]
	for i in range(k-d+1,k-s+1):
		var alpha := (u-knots[i])/(knots[i+d]-knots[i]); q[i]=p[i-1]*(1-alpha)+p[i]*alpha
	var result_knots := knots.duplicate(); result_knots.insert(k+1,u)
	return [q,result_knots]

func with_control(index: int,point: Vector3) -> MoldCurve:
	if index<0 or index>=_controls.size(): return _error("Control index out of range.")
	var c := _controls.duplicate(); c[index]=point
	match _kind:
		"quadratic": return quadratic_bezier(c,closed)
		"hermite": return hermite(c,_in_derivatives,_out_derivatives,closed)
		"catmull": return catmull_rom(c,closed,_parameterization)
		"bspline": return bspline(c,_degree,PackedFloat32Array() if closed else _knots,closed)
		"nurbs": return nurbs(c,_weights,_degree,PackedFloat32Array() if closed else _knots,closed)
	return _error("Use with_knot for Bezier curves.")
func with_derivatives(index: int,incoming: Vector3,outgoing: Vector3) -> MoldCurve:
	if _kind!="hermite" or index<0 or index>=_controls.size(): return _error("Invalid Hermite control index.")
	var a := _in_derivatives.duplicate();var b := _out_derivatives.duplicate()
	a[index]=incoming;b[index]=outgoing
	return hermite(_controls,a,b,closed)
func with_weight(index: int,weight: float) -> MoldCurve:
	if _kind!="nurbs" or index<0 or index>=_weights.size(): return _error("Invalid weight index.")
	var w := _weights.duplicate(); w[index]=weight
	return nurbs(_controls,w,_degree,PackedFloat32Array() if closed else _knots,closed)
func get_bezier_knots() -> Array[MoldBezierKnot]:
	var result: Array[MoldBezierKnot]=[]
	for k in _bezier_knots: result.append(MoldBezierKnot.new(k.position,k.in_offset,k.out_offset))
	return result
func with_knot(index: int,knot: MoldBezierKnot) -> MoldCurve:
	if _kind!="bezier" or index<0 or index>=_bezier_knots.size(): return _error("Invalid Bezier knot index.")
	var k := get_bezier_knots(); k[index]=knot
	return bezier(k,closed)
func insert_knot(parameter: float) -> MoldCurve:
	if closed or _kind not in ["bspline","nurbs"] or not is_finite(parameter) or parameter<=0 or parameter>=1: return _error("Knot insertion requires an open spline and an interior parameter.")
	var p := PackedVector4Array()
	var controls_count_7 := _controls.size()
	for i in controls_count_7: p.append(_h(_controls[i],_weights[i]))
	var u := _knots[_degree]+parameter*(_knots[_controls.size()]-_knots[_degree])
	if _knots.count(u)>=_degree: return _error("Maximum knot multiplicity reached.")
	var inserted := _insert(p,_knots,_degree,u)
	var c := PackedVector3Array(); var w := PackedFloat32Array()
	for v: Vector4 in inserted[0]: c.append(_project(v)); w.append(v.w)
	return nurbs(c,w,_degree,inserted[1]) if _kind=="nurbs" else bspline(c,_degree,inserted[1])
func insert_bezier_knot(span_index: int,u := 0.5) -> MoldCurve:
	if _kind!="bezier" or span_index<0 or span_index>=span_count or u<=0 or u>=1 or not is_finite(u): return _error("Invalid Bezier split.")
	var halves := _split(_spans[span_index].controls,u)
	var l: PackedVector4Array=halves[0]; var r: PackedVector4Array=halves[1]
	var k := get_bezier_knots(); var next := (span_index+1)%k.size()
	k[span_index]=k[span_index].with_out_offset(_project(l[1])-k[span_index].position)
	k[next]=k[next].with_in_offset(_project(r[2])-k[next].position)
	var point := _project(l[-1]); k.insert(span_index+1,MoldBezierKnot.new(point,_project(l[-2])-point,_project(r[1])-point))
	return bezier(k,closed)

# Accumulate Bernstein coefficients from the nearer endpoint. Degree is capped at
# 32, so the initial coefficient stays representable. No scratch array is needed.
static func _evaluate_homogeneous(source: PackedVector4Array,t: float,derivative := false) -> Vector4:
	var degree := source.size()-1
	var s := 1.0-t
	if degree==1:
		return source[1]-source[0] if derivative else source[0]*s+source[1]*t
	if degree==2:
		if derivative: return ((source[1]-source[0])*s+(source[2]-source[1])*t)*2
		return source[0]*(s*s)+source[1]*(2*s*t)+source[2]*(t*t)
	if degree==3:
		var s2 := s*s;var t2 := t*t
		if derivative: return ((source[1]-source[0])*s2+(source[2]-source[1])*(2*s*t)+(source[3]-source[2])*t2)*3
		return source[0]*(s2*s)+source[1]*(3*s2*t)+source[2]*(3*s*t2)+source[3]*(t2*t)
	var terms := degree-1 if derivative else degree
	var reverse := t>0.5
	var u := 1.0-t if reverse else t
	var ratio := u/(1.0-u)
	var coefficient := pow(1.0-u,terms)
	var result := Vector4.ZERO
	var count := terms+1
	for j in count:
		var i := terms-j if reverse else j
		var control := (source[i+1]-source[i])*degree if derivative else source[i]
		result+=control*coefficient
		coefficient*=ratio*float(terms-j)/float(j+1)
	return result
static func _split(source: PackedVector4Array,t: float) -> Array:
	var n := source.size(); var c := source.duplicate(); var l := PackedVector4Array(); var r := PackedVector4Array(); l.resize(n); r.resize(n)
	l[0]=c[0]; r[n-1]=c[n-1]
	for k in range(1,n):
		for i in n-k: c[i]=c[i]*(1-t)+c[i+1]*t
		l[k]=c[0]; r[n-k-1]=c[n-k-1]
	return [l,r]
func _find_span(t: float,incoming: bool) -> Dictionary:
	for i in span_count-1:
		if t<_spans[i].end or (incoming and t==_spans[i].end): return _spans[i]
	return _spans[-1]
func evaluate(t: float) -> Vector3:
	if not is_finite(t): push_error("Parameter must be finite."); return Vector3.ZERO
	t=clampf(t,0,1); var s := _find_span(t,false)
	return _project(_evaluate_homogeneous(s.controls,(t-s.start)/(s.end-s.start)))
func evaluate_span(index: int,u: float) -> Vector3:
	if index<0 or index>=span_count or not is_finite(u): push_error("Invalid span or parameter."); return Vector3.ZERO
	return _project(_evaluate_homogeneous(_spans[index].controls,clampf(u,0,1)))
func evaluate_derivative(t: float,incoming := false) -> Vector3:
	if not is_finite(t): push_error("Parameter must be finite."); return Vector3.ZERO
	t=clampf(t,0,1); var s := _find_span(t,incoming); var c: PackedVector4Array=s.controls
	var u: float=(t-s.start)/(s.end-s.start); var h := _evaluate_homogeneous(c,u)
	var d := _evaluate_homogeneous(c,u,true)
	return (Vector3(d.x,d.y,d.z)-_project(h)*d.w)/h.w/(s.end-s.start)
func evaluate_tangent(t: float,incoming := false) -> Vector3:
	return evaluate_derivative(t,incoming).normalized()

static func _flatness(c: PackedVector4Array) -> float:
	var a := _project(c[0]); var b := _project(c[-1]); var chord := a.distance_to(b); var polygon := 0.0; var error := 0.0
	var c_count_8 := c.size()
	for i in range(1,c_count_8):
		var p := _project(c[i]); polygon+=p.distance_to(_project(c[i-1]))
		var u := clampf((p-a).dot(b-a)/(chord*chord),0,1) if chord>0.00000001 else 0.0
		error=maxf(error,(p-a-(b-a)*u).length())
	return maxf(error,polygon-chord)
static func _parameter_error(c: PackedVector4Array) -> float:
	var start := _project(c[0]); var end := _project(c[-1])
	var minimum_weight := INF; var error := 0.0
	for control in c: minimum_weight=minf(minimum_weight,control.w)
	var c_count_9 := c.size()
	for i in range(1,c_count_9):
		var f := float(i)/c.size()
		var difference := (_project(c[i])-start)*(c[i].w*(1-f))+(_project(c[i-1])-end)*(c[i-1].w*f)
		error=maxf(error,difference.length())
	return error/minimum_weight
func sample(sampling: MoldCurveSampling = null, preserve_parameter := false) -> Array:
	if not sampling: sampling=MoldCurveSampling.fixed()
	var result: Array=[]
	if not sampling.is_adaptive and span_count*sampling.subdivisions+1>sampling.max_points: push_error("Curve point budget exceeded."); return []
	for s: Dictionary in _spans:
		if result.is_empty(): result.append([_project(s.controls[0]),s.start])
		if sampling.is_adaptive:
			if not _sample_adaptive(s.controls,s.start,s.end,0,sampling,result,preserve_parameter): return []
		else:
			for i in range(1,sampling.subdivisions+1):
				var u := float(i)/sampling.subdivisions; result.append([_project(_evaluate_homogeneous(s.controls,u)),lerpf(s.start,s.end,u)])
	return result
func _sample_adaptive(c: PackedVector4Array,a: float,b: float,depth: int,settings: MoldCurveSampling,result: Array,preserve_parameter: bool) -> bool:
	if result.size()>=settings.max_points: push_error("Curve point budget exceeded."); return false
	if _flatness(c)<=settings.tolerance and (not preserve_parameter or _parameter_error(c)<=settings.tolerance): result.append([_project(c[-1]),b]); return true
	if depth>=settings.max_depth: push_error("Curve tolerance was not reached within MaxDepth."); return false
	var halves := _split(c,0.5); var m := (a+b)*0.5
	return _sample_adaptive(halves[0],a,m,depth+1,settings,result,preserve_parameter) and _sample_adaptive(halves[1],m,b,depth+1,settings,result,preserve_parameter)
func _validate_stroke(stroke: MoldStroke) -> bool:
	if not stroke.is_valid(): push_error("Invalid stroke settings."); return false
	if stroke.geometry==MoldPolyline.Geometry.FLAT_2D:
		var z := evaluate(0).z
		for s: Dictionary in _spans:
			for p: Vector4 in s.controls:
				if absf(_project(p).z-z)>0.00001: push_error("Flat2D controls must share one XY plane."); return false
	return true
# Profiles store float32 parameters; recursive sampling may differ by a few ULPs.
static func _same_parameter(a: float,b: float) -> bool:
	return absf(a-b)<=4e-7*maxf(absf(a),absf(b))
func to_polyline(stroke: MoldStroke = null,sampling: MoldCurveSampling = null) -> MoldPolyline:
	if not stroke: stroke=MoldStroke.new()
	if not stroke.is_valid(): push_error("Invalid stroke settings."); return null
	if not sampling: sampling=MoldCurveSampling.fixed()
	for entry: Array in _bakes:
		if entry[0].equals(stroke) and entry[1].equals(sampling) and entry[2].get_ref(): return entry[2].get_ref()
	if not _validate_stroke(stroke): return null
	var samples := sample(sampling)
	if samples.is_empty(): return null
	if sampling.is_adaptive and stroke.profile:
		var keys: PackedFloat32Array=stroke.profile._keys
		var key_count := keys.size()
		for key in range(0,key_count,6):
			var parameter := keys[key]
			var found := false
			for point: Array in samples:
				if _same_parameter(point[1],parameter): found=true; break
			if not found:
				if samples.size()>=sampling.max_points: push_error("Curve profile exceeded its point budget."); return null
				samples.append([evaluate(parameter),parameter])
		samples.sort_custom(func(a: Array,b: Array) -> bool: return a[1]<b[1])
	var count := samples.size()-(1 if closed else 0)
	if count<(3 if closed else 2): push_error("Increase subdivisions: too few stroke samples."); return null
	var points: Array[MoldPolylinePoint]=[]
	for i in count:
		points.append(stroke.profile.sample(samples[i][0],samples[i][1]) if stroke.profile else MoldPolylinePoint.new(samples[i][0]))
	var path := MoldPolyline.new(points,stroke.thickness,closed,stroke.join,stroke.cap,stroke.miter_limit,stroke.geometry,true)
	path._source_curve=self; path._curve_stroke=stroke; path._curve_sampling=sampling
	if _bakes.size()==8: _bakes.pop_front()
	_bakes.append([stroke,sampling,weakref(path)])
	return path
func bake_distance_table(tolerance := 0.001,max_depth := 20) -> MoldCurveDistanceTable:
	var sampling := MoldCurveSampling.adaptive(tolerance,max_depth)
	if not sampling: return null
	var samples := sample(sampling,true)
	if samples.is_empty(): return null
	return MoldCurveDistanceTable.new(self,samples)

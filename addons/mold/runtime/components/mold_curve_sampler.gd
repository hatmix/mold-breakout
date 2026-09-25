class_name MoldCurveSampler
extends RefCounted
## Reusable curve sampling. Copy samples into shared point buffers for batched GPU ranges.
var _curve: MoldCurve
var _stroke: MoldStroke
var _sampling: MoldCurveSampling
var _points := PackedFloat32Array()
var _sample_colors := PackedColorArray()
var _sample_widths := PackedFloat32Array()
var _closed := false
var _spans: Array = []
var sample_count: int:
	get: return _points.size()/8
func set_curve(curve: MoldCurve,stroke: MoldStroke = null,sampling: MoldCurveSampling = null) -> bool:
	if not curve: return false
	if not stroke: stroke=MoldStroke.new()
	if not sampling: sampling=MoldCurveSampling.fixed()
	if sampling.is_adaptive: push_error("Curve samplers require fixed sampling; use retained curves for adaptive geometry."); return false
	if not curve._validate_stroke(stroke): return false
	var count := curve.span_count*sampling.subdivisions+(0 if curve.closed else 1)
	if count<(3 if curve.closed else 2) or count+(1 if curve.closed else 0)>sampling.max_points: push_error("Curve point budget exceeded or too few samples."); return false
	_curve=curve;_stroke=stroke;_sampling=sampling;_closed=curve.closed;_copy_spans(curve)
	_points.resize((curve.span_count*sampling.subdivisions+(0 if _closed else 1))*8)
	_sample(true)
	return true
func _copy_spans(curve: MoldCurve) -> void:
	var count := curve.span_count
	_spans.resize(count)
	for i in count:
		if _spans[i]==null: _spans[i]={"controls":PackedVector4Array()}
		var source: PackedVector4Array=curve._spans[i].controls
		var target: PackedVector4Array=_spans[i].controls
		_spans[i].controls=PackedVector4Array()
		var control_count := source.size()
		target.resize(control_count)
		for j in control_count: target[j]=source[j]
		_spans[i].controls=target
		_spans[i].start=curve._spans[i].start
		_spans[i].end=curve._spans[i].end
func update_curve(curve: MoldCurve) -> bool:
	if not curve or curve.closed!=_closed or curve.span_count!=_spans.size(): push_error("Curve topology changed; use set_curve."); return false
	if not curve._validate_stroke(_stroke): return false
	_curve=curve;_copy_spans(curve);_sample(true);return true
## Nine floats per knot: position xyz, incoming offset xyz, outgoing offset xyz.
func update_bezier_knots(knots: PackedFloat32Array) -> bool:
	if not _curve or _curve._kind!="bezier" or knots.size()!=(_spans.size()+(0 if _closed else 1))*9: push_error("Bezier control count changed; use set_curve."); return false
	for v in knots:
		if not is_finite(v): push_error("Curve controls must be finite."); return false
	var count := knots.size()/9
	if _stroke.geometry==MoldPolyline.Geometry.FLAT_2D:
		for i in count:
			if absf(knots[i*9+2]-knots[2])>0.00001 or absf(knots[i*9+5])>0.00001 or absf(knots[i*9+8])>0.00001: push_error("Flat2D controls must share an XY plane."); return false
	var spans_count_1 := _spans.size()
	for i in spans_count_1:
		var a := i*9;var b := ((i+1)%count)*9
		var p := Vector3(knots[a],knots[a+1],knots[a+2]);var q := Vector3(knots[b],knots[b+1],knots[b+2])
		var c: PackedVector4Array=_spans[i].controls
		_spans[i].controls=PackedVector4Array() # Transfer ownership before editing; avoid a COW copy each frame.
		c[0]=MoldCurve._h(p);c[1]=MoldCurve._h(p+Vector3(knots[a+6],knots[a+7],knots[a+8]));c[2]=MoldCurve._h(q+Vector3(knots[b+3],knots[b+4],knots[b+5]));c[3]=MoldCurve._h(q)
		_spans[i].controls=c
	_sample();return true
func _sample(refresh_profile := false) -> void:
	var subdivisions := _sampling.subdivisions
	if refresh_profile:
		_sample_colors.resize(sample_count)
		_sample_widths.resize(sample_count)
	var index := 0
	for span: Dictionary in _spans:
		var controls: PackedVector4Array=span.controls
		for i in subdivisions:
			var u := float(i)/subdivisions
			_write(index,MoldCurve._project(MoldCurve._evaluate_homogeneous(controls,u)),lerpf(span.start,span.end,u),refresh_profile);index+=1
	if not _closed: _write(index,MoldCurve._project(_spans[-1].controls[-1]),1,refresh_profile)
func _write(index: int,p: Vector3,t: float,refresh_profile: bool) -> void:
	if refresh_profile:
		var color := Color.WHITE;var width := _stroke.thickness
		if _stroke.profile:
			var keys: PackedFloat32Array=_stroke.profile._keys
			var count := keys.size()
			var key := 0
			while key+6<count and keys[key+6]<t: key+=6
			var next := mini(key+6,count-6)
			var f := clampf((t-keys[key])/(keys[next]-keys[key]),0,1) if next!=key else 0.0
			color=Color(keys[key+1],keys[key+2],keys[key+3],keys[key+4]).lerp(Color(keys[next+1],keys[next+2],keys[next+3],keys[next+4]),f)
			width*=lerpf(keys[key+5],keys[next+5],f)
		_sample_colors[index]=color;_sample_widths[index]=width
	var color := _sample_colors[index]
	var i := index*8
	_points[i]=p.x;_points[i+1]=p.y;_points[i+2]=p.z;_points[i+3]=_sample_widths[index]
	_points[i+4]=color.r;_points[i+5]=color.g;_points[i+6]=color.b;_points[i+7]=color.a

## Returns the destination because Packed arrays use copy-on-write. Offset is measured in points.
func copy_points_to(destination: PackedFloat32Array, start_index := 0) -> PackedFloat32Array:
	assert(start_index>=0 and (start_index+sample_count)*8<=destination.size())
	for i in _points.size(): destination[start_index*8+i]=_points[i]
	return destination

func update_catmull_rom_points(points: PackedVector3Array) -> bool:
	if not _curve or _curve._kind!="catmull" or points.size()!=_spans.size()+(0 if _closed else 1):
		push_error("Catmull–Rom control count changed; use set_curve."); return false
	var count := points.size()
	for i in count:
		if not points[i].is_finite(): push_error("Curve controls must be finite."); return false
		if _stroke.geometry==MoldPolyline.Geometry.FLAT_2D and absf(points[i].z-points[0].z)>0.00001:
			push_error("Flat2D controls must share an XY plane."); return false
		if (i>0 and points[i].distance_to(points[i-1])<=0.000001) or (_closed and i==count-1 and points[i].distance_to(points[0])<=0.000001):
			push_error("Adjacent Catmull–Rom anchors must be distinct."); return false
	for i in _spans.size():
		var a := points[i]; var next := points[(i+1)%count]
		var before := points[i-1] if i>0 else (points[-1] if _closed else 2*a-next)
		var after := points[i+2] if i+2<count else (points[(i+2)%count] if _closed else 2*next-a)
		var controls: PackedVector4Array=_spans[i].controls
		_spans[i].controls=PackedVector4Array()
		_spans[i].controls=MoldCurve._catmull_controls(before,a,next,after,_curve._parameterization,controls)
	_sample()
	return true

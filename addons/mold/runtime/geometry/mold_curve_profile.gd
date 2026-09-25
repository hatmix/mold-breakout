class_name MoldCurveProfile
extends RefCounted
## Keys use six floats: normalized parameter, red, green, blue, alpha, width multiplier.
var _keys := PackedFloat32Array()
static func create(keys: PackedFloat32Array) -> MoldCurveProfile:
	if keys.is_empty() or keys.size()%6!=0: push_error("A profile needs packed six-float keys."); return null
	for v in keys:
		if not is_finite(v): push_error("Profile keys must be finite."); return null
	var keys_count_1 := keys.size()
	for i in range(0,keys_count_1,6):
		if keys[i]<0 or keys[i]>1 or keys[i+5]<=0 or (i>0 and keys[i]<=keys[i-6]): push_error("Profile keys must be ordered with positive width."); return null
	var result := MoldCurveProfile.new(); result._keys=keys.duplicate(); return result
func sample(p: Vector3,t: float) -> MoldPolylinePoint:
	var i := 0
	var keys_count_2 := _keys.size()
	while i+6<keys_count_2 and _keys[i+6]<t: i+=6
	var j := mini(i+6,_keys.size()-6)
	var f := clampf((t-_keys[i])/(_keys[j]-_keys[i]),0,1) if j!=i else 0.0
	var a := Color(_keys[i+1],_keys[i+2],_keys[i+3],_keys[i+4]); var b := Color(_keys[j+1],_keys[j+2],_keys[j+3],_keys[j+4])
	return MoldPolylinePoint.new(p,a.lerp(b,f),lerpf(_keys[i+5],_keys[j+5],f))


## Native-control colors and thickness: anchors blend by span distance; off-curve controls use their basis.
static func bake_from_controls(curve: MoldCurve,kind: int,colors: PackedColorArray,widths: PackedFloat32Array,weights: PackedFloat32Array,settings: MoldCurveSampling,interpolation := 0,degree := 3,knots := PackedFloat32Array()) -> MoldCurveProfile:
	var count := colors.size()
	if widths.size()!=count: push_error("Curve thickness count must match controls."); return null
	widths=widths.duplicate()
	var unit_width := true
	for width in widths:
		if not is_finite(width) or width<=0: push_error("Curve thickness multipliers must be finite and positive."); return null
		unit_width=unit_width and width==1.0
	if curve.closed and kind==1: widths[count-1]=widths[0]
	var white := true
	for i in count:
		var color := colors[i]
		if not is_finite(color.r) or not is_finite(color.g) or not is_finite(color.b) or not is_finite(color.a): push_error("Curve colors must be finite."); return null
		white=white and color==Color.WHITE
	if white and unit_width: return null
	colors=colors.duplicate()
	for i in count: colors[i]=MoldPointColors.convert(colors[i],interpolation,false)
	if curve.closed and kind==1: colors[count-1]=colors[0]
	var basis := kind in [1,4,5]
	var samples := curve.sample(settings,true)
	var rgb: MoldCurve; var scalars: MoldCurve
	if basis:
		var rgb_points := PackedVector3Array(); var scalar_points := PackedVector3Array()
		rgb_points.resize(count); scalar_points.resize(count)
		for i in count:
			var color := colors[i]
			rgb_points[i]=Vector3(color.r,color.g,color.b); scalar_points[i]=Vector3(color.a,widths[i],0)
		if kind==1:
			rgb=MoldCurve.quadratic_bezier(rgb_points,curve.closed); scalars=MoldCurve.quadratic_bezier(scalar_points,curve.closed)
		elif kind==4:
			rgb=MoldCurve.bspline(rgb_points,degree,knots,curve.closed); scalars=MoldCurve.bspline(scalar_points,degree,knots,curve.closed)
		else:
			rgb=MoldCurve.nurbs(rgb_points,weights,degree,knots,curve.closed); scalars=MoldCurve.nurbs(scalar_points,weights,degree,knots,curve.closed)
		if settings.is_adaptive:
			var attribute_samples := rgb.sample(settings,true); attribute_samples.append_array(scalars.sample(settings,true))
			for sample in attribute_samples: samples.append([curve.evaluate(sample[1]),sample[1]])
			samples.sort_custom(func(a,b): return a[1]<b[1])
			var write := 1; var total := samples.size()
			for i in range(1,total):
				if not MoldCurve._same_parameter(samples[i][1],samples[write-1][1]): samples[write]=samples[i]; write+=1
				else: samples[write-1]=samples[i]
			samples.resize(write)
	# Preserve perceptual color variation even on straight adaptive spans.
	if settings.is_adaptive and interpolation==1:
		samples.append_array(curve.sample(MoldCurveSampling.fixed(16,settings.max_points)))
		samples.sort_custom(func(a,b): return a[1]<b[1])
		var write := 1; var total := samples.size()
		for i in range(1,total):
			if not MoldCurve._same_parameter(samples[i][1],samples[write-1][1]): samples[write]=samples[i]; write+=1
			else: samples[write-1]=samples[i]
		samples.resize(write)
	var sample_count := samples.size()
	if sample_count>settings.max_points: push_error("Curve profile exceeded its point budget."); return null
	var distances := PackedFloat32Array(); distances.resize(sample_count)
	var span_count := curve.span_count
	var starts := PackedInt32Array(); starts.resize(span_count+1)
	var span := 0
	for i in range(1,sample_count):
		distances[i]=distances[i-1]+samples[i][0].distance_to(samples[i-1][0])
		if samples[i][1]>=curve._spans[span].end: span+=1; starts[span]=i
	var keys := PackedFloat32Array(); keys.resize(sample_count*6); span=0
	for i in sample_count:
		var t: float = samples[i][1]
		var color: Color
		var width: float
		if basis:
			var value := rgb.evaluate(t); var scalar := scalars.evaluate(t); color=Color(value.x,value.y,value.z,scalar.x); width=scalar.y
		else:
			while span<span_count-1 and t>curve._spans[span].end: span+=1
			var first := starts[span]; var last := starts[span+1]
			var length := distances[last]-distances[first]
			var f: float = (distances[i]-distances[first])/length if length>0.000000000001 else (t-curve._spans[span].start)/(curve._spans[span].end-curve._spans[span].start)
			color=colors[span].lerp(colors[(span+1)%count],f)
			width=lerpf(widths[span],widths[(span+1)%count],f)
		color=MoldPointColors.convert(color,interpolation,true)
		var index := i*6
		keys[index]=t; keys[index+1]=color.r; keys[index+2]=color.g; keys[index+3]=color.b; keys[index+4]=color.a; keys[index+5]=width
	return create(keys)

class_name MoldPencil
extends RefCounted

enum Target { STROKE, GPU_POLYLINE, SURFACE, CPU_POLYGON, GPU_POLYGON }
static func preset(value: MoldPencilSettings.Preset) -> MoldPencilSettings:
	return MoldPencilSettings.preset(value)

static func create_material(settings: MoldPencilSettings, target: Target = Target.STROKE, mode: MoldStyle.BlendMode = MoldStyle.BlendMode.TRANSPARENT, state: MoldRenderState = null) -> ShaderMaterial:
	assert(settings != null)
	var values := settings.uniforms()
	assert(not values.is_empty(), "Invalid appearance settings")
	var effect := MoldAppearanceSnapshot.new(2,values,false,target == Target.SURFACE)
	var backend := MoldShader.Backend.GPU_POLYLINE if target == Target.GPU_POLYLINE else MoldShader.Backend.POLYGON if target in [Target.CPU_POLYGON,Target.GPU_POLYGON] else MoldShader.Backend.MULTIMESH
	var material := ShaderMaterial.new()
	material.shader=MoldShader.get_shader(mode,state if state else MoldRenderState.new(),backend,false,effect)
	effect.apply(material)
	if target == Target.GPU_POLYLINE: material.set_meta("MoldGpuPolyline",true)
	return material

static func point(position: Vector3, pressure: float, color := Color.WHITE) -> MoldPolylinePoint:
	assert(is_finite(pressure))
	pressure=clampf(pressure,0,1)
	color.a*=pressure
	return MoldPolylinePoint.new(position,color,lerpf(.15,1.0,pressure))

# Fixed subtractive sequence keeps a sketch seed reproducible across runtime versions.
class SketchRandom:
	var values := PackedInt64Array()
	var first := 0
	var second := 21
	static func _int32(value: int) -> int: return ((value+2147483648)&4294967295)-2147483648
	func _init(seed: int) -> void:
		assert(seed>=-2147483648 and seed<=2147483647,"Sketch seed must fit a signed 32-bit integer.")
		values.resize(56)
		var mj := 161803398-(2147483647 if seed == -2147483648 else absi(seed))
		values[55]=mj
		var mk := 1
		for i in range(1,55):
			var slot := (21*i)%55
			values[slot]=mk
			mk=_int32(mj-mk)
			if mk<0: mk+=2147483647
			mj=values[slot]
		for k in range(4):
			for i in range(1,56):
				values[i]=_int32(values[i]-values[1+(i+30)%55])
				if values[i]<0: values[i]+=2147483647
	func next_double() -> float:
		first=first+1 if first<55 else 1
		second=second+1 if second<55 else 1
		var result := _int32(values[first]-values[second])
		if result == 2147483647: result-=1
		if result<0: result+=2147483647
		values[first]=result
		return float(result)*(1.0/2147483647.0)

static func sketch_paths(points: Array[MoldPolylinePoint], thickness: float, copies := 3, jitter := .035, seed := 1) -> Array[MoldPolyline]:
	assert(points.size()>=2 and copies>=1 and copies<=16 and is_finite(jitter) and jitter>=0)
	var distances := PackedFloat32Array()
	distances.resize(points.size())
	for i in range(1,points.size()): distances[i]=distances[i-1]+points[i-1].position.distance_to(points[i].position)
	var random := SketchRandom.new(seed)
	var result: Array[MoldPolyline] = []
	for copy in copies:
		var phase := random.next_double()*TAU
		var displaced: Array[MoldPolylinePoint] = []
		for i in points.size():
			var tangent := points[mini(i+1,points.size()-1)].position-points[maxi(i-1,0)].position
			var normal := Vector3(-tangent.y,tangent.x,0).normalized()
			var t := distances[i]/maxf(distances[-1],.000001)
			var offset := jitter*sin(t*PI)*(.65*sin(distances[i]*2.3+phase)+.35*sin(distances[i]*5.1+phase*.7))
			displaced.append(MoldPolylinePoint.new(points[i].position+normal*offset,points[i].color,points[i].thickness))
		result.append(MoldPolyline.new(displaced,thickness))
	return result

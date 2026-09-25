class_name MoldPaint
extends RefCounted

enum Target { STROKE, GPU_POLYLINE, SURFACE, CPU_POLYGON, GPU_POLYGON }
static func preset(value: MoldPaintSettings.Preset) -> MoldPaintSettings:
	return MoldPaintSettings.preset(value)

static func create_material(settings: MoldPaintSettings, target: Target = Target.STROKE, mode: MoldStyle.BlendMode = MoldStyle.BlendMode.TRANSPARENT, state: MoldRenderState = null) -> ShaderMaterial:
	assert(settings != null)
	var values := settings.uniforms()
	assert(not values.is_empty(), "Invalid appearance settings")
	var effect := MoldAppearanceSnapshot.new(1,values,false,target == Target.SURFACE)
	var backend := MoldShader.Backend.GPU_POLYLINE if target == Target.GPU_POLYLINE else MoldShader.Backend.POLYGON if target in [Target.CPU_POLYGON,Target.GPU_POLYGON] else MoldShader.Backend.MULTIMESH
	var material := ShaderMaterial.new()
	material.shader=MoldShader.get_shader(mode,state if state else MoldRenderState.new(),backend,false,effect)
	effect.apply(material)
	if target == Target.GPU_POLYLINE: material.set_meta("MoldGpuPolyline",true)
	return material

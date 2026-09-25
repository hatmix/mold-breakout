class_name MoldShader
extends RefCounted

enum Backend { PREVIEW, MULTIMESH, POLYGON, GPU_POLYLINE }
# Application-lifetime immutable variants. Renderers borrow these resources;
# materials and public custom shader factories keep independent ownership.
static var _shaders: Dictionary = {}

static func get_shader(mode: MoldStyle.BlendMode, state: MoldRenderState, backend := Backend.PREVIEW, coverage_output := false, appearance: MoldAppearanceSnapshot = null) -> Shader:
	mode = _shader_blend_mode(mode)
	coverage_output = coverage_output and mode == MoldStyle.BlendMode.OPAQUE
	var key := state.shader_key(mode, coverage_output) | (int(coverage_output) << 24) | (backend << 25) | ((appearance.kind if appearance else 0) << 28) | (int(appearance.surface if appearance else false) << 30)
	var cached: Shader = _shaders.get(key)
	if is_instance_valid(cached): return cached
	var shader := Shader.new()
	shader.code = source(mode, state, backend, coverage_output, appearance)
	_shaders[key] = shader
	return shader

static func source(mode: MoldStyle.BlendMode, state: MoldRenderState, backend: Backend, coverage_output := false, appearance: MoldAppearanceSnapshot = null) -> String:
	mode = _shader_blend_mode(mode)
	var blend := "blend_mix"
	if mode == MoldStyle.BlendMode.ADDITIVE: blend = "blend_add"
	elif mode == MoldStyle.BlendMode.SUBTRACTIVE: blend = "blend_sub"
	elif mode == MoldStyle.BlendMode.MULTIPLICATIVE: blend = "blend_mul"
	var stencil_read := bool(state.stencil_flags & MoldRenderState.StencilFlags.READ)
	var depth_write := state.effective_depth_write(mode)
	var depth := "depth_draw_never"
	if depth_write:
		depth = "depth_draw_opaque" if state.depth_write == MoldRenderState.DepthWrite.AUTO and not stencil_read else "depth_draw_always"
	var depth_test := "depth_test_default"
	if state.depth_test == MoldRenderState.DepthTest.GREATER: depth_test = "depth_test_inverted"
	elif state.depth_test == MoldRenderState.DepthTest.ALWAYS: depth_test = "depth_test_disabled"
	var cull := "cull_disabled"
	if state.face_cull == MoldRenderState.FaceCull.BACK: cull = "cull_back"
	elif state.face_cull == MoldRenderState.FaceCull.FRONT: cull = "cull_front"
	var opaque := mode in [MoldStyle.BlendMode.OPAQUE, MoldStyle.BlendMode.DITHER]
	coverage_output = coverage_output and mode == MoldStyle.BlendMode.OPAQUE
	if coverage_output:
		# Shapes writes opaque surviving samples after generating the sample mask.
		# Alpha-to-one prevents source-alpha blending from applying coverage twice.
		blend += ", alpha_to_coverage_and_one"
		if state.depth_write == MoldRenderState.DepthWrite.AUTO and depth_write: depth = "depth_draw_always"
	var alpha_write := "" if opaque and not coverage_output and not stencil_read else "\tALPHA = result.a;"
	var stencil := _stencil_source(state)
	var backend_define := ""
	match backend:
		Backend.MULTIMESH: backend_define = "#define MOLD_INSTANCED\n"
		Backend.POLYGON: backend_define = "#define MOLD_POLYGON\n"
		Backend.GPU_POLYLINE: backend_define = "#define MOLD_GPU_POLYLINE\n"
	return "shader_type spatial;\nrender_mode unshaded, %s, %s, %s, %s;\n%s\n" % [cull, blend, depth, depth_test, stencil] \
		+ "#define MOLD_BLEND_MODE %d\n#define MOLD_COVERAGE_OUTPUT %s\n" % [mode, "true" if coverage_output else "false"] \
		+ ("#define MOLD_WRITE_ALPHA\n" if not alpha_write.is_empty() else "") \
		+ (appearance.shader_prefix() if appearance else "") + backend_define + '#include "res://addons/mold/runtime/rendering/mold_spatial.gdshaderinc"\n'


static func _shader_blend_mode(mode: MoldStyle.BlendMode) -> MoldStyle.BlendMode:
	match mode:
		MoldStyle.BlendMode.SCREEN, MoldStyle.BlendMode.LIGHTEN, MoldStyle.BlendMode.COLOR_DODGE:
			return MoldStyle.BlendMode.ADDITIVE
		MoldStyle.BlendMode.LINEAR_BURN, MoldStyle.BlendMode.DARKEN, MoldStyle.BlendMode.COLOR_BURN:
			return MoldStyle.BlendMode.MULTIPLICATIVE
	return mode


static func _stencil_source(state: MoldRenderState) -> String:
	if state.stencil_flags == MoldRenderState.StencilFlags.DISABLED: return ""
	var modes := PackedStringArray()
	if state.stencil_flags & MoldRenderState.StencilFlags.READ: modes.append("read")
	if state.stencil_flags & MoldRenderState.StencilFlags.WRITE: modes.append("write")
	if state.stencil_flags & MoldRenderState.StencilFlags.WRITE_DEPTH_FAIL:
		modes.append("write_if_depth_fail")
	var comparison := state.stencil_compare if state.stencil_flags & MoldRenderState.StencilFlags.READ else MoldRenderState.StencilCompare.ALWAYS
	match comparison:
		MoldRenderState.StencilCompare.LESS: modes.append("compare_less")
		MoldRenderState.StencilCompare.EQUAL: modes.append("compare_equal")
		MoldRenderState.StencilCompare.LESS_OR_EQUAL: modes.append("compare_less_or_equal")
		MoldRenderState.StencilCompare.GREATER: modes.append("compare_greater")
		MoldRenderState.StencilCompare.NOT_EQUAL: modes.append("compare_not_equal")
		MoldRenderState.StencilCompare.GREATER_OR_EQUAL: modes.append("compare_greater_or_equal")
		_: modes.append("compare_always")
	return "stencil_mode %s, %d;" % [", ".join(modes), state.stencil_reference]

class_name MoldRenderState
extends RefCounted

enum DepthTest { LESS_EQUAL = 4, GREATER = 5, ALWAYS = 8 }
enum DepthWrite { AUTO, ENABLED, DISABLED }
enum FaceCull { DISABLED, BACK, FRONT }
enum StencilFlags { DISABLED = 0, READ = 1, WRITE = 2, WRITE_DEPTH_FAIL = 4 }
enum StencilCompare { ALWAYS, LESS, EQUAL, LESS_OR_EQUAL, GREATER, NOT_EQUAL, GREATER_OR_EQUAL }

var render_layer_mask: int
const MIN_SORTING_ORDER := -128
const MAX_SORTING_ORDER := 127

## 3D material priority. Depth testing still applies.
var sorting_order: int:
	set(value): sorting_order = clampi(value, MIN_SORTING_ORDER, MAX_SORTING_ORDER)
var depth_test: DepthTest
var depth_write: DepthWrite
var stencil_flags: int
var stencil_compare: StencilCompare
var stencil_reference: int
var face_cull: FaceCull


func _init(
	layer_mask: int = 1,
	order: int = 0,
	value_depth_test: DepthTest = DepthTest.LESS_EQUAL,
	value_depth_write: DepthWrite = DepthWrite.AUTO,
	value_stencil_flags: int = StencilFlags.DISABLED,
	value_stencil_compare: StencilCompare = StencilCompare.ALWAYS,
	value_stencil_reference: int = 0,
	value_face_cull: FaceCull = FaceCull.DISABLED,
) -> void:
	render_layer_mask = maxi(1, layer_mask)
	sorting_order = order
	if value_depth_test == DepthTest.LESS_EQUAL \
		or value_depth_test == DepthTest.GREATER \
		or value_depth_test == DepthTest.ALWAYS:
		depth_test = value_depth_test
	else:
		depth_test = DepthTest.LESS_EQUAL
	depth_write = value_depth_write if value_depth_write >= DepthWrite.AUTO and value_depth_write <= DepthWrite.DISABLED else DepthWrite.AUTO
	stencil_flags = value_stencil_flags & (StencilFlags.READ | StencilFlags.WRITE | StencilFlags.WRITE_DEPTH_FAIL)
	stencil_compare = value_stencil_compare if value_stencil_compare >= StencilCompare.ALWAYS and value_stencil_compare <= StencilCompare.GREATER_OR_EQUAL else StencilCompare.ALWAYS
	stencil_reference = clampi(value_stencil_reference, 0, 255)
	face_cull = value_face_cull if value_face_cull >= FaceCull.DISABLED and value_face_cull <= FaceCull.FRONT else FaceCull.DISABLED


## A null source resets this owned state to the defaults.
func copy_from(value: MoldRenderState) -> void:
	if value == null: _init()
	else: _init(value.render_layer_mask,value.sorting_order,value.depth_test,value.depth_write,value.stencil_flags,value.stencil_compare,value.stencil_reference,value.face_cull)


func duplicate_state() -> MoldRenderState:
	return MoldRenderState.new(render_layer_mask, sorting_order, depth_test, depth_write, stencil_flags, stencil_compare, stencil_reference, face_cull)


func equals(other: MoldRenderState) -> bool:
	return other != null and render_layer_mask == other.render_layer_mask \
		and sorting_order == other.sorting_order and depth_test == other.depth_test \
		and depth_write == other.depth_write and stencil_flags == other.stencil_flags \
		and stencil_compare == other.stencil_compare and stencil_reference == other.stencil_reference \
		and face_cull == other.face_cull


func effective_depth_write(mode: MoldStyle.BlendMode) -> bool:
	if depth_write == DepthWrite.ENABLED: return true
	if depth_write == DepthWrite.DISABLED: return false
	return mode == MoldStyle.BlendMode.OPAQUE or mode == MoldStyle.BlendMode.DITHER


func shader_key(mode: MoldStyle.BlendMode, coverage_output := false) -> int:
	var comparison := stencil_compare if stencil_flags & StencilFlags.READ else StencilCompare.ALWAYS
	var reference := stencil_reference if stencil_flags != StencilFlags.DISABLED else 0
	# Alpha-to-coverage uses depth_draw_always even when depth writing is automatic.
	coverage_output = coverage_output and mode == MoldStyle.BlendMode.OPAQUE
	var depth_mode := 0
	if effective_depth_write(mode):
		depth_mode = 1 if depth_write == DepthWrite.AUTO and not coverage_output and (stencil_flags & StencilFlags.READ) == 0 else 2
	return mode | (depth_test << 4) | (depth_mode << 6) | (stencil_flags << 8) \
		| (comparison << 11) | (reference << 14) | (face_cull << 22)

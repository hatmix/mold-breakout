class_name MoldDash
extends RefCounted

enum Type { NORMAL, CHEVRON, ROUNDED }
enum Mode { FIXED_COUNT, LENGTH }
enum Snap { OFF, TILING, END_TO_END }

const _TYPE_CODE_START := 0.1
const _TYPE_CODE_STEP := 0.3
const _MODIFIER_CODE_SCALE := 0.075

var mode: Mode = Mode.FIXED_COUNT
var snap: Snap = Snap.OFF
var count := 0
var dash_length := 0.0
var spacing := 0.1
var offset := 0.0
var type: Type = Type.NORMAL
var modifier := 0.0
var is_enabled: bool:
	get: return count > 0 if mode == Mode.FIXED_COUNT else dash_length > 0.0

static func fixed_count(dash_count: int, dash_spacing := 0.1, dash_offset := 0.0,
		dash_type: Type = Type.NORMAL, dash_modifier := 0.0) -> MoldDash:
	assert(dash_count >= 1 and dash_count <= 4096)
	assert(is_finite(dash_spacing) and dash_spacing >= 0.0 and dash_spacing <= 1.0)
	return _create(Mode.FIXED_COUNT, Snap.END_TO_END, dash_count, 0.0, dash_spacing, dash_offset, dash_type, dash_modifier)

static func length(length_value: float, dash_spacing: float, dash_snap: Snap = Snap.OFF,
		dash_offset := 0.0,
		dash_type: Type = Type.NORMAL, dash_modifier := 0.0) -> MoldDash:
	return _create(Mode.LENGTH, dash_snap, 0, length_value, dash_spacing, dash_offset, dash_type, dash_modifier)

static func _create(value_mode: Mode, value_snap: Snap, value_count: int, value_length: float,
		value_spacing: float, value_offset: float, value_type: Type, value_modifier: float) -> MoldDash:
	assert(is_finite(value_offset) and value_type >= Type.NORMAL and value_type <= Type.ROUNDED)
	assert(value_snap >= Snap.OFF and value_snap <= Snap.END_TO_END)
	assert(is_finite(value_modifier) and value_modifier >= -1.0 and value_modifier <= 1.0)
	if value_mode != Mode.FIXED_COUNT:
		assert(is_finite(value_length) and value_length > 0.0)
		assert(is_finite(value_spacing) and value_spacing >= 0.0)
	var result := MoldDash.new()
	result.mode = value_mode; result.snap = value_snap; result.count = value_count; result.dash_length = value_length
	result.spacing = value_spacing; result.offset = value_offset
	result.type = value_type; result.modifier = value_modifier
	return result

static func corner(side_count: int) -> MoldDash: return fixed_count(side_count, 0.5, 0.25)
static func edge(side_count: int) -> MoldDash: return fixed_count(side_count, 0.5, -0.25)

func copy_from(value: MoldDash) -> void:
	if value == null:
		mode = Mode.FIXED_COUNT; snap = Snap.OFF; count = 0; dash_length = 0.0; spacing = 0.1; offset = 0.0
		type = Type.NORMAL; modifier = 0.0
		return
	mode = value.mode; snap = value.snap; count = value.count; dash_length = value.dash_length; spacing = value.spacing
	offset = value.offset; type = value.type; modifier = value.modifier

func duplicate_dash() -> MoldDash:
	return _create(mode, snap, count, dash_length, spacing, offset, type, modifier) if is_enabled else MoldDash.new()

func equals(other: MoldDash) -> bool:
	return other != null and mode == other.mode and snap == other.snap and count == other.count \
		and dash_length == other.dash_length and spacing == other.spacing and offset == other.offset \
		and type == other.type and modifier == other.modifier

func to_gpu_data(path_length := 1.0) -> Vector4:
	if not is_enabled or not is_finite(path_length) or path_length <= 0.0: return Vector4.ZERO
	var gap_ratio: float
	var repeat_span: float
	var gpu_offset := offset
	if mode == Mode.FIXED_COUNT:
		gap_ratio = clampf(spacing, 0.0, 1.0)
		repeat_span = maxf(count - gap_ratio, 0.00001)
	else:
		var period := maxf(dash_length + spacing, 0.00001)
		gap_ratio = clampf(spacing / period, 0.0, 1.0)
		var raw_period_count := path_length / period
		if snap == Snap.TILING:
			repeat_span = maxf(roundf(raw_period_count), 1.0)
			gpu_offset -= gap_ratio * 0.5
		elif snap == Snap.END_TO_END:
			var dash_count := maxf(floorf(raw_period_count + gap_ratio + 0.00001), 1.0)
			repeat_span = maxf(dash_count - gap_ratio, 0.00001)
		else:
			repeat_span = maxf(raw_period_count, 0.00001)
	var type_code := _TYPE_CODE_START + _TYPE_CODE_STEP * type + _MODIFIER_CODE_SCALE * modifier
	return Vector4(repeat_span, type_code, gap_ratio, gpu_offset)

@tool
class_name MoldAppearanceResource
extends Resource

enum Kind { STANDARD, PAINT, PENCIL }
@export var kind: Kind = Kind.STANDARD:
	set(value):
		if kind == value: return
		kind=value
		notify_property_list_changed()
		emit_changed()
@export var automatic_length := true:
	set(value):
		if automatic_length == value: return
		automatic_length=value
		notify_property_list_changed()
		emit_changed()
@export var paint_preset: MoldPaintSettings.Preset = MoldPaintSettings.Preset.RAGGED
@export var pencil_preset: MoldPencilSettings.Preset = MoldPencilSettings.Preset.HARD_PENCIL
@export var paint: MoldPaintSettings = MoldPaintSettings.preset(MoldPaintSettings.Preset.RAGGED):
	set(value):
		if paint and paint.changed.is_connected(_settings_changed): paint.changed.disconnect(_settings_changed)
		paint=value
		_connect_settings()
		emit_changed()
@export var pencil: MoldPencilSettings = MoldPencilSettings.preset(MoldPencilSettings.Preset.HARD_PENCIL):
	set(value):
		if pencil and pencil.changed.is_connected(_settings_changed): pencil.changed.disconnect(_settings_changed)
		pencil=value
		_connect_settings()
		emit_changed()

func _init() -> void:
	_connect_settings()
func _connect_settings() -> void:
	for settings in [paint,pencil]:
		if settings and not settings.changed.is_connected(_settings_changed): settings.changed.connect(_settings_changed)
func _settings_changed() -> void:
	emit_changed()
func apply_preset() -> void:
	if kind == Kind.PAINT: paint=MoldPaintSettings.preset(paint_preset)
	elif kind == Kind.PENCIL: pencil=MoldPencilSettings.preset(pencil_preset)
func snapshot() -> MoldAppearanceSnapshot:
	if kind == Kind.STANDARD: return null
	var settings: Resource = paint if kind == Kind.PAINT else pencil
	if not settings: return null
	var values: Dictionary = settings.uniforms()
	if values.is_empty(): return null
	return MoldAppearanceSnapshot.new(kind,values,automatic_length)

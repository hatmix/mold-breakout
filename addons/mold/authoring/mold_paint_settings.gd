@tool
class_name MoldPaintSettings
extends Resource

enum Preset { RAGGED, DRY_BRUSH, INK, ACRYLIC, WATERCOLOR, IMPASTO }

@export var seed: float = 1.0:
	set(value):
		if not is_finite(value): push_error("Seed must be finite."); return
		var next := value
		if seed == next: return
		seed = next
		emit_changed()

@export_range(0.001, 100.0, 0.01, "or_greater") var length: float = 5.0:
	set(value):
		if not is_finite(value): push_error("Length must be finite."); return
		var next := maxf(value, 0.001)
		if length == next: return
		length = next
		emit_changed()

@export_range(1.0, 80.0, 0.01) var bristles: float = 24.0:
	set(value):
		if not is_finite(value): push_error("Bristles must be finite."); return
		var next := clampf(value, 1.0, 80.0)
		if bristles == next: return
		bristles = next
		emit_changed()

@export_range(0.0, 0.8, 0.01) var roughness: float = 0.18:
	set(value):
		if not is_finite(value): push_error("Roughness must be finite."); return
		var next := clampf(value, 0.0, 0.8)
		if roughness == next: return
		roughness = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var dryness: float = 0.35:
	set(value):
		if not is_finite(value): push_error("Dryness must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if dryness == next: return
		dryness = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var taper: float = 0.3:
	set(value):
		if not is_finite(value): push_error("Taper must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if taper == next: return
		taper = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var loading: float = 0.3:
	set(value):
		if not is_finite(value): push_error("Loading must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if loading == next: return
		loading = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var pigment: float = 0.3:
	set(value):
		if not is_finite(value): push_error("Pigment must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if pigment == next: return
		pigment = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var wash: float = 0.0:
	set(value):
		if not is_finite(value): push_error("Wash must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if wash == next: return
		wash = next
		emit_changed()

@export_range(0.0, 2.0, 0.01) var ridge: float = 0.0:
	set(value):
		if not is_finite(value): push_error("Ridge must be finite."); return
		var next := clampf(value, 0.0, 2.0)
		if ridge == next: return
		ridge = next
		emit_changed()

@export_range(0.001, 100.0, 0.01, "or_greater") var surface_scale: float = 5.0:
	set(value):
		if not is_finite(value): push_error("SurfaceScale must be finite."); return
		var next := maxf(value, 0.001)
		if surface_scale == next: return
		surface_scale = next
		emit_changed()

@export_range(-180.0, 180.0, 0.1, "or_less", "or_greater", "radians_as_degrees") var surface_direction: float = 0.0:
	set(value):
		if not is_finite(value): push_error("SurfaceDirection must be finite."); return
		var next := value
		if surface_direction == next: return
		surface_direction = next
		emit_changed()

static func preset(value: Preset) -> MoldPaintSettings:
	var s := MoldPaintSettings.new()
	match value:
		Preset.RAGGED:
			s.dryness=0.0
			s.roughness=0.38
			s.loading=0.0
			s.taper=0.15
		Preset.DRY_BRUSH:
			s.bristles=18.0
			s.dryness=0.75
			s.roughness=0.28
			s.taper=0.35
			s.pigment=0.5
		Preset.INK:
			s.dryness=0.12
			s.roughness=0.08
			s.taper=0.95
			s.loading=0.65
			s.bristles=28.0
		Preset.ACRYLIC:
			s.dryness=0.1
			s.loading=0.0
			s.ridge=0.45
			s.pigment=0.4
		Preset.WATERCOLOR:
			s.dryness=0.08
			s.wash=1.0
			s.roughness=0.22
			s.loading=0.35
			s.pigment=0.6
		Preset.IMPASTO:
			s.dryness=0.15
			s.ridge=1.5
			s.bristles=28.0
			s.pigment=0.65
			s.loading=0.0
		_: assert(false, "Unknown preset")
	return s

func uniforms() -> Dictionary:
	var result := {}
	result["_PaintSeed"]=seed
	result["_PaintLength"]=length
	result["_PaintBristles"]=bristles
	result["_PaintRoughness"]=roughness
	result["_PaintDryness"]=dryness
	result["_PaintTaper"]=taper
	result["_PaintLoading"]=loading
	result["_PaintPigment"]=pigment
	result["_PaintWash"]=wash
	result["_PaintRidge"]=ridge
	result["_PaintScale"]=surface_scale
	result["_PaintDirection"]=surface_direction
	return result

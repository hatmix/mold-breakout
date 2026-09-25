@tool
class_name MoldPencilSettings
extends Resource

enum Preset { HARD_PENCIL, SOFT_GRAPHITE, SIDE_SHADING, HATCHING, CROSSHATCHING, SMUDGED_GRAPHITE }

@export var seed: float = 1.0:
	set(value):
		if not is_finite(value): push_error("Seed must be finite."); return
		var next := value
		if seed == next: return
		seed = next
		emit_changed()

@export var paper_seed: float = 7.0:
	set(value):
		if not is_finite(value): push_error("PaperSeed must be finite."); return
		var next := value
		if paper_seed == next: return
		paper_seed = next
		emit_changed()

@export_range(0.001, 100.0, 0.01, "or_greater") var paper_scale: float = 18.0:
	set(value):
		if not is_finite(value): push_error("PaperScale must be finite."); return
		var next := maxf(value, 0.001)
		if paper_scale == next: return
		paper_scale = next
		emit_changed()

@export_range(0.001, 100.0, 0.01, "or_greater") var length: float = 5.0:
	set(value):
		if not is_finite(value): push_error("Length must be finite."); return
		var next := maxf(value, 0.001)
		if length == next: return
		length = next
		emit_changed()

@export_range(0.001, 100.0, 0.01, "or_greater") var hatch_scale: float = 10.0:
	set(value):
		if not is_finite(value): push_error("HatchScale must be finite."); return
		var next := maxf(value, 0.001)
		if hatch_scale == next: return
		hatch_scale = next
		emit_changed()

@export_range(0.001, 100.0, 0.01, "or_greater") var surface_scale: float = 1.0:
	set(value):
		if not is_finite(value): push_error("SurfaceScale must be finite."); return
		var next := maxf(value, 0.001)
		if surface_scale == next: return
		surface_scale = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var pressure: float = 0.8:
	set(value):
		if not is_finite(value): push_error("Pressure must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if pressure == next: return
		pressure = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var softness: float = 0.3:
	set(value):
		if not is_finite(value): push_error("Softness must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if softness == next: return
		softness = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var taper: float = 0.3:
	set(value):
		if not is_finite(value): push_error("Taper must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if taper == next: return
		taper = next
		emit_changed()

@export_range(0.0, 0.5, 0.01) var roughness: float = 0.1:
	set(value):
		if not is_finite(value): push_error("Roughness must be finite."); return
		var next := clampf(value, 0.0, 0.5)
		if roughness == next: return
		roughness = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var side: float = 0.0:
	set(value):
		if not is_finite(value): push_error("Side must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if side == next: return
		side = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var smudge: float = 0.0:
	set(value):
		if not is_finite(value): push_error("Smudge must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if smudge == next: return
		smudge = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var hatching: float = 0.0:
	set(value):
		if not is_finite(value): push_error("Hatching must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if hatching == next: return
		hatching = next
		emit_changed()

@export_range(0.0, 1.0, 0.01) var crosshatch: float = 0.0:
	set(value):
		if not is_finite(value): push_error("Crosshatch must be finite."); return
		var next := clampf(value, 0.0, 1.0)
		if crosshatch == next: return
		crosshatch = next
		emit_changed()

@export_range(-180.0, 180.0, 0.1, "or_less", "or_greater", "radians_as_degrees") var angle: float = 0.65:
	set(value):
		if not is_finite(value): push_error("Angle must be finite."); return
		var next := value
		if angle == next: return
		angle = next
		emit_changed()

@export var paper_origin: Vector3 = Vector3.ZERO:
	set(value):
		if not (value.is_finite()): push_error("PaperOrigin must be finite."); return
		if paper_origin == value: return
		paper_origin = value
		emit_changed()

@export var paper_u: Vector3 = Vector3.RIGHT:
	set(value):
		if not (value.is_finite()): push_error("PaperU must be finite."); return
		if paper_u == value: return
		paper_u = value
		emit_changed()

@export var paper_v: Vector3 = Vector3.UP:
	set(value):
		if not (value.is_finite()): push_error("PaperV must be finite."); return
		if paper_v == value: return
		paper_v = value
		emit_changed()

@export var paper_color: Color = Color(.94,.92,.86,1):
	set(value):
		if not (is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)): push_error("PaperColor must be finite."); return
		if paper_color == value: return
		paper_color = value
		emit_changed()

static func preset(value: Preset) -> MoldPencilSettings:
	var s := MoldPencilSettings.new()
	match value:
		Preset.HARD_PENCIL:
			s.pressure=0.55
			s.softness=0.05
			s.roughness=0.08
		Preset.SOFT_GRAPHITE:
			s.pressure=0.95
			s.softness=0.45
			s.roughness=0.18
		Preset.SIDE_SHADING:
			s.pressure=0.8
			s.side=1.0
			s.softness=0.65
		Preset.HATCHING:
			s.hatching=1.0
			s.pressure=0.85
			s.taper=0.0
		Preset.CROSSHATCHING:
			s.hatching=1.0
			s.crosshatch=1.0
			s.pressure=1.0
			s.taper=0.0
		Preset.SMUDGED_GRAPHITE:
			s.smudge=1.0
			s.softness=1.0
			s.roughness=0.0
			s.pressure=0.65
		_: assert(false, "Unknown preset")
	return s

func uniforms() -> Dictionary:
	var result := {}
	result["_PencilSeed"]=seed
	result["_PencilPaperSeed"]=paper_seed
	result["_PencilPaperScale"]=paper_scale
	result["_PencilLength"]=length
	result["_PencilHatchScale"]=hatch_scale
	result["_PencilSurfaceScale"]=surface_scale
	result["_PencilPressure"]=pressure
	result["_PencilSoftness"]=softness
	result["_PencilTaper"]=taper
	result["_PencilRoughness"]=roughness
	result["_PencilSide"]=side
	result["_PencilSmudge"]=smudge
	result["_PencilHatching"]=hatching
	result["_PencilCrosshatch"]=crosshatch
	result["_PencilAngle"]=angle
	var u := paper_u.normalized()
	var v := paper_v-u*paper_v.dot(u)
	if u.length_squared()<0.5 or v.length_squared()<1e-8:
		push_error("Paper axes must be nonzero and nonparallel.")
		return {}
	v=v.normalized()
	result["_PencilPaperOrigin"]=Vector4(paper_origin.x,paper_origin.y,paper_origin.z,0)
	result["_PencilPaperU"]=Vector4(u.x,u.y,u.z,0)
	result["_PencilPaperV"]=Vector4(v.x,v.y,v.z,0)
	result["_PencilPaperColor"]=paper_color
	return result

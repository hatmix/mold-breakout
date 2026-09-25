class_name MoldStroke
extends RefCounted
var _thickness := 0.05
var _join := MoldPolyline.Join.MITER
var _cap := MoldPolyline.Cap.BUTT
var _miter_limit := 4.0
var _geometry := MoldPolyline.Geometry.FLAT_2D
var _profile: MoldCurveProfile
var thickness: float:
	get: return _thickness
var join: int:
	get: return _join
var cap: int:
	get: return _cap
var miter_limit: float:
	get: return _miter_limit
var geometry: int:
	get: return _geometry
var profile: MoldCurveProfile:
	get: return _profile
func _init(width := 0.05,join_mode := MoldPolyline.Join.MITER,cap_mode := MoldPolyline.Cap.BUTT,miter := 4.0,geometry_mode := MoldPolyline.Geometry.FLAT_2D,attribute_profile: MoldCurveProfile = null) -> void:
	_thickness=width; _join=join_mode; _cap=cap_mode; _miter_limit=miter; _geometry=geometry_mode; _profile=attribute_profile
func is_valid() -> bool:
	return is_finite(thickness) and thickness>0 and join in [0,1,2] and cap in [0,1,2] and geometry in [0,1] and is_finite(miter_limit) and miter_limit>=1
func equals(other: MoldStroke) -> bool:
	return thickness==other.thickness and join==other.join and cap==other.cap and miter_limit==other.miter_limit and geometry==other.geometry and profile==other.profile

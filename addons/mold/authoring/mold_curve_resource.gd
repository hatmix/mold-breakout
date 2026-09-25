@tool
class_name MoldCurveResource
extends MoldPolylineResource

@export_range(1, 65536, 1, "hide_slider") var curve_subdivisions := 8:
	set(value): curve_subdivisions = clampi(value, 1, 65536); emit_changed()
enum Kind { BEZIER, QUADRATIC_BEZIER, CATMULL_ROM, HERMITE, BSPLINE, NURBS, LINEAR }
@export var kind: Kind = Kind.BEZIER:
	set(value): kind=value; notify_property_list_changed(); emit_changed()
@export var parameterization: MoldCurve.Parameterization = MoldCurve.Parameterization.CENTRIPETAL:
	set(value): parameterization=value; emit_changed()
@export_range(1,32,1) var degree := 3:
	set(value): degree=value; emit_changed()
@export var knot_vector := PackedFloat32Array():
	set(value): knot_vector=value; emit_changed()
@export var adaptive := false:
	set(value): adaptive=value; notify_property_list_changed(); emit_changed()
@export_range(0.000001, 0.1, 0.000001, "or_greater", "hide_slider") var tolerance := 0.001:
	set(value): tolerance=maxf(value, 0.000001) if is_finite(value) else 0.001; emit_changed()
func _init() -> void:
	var a := MoldCurvePointResource.new(); a.position=Vector3(-1,0,0); a.out_offset=Vector3(.5,1,0)
	var b := MoldCurvePointResource.new(); b.position=Vector3(1,0,0); b.in_offset=Vector3(-.5,1,0)
	points=[a,b]
func _handle_knot(index: int) -> MoldBezierKnot:
	var p := points[index] as MoldCurvePointResource
	var incoming := p.in_offset; var outgoing := p.out_offset
	if kind==Kind.HERMITE: incoming/=-3; outgoing/=3
	if p.mode==MoldBezierKnot.HandleMode.AUTO:
		var before := points[index-1].position if index>0 else (points[-1].position if closed else 2*p.position-points[mini(index+1,points.size()-1)].position)
		var after := points[index+1].position if index+1<points.size() else (points[0].position if closed else 2*p.position-points[maxi(index-1,0)].position)
		outgoing=(after-before)/6; incoming=-outgoing
	return MoldBezierKnot.new(p.position,incoming,outgoing)
func handle_position(index: int,role: int) -> Vector3:
	var k := _handle_knot(index)
	return k.position+(k.in_offset if role==1 else k.out_offset if role==2 else Vector3.ZERO)
func move_handle(index: int,role: int,position: Vector3) -> void:
	var p := points[index] as MoldCurvePointResource
	if role==0: p.position=position; return
	var current := _handle_knot(index)
	if p.mode==MoldBezierKnot.HandleMode.AUTO: p.mode=MoldBezierKnot.HandleMode.FREE
	var k := current.move_handle(role==1,position-p.position,p.mode)
	p.in_offset=k.in_offset*-3 if kind==Kind.HERMITE else k.in_offset
	p.out_offset=k.out_offset*3 if kind==Kind.HERMITE else k.out_offset
func to_curve() -> MoldCurve:
	if points.size() < 2:
		push_error("Add at least two curve controls.")
		return null
	for point in points:
		if not point is MoldCurvePointResource:
			push_error("Curve controls must be MoldCurvePointResource.")
			return null
	if kind == Kind.BEZIER:
		var knots: Array[MoldBezierKnot] = []
		for i in points.size(): knots.append(_handle_knot(i))
		return MoldCurve.bezier(knots, closed)
	var positions := PackedVector3Array()
	positions.resize(points.size())
	for i in points.size(): positions[i] = points[i].position
	match kind:
		Kind.LINEAR: return MoldCurve.linear(positions, closed)
		Kind.QUADRATIC_BEZIER: return MoldCurve.quadratic_bezier(positions, closed)
		Kind.CATMULL_ROM: return MoldCurve.catmull_rom(positions, closed, parameterization)
		Kind.HERMITE:
			var incoming := PackedVector3Array()
			var outgoing := PackedVector3Array()
			incoming.resize(points.size())
			outgoing.resize(points.size())
			for i in points.size():
				var knot := _handle_knot(i)
				incoming[i] = -knot.in_offset * 3
				outgoing[i] = knot.out_offset * 3
			return MoldCurve.hermite(positions, incoming, outgoing, closed)
		Kind.BSPLINE: return MoldCurve.bspline(positions, degree, knot_vector, closed)
		Kind.NURBS:
			var weights := PackedFloat32Array()
			weights.resize(points.size())
			for i in points.size(): weights[i] = points[i].weight
			return MoldCurve.nurbs(positions, weights, degree, knot_vector, closed)
	return null
func to_polyline() -> MoldPolyline:
	var c := to_curve()
	if not c: return null
	var settings := MoldCurveSampling.adaptive(tolerance) if adaptive else MoldCurveSampling.fixed(curve_subdivisions)
	if not settings: return null
	var colors := PackedColorArray(); var weights := PackedFloat32Array(); var widths := PackedFloat32Array()
	for point in points: colors.append(point.color); weights.append(point.weight); widths.append(point.thickness)
	var profile := MoldCurveProfile.bake_from_controls(c,kind,colors,widths,weights,settings,point_color_interpolation,degree,knot_vector)
	return c.to_polyline(MoldStroke.new(thickness,join,cap,miter_limit,geometry,profile),settings).with_dash(to_dash())
func _validate_property(property: Dictionary) -> void:
	super._validate_property(property)
	var name := str(property.name)
	if (name=="parameterization" and kind!=Kind.CATMULL_ROM) or (name in ["degree","knot_vector"] and kind not in [Kind.BSPLINE,Kind.NURBS]) or (name=="tolerance" and not adaptive) or (name=="curve_subdivisions" and adaptive): property.usage &= ~PROPERTY_USAGE_EDITOR

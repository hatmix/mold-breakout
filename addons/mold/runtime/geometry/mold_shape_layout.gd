class_name MoldShapeLayout
extends RefCounted


static func resolve(shape: MoldShape) -> Dictionary:
	var result := {}
	resolve_into(shape, result)
	return result


## Reuse a dictionary initialized once with the three layout keys.
static func resolve_into(shape: MoldShape, result: Dictionary) -> void:
	var scale := Vector3.ONE
	var custom := Vector4.ZERO
	match shape.kind:
		MoldShape.Kind.RECTANGLE:
			scale = Vector3(shape.size.x, shape.size.y, 1.0)
			custom = Vector4(2.0 if shape.roundness > 0.0 else 1.0,
				_rectangle_aspect_marker(shape), shape.roundness, 0.0)
		MoldShape.Kind.RECTANGLE_RIM:
			scale = Vector3(shape.size.x, shape.size.y, 1.0)
			# The square-rim shader requires separate X/Y thickness, not an aspect marker.
			if shape.roundness > 0.0 and shape.rectangle_roundness_mode == MoldShape.RectangleRoundnessMode.CORNER_LOCAL:
				custom = Vector4(4.0,
					_rectangle_aspect_marker(shape),
					shape.thickness / minf(shape.size.x, shape.size.y), shape.roundness)
			else:
				custom = Vector4(4.0 if shape.roundness > 0.0 else 3.0,
					shape.thickness / shape.size.x,
					shape.thickness / shape.size.y, shape.roundness)
		MoldShape.Kind.ELLIPSOID:
			scale = shape.size
		MoldShape.Kind.ELLIPSE:
			scale = Vector3(shape.size.x, shape.size.y, 1.0)
			custom = Vector4(5.0, shape.start_radians, 0.0, shape.span_radians)
		MoldShape.Kind.ELLIPSE_RIM:
			scale = Vector3(shape.size.x + shape.thickness, shape.size.y + shape.thickness, 1.0)
			var extent := maxf(scale.x, scale.y)
			custom = Vector4(11.0, shape.size.x/extent, shape.size.y/extent, shape.thickness/extent)
		MoldShape.Kind.DISC:
			scale = Vector3(shape.radius * 2.0, shape.radius * 2.0, 1.0)
			custom = Vector4(5.0, shape.start_radians, 0.0, shape.span_radians)
		MoldShape.Kind.DISC_RIM:
			var disc_rim_outer_radius := shape.rim_outer_radius()
			scale = Vector3(disc_rim_outer_radius * 2.0, disc_rim_outer_radius * 2.0, 1.0)
			custom = Vector4(6.0, shape.start_radians, shape.rim_normalized_thickness(), shape.span_radians)
		MoldShape.Kind.REGULAR_POLYGON:
			scale = Vector3(shape.radius * 2.0, shape.radius * 2.0, 1.0)
			custom = Vector4(8.0 if shape.roundness > 0.0 else 7.0, shape.sides, shape.roundness, 0.0)
		MoldShape.Kind.REGULAR_POLYGON_RIM:
			var polygon_outer_radius := shape.rim_outer_radius()
			scale = Vector3(polygon_outer_radius * 2.0, polygon_outer_radius * 2.0, 1.0)
			custom = Vector4(10.0 if shape.roundness > 0.0 else 9.0, shape.sides, shape.rim_normalized_thickness(), shape.roundness)
		MoldShape.Kind.CUBOID:
			scale = shape.size
		MoldShape.Kind.CYLINDER, MoldShape.Kind.REGULAR_PRISM, MoldShape.Kind.CONE, MoldShape.Kind.PYRAMID:
			scale = Vector3(shape.radius * 2.0, shape.height, shape.radius * 2.0)
		MoldShape.Kind.SPHERE, MoldShape.Kind.HEMISPHERE:
			scale = Vector3.ONE * shape.radius * 2.0
		MoldShape.Kind.CAPSULE:
			var capsule_diameter := shape.radius * 2.0
			scale = Vector3.ONE * capsule_diameter
			custom = Vector4(1.0, shape.height / (capsule_diameter * 2.0) - 1.0, 0.0, 0.0)
		MoldShape.Kind.TORUS:
			var tube_radius := shape.thickness * 0.5
			var outer_diameter := (shape.radius + tube_radius) * 2.0
			var normalized_tube_radius := tube_radius / outer_diameter
			scale = Vector3.ONE * outer_diameter
			custom = Vector4(2.0, normalized_tube_radius, shape.start_radians, shape.span_radians)

	var local_transform := Transform3D(Basis.IDENTITY.scaled_local(scale), Vector3.ZERO)
	if shape.is_line:
		var center := (shape.start_position + shape.end_position) * 0.5
		var delta := shape.end_position - shape.start_position
		if shape.kind == MoldShape.Kind.RECTANGLE:
			if shape.billboard_mode != MoldShape.BillboardMode.FACE_CAMERA:
				delta.z = 0.0
			var length := maxf(delta.length(), 0.0001)
			var basis: Basis
			if shape.billboard_mode == MoldShape.BillboardMode.FACE_CAMERA:
				var direction := delta / length if length > 0.0001 else Vector3.RIGHT
				basis = Basis(Quaternion(Vector3.RIGHT, direction)).scaled_local(Vector3(length, shape.thickness, 1.0))
			else:
				var angle := atan2(delta.y, delta.x)
				basis = Basis(Quaternion(Vector3.BACK, angle)).scaled_local(Vector3(length, shape.thickness, 1.0))
			scale = Vector3(length, shape.thickness, 1.0)
			local_transform = Transform3D(basis, center)
		else:
			var length := maxf(delta.length(), 0.0001)
			var direction := delta / length if length > 0.0001 else Vector3.UP
			var basis := Basis(Quaternion(Vector3.UP, direction)).scaled_local(Vector3(shape.thickness, length, shape.thickness))
			scale = Vector3(shape.thickness, length, shape.thickness)
			local_transform = Transform3D(basis, center)
	if deformation_kind(shape) == 3:
		var shortest := minf(scale.x, minf(scale.y, scale.z))
		var radius := shape.roundness * shortest * (0.25 if shape.kind == MoldShape.Kind.CUBOID else 0.5)
		custom = Vector4(3, radius / scale.x, radius / scale.y, radius / scale.z)
	if deformation_kind(shape) == 4:
		custom = Vector4(4, shape.roundness, scale.y / scale.x, cos(PI / shape.sides))
	result.scale = scale
	result.custom_data = custom
	result.local_transform = local_transform


static func _rectangle_aspect_marker(shape: MoldShape) -> float:
	if shape.roundness <= 0.0 or shape.rectangle_roundness_mode != MoldShape.RectangleRoundnessMode.CORNER_LOCAL:
		return 0.0
	if shape.is_line:
		var delta := shape.end_position - shape.start_position
		if shape.billboard_mode != MoldShape.BillboardMode.FACE_CAMERA:
			delta.z = 0.0
		return -maxf(delta.length(), 0.0001) / maxf(shape.thickness, 0.0001)
	return -shape.size.x / shape.size.y


static func deformation_kind(shape: MoldShape) -> int:
	if shape.kind == MoldShape.Kind.PYRAMID and shape.roundness > 0.0: return 4
	if shape.kind == MoldShape.Kind.CAPSULE: return 1
	if shape.kind == MoldShape.Kind.TORUS: return 2
	if shape.roundness > 0.0 and shape.kind in [MoldShape.Kind.CUBOID, MoldShape.Kind.CYLINDER, MoldShape.Kind.REGULAR_PRISM]: return 3
	return 0

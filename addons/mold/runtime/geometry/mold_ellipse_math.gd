class_name MoldEllipseGeometry
extends RefCounted

## Signed distance and closest-point parameter, in authored units.
static func nearest(point: Vector2, radii: Vector2) -> Vector2:
 var p := point.abs()
 var r := radii
 var swap := r.x < r.y
 if swap:
  r = Vector2(r.y, r.x)
  p = Vector2(p.y, p.x)
 var lo := 0.0
 var hi := PI * .5
 for i in 20:
  var t := (lo + hi) * .5
  var sn := sin(t)
  var cs := cos(t)
  var derivative := (r.y*r.y-r.x*r.x)*sn*cs+r.x*p.x*sn-r.y*p.y*cs
  if derivative < 0.0: lo = t
  else: hi = t
 var t := (lo + hi) * .5
 var q := Vector2(r.x*cos(t), r.y*sin(t))
 if swap: q = Vector2(q.y,q.x)
 q *= Vector2(-1 if point.x < 0 else 1, -1 if point.y < 0 else 1)
 var distance := point.distance_to(q)
 if (point/radii).length_squared() < 1.0: distance = -distance
 return Vector2(distance, atan2(q.x/radii.x,q.y/radii.y))

static func arc_length(r: Vector2, start: float, span: float) -> float:
 start = fposmod(start, TAU)
 return maxf(0.0, primitive(r,start+span)-primitive(r,start))

static func primitive(r: Vector2, angle: float) -> float:
 var quarter := PI*.5
 var turns := floorf(angle/quarter)
 var rest := angle-turns*quarter
 var full := integral(r,quarter)
 return turns*full+(integral(r,rest) if (int(turns)&1)==0 else full-integral(r,quarter-rest))

static func speed(r: Vector2, t: float) -> float:
 return Vector2(r.x*cos(t),r.y*sin(t)).length()

static func integral(r: Vector2, end: float) -> float:
 var half := end*.5
 var total := 0.0
 total += 0.36268378337836*(speed(r,half*(1.0-0.18343464249565))+speed(r,half*(1.0+0.18343464249565)))
 total += 0.31370664587789*(speed(r,half*(1.0-0.52553240991633))+speed(r,half*(1.0+0.52553240991633)))
 total += 0.22238103445337*(speed(r,half*(1.0-0.79666647741363))+speed(r,half*(1.0+0.79666647741363)))
 total += 0.10122853629038*(speed(r,half*(1.0-0.96028985649754))+speed(r,half*(1.0+0.96028985649754)))
 return half*total

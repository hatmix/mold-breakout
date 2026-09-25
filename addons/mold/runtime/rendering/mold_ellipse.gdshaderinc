// Ellipse rim: shape.yz = centerline radii, shape.w = half thickness,
// normalized by the largest outer semiaxis. Nearest point uses a bounded
// first-quadrant solve, including the axis/center cases without division by zero.
vec2 mold_ellipse_nearest(vec2 point, vec2 radii) {
 vec2 p = abs(point), r = radii;
 bool swap_axes = r.x < r.y;
 if (swap_axes) { r = r.yx; p = p.yx; }
 float lo = 0.0, hi = 1.5707963267949;
 for (int i=0; i<20; i++) {
  float t=(lo+hi)*0.5, sn=sin(t), cs=cos(t);
  float derivative=(r.y*r.y-r.x*r.x)*sn*cs+r.x*p.x*sn-r.y*p.y*cs;
  if(derivative<0.0) lo=t; else hi=t;
 }
 float t=(lo+hi)*0.5;
 vec2 q=r*vec2(cos(t),sin(t));
 if(swap_axes) q=q.yx;
 q*=vec2(point.x<0.0?-1.0:1.0,point.y<0.0?-1.0:1.0);
 float distance=length(point-q);
 if(length(point/radii)<1.0) distance=-distance;
 return vec2(distance,atan(q.x/radii.x,q.y/radii.y));
}
float mold_ellipse_speed(vec2 r,float t) { return length(r*vec2(cos(t),sin(t))); }
float mold_ellipse_integral(vec2 r,float end_angle) {
 float half_angle=end_angle*0.5, total=0.0;
 total+=0.36268378337836*(mold_ellipse_speed(r,half_angle*(1.0-0.18343464249565))+mold_ellipse_speed(r,half_angle*(1.0+0.18343464249565)));
 total+=0.31370664587789*(mold_ellipse_speed(r,half_angle*(1.0-0.52553240991633))+mold_ellipse_speed(r,half_angle*(1.0+0.52553240991633)));
 total+=0.22238103445337*(mold_ellipse_speed(r,half_angle*(1.0-0.79666647741363))+mold_ellipse_speed(r,half_angle*(1.0+0.79666647741363)));
 total+=0.10122853629038*(mold_ellipse_speed(r,half_angle*(1.0-0.96028985649754))+mold_ellipse_speed(r,half_angle*(1.0+0.96028985649754)));
 return half_angle*total;
}
float mold_ellipse_primitive(vec2 r,float angle) {
 float quarter=1.5707963267949;
 float turns=floor(angle/quarter), rest=angle-turns*quarter;
 float full=mold_ellipse_integral(r,quarter);
 return turns*full+(mod(turns,2.0)<0.5 ? mold_ellipse_integral(r,rest) : full-mold_ellipse_integral(r,quarter-rest));
}
float mold_ellipse_progress(vec2 r,float angle,float start,float span) {
 float tau=6.2831853071796;
 start=mod(start,tau);
 float delta=mod(angle-start,tau);
 float base=mold_ellipse_primitive(r,start);
 return (mold_ellipse_primitive(r,start+delta)-base)/max(mold_ellipse_primitive(r,start+span)-base,1e-8);
}

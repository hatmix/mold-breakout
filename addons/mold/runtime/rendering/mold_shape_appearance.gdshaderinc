#ifndef MOLD_SHAPE_APPEARANCE
#define MOLD_SHAPE_APPEARANCE
float MoldRoundedDistance(vec2 p,float radius) {
 vec2 q=abs(p)-(vec2(1.0)-vec2(radius));
 return length(max(q,vec2(0.0)))+min(max(q.x,q.y),0.0)-radius;
}
bool MoldShapeIsRim(float kind) {
 return (kind > 2.5 && kind < 4.5) || (kind > 5.5 && kind < 6.5) || kind > 8.5;
}
vec2 MoldShapeBoundary(vec2 uv, vec4 shape) {
 vec2 p=uv*2.0-1.0;
 float along; float across;
 if(shape.x>10.5) {
  vec2 nearest=mold_ellipse_nearest(p*(shape.yz+vec2(shape.w)),shape.yz);
  return vec2(mold_ellipse_progress(shape.yz,nearest.y,0.0,6.28318530718),clamp(-nearest.x/max(shape.w,1e-8),-1.0,1.0));
 }

 if(shape.x<4.5) {
  vec2 rim=p/max(max(abs(p.x),abs(p.y)),0.00001);
  vec2 thickness=shape.y<0.0 ? vec2(shape.z)/local_rectangle_extent(shape.y) : shape.yz;
  along=rectangle_perimeter_progress(rim*0.5+0.5,thickness);
  if(shape.y<0.0) across=local_rectangle_rim_across(uv,shape);
  else {
   float radius=shape.x>3.5?shape.w:0.0;
   vec2 inner_scale=max(vec2(1.0)-2.0*shape.yz,vec2(0.00001));
   float inner_unit=min(inner_scale.x,inner_scale.y);
   float outer_depth=-MoldRoundedDistance(p,radius);
   float inner_radius=clamp(radius/inner_unit,0.0,1.0);
   vec2 q=abs(p/inner_scale)-vec2(1.0-inner_radius);
   vec2 normal=max(q,vec2(0.0));
   normal=length(normal)>0.00001 ? normalize(normal) : (q.x>q.y ? vec2(1,0) : vec2(0,1));
   float inner_distance=MoldRoundedDistance(p/inner_scale,inner_radius)/length(normal/inner_scale);
   across=clamp(2.0*outer_depth/max(outer_depth+inner_distance,0.00001)-1.0,-1.0,1.0);
  }
 } else if(shape.x<6.5) {
  along=atan(p.y,p.x)/MOLD_TAU; across=disc_rim_rim_across(p,shape.z);
 } else {
  float sides=max(shape.y,3.0),sector=MOLD_TAU/sides;
  float angle=atan(p.x,-p.y),edge=floor(angle/sector+.5);
  along=(edge+tan(angle-edge*sector)/(2.0*tan(sector*.5)))/sides;
  across=polygon_rim_across(p,sides,shape.z);
 }
 return vec2(along,across);
}
vec2 MoldBoundaryLoop(float along,float pattern_length) {
 return vec2(cos(along*MOLD_TAU),sin(along*MOLD_TAU))*max(pattern_length,0.001)/MOLD_TAU;
}
#endif

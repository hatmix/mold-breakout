#ifdef MOLD_UI_MATERIAL_PARAMETERS
#define MOLD_UI_PARAMETER uniform
#else
#define MOLD_UI_PARAMETER instance uniform
#endif
// Canvas wrapper; coverage, colors and appearances are shared with spatial rendering.
MOLD_UI_PARAMETER vec4 primary_color = vec4(1.0);
MOLD_UI_PARAMETER vec4 secondary_color = vec4(1.0);
MOLD_UI_PARAMETER vec4 shape_data = vec4(1.0,0.0,0.0,0.0);
MOLD_UI_PARAMETER vec4 dash_data = vec4(0.0);
MOLD_UI_PARAMETER vec4 mold_flags = vec4(0.0,1.0,0.0,33.0);
MOLD_UI_PARAMETER vec4 gradient_data = vec4(0.0,1.0,0.0,16.0);
MOLD_UI_PARAMETER vec4 ui_geometry = vec4(0.0,0.0,0.0,1.0);
MOLD_UI_PARAMETER vec4 ui_extent = vec4(1.0,1.0,0.0,6.28318530718);
MOLD_UI_PARAMETER vec4 ui_bounds = vec4(0.0,0.0,1.0,1.0);
MOLD_UI_PARAMETER vec4 mold_shader_data = vec4(0.0);
MOLD_UI_PARAMETER vec4 mold_shader_data_2 = vec4(0.0);
#define emission_strength mold_flags.x
#define angular_data ui_extent.zw
const float MOLD_TAU = 6.28318530718;
varying float mold_gradient_t;
varying vec4 mold_polyline_coord;
varying vec4 ui_point_color;
varying vec2 ui_position;
varying vec4 ui_tint;
varying float ui_join;
uniform sampler2D ui_vertices : filter_nearest, repeat_disable;
uniform bool ui_linear_output = false;
#include "res://addons/mold/runtime/rendering/mold_evaluation.gdshaderinc"
#include "res://addons/mold/runtime/rendering/mold_polygon.gdshaderinc"
#ifdef MOLD_APPEARANCE
#include "res://addons/mold/runtime/rendering/mold_appearance_uniforms.gdshaderinc"
#ifdef MOLD_PAINT
#include "res://addons/mold/runtime/rendering/mold_paint_stroke.gdshaderinc"
#include "res://addons/mold/runtime/rendering/mold_paint_shape.gdshaderinc"
#else
#include "res://addons/mold/runtime/rendering/mold_pencil_stroke.gdshaderinc"
#include "res://addons/mold/runtime/rendering/mold_pencil_shape.gdshaderinc"
#endif
#endif
vec4 ui_fetch(int index) {
 int width=textureSize(ui_vertices,0).x;
 return texelFetch(ui_vertices,ivec2(index%width,index/width),0);
}
vec3 ui_to_linear(vec3 c) { return mix(pow((max(c,vec3(0.0))+.055)/1.055,vec3(2.4)),c/12.92,lessThanEqual(c,vec3(.04045))); }
vec3 ui_to_srgb(vec3 c) { return mix(1.055*pow(max(c,vec3(0.0)),vec3(1.0/2.4))-.055,c*12.92,lessThanEqual(c,vec3(.0031308))); }
void vertex() {
 ui_tint=COLOR;
 ui_position=VERTEX;
 mold_polygon_position=VERTEX;
 ui_point_color=vec4(1.0);
 ui_join=0.0;
 mold_polyline_coord=vec4(0.0);
 if(ui_geometry.x>.5 && ui_geometry.x<1.5) {
  vec4 row=ui_fetch(VERTEX_ID*2);
  mold_polyline_coord=row;
  ui_point_color=ui_fetch(VERTEX_ID*2+1);
  ui_join=UV.y>=2.0?2.0:0.0;
  if(ui_join>1.5) UV.y-=2.0;
  mold_gradient_t=clamp(UV.x,0.0,1.0);
 } else {
  vec2 local=(UV-.5)*2.0;
  vec2 dir=gradient_data.xy;
  mold_gradient_t=clamp(.5+dot(local,dir)/(2.0*max(abs(dir.x)+abs(dir.y),.00001)),0.0,1.0);
 }
}
void fragment() {
 float coverage;
 vec4 point=ui_point_color;
 bool stroke=ui_geometry.x>.5 && ui_geometry.x<1.5;
 bool polygon=ui_geometry.x>1.5;
 float across=UV.y*2.0-1.0;
 if(polygon) {coverage=mold_polygon_coverage();point=mold_polygon_color(ui_position);}
 else if(stroke) {
  float edge=ui_join>1.5?length(mold_polyline_coord.xy):mold_polyline_coord.y;
  float pixels=polyline_pixel_coverage(edge);
  coverage=min(line_local_aa(edge,pixels),min(polyline_cap_aa(mold_polyline_coord.z,pixels),polyline_cap_aa(mold_polyline_coord.w,pixels)))*clamp(pixels,0.0,1.0);
  if(mold_local_aa_quality()==0) coverage=step(edge,1.0)*step(mold_polyline_coord.z,1.0)*step(mold_polyline_coord.w,1.0);
  coverage*=ui_geometry.w<=0.0?0.0:(ui_geometry.w>=1.0?1.0:dash_aa(ui_geometry.w-UV.x));
  if(ui_geometry.z>.5)point.rgb=oklab_to_linear(point.rgb);
 } else {
  coverage=shape_coverage(UV,shape_data,dash_data);
  if((int(mold_flags.w)&4)!=0)coverage*=dashed_mask(UV.x,across,dash_data);
 }
 vec4 result=evaluated_color(UV,ui_extent.xy)*point;
#ifdef MOLD_APPEARANCE
#ifdef MOLD_PAINT
 if(polygon) MoldPaintFill(ui_position,vec3(0.0),result,coverage);
 else if(stroke || (int(mold_flags.w)&4)!=0) MoldPaintStroke(vec2(UV.x,across),result,coverage);
 else MoldPaintShape(UV,shape_data,result,coverage);
#else
 if(polygon) MoldPencilFill(ui_position,ui_position,result,coverage);
 else if(stroke || (int(mold_flags.w)&4)!=0) MoldPencilStroke(vec2(UV.x,across),ui_position,point.a,result,coverage);
 else MoldPencilShape(UV,shape_data,ui_position,result,coverage);
#endif
#endif
 result.rgb*=ui_linear_output?ui_tint.rgb:ui_to_linear(ui_tint.rgb);
 result.a*=coverage*ui_tint.a;
#if MOLD_UI_BLEND_MODE == 4
 if(result.a<dither_threshold(FRAGCOORD.xy))discard;
 result.a=1.0;
#endif
 vec3 output_rgb=ui_linear_output?result.rgb:ui_to_srgb(result.rgb);
#if MOLD_UI_BLEND_MODE == 3 || MOLD_UI_BLEND_MODE == 8 || MOLD_UI_BLEND_MODE == 11 || MOLD_UI_BLEND_MODE == 13
 output_rgb=mix(vec3(1.0),output_rgb,result.a);
#endif
#ifdef MOLD_UI_PICK
 // Select the authored silhouette, without Paint/Pencil grain or blend artifacts.
 COLOR=vec4(vec3(1.0),coverage*step(.00001,result.a));
#else
 COLOR=vec4(output_rgb,result.a);
#endif
}

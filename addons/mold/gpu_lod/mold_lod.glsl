#[compute]
#version 450
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Source { vec4 source_rows[]; };
layout(set=0,binding=1) uniform sampler2D source_properties;
layout(set=0,binding=2,std430) buffer History { uvec2 history[]; };
layout(set=0,binding=3,std430) buffer Selection { vec4 selection[]; };
layout(set=0,binding=4,std430) writeonly buffer Output { vec4 output_rows[]; };
layout(set=0,binding=5,rgba32f) uniform writeonly image2D output_properties;
layout(set=0,binding=6,std430) buffer Command { uint command[]; };
layout(set=0,binding=7,std430) readonly buffer View { mat4 view_projection; vec4 culling; };
layout(push_constant,std430) uniform Params {
 vec4 origin; vec4 forward; vec4 thresholds; vec4 policy;
 uvec4 dispatch_data; uvec4 mesh_data;
} pc;
vec4 fetch(uint id,uint slot) { uint n=id*7+slot; uint width=uint(textureSize(source_properties,0).x); return texelFetch(source_properties,ivec2(n%width,n/width),0); }
void main() {
 uint id=gl_GlobalInvocationID.x,stage=pc.dispatch_data.x,count=pc.dispatch_data.y,detail=pc.dispatch_data.z,cap=pc.dispatch_data.w;
 if(stage==1) { if(id==0) command[1]=0; return; }
 if(id>=count) return;
 if(stage==0) {
  vec4 a=source_rows[id*3],b=source_rows[id*3+1],c=source_rows[id*3+2];
  float x=length(vec3(a.x,b.x,c.x)),y=length(vec3(a.y,b.y,c.y)),z=length(vec3(a.z,b.z,c.z));
  float radial=max(x,z),diameter=sqrt(radial*radial+y*y); uint kind=pc.mesh_data.x;
  if(kind==8 || kind==9 || kind==11) diameter=max(radial,y);
  if(kind==10) diameter=max(radial,y*max(2*(1+fetch(id,2).y),1));
  if(kind==2) diameter=sqrt(x*x+y*y+z*z);
  float depth=dot(vec3(a.w,b.w,c.w)-pc.origin.xyz,pc.forward.xyz);
  float pixels=max(diameter,.0001)*pc.policy.w*pc.policy.x/max(pc.forward.w*(pc.origin.w>0?1:depth),.0001);
  if(pc.origin.w==0 && depth<=.0001) pixels=0;
  uint primary=cap,secondary=cap; float blend=0;
  if(pc.mesh_data.w!=0) {
  vec4 metadata=fetch(id,6); uint slot=uint(metadata.z),generation=(uint(metadata.x)-1u) | (uint(metadata.y)<<16u);
  uvec2 old=history[slot];
  if(pc.mesh_data.w==1) {
   primary=old.x==generation?min(old.y,cap):cap;
   while(primary<cap && pixels>=pc.thresholds[primary]*(1+pc.policy.y)) primary++;
   while(primary>0 && pixels<pc.thresholds[primary-1]*(1-pc.policy.y)) primary--;
   secondary=primary;
  } else {
   for(uint boundary=0;boundary<cap;boundary++) {
    float low=pc.thresholds[boundary]*(1-pc.policy.z),high=pc.thresholds[boundary]*(1+pc.policy.z);
    if(pixels<low){primary=boundary;secondary=primary;break;}
    if(pixels<=high){
     primary=boundary;secondary=boundary+1;float t=clamp((pixels-low)/max(high-low,.0001),0,1);blend=t*t*(3-2*t);
     if(blend<=.001){secondary=primary;blend=0;} else if(blend>=.999){primary=secondary;blend=0;} break;
    }
   }
  }
  history[slot]=uvec2(generation,primary);
  }
  float visible=1;
  if(culling.y>0) {
   // Conservative sphere contains the transformed template and procedural capsule extension.
   float radius=.5*length(vec3(x,y,z));
   if(kind==10) radius*=max(1,2*(1+fetch(id,2).y));
   radius+=culling.x;
   mat4 rows=transpose(view_projection);vec4 center=vec4(a.w,b.w,c.w,1);
   for(uint axis=0;axis<3;axis++) {
    vec4 low=rows[3]+rows[axis],high=rows[3]-rows[axis];
    if(dot(low,center)<-radius*length(low.xyz) || dot(high,center)<-radius*length(high.xyz)) visible=0;
   }
  }
  selection[id]=vec4(primary,secondary,blend,visible);return;
 }
 vec4 lod=selection[id];if(lod.w==0) return;bool primary=uint(lod.x)==detail,secondary=lod.z>0 && uint(lod.y)==detail;
 if(!primary && !secondary) return;
 uint destination=atomicAdd(command[1],1);
 for(uint row=0;row<3;row++) output_rows[destination*3+row]=source_rows[id*3+row];
 uint width=pc.mesh_data.y;
 for(uint row=0;row<7;row++) {
  vec4 value=fetch(id,row);
  if(row==6 && pc.mesh_data.w!=0) value=vec4(secondary?lod.z:1-lod.z,secondary?1:0,0,6.28318530718);
  uint n=destination*7+row;imageStore(output_properties,ivec2(n%width,n/width),value);
 }
}

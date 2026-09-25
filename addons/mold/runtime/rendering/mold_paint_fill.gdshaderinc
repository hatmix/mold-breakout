#ifndef MOLD_UNITY_PAINT_FILL_INCLUDED
#define MOLD_UNITY_PAINT_FILL_INCLUDED
#include "mold_paint.gdshaderinc"
// A planar pigment field, clipped by the polygon rather than a stroke profile.
void MoldPaintFill(vec2 localPosition,vec3 worldPosition,inout vec4 color,inout float coverage)
{
    float sn,cs;sn=sin(_PaintDirection); cs=cos(_PaintDirection);
    vec2 p=vec2(cs*localPosition.x-sn*localPosition.y,sn*localPosition.x+cs*localPosition.y)*max(_PaintScale,.001);
    p+=_PaintSeed*vec2(7.13,3.71);
    float broad=PaintFilteredNoise(p);
    vec2 bristleUV=p*vec2(.65,max(_PaintBristles*.5,1.0));
    vec2 brokenUV=p*vec2(4.0,13.0)+31.0;
    float pigment=MoldProceduralNoise(bristleUV)*.75+MoldProceduralNoise(brokenUV)*.25;
    float threshold=_PaintDryness*.7;
    float footprint=max(max(length(dFdx(bristleUV)),length(dFdy(bristleUV))),
        max(length(dFdx(brokenUV)),length(dFdy(brokenUV))));
    float gaps=mix(PaintInside(pigment-threshold),saturate(1.0-threshold),smoothstep(.5,1.4,footprint));
    coverage*=gaps;
    color.a*=mix(1.0,.35+broad*.5,_PaintWash);
#if !defined(MOLD_COVERAGE_ONLY)
    float ridge=0.0;
     if(_PaintRidge!=0.0)ridge=clamp(PaintNoiseY(bristleUV).y*.025*max(_PaintBristles*.5,1.0),-.28,.28)*(1.0-smoothstep(.35,1.2,footprint));
    color.rgb*=max(.05,1.0+(broad-.5)*_PaintPigment+_PaintRidge*ridge);
#endif
}
#endif

#define MoldPolygonEffect MoldPaintFill

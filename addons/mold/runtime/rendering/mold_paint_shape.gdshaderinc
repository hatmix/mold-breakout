#ifndef MOLD_UNITY_PAINT_SHAPE_INCLUDED
#define MOLD_UNITY_PAINT_SHAPE_INCLUDED
#include "mold_paint_fill.gdshaderinc"
#include "mold_shape_appearance.gdshaderinc"
void MoldPaintShape(vec2 uv,vec4 shape,inout vec4 color,inout float coverage)
{
    if(!MoldShapeIsRim(shape.x)) {MoldPaintFill(uv-.5,vec3(0.0),color,coverage);return;}
    vec2 stroke=MoldShapeBoundary(uv,shape);
    vec2 loop=MoldBoundaryLoop(stroke.x,_PaintLength);
    vec2 seed=_PaintSeed*vec2(7.13,3.71);
    float broad=PaintFilteredNoise(loop*1.7+seed);
    vec2 bristleUV=loop*.65+vec2(0,stroke.y*max(_PaintBristles*.5,1.0))+seed;
    vec2 brokenUV=loop*4.0+stroke.y*13.0+seed+31.0;
    float footprint=max(max(length(dFdx(bristleUV)),length(dFdy(bristleUV))),
        max(length(dFdx(brokenUV)),length(dFdy(brokenUV))));
    float pigment=MoldProceduralNoise(bristleUV)*.75+MoldProceduralNoise(brokenUV)*.25;
    float threshold=_PaintDryness*.7;
    float gaps=mix(PaintInside(pigment-threshold),saturate(1.0-threshold),smoothstep(.5,1.4,footprint));
    vec2 edgeUV=loop*3.0+seed;
    float edge=1.0-abs(stroke.y)-_PaintRoughness*MoldProceduralNoise(edgeUV);
    float edgeFootprint=max(length(dFdx(edgeUV)),length(dFdy(edgeUV)));
    float meanEdge=1.0-abs(stroke.y)-_PaintRoughness*.5;
    float edgeCoverage=mix(PaintInside(edge),PaintInside(meanEdge),smoothstep(.5,1.4,edgeFootprint));
    coverage*=edgeCoverage*gaps;
    color.a*=mix(1.0,.35+broad*.5,_PaintWash);
#if !defined(MOLD_COVERAGE_ONLY)
    float ridge=0.0;
     if(_PaintRidge!=0.0)ridge=clamp(PaintNoiseY(bristleUV).y*.025*max(_PaintBristles*.5,1.0),-.28,.28)*(1.0-smoothstep(.35,1.2,footprint));
    color.rgb*=max(.05,1.0+(broad-.5)*_PaintPigment+_PaintRidge*ridge);
#endif
}
#endif

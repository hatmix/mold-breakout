#ifndef MOLD_UNITY_PENCIL_SHAPE_INCLUDED
#define MOLD_UNITY_PENCIL_SHAPE_INCLUDED
#include "mold_pencil_fill.gdshaderinc"
#include "mold_shape_appearance.gdshaderinc"
void MoldPencilShape(vec2 uv,vec4 shape,vec2 paperPosition,inout vec4 color,inout float coverage)
{
    if(!MoldShapeIsRim(shape.x)) {MoldPencilFill(uv-.5,paperPosition,color,coverage);return;}
    vec2 stroke=MoldShapeBoundary(uv,shape);
    vec2 loop=MoldBoundaryLoop(stroke.x,_PencilLength);
    float edge=1.0-abs(stroke.y)-_PencilRoughness*PencilNoiseFiltered(loop*7.0+_PencilSeed);
    float profile=pow(saturate(1.0-stroke.y*stroke.y),mix(.12,1.8,_PencilSoftness));
    profile*=mix(1.0,saturate(.55+.45*stroke.y),_PencilSide);
    coverage*=smoothstep(-max(fwidth(edge),.001),max(fwidth(edge),.001),edge)*profile;
    MoldPencilFill(uv-.5,paperPosition,color,coverage);
#if !defined(MOLD_COVERAGE_ONLY)
    color.rgb*=.88+.12*PencilNoiseFiltered(loop*1.3+stroke.y*21.0+_PencilSeed);
#endif
}
#endif

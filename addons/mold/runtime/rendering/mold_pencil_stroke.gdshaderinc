#ifndef MOLD_UNITY_PENCIL_STROKE_INCLUDED
#define MOLD_UNITY_PENCIL_STROKE_INCLUDED
#include "mold_pencil.gdshaderinc"

void MoldPencilStroke(vec2 stroke,vec2 paperPosition,float pointPressure,
    inout vec4 color,inout float coverage)
{
    float u=saturate(stroke.x),v=stroke.y;
    float taper=mix(1.0,smoothstep(0.0,.07,u)*(1.0-.85*smoothstep(.72,1.0,u)),_PencilTaper);
    float pressure=saturate(_PencilPressure*pointPressure*taper);
    float edgeNoise=PencilNoiseFiltered(vec2(u*max(_PencilLength,.001)*7.0,_PencilSeed));
    float edge=1.0-abs(v)-_PencilRoughness*edgeNoise;
    float aa=max(fwidth(edge),.001);
    float profile=pow(saturate(1.0-v*v),mix(.12,1.8,_PencilSoftness));
    profile*=mix(1.0,saturate(.55+.45*v),_PencilSide);
    float deposit=PencilDeposit(paperPosition,pressure);
    coverage*=smoothstep(-aa,aa,edge)*profile*deposit;
    // Point alpha already contributes opacity. Use it for grain contact above,
    // without multiplying it into opacity a second time.
    color.a*=saturate(_PencilPressure*taper)*mix(1.0,.5,_PencilSmudge);
#if !defined(MOLD_COVERAGE_ONLY)
    float scratch=PencilNoiseFiltered(vec2(u*max(_PencilLength,.001)*1.3,v*21.0)+_PencilSeed);
    color.rgb*=.88+.12*scratch;
#endif
}
#endif

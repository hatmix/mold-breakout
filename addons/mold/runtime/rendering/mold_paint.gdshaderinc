#ifndef MOLD_UNITY_PAINT_INCLUDED
#define MOLD_UNITY_PAINT_INCLUDED
// Analytic pigment only: no samplers, lookup textures, screen buffers, or time.


#include "mold_procedural_noise.gdshaderinc"
// Value plus analytic derivative across the bristles. Unlike screen finite
// differences this stays smooth under rotation and at a two-pixel quad boundary.
vec2 PaintNoiseY(vec2 p)
{
    vec2 i=floor(p), t=fract(p), f=t*t*(3.0-2.0*t);
    float a=MoldProceduralHash(i), b=MoldProceduralHash(i+vec2(1,0));
    float c=MoldProceduralHash(i+vec2(0,1)), d=MoldProceduralHash(i+1.0);
    return vec2(mix(mix(a,b,f.x),mix(c,d,f.x),f.y),
        mix(c-a,d-b,f.x)*6.0*t.y*(1.0-t.y));
}
float PaintFilteredNoise(vec2 p)
{
    // Fade to the mean above the pixel footprint, including on distant strokes.
    float visibility = 1.0 - smoothstep(.35, 1.2, max(length(dFdx(p)), length(dFdy(p))));
    return mix(.5, MoldProceduralNoise(p), visibility);
}
float PaintInside(float distance)
{
    float aa = max(fwidth(distance), 1e-4);
    return smoothstep(-aa, aa, distance);
}
#endif

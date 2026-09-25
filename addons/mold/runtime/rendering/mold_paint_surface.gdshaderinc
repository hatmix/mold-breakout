#ifndef MOLD_UNITY_PAINT_SURFACE_INCLUDED
#define MOLD_UNITY_PAINT_SURFACE_INCLUDED
#include "mold_procedural_noise.gdshaderinc"

// Overlapping short brush marks. Neighbor contributions go to zero continuously;
// rotating each mark breaks visible grids while preserving object attachment.
vec3 PaintSurfacePlane(vec2 p)
{
    vec2 cell = floor(p);
    float sum = 0.0, tone = 0.0, height = 0.0;
    float footprint = max(length(dFdx(p)), length(dFdy(p)));
    float frequency = max(_PaintBristles*.45,1.0);
    float ridgeVisibility = 1.0-smoothstep(.3,1.2,footprint*frequency);
     for (int y=-1; y<=1; y++)
     for (int x=-1; x<=1; x++)
    {
        vec2 id = cell + vec2(float(x),float(y));
        float h = MoldProceduralHash(id + _PaintSeed);
        float angle = _PaintDirection + (h-.5)*1.3;
        float sn, cs; sn=sin(angle); cs=cos(angle);
        vec2 q = p - (id + .5 + .3*vec2(h-.5,MoldProceduralHash(id+18.2)-.5));
        q = vec2(cs*q.x-sn*q.y,sn*q.x+cs*q.y);
        float envelope = saturate(1.0 - dot(q*vec2(.95,2.1),q*vec2(.95,2.1)));
        envelope *= envelope;
        float ridge = 0.0;
         if (_PaintRidge != 0.0)
        {
            float phase = q.y*frequency + h*6.28 + sin(q.x*3.0+h)*.4;
            ridge = .5 + .5*sin(phase) * ridgeVisibility;
        }
        sum += envelope;
        tone += envelope*(h-.5);
        height += envelope*ridge;
    }
    float fade = 1.0-smoothstep(.4,1.5,footprint);
    return vec3(tone/max(sum,.001)*fade, height/max(sum,.001)*fade, saturate(sum));
}
void MoldPaintSurface(vec3 localPosition, inout vec4 color)
{
    vec3 localNormal = cross(dFdx(localPosition),dFdy(localPosition));
    localNormal /= max(length(localNormal),1e-12);
    vec3 weights = abs(localNormal)+1e-7;
    weights *= weights;
    weights *= weights;
    weights /= max(dot(weights,vec3(1.0)),1e-20);
    vec3 p = localPosition * max(_PaintScale,.001);
    vec3 field = PaintSurfacePlane(p.yz)*weights.x
        + PaintSurfacePlane(p.zx)*weights.y + PaintSurfacePlane(p.xy)*weights.z;
    float pigment = 1.0 + field.x*_PaintPigment*1.5;
    // Surface wash affects pigment, never cuts holes through a solid object.
    pigment *= 1.0 - _PaintWash*(1.0-field.z)*.25;
    color.rgb *= max(.05,pigment)*(1.0+_PaintRidge*(field.y-.5)*.12);
}
#endif

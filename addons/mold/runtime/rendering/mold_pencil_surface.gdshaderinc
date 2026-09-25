#ifndef MOLD_UNITY_PENCIL_SURFACE_INCLUDED
#define MOLD_UNITY_PENCIL_SURFACE_INCLUDED
#include "mold_pencil.gdshaderinc"

void MoldPencilSurface(vec3 localPosition,inout vec4 color,inout float coverage)
{
    float paperAlpha=saturate(_PencilPaperColor.a);
#if defined(MOLD_COVERAGE_ONLY)
    // Opaque paper has full coverage regardless of graphite. Transparent paper
    // must evaluate the same field in depth, picking, and occupancy passes.
     if(paperAlpha>=1.0)return;
#endif
    vec3 localNormal=cross(dFdx(localPosition),dFdy(localPosition));
    localNormal/=max(length(localNormal),1e-12);
    vec3 weights=abs(localNormal)+1e-6;
    weights*=weights; weights*=weights; weights/=dot(weights,vec3(1.0));
    float pressure=saturate(_PencilPressure);
    vec3 p=localPosition*max(_PencilSurfaceScale,.001);
    float deposit=PencilDeposit(p.yz,pressure)*weights.x
        +PencilDeposit(p.zx,pressure)*weights.y+PencilDeposit(p.xy,pressure)*weights.z;
    float graphite=saturate(deposit*pressure);
    float paper=(1.0-graphite)*paperAlpha;
    float alpha=graphite+paper;
#if !defined(MOLD_COVERAGE_ONLY)
    // Mix premultiplied contributions, then return straight RGB for the selected
    // blend mode. Invisible paper RGB must never tint the graphite.
    color.rgb=(color.rgb*graphite+_PencilPaperColor.rgb*paper)/max(alpha,1e-6);
#endif
    coverage*=alpha;
}
#endif

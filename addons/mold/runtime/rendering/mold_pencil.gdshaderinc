#ifndef MOLD_UNITY_PENCIL_INCLUDED
#define MOLD_UNITY_PENCIL_INCLUDED
// Paper and graphite are arithmetic fields. Neither uses a sampler or time.
#include "mold_procedural_noise.gdshaderinc"
float PencilNoiseFiltered(vec2 p)
{
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    return mix(MoldProceduralNoise(p),.5,smoothstep(.4,1.2,footprint));
}
vec2 PencilPaper(vec3 worldPosition)
{
    vec3 p=worldPosition-_PencilPaperOrigin.xyz;
    return vec2(dot(p,_PencilPaperU.xyz),dot(p,_PencilPaperV.xyz));
}
float PencilTooth(vec2 paper,float pressure)
{
    vec2 p=paper*max(_PencilPaperScale,.001)+_PencilPaperSeed*vec2(3.17,7.93);
    float grain=.25*MoldProceduralNoise(p)+.75*MoldProceduralNoise(p*2.37+19.7);
    float threshold=.66-.48*saturate(pressure);
    float aa=max(fwidth(grain),.025);
    float contact=smoothstep(threshold-aa,threshold+aa,grain)*(.65+.35*grain);
    float footprint=max(length(dFdx(p)),length(dFdy(p)))*2.37;
    // Preserve average graphite at a distance instead of thresholding blurred noise.
    return mix(contact,.825*saturate(.12+pressure*.88),smoothstep(.45,1.4,footprint));
}
float PencilHatchFamily(vec2 paper,float angle,float pressure,float family)
{
    float sn,cs; sn=sin(angle); cs=cos(angle);
    vec2 p=vec2(cs*paper.x-sn*paper.y,sn*paper.x+cs*paper.y);
    float across=p.y*max(_PencilHatchScale,.01);
    float id=floor(across);
    float seed=MoldProceduralHash(vec2(id,family+_PencilSeed));
    float wobble=.10*sin(p.x*3.0+seed*12.0);
    float distance=abs(fract(across)-(.5+(seed-.5)*.22+wobble));
    float halfWidth=mix(.045,.14,saturate(pressure));
    float aa=max(fwidth(across),.001);
    float hatchMask=1.0-smoothstep(halfWidth-aa,halfWidth+aa,distance);
    float breaks=.7+.3*PencilNoiseFiltered(vec2(p.x*5.0,id+_PencilSeed));
    // The mean coverage of each family is twice its half width.
    return mix(hatchMask,2.0*halfWidth,smoothstep(.45,1.3,aa))*breaks;
}
float PencilHatches(vec2 paper,float pressure)
{
    float a=PencilHatchFamily(paper,_PencilAngle,pressure,0);
    // Material-uniform control flow keeps derivatives valid across each quad.
    // Do not branch on pressure: it can vary between neighboring fragments.
     if (_PencilCrosshatch <= 0.0) return a;
    float b=PencilHatchFamily(paper,_PencilAngle+1.15,pressure,17)
        *smoothstep(.25,.65,pressure)*_PencilCrosshatch;
    float c=PencilHatchFamily(paper,_PencilAngle+2.05,pressure,37)
        *smoothstep(.65,1.0,pressure)*_PencilCrosshatch;
    return 1.0-(1.0-a)*(1.0-b)*(1.0-c);
}
float PencilDeposit(vec2 paper,float pressure)
{
    float tooth=PencilTooth(paper,pressure);
    float graphite=mix(tooth,.35+.65*tooth,_PencilSmudge);
     if (_PencilHatching <= 0.0) return graphite;
    return graphite*mix(1.0,PencilHatches(paper,pressure),_PencilHatching);
}
#endif

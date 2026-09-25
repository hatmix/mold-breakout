#ifndef MOLD_UNITY_PROCEDURAL_NOISE_INCLUDED
#define MOLD_UNITY_PROCEDURAL_NOISE_INCLUDED
// Shared arithmetic noise; only procedural effect shaders depend on this file.
float MoldProceduralHash(vec2 p)
{
    vec3 q = fract(vec3(p.xyx) * .1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float MoldProceduralNoise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(MoldProceduralHash(i), MoldProceduralHash(i + vec2(1,0)), f.x),
        mix(MoldProceduralHash(i + vec2(0,1)), MoldProceduralHash(i + 1.0), f.x), f.y);
}
#endif

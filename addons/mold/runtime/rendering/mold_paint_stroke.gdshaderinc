#ifndef MOLD_UNITY_PAINT_STROKE_INCLUDED
#define MOLD_UNITY_PAINT_STROKE_INCLUDED
#include "mold_paint.gdshaderinc"

void MoldPaintStroke(vec2 stroke, inout vec4 color, inout float coverage)
{
    float u = saturate(stroke.x), v = stroke.y;
    float s = u * max(_PaintLength, .001);
    vec2 seed = vec2(_PaintSeed * 7.13, _PaintSeed * 3.71);
    float broad = PaintFilteredNoise(vec2(s * 1.7, v * 2.0) + seed);
    vec2 leftUV = vec2(s * 3.1, 19.2) + seed;
    vec2 rightUV = vec2(s * 2.7, 71.8) + seed;
    float left = MoldProceduralNoise(leftUV);
    float right = MoldProceduralNoise(rightUV);
    float pressure = mix(1.0, (.2 + .8 * smoothstep(0.0,.12,u)) *
        (1.0 - .88 * smoothstep(.55,1.0,u)), _PaintTaper);
    float edge = min(v + pressure - _PaintRoughness * left,
        pressure - v - _PaintRoughness * right);
    vec2 bristleUV = vec2(s * .65, v * max(_PaintBristles*.5,1.0) + (broad-.5)*.8) + seed;
    float footprint = max(length(dFdx(bristleUV)), length(dFdy(bristleUV)));
    vec2 bristleField;
#if defined(MOLD_COVERAGE_ONLY)
    bristleField = vec2(MoldProceduralNoise(bristleUV), 0.0);
#else
     if (_PaintRidge == 0.0)
        bristleField = vec2(MoldProceduralNoise(bristleUV), 0.0);
    else
        bristleField = PaintNoiseY(bristleUV);
#endif
    float bristles = bristleField.x;
    vec2 brokenUV = vec2(s * 4.0, v * 13.0) + seed + 31.0;
    float broken = MoldProceduralNoise(brokenUV);
    footprint = max(footprint,
        max(length(dFdx(brokenUV)), length(dFdy(brokenUV))));
    float pigment = bristles * .75 + broken * .25;
    float dryThreshold = _PaintDryness * (.6 + .25 * u);
    float gaps = PaintInside(pigment - dryThreshold);
    // At subpixel sizes average the missing bristles instead of sparkling cutouts.
    gaps = mix(gaps, saturate(1.0 - dryThreshold), smoothstep(.5,1.4,footprint));
    // Preserve the authored field while it is resolved. Filtering the noise
    // before these thresholds moves dry-brush islands as the camera zooms.
    float edgeFootprint = max(max(length(dFdx(leftUV)), length(dFdy(leftUV))),
        max(length(dFdx(rightUV)), length(dFdy(rightUV))));
    float meanEdge = min(v + pressure - _PaintRoughness * .5,
        pressure - v - _PaintRoughness * .5);
    float edgeCoverage = mix(PaintInside(edge), PaintInside(meanEdge),
        smoothstep(.5, 1.4, edgeFootprint));
    coverage *= edgeCoverage * gaps;
    float loading = mix(1.0, mix(1.15,.35,u), _PaintLoading);
    color.a *= saturate(loading * mix(1.0, .35 + broad*.5, _PaintWash));
#if !defined(MOLD_COVERAGE_ONLY)
    float edgePool = (1.0 - smoothstep(0.0,.25,max(edge,0.0))) * _PaintWash;
    float shade = 1.0 + (broad-.5)*_PaintPigment - edgePool*.45;
    // A directional, derivative-filtered ridge highlight on the planar stroke.
    float bristleVisibility = 1.0-smoothstep(.35,1.2,footprint);
    float slope = bristleField.y * max(_PaintBristles*.5,1.0) * bristleVisibility;
    shade += _PaintRidge * clamp(slope * .025, -.28, .28);
    color.rgb *= max(.05,shade);
#endif
}

#endif

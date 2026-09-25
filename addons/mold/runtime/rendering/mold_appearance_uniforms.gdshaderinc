#ifndef MOLD_APPEARANCE_UNIFORMS
#define MOLD_APPEARANCE_UNIFORMS
float saturate(float value) { return clamp(value,0.0,1.0); }
#ifdef MOLD_PAINT
uniform float _PaintSeed = 0.0;
uniform float _PaintLength = 0.0;
uniform float _PaintBristles = 0.0;
uniform float _PaintRoughness = 0.0;
uniform float _PaintDryness = 0.0;
uniform float _PaintTaper = 0.0;
uniform float _PaintLoading = 0.0;
uniform float _PaintPigment = 0.0;
uniform float _PaintWash = 0.0;
uniform float _PaintRidge = 0.0;
uniform float _PaintScale = 0.0;
uniform float _PaintDirection = 0.0;
#endif
#ifdef MOLD_PENCIL
uniform float _PencilSeed = 0.0;
uniform float _PencilPaperSeed = 0.0;
uniform float _PencilPaperScale = 0.0;
uniform float _PencilPressure = 0.0;
uniform float _PencilSoftness = 0.0;
uniform float _PencilRoughness = 0.0;
uniform float _PencilTaper = 0.0;
uniform float _PencilSide = 0.0;
uniform float _PencilSmudge = 0.0;
uniform float _PencilHatching = 0.0;
uniform float _PencilCrosshatch = 0.0;
uniform float _PencilHatchScale = 0.0;
uniform float _PencilAngle = 0.0;
uniform float _PencilLength = 0.0;
uniform float _PencilSurfaceScale = 0.0;
uniform vec4 _PencilPaperOrigin = vec4(0.0);
uniform vec4 _PencilPaperU = vec4(0.0);
uniform vec4 _PencilPaperV = vec4(0.0);
uniform vec4 _PencilPaperColor : source_color = vec4(0.0);
#endif
#endif

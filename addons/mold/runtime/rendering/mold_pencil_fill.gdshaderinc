#ifndef MOLD_UNITY_PENCIL_FILL_INCLUDED
#define MOLD_UNITY_PENCIL_FILL_INCLUDED
#include "mold_pencil.gdshaderinc"
void MoldPencilFill(vec2 localPosition,vec2 paperPosition,inout vec4 color,inout float coverage)
{
    coverage*=PencilDeposit(paperPosition,saturate(_PencilPressure));
    color.a*=saturate(_PencilPressure)*mix(1.0,.5,_PencilSmudge);
}
#endif

#define MoldPolygonEffect MoldPencilFill

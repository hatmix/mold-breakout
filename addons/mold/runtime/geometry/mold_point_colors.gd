class_name MoldPointColors
extends RefCounted

static func convert(c: Color,interpolation: int,inverse: bool) -> Color:
	if interpolation==0: return c
	var r := c.r; var g := c.g; var b := c.b
	if not inverse:
		var l := .4122214708*r+.5363325363*g+.0514459929*b
		var m := .2119034982*r+.6806995451*g+.1073969566*b
		var s := .0883024619*r+.2817188376*g+.6299787005*b
		l=signf(l)*pow(absf(l),1.0/3); m=signf(m)*pow(absf(m),1.0/3); s=signf(s)*pow(absf(s),1.0/3)
		return Color(.2104542553*l+.793617785*m-.0040720468*s,1.9779984951*l-2.428592205*m+.4505937099*s,.0259040371*l+.7827717662*m-.808675766*s,c.a)
	var l := r+.3963377774*g+.2158037573*b
	var m := r-.1055613458*g-.0638541728*b
	var s := r-.0894841775*g-1.291485548*b
	l*=l*l; m*=m*m; s*=s*s
	return Color(4.0767416621*l-3.3077115913*m+.2309699292*s,-1.2684380046*l+2.6097574011*m-.3413193965*s,-.0041960863*l-.7034186147*m+1.707614701*s,c.a)

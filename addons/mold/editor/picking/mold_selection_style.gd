@tool
extends RefCounted
## Logical pixel widths; apply editor scale once at the rendering boundary.
const HOVER_WIDTH := 1.5
const SELECTED_WIDTH := 1.0
const HOVER_COLOR := Color(0.2, 0.85, 1.0)
const SELECTED_COLOR := Color(1.0, 0.7, 0.15)

static func width(chosen: bool) -> float:
 return (SELECTED_WIDTH if chosen else HOVER_WIDTH)*EditorInterface.get_editor_scale()

static func color(chosen: bool) -> Color:
 return SELECTED_COLOR if chosen else HOVER_COLOR

@tool
extends VBoxContainer

var subject: Resource
var undo: EditorUndoRedoManager
var _updating := false
var _queued := false
var _folds: Dictionary = {}
static var _saved_folds: Dictionary = {}
static var _fold_owners: Dictionary = {}
var _connections: Array[Resource] = []
var _targets: Array[Resource] = []
var _binders: Array[Callable] = []
var _layout := ""
var _selection_nodes: Array[Node] = []

const Properties = preload("../mold_editor_properties.gd")

func setup_many(values: Array[Resource], nodes: Array[Node], manager: EditorUndoRedoManager) -> void:
	_targets=values
	_selection_nodes=nodes
	setup(values[0],manager)
func setup(value: Resource, manager: EditorUndoRedoManager) -> void:
	subject=value
	for key in _fold_owners.keys():
		if _fold_owners[key].get_ref()==null:_fold_owners.erase(key);_saved_folds.erase(key)
	var id := subject.get_instance_id()
	_folds=_saved_folds.get(id,{})
	_saved_folds[id]=_folds;_fold_owners[id]=weakref(subject)
	undo=manager
	_build()
func _notification(what: int) -> void:
	if what==NOTIFICATION_RESIZED: call_deferred("_align_rows")
func _align_rows() -> void:
	for label in find_children("*","Label",true,false):
		if label.has_meta("mold_field_label"): label.custom_minimum_size.x=maxf(110,size.x*.42)
func _exit_tree() -> void:
	_disconnect()
func _disconnect() -> void:
	for resource in _connections:
		if is_instance_valid(resource) and resource.changed.is_connected(_changed): resource.changed.disconnect(_changed)
	_connections.clear()
func _changed() -> void:
	if _queued: return
	_queued=true
	call_deferred("_refresh")
func _layout_key() -> String:
	var style: Resource = subject if not Properties.field(subject,"appearance").is_empty() else null
	var signature: Array = [_context(style)]
	# Layout depends on every selected resource, including replacements and mixed states.
	var targets: Array = _targets if not _targets.is_empty() else [subject]
	for target in targets:
		var appearance: Resource = Properties.read(target,"appearance") if style else target
		signature.append([target, Properties.read(target,"mode"), Properties.read(target,"color_mode"),
			appearance, Properties.read(appearance,"kind"), Properties.read(appearance,"automatic_length"),
			Properties.read(appearance,"paint"), Properties.read(appearance,"pencil")])
	for node in _selection_nodes:
		signature.append(Properties.read(node,"appearance_mode"))
	return str(signature)

func _refresh() -> void:
	_queued=false
	if _layout != _layout_key(): _build(); return
	_updating=true
	for update in _binders: update.call()
	_updating=false

func _watch(resource: Resource) -> void:
	if resource and not resource.changed.is_connected(_changed):
		resource.changed.connect(_changed)
		_connections.append(resource)
func _build() -> void:
	_queued=false
	_updating=true
	_disconnect()
	_binders.clear()
	_layout=_layout_key()
	for child in get_children(): remove_child(child); child.queue_free()
	_watch(subject)
	for target in _targets:
		_watch(target)
		var a: Resource = Properties.read(target,"appearance")
		_watch(a)
		_watch(Properties.read(a,"paint"));_watch(Properties.read(a,"pencil"))
	var style: Resource = subject if not Properties.field(subject,"appearance").is_empty() else null
	var appearance: Resource = Properties.read(style,"appearance") if style else subject
	var context := _context(style)
	if style:
		var colors := _group("Blend and Color")
		_choice(colors,style,"mode","Blend Mode",["Opaque","Transparent","Additive","Multiplicative","Dither","Custom","Subtractive","Linear Burn","Screen","Lighten","Darken","Color Dodge","Color Burn"],[0,1,2,3,4,6,7,8,9,10,11,12,13])
		var custom: bool = Properties.read(style,"mode",0)==6
		if not custom and not _mixed(style,"mode"):
			var path: bool = context.linear_color
			_choice(colors,style,"color_mode","Color Mode",["Single","Dual Directional"] if path or context.polygon else ["Single","Dual Directional","Dual Radial","Dual Radial Bounds","Dual Angular"])
		_value(colors,style,"color","Primary Color")
		if _mixed(style,"mode"):
			_updating=false
			return
		if custom:
			var picker := EditorResourcePicker.new()
			picker.base_type="ShaderMaterial"
			picker.edited_resource=Properties.read(style,"custom_material")
			picker.resource_changed.connect(func(value): _commit(style,"custom_material",value))
			colors.add_child(picker)
			_binders.append(func():
				picker.edited_resource=null if _mixed(style,"custom_material") else Properties.read(style,"custom_material")
				picker.tooltip_text="Multiple materials" if _mixed(style,"custom_material") else "Custom Material")
			_binders[-1].call()
			_value(colors,style,"shader_data","Shader Data")
			_value(colors,style,"shader_data_2","Shader Data 2")
			_updating=false
			return
		if not _mixed(style,"color_mode") and Properties.read(style,"color_mode",0)!=0:
			_value(colors,style,"secondary_color","Secondary Color")
			_choice(colors,style,"style_color_interpolation","Style Color Interpolation",["Linear RGB","Oklab"])
			_value(colors,style,"emission_strength","Emission Strength")
		if not _mixed(style,"color_mode") and Properties.read(style,"color_mode",0)==1 and (not context.path or context.polygon):
			_value(colors,style,"gradient_direction","Gradient Direction")
			if context.canvas:
				var space_label:=Label.new()
				space_label.text="Object (Canvas)"
				space_label.tooltip_text="Native UI evaluates gradients in local coordinates. The shared style resource keeps its world-renderer setting."
				_row(colors,"Gradient Space").add_child(space_label)
			else:
				_choice(colors,style,"gradient_space","Gradient Space",["World","Object"])
	if not appearance:
		var empty := Label.new();empty.text="Assign an Appearance resource to edit effects.";add_child(empty)
		_updating=false;return
	_watch(appearance)
	var header := _group("Appearance")
	_choice(header,appearance,"kind","Appearance",["Standard","Paint","Pencil"])
	var kind: int = Properties.read(appearance,"kind",0)
	if kind==0 or _mixed(appearance,"kind"): _updating=false; return
	if context.polygon and context.node:
		_choice(header,context.node,"appearance_mode","Appearance Mode",["Fill","Outline","Fill And Outline"])
		if not _mixed(context.node,"appearance_mode") and Properties.read(context.node,"appearance_mode",0)!=0: _value(header,context.node,"outline_width","Outline Width")
	var paint: bool = kind==1
	var settings: Resource = Properties.read(appearance,"paint" if paint else "pencil")
	_watch(settings)
	var presets := ["Ragged","Dry Brush","Ink","Acrylic","Watercolor","Impasto"] if paint else ["Hard Pencil","Soft Graphite","Side Shading","Hatching","Crosshatching","Smudged Graphite"]
	_choice(header,appearance,"paint_preset" if paint else "pencil_preset","Preset",presets,[],true)
	var apply := Button.new();apply.text="Apply Preset";apply.pressed.connect(func(): _preset(appearance,int(Properties.read(appearance,"paint_preset" if paint else "pencil_preset",0))));header.add_child(apply)
	var path: bool = context.path or context.all
	var fill: bool = context.fill or context.all
	var surface: bool = context.surface or context.all
	var boundary: bool = context.boundary
	if paint:
		var pattern := _group("Pattern")
		_value(pattern,settings,"seed","Seed")
		_length(pattern,appearance,settings,path,context.canvas)
		var brush := _group("Brush")
		_value(brush,settings,"bristles","Bristles")
		if path: _value(brush,settings,"roughness","Roughness")
		if path or fill: _value(brush,settings,"dryness","Dryness")
		if path and not boundary:
			_value(brush,settings,"taper","Taper")
			_value(brush,settings,"loading","Loading")
		var pigment := _group("Pigment")
		for name in ["pigment","wash","ridge"]: _value(pigment,settings,name,name.capitalize())
		if fill or surface:
			var mapping := _group("Fill / Surface Mapping")
			_value(mapping,settings,"surface_scale","Surface Scale" if context.surface else "Fill Scale")
			_value(mapping,settings,"surface_direction","Surface Direction" if context.surface else "Fill Direction")
	else:
		var graphite := _group("Graphite")
		_value(graphite,settings,"pressure","Pressure")
		if path:
			for name in ["softness","roughness","taper","side"]:
				if name=="taper" and boundary: continue
				_value(graphite,settings,name,name.capitalize())
		_value(graphite,settings,"smudge","Smudge")
		var pattern := _group("Stroke Pattern")
		_value(pattern,settings,"seed","Seed")
		_length(pattern,appearance,settings,path,context.canvas)
		var paper := _group("Paper")
		_value(paper,settings,"paper_seed","Paper Seed")
		_value(paper,settings,"paper_scale","Paper Scale")
		if surface: _value(paper,settings,"paper_color","Paper Color")
		var hatch := _group("Hatching")
		for name in ["hatching","crosshatch","hatch_scale","angle"]: _value(hatch,settings,name,name.capitalize())
		if path or fill:
			var frame := _group("Paper Frame",false)
			for name in ["paper_origin","paper_u","paper_v"]: _value(frame,settings,name,name.capitalize())
		if surface: _value(_group("Surface Mapping"),settings,"surface_scale","Surface Scale")
	_updating=false

func _node_context(node: Node) -> Dictionary:
	var context := {"all":false,"path":false,"fill":false,"surface":false,"boundary":false,"linear_color":false,"polygon":false,"canvas":false,"node":node}
	var script: Script=node.get_script()
	context.canvas=node is Control and script!=null and ("/ui/mold_" in script.resource_path or "/UI/Mold" in script.resource_path)
	if not Properties.field(node,"polygon").is_empty():
		context.polygon=true
		var mode: int = Properties.read(node,"appearance_mode",0)
		context.path=mode!=0;context.fill=mode!=1
	elif not Properties.field(node,"polyline").is_empty() or not Properties.field(node,"curve").is_empty(): context.path=true;context.linear_color=true
	else:
		var shape: Resource = Properties.read(node,"shape")
		_watch(shape)
		var kind: int = Properties.read(shape,"kind",0)
		context.surface=kind>=100
		var kind_name := Properties.enum_name(shape,"kind")
		context.boundary=kind_name in ["rectanglerim","discrim","regularpolygonrim","ellipserim"]
		context.path=not context.surface and (context.boundary or Properties.read(shape,"line_enabled",false))
		context.fill=not context.surface and not context.path
		context.linear_color=kind_name in ["rectangle","cylinder"] and Properties.read(shape,"line_enabled",false)
	return context
func _context(style: Resource) -> Dictionary:
	var context := {"all":true,"path":false,"fill":false,"surface":false,"boundary":false,"linear_color":false,"polygon":false,"canvas":false,"node":null}
	if not style: return context
	if not _selection_nodes.is_empty():
		context=_node_context(_selection_nodes[0])
		for node in _selection_nodes.slice(1):
			var other := _node_context(node)
			for key in ["path","fill","surface","polygon","canvas"]: context[key]=context[key] and other[key]
			context.boundary=context.boundary or other.boundary
			context.linear_color=context.linear_color or other.linear_color
		return context
	var inspected:=EditorInterface.get_inspector().get_edited_object()
	if inspected is Node and Properties.read(inspected,"style")==style:return _node_context(inspected)
	for node in EditorInterface.get_selection().get_selected_nodes():
		if Properties.read(node,"style")==style:
			context=_node_context(node)
			context.canvas=context.canvas and EditorInterface.get_inspector().get_edited_object()==node
			return context
	return context
func _objects(object: Object) -> Array[Object]:
	var result: Array[Object] = []
	if _targets.is_empty(): result.append(object);return result
	var origin: Resource = Properties.read(subject,"appearance")
	for target in _targets:
		var other: Object = target
		var appearance: Resource = Properties.read(target,"appearance")
		if object==origin: other=appearance
		elif object==Properties.read(origin,"paint"): other=Properties.read(appearance,"paint")
		elif object==Properties.read(origin,"pencil"): other=Properties.read(appearance,"pencil")
		elif object is Node: continue
		if other and not result.has(other): result.append(other)
	if object is Node:
		for node in _selection_nodes: result.append(node)
	return result
func _mixed(object: Object, name: String) -> bool:
	for other in _objects(object):
		if Properties.read(other,name)!=Properties.read(object,name): return true
	return false
func _revert(row: Control, object: Object, name: String) -> void:
	var key := Properties.field(object,name)
	var script: Script = object.get_script()
	var initial: Variant = object.property_get_revert(key) if object.property_can_revert(key) else (script.get_property_default_value(key) if script else null)
	if initial == null: return
	var button := Button.new();button.text="↶";button.flat=true;button.tooltip_text="Revert "+name.capitalize();row.add_child(button)
	button.pressed.connect(func(): _commit(object,name,initial))
	var update := func(): button.disabled=not _mixed(object,name) and Properties.read(object,name)==initial
	_binders.append(update);update.call()

func _group(title: String, expanded := true) -> VBoxContainer:
	var button := Button.new();button.text=title;button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.toggle_mode=true;button.button_pressed=_folds.get(title,expanded);add_child(button)
	var box := VBoxContainer.new();box.visible=button.button_pressed;add_child(box)
	button.toggled.connect(func(on): box.visible=on;_folds[title]=on)
	return box
func _row(parent: Control, title: String) -> HBoxContainer:
	var row := HBoxContainer.new();parent.add_child(row)
	var label := Label.new();label.text=title;label.size_flags_horizontal=0;label.set_meta("mold_field_label",true);label.custom_minimum_size.x=maxf(110,size.x*.42);row.add_child(label)
	return row
func _length(parent: Control, appearance: Resource, settings: Resource, enabled: bool, canvas: bool) -> void:
	if not enabled: return
	if canvas:
		_value(parent,settings,"length","Length")
		return
	_value(parent,appearance,"automatic_length","Automatic Length")
	if not _mixed(appearance,"automatic_length") and not Properties.read(appearance,"automatic_length",true): _value(parent,settings,"length","Length")
func _choice(parent: Control, object: Object, name: String, label: String, options: Array, ids: Array = [], preset := false) -> void:
	if Properties.field(object,name).is_empty(): return
	var picker := OptionButton.new();picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for i in options.size():
		var id: int = ids[i] if not ids.is_empty() else i
		if name=="mode" and id==6 and (_context(subject).canvas or _context(subject).polygon or _selection_nodes.any(func(node): return _node_context(node).canvas or not Properties.field(node,"polygon").is_empty())): continue
		picker.add_item(options[i],id)
	var update := func(): picker.select(-1 if _mixed(object,name) else picker.get_item_index(int(Properties.read(object,name,0))))
	_binders.append(update);update.call()
	picker.item_selected.connect(func(index):
		if preset: _preset(object,picker.get_item_id(index))
		else: _commit(object,name,picker.get_item_id(index)))
	var row := _row(parent,label);row.add_child(picker);_revert(row,object,name)
func _value(parent: Control, object: Object, name: String, label: String) -> void:
	var key := Properties.field(object,name)
	if key.is_empty(): return
	var value: Variant = object.get(key)
	var row := _row(parent,label)
	var mixed_label := row.get_child(0) as Label
	var update_label := func(): mixed_label.text=label+(" —" if _mixed(object,name) else "")
	_binders.append(update_label);update_label.call()
	row.tooltip_text={"automatic_length":"Use authored local path length or full rim perimeter; transform scaling stretches the pattern.","length":"Longitudinal grain units along the authored path.","paper_origin":"World-space origin of the sheet. Move the frame with the sheet, or leave it fixed to expose new grain when strokes move.","paper_u":"First nonzero axis of the shared paper plane.","paper_v":"Second paper axis; must not be parallel to Paper U. Normalized and orthogonalized at resolution.","pressure":"Controls paper contact and graphite opacity. Point alpha adds pressure independently of style alpha.","paper_color":"Surface-only paper color and opacity; alpha zero leaves only graphite.","angle":"Hatch angle in degrees (stored in radians).","surface_direction":"Brush direction in degrees (stored in radians)."}.get(name,"")
	if value is bool:
		var toggle := CheckBox.new();toggle.button_pressed=value;toggle.toggled.connect(func(v): _commit(object,name,v));row.add_child(toggle)
		_binders.append(func(): toggle.set_pressed_no_signal(Properties.read(object,name)))
	elif value is Color:
		var picker := ColorPickerButton.new();picker.color=value;picker.edit_alpha=true;picker.edit_intensity=true;picker.size_flags_horizontal=SIZE_EXPAND_FILL
		picker.color_changed.connect(func(v): _commit(object,name,v));row.add_child(picker)
		_binders.append(func(): picker.color=Properties.read(object,name))
	elif value is Vector3 or value is Vector4:
		for axis in (4 if value is Vector4 else 3):
			var input := SpinBox.new();input.allow_greater=true;input.allow_lesser=true;input.step=.01;input.value=value[axis];input.size_flags_horizontal=SIZE_EXPAND_FILL
			input.value_changed.connect(func(v):
				_commit_axis(object,name,axis,v))
			row.add_child(input)
			_binders.append(func(): input.set_value_no_signal(Properties.read(object,name)[axis]))
	else:
		var input := SpinBox.new();input.step=.01;input.allow_greater=true;input.allow_lesser=true
		var hints := PackedStringArray()
		for property in object.get_property_list():
			if property.name==key and property.hint==PROPERTY_HINT_RANGE:
				hints = property.hint_string.split(",")
				for i in hints.size(): hints[i] = hints[i].strip_edges()
				input.min_value=float(hints[0]);input.max_value=float(hints[1])
				input.step=float(hints[2]) if hints.size()>2 and hints[2].is_valid_float() else .01
				input.allow_lesser="or_less" in hints;input.allow_greater="or_greater" in hints
		var radians := "radians_as_degrees" in hints
		if radians or "degrees" in hints: input.suffix="°"
		for hint in hints:
			if hint.begins_with("suffix:"): input.suffix=hint.trim_prefix("suffix:")
		var display := func(v): return rad_to_deg(float(v)) if radians else float(v)
		var commit := func(v): _commit(object,name,deg_to_rad(v) if radians else v)
		input.value=display.call(value);input.size_flags_horizontal=SIZE_EXPAND_FILL
		if not input.allow_greater and not input.allow_lesser and not "hide_slider" in hints:
			var slider := HSlider.new();slider.min_value=input.min_value;slider.max_value=input.max_value;slider.step=input.step;slider.value=input.value;slider.size_flags_horizontal=SIZE_EXPAND_FILL
			slider.value_changed.connect(commit);row.add_child(slider)
			_binders.append(func(): slider.set_value_no_signal(display.call(Properties.read(object,name))))
		input.custom_minimum_size.x=76
		input.value_changed.connect(commit);row.add_child(input)
		_binders.append(func(): input.set_value_no_signal(display.call(Properties.read(object,name))))
	_revert(row,object,name)
func _commit_axis(object: Object, name: String, axis: int, value: float) -> void:
	if _updating or not is_finite(value): return
	undo.create_action("Set "+name.capitalize(),UndoRedo.MERGE_ENDS,object)
	for other in _objects(object):
		var vector: Variant = Properties.read(other,name);var previous: Variant = vector;vector[axis]=value
		undo.add_do_property(other,Properties.field(other,name),vector);undo.add_undo_property(other,Properties.field(other,name),previous)
	undo.commit_action()
func _commit(object: Object, name: String, value: Variant) -> void:
	if _updating or (value is float and not is_finite(value)): return
	var key := Properties.field(object,name)
	if key.is_empty() or (object.get(key)==value and not _mixed(object,name)): return
	undo.create_action("Set "+name.capitalize(),UndoRedo.MERGE_ENDS,object)
	for other in _objects(object):
		var other_key := Properties.field(other,name)
		if other_key.is_empty(): continue
		undo.add_do_property(other,other_key,value)
		undo.add_undo_property(other,other_key,other.get(other_key))
	undo.commit_action()
	_changed()
func _preset(appearance: Resource, index: int) -> void:
	var paint: bool = Properties.read(appearance,"kind")==1
	var settings_name := "paint" if paint else "pencil"
	undo.create_action("Apply "+("Paint" if paint else "Pencil")+" Preset",UndoRedo.MERGE_DISABLE,appearance)
	for target in _objects(appearance):
		var old: Resource = Properties.read(target,settings_name)
		var script: Script = old.get_script()
		var replacement: Resource = script.preset(index) if script.resource_path.ends_with(".gd") else old.call("PresetResource",index)
		var preset_key := Properties.field(target,settings_name+"_preset")
		var settings_key := Properties.field(target,settings_name)
		undo.add_do_property(target,preset_key,index);undo.add_undo_property(target,preset_key,target.get(preset_key))
		undo.add_do_property(target,settings_key,replacement);undo.add_undo_property(target,settings_key,old)
	undo.commit_action();_changed()

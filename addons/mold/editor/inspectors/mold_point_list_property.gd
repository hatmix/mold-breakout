@tool
extends EditorProperty

var state
var box := VBoxContainer.new()
var cached_points: Array = []
var cached_spatial := false
var cached_kind := -2
var cached_closed := false
var controls := []
func _init(editor):
	state = editor
	add_child(box); add_focusable(box)
	set_bottom_editor(box)
func _update_property() -> void:
	var owner: Resource = get_edited_object()
	if not owner: return
	var points = owner.get(get_edited_property())
	var curve: bool = state.curve_resource(owner)
	var kind: int = owner.get(state.resource_field(owner,"kind","Kind")) if curve else -1
	var closed: bool = owner.get(state.resource_field(owner,"closed","Closed")) if curve else false
	var polygon: bool = state.polygon_resource(owner)
	var spatial: bool = polygon or owner.get(state.resource_field(owner,"geometry","Geometry")) == 1
	var point_count: int = points.size()
	var rebuild := cached_spatial != spatial or cached_kind != kind or cached_closed != closed or cached_points.size() != point_count
	if not rebuild:
		for i in point_count:
			if cached_points[i] != points[i]: rebuild=true; break
	if rebuild:
		cached_points = points.duplicate()
		cached_spatial=spatial; cached_kind=kind; cached_closed=closed
		for child in box.get_children(): box.remove_child(child); child.queue_free()
		controls.clear()
		for i in point_count:
			var point: Resource = points[i]
			var row := HBoxContainer.new(); box.add_child(row)
			var label := Label.new(); label.text = str(i); row.add_child(label)
			for axis in 3:
				var spin := SpinBox.new(); spin.step=0.01; spin.allow_greater=true; spin.allow_lesser=true
				spin.prefix=["X","Y","Z"][axis]; spin.editable=point!=null and (axis!=2 or spatial)
				spin.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(spin)
				controls.append([spin,point,"position",axis])
				spin.value_changed.connect(func(value):
					var key: String = state.resource_field(owner,"position","Position")
					var p: Vector3 = point.get(key); p[axis]=value
					state.edit_point_field(owner,point,key,p))
			var details := HBoxContainer.new(); box.add_child(details)
			if point:
				var color := ColorPickerButton.new(); color.custom_minimum_size=Vector2(32,24); color.edit_alpha=true; color.edit_intensity=true; color.tooltip_text="Point color"; row.add_child(color)
				var closing_color := curve and kind==1 and closed and i==point_count-1
				var color_point = points[0] if closing_color else point
				color.disabled=closing_color
				if closing_color: color.tooltip_text="Closing endpoint shares the first point color"
				controls.append([color,color_point,"color",0])
				color.color_changed.connect(func(value): state.edit_point_field(owner,color_point,state.resource_field(owner,"color","Color"),value))
				if not polygon:
					var width := SpinBox.new(); width.min_value=0.0; width.max_value=10; width.allow_greater=true; width.step=0.01; width.prefix="T"; width.tooltip_text="Point thickness multiplier"; width.custom_minimum_size.x=64; row.add_child(width)
					width.editable=not closing_color
					if closing_color: width.tooltip_text="Closing endpoint shares the first point thickness"
					controls.append([width,color_point,"thickness",0])
					width.value_changed.connect(func(value): state.edit_point_field(owner,color_point,state.resource_field(owner,"thickness","Thickness"),value))
				if curve and kind in [0,3,5]:
					var settings_row := HBoxContainer.new(); box.add_child(settings_row)
					if kind in [0,3]:
						var mode := OptionButton.new(); mode.tooltip_text="Handle mode"; mode.size_flags_horizontal=Control.SIZE_EXPAND_FILL; settings_row.add_child(mode)
						for mode_label in ["Free","Aligned","Mirrored","Auto"]: mode.add_item(mode_label)
						controls.append([mode,point,"mode",0])
						mode.item_selected.connect(func(value): state.edit_point_field(owner,point,state.resource_field(owner,"mode","Mode"),value))
					if kind == 5:
						var weight := SpinBox.new(); weight.min_value=0.000001; weight.max_value=10; weight.allow_greater=true; weight.step=0.000001; weight.prefix="Weight"; weight.size_flags_horizontal=Control.SIZE_EXPAND_FILL; settings_row.add_child(weight)
						controls.append([weight,point,"weight",0])
						weight.value_changed.connect(func(value): state.edit_point_field(owner,point,state.resource_field(owner,"weight","Weight"),value))
			for operation in [-1,1,0]:
				var button := Button.new(); button.text="↑" if operation==-1 else ("↓" if operation==1 else "Remove"); details.add_child(button)
				button.disabled=(operation==-1 and i==0) or (operation==1 and i==point_count-1)
				if curve:
					if operation==0: button.disabled=point_count<=(3 if kind==1 else 2) or (kind==1 and (i==0 or (closed and i==point_count-1)))
					elif kind==1: button.disabled=true
				button.pressed.connect(func():
					var copy=points.duplicate()
					if operation==0:
						if curve and kind==1:
							var start: int = i if i%2==1 else i-1
							if closed and start+1==point_count-1: start-=1
							copy.remove_at(start+1); copy.remove_at(start)
						else: copy.remove_at(i)
					else: var other=copy[i+operation]; copy[i+operation]=copy[i]; copy[i]=other
					if curve: state.edit_curve_points(owner,copy)
					else: emit_changed(get_edited_property(),copy))
			box.move_child(details,box.get_child_count()-1)
		var add := Button.new(); add.text="Add Segment" if kind==1 else "Add Point"; box.add_child(add)
		add.pressed.connect(func():
			var copy=points.duplicate()
			var script_path: String = owner.get_script().resource_path.replace("mold_polyline_resource.gd","mold_polyline_point_resource.gd").replace("MoldPolylineResource.cs","MoldPolylinePointResource.cs").replace("mold_polygon_resource.gd","mold_polygon_point_resource.gd").replace("MoldPolygonResource.cs","MoldPolygonPointResource.cs").replace("mold_curve_resource.gd","mold_curve_point_resource.gd").replace("MoldCurveResource.cs","MoldCurvePointResource.cs")
			var point: Resource = load(script_path).new()
			var position_key: String = state.resource_field(owner,"position","Position")
			var count: int = copy.size()
			var last: Vector3 = copy[-1].get(position_key) if count>0 and copy[-1] else Vector3.ZERO
			# Left extends the default polygon without crossing its closing edge.
			var step := maxf(1.0,absf(last.x)*0.000001) * (-1.0 if polygon else 1.0)
			var next := last+Vector3.RIGHT*step if count>0 else Vector3.ZERO
			if kind==1 and count==0:
				copy.append(load(script_path).new())
				if closed: copy.append(load(script_path).new())
				count=copy.size(); next=Vector3.RIGHT
			var index := 0
			while index<count:
				var existing: Resource = copy[index]
				if existing and (next.distance_squared_to(existing.get(position_key))<=0.000000000001 or (kind==1 and (next-Vector3.RIGHT*(step*0.5)).distance_squared_to(existing.get(position_key))<=0.000000000001)):
					next.x+=step; index=0
				else: index+=1
			point.set(position_key,next)
			if curve:
				if kind==1:
					var control: Resource = load(script_path).new()
					control.set(position_key,next-Vector3.RIGHT*(step*0.5))
					if closed:
						if count==2: copy.insert(1,control)
						else: copy.insert(copy.size()-1,point); copy.insert(copy.size()-1,control)
					else: copy.append(control); copy.append(point)
				else:
					point.set(state.resource_field(owner,"in_offset","InOffset"),Vector3.RIGHT if kind==3 else Vector3.LEFT/3)
					point.set(state.resource_field(owner,"out_offset","OutOffset"),Vector3.RIGHT if kind==3 else Vector3.RIGHT/3)
					copy.append(point)
				state.edit_curve_points(owner,copy)
			else: copy.append(point); emit_changed(get_edited_property(),copy))
	for entry in controls:
		if not entry[1]: continue
		var key: String = state.resource_field(owner,entry[2],entry[2].to_pascal_case())
		var value = entry[1].get(key)
		if entry[2]=="mode": entry[0].select(value)
		elif entry[2]=="color": entry[0].color=value
		else: entry[0].set_value_no_signal(value[entry[3]] if entry[2] in ["position","in_offset","out_offset"] else value)

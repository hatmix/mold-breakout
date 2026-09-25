@tool
extends RefCounted

# Script API names also cover methods that are absent from get_property_list().
static func api_name(object: Object, snake: String, managed: String = "") -> String:
	var script: Script = object.get_script() if object else null
	if script and script.resource_path.ends_with(".cs"):
		return managed if not managed.is_empty() else snake.to_pascal_case()
	return snake

# Property lookup respects the actual exported schema, including inherited fields.
static func field(object: Object, snake: String) -> String:
	if not object: return ""
	for property in object.get_property_list():
		if str(property.name).to_snake_case() == snake: return property.name
	return ""

static func read(object: Object, snake: String, fallback: Variant = null) -> Variant:
	var key := field(object, snake)
	return object.get(key) if not key.is_empty() else fallback

static func enum_choices(object: Object, snake: String) -> Dictionary:
	var result := {}
	var key := field(object,snake)
	for property in object.get_property_list():
		if property.name!=key: continue
		var next_id := 0
		for entry in String(property.hint_string).split(","):
			var parts := entry.split(":")
			if parts.size()>1: next_id=int(parts[1])
			result[next_id]=parts[0]
			next_id+=1
	return result

static func enum_name(object: Object, snake: String) -> String:
	return String(enum_choices(object,snake).get(int(read(object,snake,0)),"")).replace("_", "").replace(" ", "").to_lower()

@tool
extends ItemList

var resources: Array[Resource] = []

func _ready():
	refresh()

func refresh():
	load_resources()
	showResources()

func filterResource(resource: Resource, rawQuery: String):
	var query = rawQuery.to_lower()
	var nameMatches = resource.name.to_lower().contains(query)
	var descriptionMatches = resource.description.to_lower().contains(query)
	print(resource.name, query, nameMatches, descriptionMatches)
	return nameMatches || descriptionMatches

func showResources():
	var query = $"../HBoxContainer/LineEdit".text
	
	var filtered_resources: Array[Resource]
	if query.is_empty():
		filtered_resources = resources
	else:
		filtered_resources = resources.filter(func(r): return filterResource(r, query))
	
	clear()
	for resource in filtered_resources:
		var id = add_item(resource.name, resource.icon)
		set_item_tooltip(id, resource.description)
		set_item_metadata(id, resource.resource_path)

func load_resources():
	var new_resources: Array[Resource] = []
	var location = "res://data/items"
	var dir = DirAccess.open(location)
	for file in dir.get_files():
		if file.ends_with(".tres"):
			new_resources.push_back(ResourceLoader.load(location + "/" + file))
	resources = new_resources

func _on_item_clicked(index, at_position, mouse_button_index):
	var resource_path = get_item_metadata(index)
	EditorInterface.edit_resource(ResourceLoader.load(resource_path))

func _on_line_edit_text_changed(new_text):
	showResources()

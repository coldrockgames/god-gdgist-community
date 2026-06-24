@tool
extends VBoxContainer


@onready var filter_text: LineEdit = %FilterText
@onready var tree: Tree = %Tree
@onready var refresh_button: Button = %RefreshButton
@onready var upgrade_button: Button = %UpgradeButton


var local_col_folder  = Color.SKY_BLUE
var local_col_file    = Color.SKY_BLUE
var global_col_folder = Color.MEDIUM_PURPLE
var global_col_file   = Color.MEDIUM_PURPLE

var _editor_dialog:GdGistEditor
var _is_loading_state:bool = false


func _ready() -> void:
	await get_tree().process_frame
	tree.set_drag_forwarding(_get_drag_data, _can_drop_data_tree, _drop_data_tree)
	tree._setup_editor(_editor_dialog)
	refresh_tree()
	_connect_tree_signals()
	_connect_changed_signal()
	GdgistFeatureBroker.scan_ui(self)
	upgrade_button.visible = not GDGistPlugin.is_pro_version


func setup_editor(editor:GdGistEditor, extractor:ConfirmationDialog) -> void:
	_editor_dialog = editor
	if _editor_dialog:
		_editor_dialog.gist_saved.connect(refresh_tree.bind(false))
	if extractor and extractor.has_signal("gist_saved"):
		extractor.connect("gist_saved", refresh_tree.bind(false))


func _connect_tree_signals() -> void:
	if not is_inside_tree():
		return
	if not tree.item_activated.is_connected(_on_tree_item_activated):
		tree.item_activated.connect(_on_tree_item_activated)
	if not tree.gist_moved.is_connected(_on_gist_moved):
		tree.gist_moved.connect(_on_gist_moved)
	if not tree.tree_update_required.is_connected(refresh_tree):
		tree.tree_update_required.connect(refresh_tree)
	if not tree.folder_created.is_connected(_on_folder_created):
		tree.folder_created.connect(_on_folder_created)
	if not tree.item_collapsed.is_connected(_on_tree_item_collapsed):
		tree.item_collapsed.connect(_on_tree_item_collapsed)


#region filter
func _connect_changed_signal() -> void:
	filter_text.text_changed.connect(_on_filter_text_changed)
	filter_text.set_deferred("text", GdGistManager.ui_state_get_filter())


func _on_filter_text_changed(new_text:String) -> void:
	if _is_loading_state:
		return
	var safe_text:String = new_text.replace("\"", "")
	if safe_text != new_text:
		filter_text.text = safe_text
		filter_text.caret_column = safe_text.length()
	GdGistManager.ui_state.set_value("gdgist", "filter_text", safe_text)
	GdGistManager.save_ui_state()
	refresh_tree(true)
#endregion

#region building the tree
func _on_gist_moved(gist_data: Dictionary, target_is_global: bool, target_folder: String) -> void:
	var success: bool = GdGistManager.move_gist(gist_data, target_is_global, target_folder)
	if success:
		refresh_tree()


func _on_folder_created(parent_item: TreeItem, folder_name: String, is_global: bool) -> void:
	var is_global_col: Color = global_col_folder if is_global else local_col_folder
	var new_node: TreeItem = _create_node(parent_item, folder_name, true, is_global_col)
	parent_item.collapsed = false


func refresh_tree(use_cache:bool = false) -> void:
	if not is_inside_tree() or _is_loading_state:
		return
	_is_loading_state = true
	var saved_selections:Array[String] = []
	var next_item := tree.get_next_selected(null)
	while next_item:
		var key := _get_item_unique_key(next_item)
		if not key.is_empty():
			saved_selections.append(key)
		next_item = tree.get_next_selected(next_item)
	tree.clear()
	refresh_button.icon = get_theme_icon("Reload", "EditorIcons")
	upgrade_button.icon = get_theme_icon("ProjectUpgradeMajor", "EditorIcons")
	filter_text.right_icon = get_theme_icon("Search", "EditorIcons")
	var root:TreeItem = tree.create_item()
	var project_node:TreeItem = _create_node(root, "Project Gists", true, local_col_folder, false)
	await _populate_scope(project_node, false, use_cache)
	if GdgistFeatureBroker.has_feature("p_global_gists"):
		var global_node:TreeItem = _create_node(root, "Global Gists", true, global_col_folder, false)
		await _populate_scope(global_node, true, use_cache)
	if not saved_selections.is_empty():
		_restore_tree_selection(root, saved_selections)
	call_deferred("_apply_ui_state")


## Generates a unique string identifier for any TreeItem based on metadata or hierarchy.
func _get_item_unique_key(item:TreeItem) -> String:
	if not item:
		return ""
	var meta:Variant = item.get_metadata(0)
	if typeof(meta) == TYPE_DICTIONARY:
		var is_global:bool = meta.get("is_global", false)
		var scope := "global" if is_global else "local"
		return "gist:%s:%s" % [scope, meta.get("file_path", "")]
	var path_parts:PackedStringArray = []
	var curr := item
	while curr:
		path_parts.append(curr.get_text(0))
		curr = curr.get_parent()
	path_parts.reverse()
	return "folder:" + "/".join(path_parts)


## Iterates through the newly built tree and re-selects matching keys.
func _restore_tree_selection(root_item:TreeItem, keys:Array[String]) -> void:
	if not root_item:
		return
	var stack:Array[TreeItem] = [root_item]
	while not stack.is_empty():
		var current := stack.pop_back()
		var key := _get_item_unique_key(current)
		if keys.has(key):
			current.select(0)
		var child:TreeItem = current.get_first_child()
		while child:
			stack.append(child)
			child = child.get_next()


func _create_node(
	parent:TreeItem, 
	text:String, 
	is_folder:bool, 
	icon_color:Color = Color.WHITE_SMOKE, 
	can_delete:bool = true
) -> TreeItem:
	var node:TreeItem = tree.create_item(parent)
	node.set_text(0, text)
	if is_folder:
		node.set_icon(0, get_theme_icon("Folder", "EditorIcons"))
		node.set_icon_modulate(0, icon_color)
	else:
		node.set_icon(0, get_theme_icon("CodeHighlighter", "EditorIcons"))
	if can_delete:
		var trash_icon:Texture2D = get_theme_icon("Remove", "EditorIcons")
		node.add_button(0, trash_icon, 0)
		node.set_button_color(0, 0, Color(1, 1, 1, 0))
		node.set_button_tooltip_text(0, 0, "Delete")
	return node


func _populate_scope(parent_node:TreeItem, is_global:bool, use_cache:bool = false):
	var filter:String = filter_text.text.strip_edges().to_lower()
	var gists:Array[Dictionary] = await GdGistManager.load_all_gists(is_global, use_cache)
	for gist:Dictionary in gists:
		if gist.has("is_empty_folder"):
			continue
		var gist_name:String = gist.get("name", "").to_lower()
		var folder_path:String = gist.get("folder", "").to_lower()
		if filter != "" and not (filter in gist_name or filter in folder_path):
			continue
		if not is_instance_valid(parent_node):
			return
		var parent_for_gist:TreeItem = _get_or_create_folder_path(parent_node, folder_path, is_global)
		var gist_item:TreeItem = _create_node(
			parent_for_gist, 
			gist.get("name", "<Unnamed Gist>"), 
			false,
			global_col_file if is_global else local_col_file
		)
		gist["is_global"] = is_global
		gist_item.set_metadata(0, gist)
		var preview_code: String = gist.get("code", "")
		if preview_code.length() > 800:
			preview_code = preview_code.substr(0, 800) + "\n... [truncated]"
		gist_item.set_tooltip_text(0, "[code]" + preview_code + "[/code]")


func _get_or_create_folder_path(root_node:TreeItem, folder_path:String, is_global:bool) -> TreeItem:
	if folder_path == "":
		return root_node
	var current_node:TreeItem = root_node
	var parts:PackedStringArray = folder_path.split("/")
	for part:String in parts:
		if part == "":
			continue
		var found_child:TreeItem = null
		var child:TreeItem = current_node.get_first_child()
		while child:
			if child.get_text(0) == part and child.get_metadata(0) == null: 
				found_child = child
				break
			child = child.get_next()
		if found_child:
			current_node = found_child
		else:
			current_node = _create_node(
				current_node, part, true,
				global_col_folder if is_global else local_col_folder
			)
	return current_node


func _apply_ui_state() -> void:
	filter_text.text = GdGistManager.ui_state_get_filter()
	var root: TreeItem = tree.get_root()
	if root:
		_walk_and_apply_state(root)
	_is_loading_state = false


func _walk_and_apply_state(item: TreeItem) -> void:
	if item.get_metadata(0) == null and item != tree.get_root():
		var info: Dictionary = _get_folder_info_for_state(item)
		item.collapsed = GdGistManager.ui_state.get_value(info.section, info.path, false)
	var child: TreeItem = item.get_first_child()
	while child:
		_walk_and_apply_state(child)
		child = child.get_next()


func _on_tree_item_activated() -> void:
	var selected:TreeItem = tree.get_selected()
	if not selected:
		return
	var meta:Variant = selected.get_metadata(0)
	if typeof(meta) == TYPE_DICTIONARY:
		var is_global:bool = meta.get("is_global", false)
		_editor_dialog.open_for_edit(meta, is_global)


func _on_add_button_pressed() -> void:
	var info:Dictionary = tree.get_selected_folder_info()
	var is_global:bool = info.get("is_global", false)
	var folder_path:String = info.get("path", "")
	_editor_dialog.open_for_new(is_global, "", "", folder_path)
#endregion

#region ui state
## Helper to reconstruct the config path dynamically from any tree item.
func _get_folder_info_for_state(item: TreeItem) -> Dictionary:
	var section: String = "Project"
	var path_parts: PackedStringArray = []
	var current: TreeItem = item
	while current and current.get_parent() != null:
		var text: String = current.get_text(0)
		if text == "Global Gists":
			section = "Global"
			break
		elif text == "Project Gists":
			section = "Project"
			break
		else:
			path_parts.insert(0, text)
		current = current.get_parent()
	var path: String = "/".join(path_parts)
	if path.is_empty():
		path = "root" # Special key for the base scope folders
	return {"section": section, "path": path}


## Applies the saved collapse-state to a newly created folder item.
func _apply_folder_state(item: TreeItem) -> void:
	var info: Dictionary = _get_folder_info_for_state(item)
	var is_collapsed: bool = GdGistManager.ui_state.get_value(info.section, info.path, false)
	item.set_deferred("collapsed", is_collapsed)


## Fired when ANY item is collapsed or expanded by the user.
func _on_tree_item_collapsed(item: TreeItem) -> void:
	if _is_loading_state or item.get_metadata(0) != null:
		return
	var info: Dictionary = _get_folder_info_for_state(item)
	GdGistManager.ui_state.set_value(info.section, info.path, item.collapsed)
	GdGistManager.save_ui_state()


## Open the browser to the pro version
func _on_upgrade_button_pressed() -> void:
	OS.shell_open(GDGistPlugin.PRO_ITCH_HOME)
#endregion

#region dragging
func _get_drag_data(_at_position: Vector2) -> Variant:
	var selected_gists: Array[Dictionary] = []
	var current := tree.get_next_selected(null)
	while current:
		var metadata = current.get_metadata(0)
		if metadata is Dictionary and metadata.has("code"):
			selected_gists.append(metadata)
		current = tree.get_next_selected(current)
	if selected_gists.is_empty():
		return null
	var preview := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = get_theme_icon("CodeHighlighter", "EditorIcons")
	icon.modulate = global_col_file # Oder local_col_file
	var label := Label.new()
	if selected_gists.size() > 1:
		label.text = " %d Gists" % selected_gists.size()
	else:
		label.text = " " + selected_gists[0].get("name", "Gist")
	preview.add_child(icon)
	preview.add_child(label)
	set_drag_preview(preview)
	return {
		"type": "gdgist",
		"gists": selected_gists
	}


func _can_drop_data_tree(_at_position: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.get("type") == "gdgist"


func _drop_data_tree(at_position: Vector2, data: Variant) -> void:
	var target_item := tree.get_item_at_position(at_position)
	var folder_info: Dictionary
	if target_item:
		if target_item.get_metadata(0) != null:
			folder_info = _get_folder_info_for_state(target_item.get_parent())
		else:
			folder_info = _get_folder_info_for_state(target_item)
	else:
		folder_info = {"section": "Project", "path": ""}
	var target_path:String = folder_info.path
	var is_global:bool = folder_info.section == "Global"
	var gists: Array = data.get("gists", [])
	var moved_any := false
	for gist in gists:
		if gist.get("folder", "") == target_path and gist.get("is_global") == is_global:
			continue
		GdGistManager.move_gist(gist, is_global, target_path)
		moved_any = true
	if moved_any:
		refresh_tree()
#endregion

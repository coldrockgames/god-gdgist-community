@tool
extends Tree

## Emitted when a gist has been moved via drag and drop
signal gist_moved(gist_data: Dictionary, target_is_global: bool, target_folder: String)
## Emitted when the tree changed due to rename or duplicate operations.
signal tree_update_required()
## Emitted when the user creates a new folder via the context menu
signal folder_created(parent_item: TreeItem, folder_name: String, is_global: bool)

enum TreeMenuId {
	CREATE_GIST = 1,
	CREATE_EDITOR_SCRIPT = 2,
	CREATE_FOLDER = 3,
	DELETE_FOLDER = 4,
	RUN_EDITOR_SCRIPT = 5,
	SHOW_IN_FILE_MANAGER = 6,
	RENAME_GIST = 7,
	DUPLICATE_GIST = 8,
	RENAME_FOLDER = 9,
}

var _tree_menu: PopupMenu
var _folder_dialog: ConfirmationDialog
var _folder_edit: LineEdit
var _action_target_item: TreeItem
var _hovered_item: TreeItem = null
var _delete_dialog: ConfirmationDialog
var _rename_dialog: ConfirmationDialog
var _rename_edit: LineEdit
var _rename_folder_dialog: ConfirmationDialog
var _rename_folder_edit: LineEdit
var _duplicate_dialog: ConfirmationDialog
var _duplicate_edit: LineEdit
var _item_to_delete: TreeItem = null
var _editor_dialog:GdGistEditor


#region regex rules for tooltip highlighting
var _lexer_regex := RegEx.new()
var inner_ph_regex := RegEx.new()

func _init() -> void:
	# Die Reihenfolge in der RegEx bestimmt die Priorität!
	# Gruppe 1: Regions (#region)
	# Gruppe 2: Kommentare (## oder #)
	# Gruppe 3: Strings ("...")
	# Gruppe 4: Keywords (func, var, etc.)
	# Gruppe 5: Annotations (@tool, etc.)
	# Gruppe 6: Types (String, int, etc.)
	var patterns := [
		r"(!>(.*?)<!)", 
		r"(!!)",
		r"(#(?:region|endregion).*)",
		r"(##?.*)",
		r"(\"(?:[^\"\\]|\\.)*\")",
		r"\b(func|var|const|not|and|or|is|in|super|await|true|false|null)\b",
		r"\b(break|continue|return|while|for|if|elif|else|match|pass)\b",
		r"(@tool|@abstract|@icon)\b",
		r"\b(String|void|int|bool|float|StringName|PackedScene|Array|Dictionary|Callable|Variant|Vector2|Vector3|Vector2i|Vector3i|Node|Node2D|Node3D|Control|CollisionShape3D|CollisionShape2D|Sprite2D|MeshInstance3D|TextureRect|ColorRect)\b"
	]
	_lexer_regex.compile("|".join(patterns))
	inner_ph_regex.compile("!>(.*?)<!")
#endregion

func _ready() -> void:
	_connect_signals()
	_setup_confirmation_dialog()
	_setup_context_menu()


func _connect_signals() -> void:
	button_clicked.connect(_on_button_clicked)
	mouse_exited.connect(_on_mouse_exited)
	item_mouse_selected.connect(_on_item_mouse_selected)


func _setup_confirmation_dialog() -> void:
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Confirm Deletion"
	_delete_dialog.ok_button_text = "Yes"
	_delete_dialog.cancel_button_text = "No"
	add_child(_delete_dialog)
	_delete_dialog.confirmed.connect(_on_delete_confirmed)


func _setup_editor(editor:GdGistEditor) -> void:
	_editor_dialog = editor


#region selection
## Returns the currently active folder path from the tree selection.
func get_active_folder_path() -> String:
	var selected_item := get_selected()
	if not selected_item:
		return ""
	var meta:Variant = selected_item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		var info := _get_folder_info(selected_item)
		return info.get("path", "") as String
	return meta.get("folder", "") as String
#endregion

#region custom tooltip
## Overrides the default tooltip rendering of the control.
func _make_custom_tooltip(for_text: String) -> Object:
	if for_text.begins_with("[code]"):
		for_text = "[color=whitesmoke]" + _highlight_tooltip_text(for_text)
		var rtl := RichTextLabel.new()
		rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		rtl.fit_content = true
		rtl.bbcode_enabled = true
		rtl.text = for_text
		if EditorInterface.get_editor_theme():
			rtl.add_theme_font_override("mono_font", get_theme_font("source", "EditorFonts"))
			rtl.add_theme_font_size_override("mono_font_size", get_theme_font_size("source_size", "EditorFonts") * 0.9)
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_top", 8)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_bottom", 8)
		margin.add_child(rtl)
		return margin
	return null


func _highlight_tooltip_text(for_text:String) -> String:
	for_text = for_text.replace("[br][br]", "\n##")
	for_text = for_text.replace("[br]", "")
	if for_text.ends_with("[/code]"):
		for_text = for_text.trim_suffix("[/code]")
	var result := ""
	var last_pos := 0
	for m in _lexer_regex.search_all(for_text):
		result += for_text.substr(last_pos, m.get_start() - last_pos)
		if m.get_string(1):   # Placeholder Selection !>...<!
			var content := m.get_string(2)
			result += " [bgcolor=#503050][color=whitesmoke]%s[/color][/bgcolor] " % content
		elif m.get_string(3): # Cursor !!
			pass
		elif m.get_string(4): # Region
			result += "[color=darkorchid]%s[/color]" % m.get_string(4)
		elif m.get_string(5): # Comments
			result += "[color=limegreen]%s[/color]" % m.get_string(5)
		elif m.get_string(6): # Strings
			#result += "[color=khaki]%s[/color]" % m.get_string(6)
			var str_content := m.get_string(6)
			str_content = str_content.replace("!!", "")
			var ph_style := "[/color][bgcolor=#503050][color=whitesmoke]$1[/color][/bgcolor][color=khaki]"
			str_content = inner_ph_regex.sub(str_content, ph_style, true)
			result += "[color=khaki]%s[/color]" % str_content
		elif m.get_string(7): # Keywords
			result += "[color=orangered]%s[/color]" % m.get_string(7)
		elif m.get_string(8): # Control Flow
			result += "[color=hotpink]%s[/color]" % m.get_string(8)
		elif m.get_string(9): # Annotations
			result += "[color=orange]%s[/color]" % m.get_string(9)
		elif m.get_string(10): # Types
			result += "[color=aquamarine]%s[/color]" % m.get_string(10)
		last_pos = m.get_end()
	result += for_text.substr(last_pos)
	return result
#endregion

#region item creation helpers
## Returns the path and scope of the currently selected item.
func get_selected_folder_info() -> Dictionary:
	var selected:TreeItem = get_selected()
	if not selected:
		return {"is_global": false, "path": ""}
	var meta:Variant = selected.get_metadata(0)
	if typeof(meta) == TYPE_DICTIONARY:
		return {"is_global": meta.get("is_global", false), "path": meta.get("folder", "")}
	return _get_folder_info(selected)
#endregion

#region item deletion
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var item: TreeItem = get_item_at_position(event.position)
		if item != _hovered_item:
			if _hovered_item and is_instance_valid(_hovered_item) and _hovered_item.get_button_count(0) > 0:
				_hovered_item.set_button_color(0, 0, Color(1, 1, 1, 0))
			_hovered_item = item
			if _hovered_item and _hovered_item.get_button_count(0) > 0:
				_hovered_item.set_button_color(0, 0, Color.WHITE_SMOKE)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
		var selected: TreeItem = get_selected()
		if selected:
			_request_delete(selected, event.shift_pressed)
			accept_event()


func _on_mouse_exited() -> void:
	if _hovered_item and is_instance_valid(_hovered_item) and _hovered_item.get_button_count(0) > 0:
		_hovered_item.set_button_color(0, 0, Color(1, 1, 1, 0))
	_hovered_item = null


func _on_button_clicked(item: TreeItem, _column: int, _id: int, mouse_button_index: int) -> void:
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		var shift_pressed: bool = Input.is_key_pressed(KEY_SHIFT)
		_request_delete(item, shift_pressed)


func _request_delete(item: TreeItem, skip_confirm: bool) -> void:
	if item.get_parent() == get_root():
		return
	if skip_confirm:
		_execute_delete(item)
	else:
		_item_to_delete = item
		var meta: Variant = item.get_metadata(0)
		var is_folder: bool = typeof(meta) != TYPE_DICTIONARY
		var item_name: String = item.get_text(0)
		var msg: String = "Delete '%s'. Are you sure?" % item_name
		if is_folder:
			msg += "\n\nThis will delete all items in all subfolders too!"
		_delete_dialog.dialog_text = msg
		_delete_dialog.popup_centered()
		_delete_dialog.get_ok_button().grab_focus()


func _on_delete_confirmed() -> void:
	if _item_to_delete and is_instance_valid(_item_to_delete):
		_execute_delete(_item_to_delete)
		_item_to_delete = null


func _execute_delete(item: TreeItem) -> void:
	var success: bool = false
	var meta: Variant = item.get_metadata(0)
	if typeof(meta) == TYPE_DICTIONARY:
		success = GdGistManager.delete_gist(meta.get("file_path", ""))
	else:
		var info: Dictionary = _get_folder_info(item)
		success = GdGistManager.delete_folder(info.is_global, info.path)
	if success:
		if item == _hovered_item:
			_hovered_item = null
		tree_update_required.emit()


func _get_folder_info(item: TreeItem) -> Dictionary:
	var is_global: bool = false
	var path_parts: PackedStringArray = []
	var current: TreeItem = item
	while current and current.get_parent() != null:
		var text: String = current.get_text(0)
		if text == "Global Gists":
			is_global = true
			break
		elif text == "Project Gists":
			is_global = false
			break
		else:
			path_parts.insert(0, text)
		current = current.get_parent()
	return { "is_global": is_global, "path": "/".join(path_parts) }
#endregion

#region drag & drop
func _get_drag_data(at_position: Vector2) -> Variant:
	var item: TreeItem = get_item_at_position(at_position)
	if not item:
		return null
	var meta: Variant = item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return null
	var drag_data = meta.duplicate()
	drag_data["type"] = "gdgist"
	var preview := Label.new()
	preview.text = "Move: " + item.get_text(0)
	set_drag_preview(preview)
	return drag_data


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY or data.get("type") != "gdgist":
		return false
	var target_item: TreeItem = get_item_at_position(at_position)
	if target_item:
		set_drop_mode_flags(Tree.DROP_MODE_ON_ITEM)
		return true
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var target_item: TreeItem = get_item_at_position(at_position)
	if not target_item:
		return
	var target_is_global: bool = false
	var target_folder: String = ""
	var current: TreeItem = target_item
	var target_meta: Variant = target_item.get_metadata(0)
	if typeof(target_meta) == TYPE_DICTIONARY:
		current = target_item.get_parent()
	var path_parts: PackedStringArray = []
	while current and current.get_parent() != null:
		var text: String = current.get_text(0)
		if text == "Global Gists":
			target_is_global = true
			break
		elif text == "Project Gists":
			target_is_global = false
			break
		else:
			path_parts.insert(0, text)
		current = current.get_parent()
	target_folder = "/".join(path_parts)
	gist_moved.emit(data, target_is_global, target_folder)
#endregion

#region context menu
func _setup_context_menu() -> void:
	allow_rmb_select = true
	_tree_menu = PopupMenu.new()
	add_child(_tree_menu)
	_tree_menu.id_pressed.connect(_on_tree_menu_id_pressed)
	# create folder
	_folder_dialog = ConfirmationDialog.new()
	_folder_dialog.title = "Create Folder"
	_folder_edit = LineEdit.new()
	_folder_edit.placeholder_text = "Folder name..."
	_folder_edit.custom_minimum_size = Vector2(200, 0)
	_folder_dialog.add_child(_folder_edit)
	add_child(_folder_dialog)
	_folder_dialog.confirmed.connect(_on_folder_dialog_confirmed)
	_folder_edit.text_submitted.connect(_on_folder_edit_text_submitted)
	# rename gist
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rename Gist"
	_rename_edit = LineEdit.new()
	_rename_edit.placeholder_text = "New Gist name..."
	_rename_edit.custom_minimum_size = Vector2(200, 0)
	_rename_dialog.add_child(_rename_edit)
	add_child(_rename_dialog)
	_rename_dialog.confirmed.connect(_on_rename_dialog_confirmed)
	_rename_edit.text_submitted.connect(_on_rename_edit_text_submitted)
	# rename folder
	_rename_folder_dialog = ConfirmationDialog.new()
	_rename_folder_dialog.title = "Rename Folder"
	_rename_folder_edit = LineEdit.new()
	_rename_folder_edit.placeholder_text = "New Folder name..."
	_rename_folder_edit.custom_minimum_size = Vector2(200, 0)
	_rename_folder_dialog.add_child(_rename_folder_edit)
	add_child(_rename_folder_dialog)
	_rename_folder_dialog.confirmed.connect(_on_rename_folder_dialog_confirmed)
	_rename_folder_edit.text_submitted.connect(_on_rename_folder_edit_text_submitted)
	# duplicate gist
	_duplicate_dialog = ConfirmationDialog.new()
	_duplicate_dialog.title = "Duplicate Gist"
	_duplicate_edit = LineEdit.new()
	_duplicate_edit.placeholder_text = "Duplicate name..."
	_duplicate_edit.custom_minimum_size = Vector2(200, 0)
	_duplicate_dialog.add_child(_duplicate_edit)
	add_child(_duplicate_dialog)
	_duplicate_dialog.confirmed.connect(_on_duplicate_dialog_confirmed)
	_duplicate_edit.text_submitted.connect(_on_duplicate_edit_text_submitted)


func _on_item_mouse_selected(pos: Vector2, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_action_target_item = get_item_at_position(pos)
		if not _action_target_item:
			return
		_tree_menu.clear()
		var meta:Variant = _action_target_item.get_metadata(0)
		var is_folder:bool = typeof(meta) != TYPE_DICTIONARY
		var is_root:bool = _action_target_item.get_parent() == get_root() or _action_target_item == get_root()
		if not is_folder:
			_tree_menu.add_icon_item(get_theme_icon("Add", "EditorIcons"), "Create Gist", TreeMenuId.CREATE_GIST)
			_tree_menu.add_icon_item(get_theme_icon("New", "EditorIcons"), "Create Editor Script", TreeMenuId.CREATE_EDITOR_SCRIPT)
			_tree_menu.add_separator()
			_tree_menu.add_icon_item(get_theme_icon("Rename", "EditorIcons"), "Rename Gist", TreeMenuId.RENAME_GIST)
			_tree_menu.add_icon_item(get_theme_icon("Duplicate", "EditorIcons"), "Duplicate Gist", TreeMenuId.DUPLICATE_GIST)
			_tree_menu.add_separator()
			var code:String = meta.get("code", "")
			if code.contains("extends EditorScript") and code.contains("func _run"):
				_tree_menu.add_icon_item(get_theme_icon("Play", "EditorIcons"), "Run EditorScript", TreeMenuId.RUN_EDITOR_SCRIPT)
				_tree_menu.add_separator()
		else:
			_tree_menu.add_icon_item(get_theme_icon("Add", "EditorIcons"), "Create Gist", TreeMenuId.CREATE_GIST)
			_tree_menu.add_icon_item(get_theme_icon("New", "EditorIcons"), "Create Editor Script", TreeMenuId.CREATE_EDITOR_SCRIPT)
			_tree_menu.add_separator()
			_tree_menu.add_icon_item(get_theme_icon("FolderCreate", "EditorIcons"), "Create Folder", TreeMenuId.CREATE_FOLDER)
			if not is_root:
				_tree_menu.add_icon_item(get_theme_icon("Rename", "EditorIcons"), "Rename Folder", TreeMenuId.RENAME_FOLDER)
				if _action_target_item.get_parent() != null:
					_tree_menu.add_icon_item(get_theme_icon("Remove", "EditorIcons"), "Delete Folder", TreeMenuId.DELETE_FOLDER)
			_tree_menu.add_separator()
		_tree_menu.add_icon_item(get_theme_icon("Filesystem", "EditorIcons"), "Show in File Manager", TreeMenuId.SHOW_IN_FILE_MANAGER)
		if not GdgistFeatureBroker.has_feature("p_editor_scripts"):
			var create_idx:int = _tree_menu.get_item_index(TreeMenuId.CREATE_EDITOR_SCRIPT)
			if create_idx != -1:
				_tree_menu.set_item_disabled(create_idx, true)
				_tree_menu.set_item_text(create_idx, _tree_menu.get_item_text(create_idx) + " (Pro)")
				_tree_menu.set_item_tooltip(create_idx, "Requires the GDGist Pro Edition")
			var run_idx:int = _tree_menu.get_item_index(TreeMenuId.RUN_EDITOR_SCRIPT)
			if run_idx != -1:
				_tree_menu.set_item_disabled(run_idx, true)
				_tree_menu.set_item_text(run_idx, _tree_menu.get_item_text(run_idx) + " (Pro)")
				_tree_menu.set_item_tooltip(run_idx, "Requires the GDGist Pro Edition")
		_tree_menu.position = DisplayServer.mouse_get_position()
		_tree_menu.popup()


func _on_tree_menu_id_pressed(id:int) -> void:
	match id:
		TreeMenuId.CREATE_GIST:
			var info:Dictionary = get_selected_folder_info()
			var is_global:bool = info.get("is_global", false)
			var folder_path:String = info.get("path", "")
			_editor_dialog.open_for_new(is_global, "", "", folder_path)
		TreeMenuId.CREATE_EDITOR_SCRIPT:
			var info:Dictionary = get_selected_folder_info()
			var is_global:bool = info.get("is_global", false)
			var folder_path:String = info.get("path", "")
			var script_template:String = "@tool\nextends EditorScript\n\n\nfunc _run() -> void:\n\tpass\n"
			_editor_dialog.open_for_new(is_global, "", script_template, folder_path)
			pass
		TreeMenuId.CREATE_FOLDER:
			_folder_edit.text = ""
			_folder_dialog.popup_centered()
			_folder_edit.grab_focus()
		TreeMenuId.DELETE_FOLDER:
			var info:Dictionary = _get_folder_info(_action_target_item)
			var success:bool = GdGistManager.delete_folder(info.is_global, info.path)
			if success:
				tree_update_required.emit()
		TreeMenuId.RUN_EDITOR_SCRIPT:
			var meta:Variant = _action_target_item.get_metadata(0)
			if typeof(meta) == TYPE_DICTIONARY:
				var code:String = meta.get("code", "")
				if code != "":
					GdGistManager.execute_editor_script(code)
		TreeMenuId.SHOW_IN_FILE_MANAGER:
			var target_path:String = ""
			var meta:Variant = _action_target_item.get_metadata(0)
			if typeof(meta) == TYPE_DICTIONARY:
				target_path = meta.get("file_path", "").get_base_dir()
			else:
				var info:Dictionary = _get_folder_info(_action_target_item)
				var base_path:String = GdGistManager.get_global_path() if info.is_global else GdGistManager.get_project_path()
				target_path = base_path.path_join(info.path)
			if target_path != "":
				var global_os_path:String = ProjectSettings.globalize_path(target_path)
				OS.shell_open(global_os_path)
		TreeMenuId.RENAME_GIST:
			var meta:Variant = _action_target_item.get_metadata(0)
			if typeof(meta) == TYPE_DICTIONARY:
				_rename_edit.text = meta.get("name", "")
			_rename_dialog.popup_centered()
			_rename_edit.grab_focus()
			_rename_edit.select_all()
		TreeMenuId.RENAME_FOLDER:
			var info:Dictionary = _get_folder_info(_action_target_item)
			var current_name:String = info.path.get_file()
			_rename_folder_edit.text = current_name
			_rename_folder_dialog.popup_centered()
			_rename_folder_edit.grab_focus()
			_rename_folder_edit.select_all()
		TreeMenuId.DUPLICATE_GIST:
			var meta:Variant = _action_target_item.get_metadata(0)
			_duplicate_edit.text = meta.get("name", "Unnamed") + " (Copy)"
			_duplicate_dialog.popup_centered()
			_duplicate_edit.grab_focus()
			_duplicate_edit.select_all()


func _on_rename_edit_text_submitted(_text: String) -> void:
	_rename_dialog.hide()
	_on_rename_dialog_confirmed()


func _on_folder_edit_text_submitted(_text: String) -> void:
	_folder_dialog.hide()
	_on_folder_dialog_confirmed()


func _on_folder_dialog_confirmed() -> void:
	var new_folder: String = _folder_edit.text.strip_edges()
	if new_folder.is_empty():
		return
	var info: Dictionary = _get_folder_info(_action_target_item)
	var target_path: String = info.path.path_join(new_folder) if info.path != "" else new_folder
	var success: bool = GdGistManager.create_folder(info.is_global, target_path)
	if success:
		folder_created.emit(_action_target_item, new_folder, info.is_global)
#endregion

#region Rename & Duplicate Execution
func _on_rename_dialog_confirmed() -> void:
	var meta:Variant = _action_target_item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var new_name:String = _rename_edit.text.strip_edges()
	if new_name.is_empty() or new_name == meta.get("name", ""):
		return
	var is_global:bool = meta.get("is_global", false)
	var success:bool = GdGistManager.rename_gist(meta, is_global, new_name)
	if success:
		tree_update_required.emit()


func _on_rename_folder_edit_text_submitted(_text: String) -> void:
	_rename_folder_dialog.hide()
	_on_rename_folder_dialog_confirmed()


func _on_rename_folder_dialog_confirmed() -> void:
	var info:Dictionary = _get_folder_info(_action_target_item)
	var new_name:String = _rename_folder_edit.text.strip_edges()
	if new_name.is_empty():
		return
	var success:bool = GdGistManager.rename_folder(info.is_global, info.path, new_name)
	if success:
		tree_update_required.emit()


func _on_duplicate_edit_text_submitted(_text: String) -> void:
	_duplicate_dialog.hide()
	_on_duplicate_dialog_confirmed()


func _on_duplicate_dialog_confirmed() -> void:
	var meta:Variant = _action_target_item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var new_name:String = _duplicate_edit.text.strip_edges()
	if new_name.is_empty():
		return
	var is_global:bool = meta.get("is_global", false)
	var success:bool = GdGistManager.duplicate_gist(meta, is_global, new_name)
	if success:
		tree_update_required.emit()
#endregion

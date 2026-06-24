## Automatically creates and removes project settings for your plugin.[br]
## Also manages Autoloads and management of removal of obsolete settings.
@tool
class_name GDGistPlugin
extends EditorPlugin

const PRO_INIT_PATH      := "res://addons/coldrock-gdgist/pro/GdGistProInit.gd"
const PRO_MANAGER_PATH   := "res://addons/coldrock-gdgist/pro/GdGistProManager.gd"
const PRO_RUNNER_PATH    := "res://addons/coldrock-gdgist/pro/GdGistScriptRunner.gd"
const PRO_EXTRACTOR_PATH := "res://addons/coldrock-gdgist/pro/GdGistCodeExtractor.gd"

const PRO_ITCH_HOME      := "https://coldrockgames.itch.io/gdgist"
## The region of the editor window.
const LAYOUT_SETTING   := "coldrock/gdgist/editor/window_rect"
## The editor's minimum (default) size.
const MIN_SIZE         := Vector2i(800, 600)



#region Settings Definition
## The name of the plugin is also the name of the settings section in the ProjectSettings.
const PLUGIN_NAME := "gdgist"
## Combined name of coldrock + plugin name. Resolves to [code]"coldrock/PLUGIN_NAME"[/code].
const CONFIG_BASE := "coldrock/%s/"%PLUGIN_NAME

const PROJECT_GIST_DEFAULT_PATH := "res://.gdgist/"
static var GLOBAL_GIST_DEFAULT_PATH    := get_default_global_path()

# Definition of all settings. 
# Key = Relative Path, Value = Property Attributes
# See the examples below on how to add hints and hint_strings.
# Remove all the blueprint settings afterwards, just keep your own in here!
# In addition to the default keys known from Godot (hint, hint_string, default, type, ...),
# these keys are interpreted as well:
# "basic":bool=true     - if true, this is a basic settings, if false, this is an advanced setting
# "restart":bool=false  - if true, the editor will show the "Save & Restart" banner when this setting changes
# "editor":bool=false   - if true, this will be added to the [EditorSettings], not the [ProjectSettings]
# "resource":bool=false - if true, the value in "default" will be used as path and will be loaded
# "res_store_in":String - if "resource" is true, this is the name of a local variable in your plugin
#                         where the loaded resource shall be stored in.
var SETTINGS := {
	"paths/project_gists": {
		"default": PROJECT_GIST_DEFAULT_PATH,
		"type": TYPE_STRING,  
		"hint": PROPERTY_HINT_DIR,
		"hint_string": ""
	},
	"code/empty_lines_between_functions": {
		"editor": true,
		"default": 2,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0,4,1",
	},
	"shortcuts/insert_gist_at_cursor": {
		"editor": true,
		"restart": true,
		"resource": true,
		"res_store_in": "_shortcut",
		"default": "res://addons/coldrock-gdgist/res/gdgist_editor_shortcut.tres",
		"type": TYPE_STRING,  
		"hint": PROPERTY_HINT_FILE,
		"hint_string": "*.tres,*.res"
	},
	"paths/global_gists": {
		"editor": true,
		"default": GLOBAL_GIST_DEFAULT_PATH,
		"type": TYPE_STRING,  
		"hint": PROPERTY_HINT_GLOBAL_DIR,
		"hint_string": ""
	},
	
}

# Definition of all autoload singletons.
# Each entry is an array with 2 values: 
# 1. global variable name
# 2. path to the tscn file to set as autoload singleton
# Those will be added as global autoload in the project settings.
const AUTOLOADS := [
]

# Those will be removed from project settings if they still exist.
# The line in the array is an example. Feel free to remove it!
const OBSOLETE_SETTINGS := [
]
#endregion

static var is_pro_version:bool = false

var _export_plugin:EditorExportPlugin
var _dock:Control
var _dock_content:VBoxContainer
var _editor_dialog: GdGistEditor
var _extractor_dialog:ConfirmationDialog
var _context_menu_plugin:GdGistContextMenu
var _quick_pick_instance:Control


#region pro edition init
## Dynamically loads the pro initialization script if it exists and injects its features.
func _inject_pro_features() -> void:
	if not FileAccess.file_exists(PRO_INIT_PATH):
		return
	var pro_script := load(PRO_INIT_PATH) as GDScript
	if not pro_script:
		return
	is_pro_version = true
	var pro_module:Variant = pro_script.new()
	if pro_module.has_method("register_pro_features"):
		pro_module.register_pro_features()
	if pro_module.has_method("get_pro_settings"):
		var pro_settings:Dictionary = pro_module.get_pro_settings()
		SETTINGS.merge(pro_settings, true)
	if pro_module.has_method("inject_manager_dependencies"):
		pro_module.inject_manager_dependencies()
#endregion

static func get_author_info(key:String, root:String = "author") -> String:
	var settings := EditorInterface.get_editor_settings()
	var path := CONFIG_BASE + root + "/" + key
	if settings.has_setting(path):
		return str(settings.get_setting(path))
	return ""


static func get_default_global_path() -> String:
	return OS.get_data_dir().path_join("coldrock.games/.gdgist")


func _enter_tree() -> void:
	_inject_pro_features()
	# Do not remove these!
	GdGistManager.load_ui_state()
	_prepare_settings()
	_prepare_autoloads()
	_remove_obsolete_settings()
	_add_settings_listener()
	_add_code_editor_listener()
	_add_dock_panel()
	_setup_export_plugin()
	get_editor_dimensions()
	print("Coldrock ", PLUGIN_NAME, " Pro" if is_pro_version else "" , " plugin activated.")


func _exit_tree() -> void:
	_remove_dock_panel()
	_remove_settings_listener()
	_remove_code_editor_listener()
	_remove_export_plugin()


func _disable_plugin() -> void:
	_remove_settings()
	_remove_autoloads()


func _notification(what:int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_refresh_dock_on_focus()


func _on_settings_changed() -> void:
	pass # NOTE: This is called VERY frequently when project settings are open!


#region export management
func _setup_export_plugin() -> void:
	_export_plugin = load("res://addons/coldrock-gdgist/plugin_export.gd").new()
	add_export_plugin(_export_plugin)


func _remove_export_plugin() -> void:
	if _export_plugin:
		remove_export_plugin(_export_plugin)
		_export_plugin = null
#endregion

#region editor shortcuts
var shortcut_res:Shortcut = load("res://addons/coldrock-gdgist/res/gdgist_editor_shortcut.tres")
var _shortcut:Shortcut
var _quick_menu:PopupMenu
var _menu_mapping:Array[Dictionary] = []


func _shortcut_input(event:InputEvent) -> void:
	if not event.is_pressed() or event.is_echo(): 
		return
	if _shortcut.matches_event(event):
		_show_insert_gist_popup()
		get_viewport().set_input_as_handled()


func _show_insert_gist_popup() -> void:
	var script_editor:ScriptEditor = EditorInterface.get_script_editor()
	var current_script:Script = script_editor.get_current_script()
	if not current_script: 
		return
	if not _quick_menu:
		_quick_menu = PopupMenu.new()
		_quick_menu.id_pressed.connect(_on_quick_menu_id_pressed)
		add_child(_quick_menu)
	_quick_menu.clear()
	_quick_menu.reset_size()
	_quick_menu.min_size = Vector2(128, 200)
	_quick_menu.max_size = Vector2(960, 300)
	_menu_mapping.clear()
	var all_project:Array[Dictionary] = await GdGistManager.load_all_gists(false, true)
	var all_global:Array[Dictionary]  = await GdGistManager.load_all_gists(true, true)
	var match_group:Array[Dictionary] = []
	var project_group:Array[Dictionary] = []
	var global_group:Array[Dictionary] = []
	for g:Dictionary in all_project:
		if _does_gist_match_class(g, current_script): match_group.append(g)
		else: project_group.append(g)
	for g:Dictionary in all_global:
		if _does_gist_match_class(g, current_script): match_group.append(g)
		else: global_group.append(g)
	if not match_group.is_empty():
		_quick_menu.add_separator("Matching Inheritance")
		_add_gist_group_to_menu(match_group)
	if not project_group.is_empty():
		_quick_menu.add_separator("Project Gists")
		_add_gist_group_to_menu(project_group)
	if not global_group.is_empty():
		_quick_menu.add_separator("Global Gists")
		_add_gist_group_to_menu(global_group)
	if match_group.is_empty() and project_group.is_empty() and global_group.is_empty():
		return
	var spawn_pos:Vector2i = DisplayServer.mouse_get_position()
	var current_editor = script_editor.get_current_editor()
	if current_editor:
		var code_edit:CodeEdit = current_editor.get_base_editor() as CodeEdit
		if code_edit:
			var caret_local_pos:Vector2 = code_edit.get_caret_draw_pos()
			var code_edit_screen_pos:Vector2i = code_edit.get_screen_position()
			spawn_pos = code_edit_screen_pos + Vector2i(caret_local_pos)
			spawn_pos.y += code_edit.get_line_height()
	_quick_menu.position = spawn_pos
	_quick_menu.popup()


func _does_gist_match_class(gist:Dictionary, current_script:Script) -> bool:
	var required_class:String = gist.get("extends_class", "").strip_edges()
	if required_class.is_empty():
		return false
	var check_script:Script = current_script
	while check_script:
		if check_script.get_global_name() == required_class:
			return true
		var native_base:String = check_script.get_instance_base_type()
		if native_base == required_class:
			return true
		if ClassDB.class_exists(native_base) and ClassDB.class_exists(required_class):
			if ClassDB.is_parent_class(native_base, required_class):
				return true
		check_script = check_script.get_base_script()
	return false


func _add_gist_group_to_menu(gists:Array[Dictionary]) -> void:
	gists.sort_custom(func(a:Dictionary, b:Dictionary) -> bool:
		var folder_a:String = a.get("folder", "")
		var name_a:String = a.get("name", "")
		var path_a:String = folder_a + "/" + name_a if folder_a != "" else name_a
		var folder_b:String = b.get("folder", "")
		var name_b:String = b.get("name", "")
		var path_b:String = folder_b + "/" + name_b if folder_b != "" else name_b
		return path_a.naturalnocasecmp_to(path_b) < 0
	)
	for g:Dictionary in gists:
		var idx:int = _menu_mapping.size()
		var display_name:String = g.get("name", "")
		if display_name.is_empty():
			continue
		var folder:String = g.get("folder", "")
		if folder != "": 
			display_name = folder + "/" + display_name
		_quick_menu.add_item(display_name, idx)
		_menu_mapping.append(g)


func _on_quick_menu_id_pressed(id:int) -> void:
	var gist:Dictionary = _menu_mapping[id]
	var code_edit := _get_code_editor()
	if code_edit:
		_insert_snippet_to_editor(gist.get("code", ""), code_edit.get_caret_line(), code_edit.get_caret_column())
#endregion

#region dock panel
func _add_dock_panel() -> void:
	if not Engine.is_editor_hint() or EditorInterface.is_playing_scene() or is_instance_valid(_editor_dialog):
		return
	# The code editor
	_editor_dialog = load("res://addons/coldrock-gdgist/classes/gdgist_editor.tscn").instantiate()
	EditorInterface.get_base_control().add_child(_editor_dialog)
	# The code extractor
	if GdgistFeatureBroker.has_feature("p_extractor"):
		_extractor_dialog = load("res://addons/coldrock-gdgist/pro/gdgist_extractor.tscn").instantiate()
		EditorInterface.get_base_control().add_child(_extractor_dialog)
	# The dock panel
	_dock = EditorDock.new()
	_dock.title = "GDGist"
	_dock.dock_icon = load("res://addons/coldrock-gdgist/icons/sprGDGistIcon.png")
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock_content = load("res://addons/coldrock-gdgist/classes/gdgist_dock.tscn").instantiate()
	_dock_content.setup_editor(_editor_dialog, _extractor_dialog)
	_dock.add_child(_dock_content)
	add_dock(_dock)
	_context_menu_plugin = GdGistContextMenu.new(self)
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCRIPT_EDITOR_CODE, _context_menu_plugin)


func _remove_dock_panel() -> void:
	if _dock:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null
	if _editor_dialog:
		_editor_dialog.queue_free()
		_editor_dialog = null
	if _extractor_dialog:
		_extractor_dialog.queue_free()
		_extractor_dialog = null
	if _context_menu_plugin:
		remove_context_menu_plugin(_context_menu_plugin)
		_context_menu_plugin = null
	if _quick_menu:
		_quick_menu.queue_free()
		_quick_menu = null


func _refresh_dock_on_focus() -> void:
	if _dock and _dock.get_child_count() > 0:
		var dock_content:Node = _dock.get_child(0)
		if dock_content and dock_content.has_method("refresh_tree"):
			dock_content.refresh_tree(false)
#endregion

#region editor window position
static func get_editor_dimensions() -> Rect2i:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(LAYOUT_SETTING):
		_init_default_layout(settings)
	var saved_rect:Rect2i = settings.get_setting(LAYOUT_SETTING)
	if saved_rect.size.x < MIN_SIZE.x or saved_rect.size.y < MIN_SIZE.y:
		_init_default_layout(settings)
		saved_rect = settings.get_setting(LAYOUT_SETTING)
	return saved_rect


static func set_editor_dimensions(editor:ConfirmationDialog) -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting(LAYOUT_SETTING, Rect2i(editor.position, editor.size))


static func _init_default_layout(settings:EditorSettings) -> void:
	var current_screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(current_screen)
	var center_x := usable_rect.position.x + (usable_rect.size.x - MIN_SIZE.x) / 2
	var center_y := usable_rect.position.y + (usable_rect.size.y - MIN_SIZE.y) / 2
	var default_rect := Rect2i(Vector2i(center_x, center_y), MIN_SIZE)
	settings.set_setting(LAYOUT_SETTING, default_rect)
#endregion

#region gist drag & drop to code editor
func _add_code_editor_listener() -> void:
	EditorInterface.get_script_editor().editor_script_changed.connect(_on_editor_script_changed)
	_on_editor_script_changed(null)


func _remove_code_editor_listener() -> void:
	EditorInterface.get_script_editor().editor_script_changed.disconnect(_on_editor_script_changed)


func _on_editor_script_changed(_script: Script) -> void:
	var script_editor := EditorInterface.get_script_editor()
	var current_editor_base := script_editor.get_current_editor()
	if current_editor_base:
		var code_edit := current_editor_base.get_base_editor() as CodeEdit
		_attach_gist_drop_zone(code_edit)


func _attach_gist_drop_zone(code_edit: CodeEdit) -> void:
	if not code_edit or code_edit.has_node("GDGistDropZone"):
		return
	var drop_zone := Control.new()
	drop_zone.name = "GDGistDropZone"
	drop_zone.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drop_zone.offset_right = -25
	drop_zone.offset_bottom = -25
	drop_zone.mouse_filter = Control.MOUSE_FILTER_PASS
	drop_zone.set_drag_forwarding(Callable(), _can_drop_data_fw, _drop_data_fw)
	code_edit.add_child(drop_zone)


func _can_drop_data_fw(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) == TYPE_DICTIONARY and data.get("type") == "gdgist":
		var code_edit := _get_code_editor()
		if code_edit:
			var drop_pos: Vector2i = code_edit.get_line_column_at_pos(at_position)
			code_edit.set_caret_line(drop_pos.y)
			code_edit.set_caret_column(drop_pos.x)
		return true
	return false


func _drop_data_fw(at_position:Vector2, data:Variant) -> void:
	var code_edit := _get_code_editor()
	if not code_edit:
		return
	var empty_lines:int = get_editor_setting("code/empty_lines_between_functions", 2)
	var empty_lines_string:String = "\n".repeat(empty_lines)
	var drop_pos:Vector2i = code_edit.get_line_column_at_pos(at_position)
	var final_code_parts:PackedStringArray = []
	if data.has("gists"):
		for gist in data.get("gists", []):
			var code:String = gist.get("code", "")
			if code.contains("func "): code += empty_lines_string
			final_code_parts.append(code)
	elif data.has("code"):
		var code:String = data.get("code", "")
		if code.contains("func "): code += empty_lines_string
		final_code_parts.append(code)
	if final_code_parts.is_empty():
		return
	var final_string := ""
	if final_code_parts.size() == 1:
		final_string = final_code_parts[0]
	else:
		var padding := empty_lines_string
		var processed_parts:PackedStringArray = []
		for i in range(final_code_parts.size()):
			var part := final_code_parts[i]
			processed_parts.append(part)
		final_string = "\n".join(processed_parts) + "\n"
	_insert_snippet_to_editor(final_string, drop_pos.y, drop_pos.x)
#endregion

#region insert code snippet
func _get_code_editor() -> CodeEdit:
	var script_editor := EditorInterface.get_script_editor()
	var current_editor := script_editor.get_current_editor()
	if not current_editor:
		return null
	return current_editor.get_base_editor() as CodeEdit


func _insert_snippet_to_editor(content:String, line:int, col:int) -> void:
	var code_edit := _get_code_editor()
	var data := _process_placeholders(content)
	if code_edit:
		code_edit.begin_complex_operation()
		code_edit.insert_text(data.clean_text, line, col)
		if data.offset != -1:
			var text_before_marker:String = data.clean_text.left(data.offset)
			var lines_before := text_before_marker.split("\n")
			var target_line := line + lines_before.size() - 1
			var target_col := lines_before[-1].length()
			if lines_before.size() == 1:
				target_col += col
			if data.length > 0:
				var selected_text:String = data.clean_text.substr(data.offset, data.length)
				var lines_in_sel := selected_text.split("\n")
				var end_line := target_line + lines_in_sel.size() - 1
				var end_col := lines_in_sel[-1].length()
				if lines_in_sel.size() == 1:
					end_col += target_col
				code_edit.select(target_line, target_col, end_line, end_col)
				code_edit.set_caret_line(end_line)
				code_edit.set_caret_column(end_col)
			else:
				code_edit.set_caret_line(target_line)
				code_edit.set_caret_column(target_col)
		code_edit.end_complex_operation()
		code_edit.grab_focus()


func _process_placeholders(text:String) -> Dictionary:
	var result := {
		"clean_text": text,
		"offset": -1,
		"length": 0
	}
	if not ("!!" in text or "!>" in text):
		text += "!!"
	var regex_sel := RegEx.new()
	var regex_cur := RegEx.new()
	regex_sel.compile(r"!>(.*?)<!")
	regex_cur.compile(r"!!")
	var m_sel := regex_sel.search(text)
	var m_cur := regex_cur.search(text)
	if m_sel:
		var internal_text := m_sel.get_string(1)
		result.length = internal_text.length()
		var temp_text = regex_sel.sub(text, internal_text)
		result.clean_text = regex_cur.sub(temp_text, "", true)
		result.offset = result.clean_text.find(internal_text)
	elif m_cur:
		result.offset = m_cur.get_start()
		result.clean_text = regex_cur.sub(text, "", true)
	return result
#endregion

#region context menu hook
class GdGistContextMenu extends EditorContextMenuPlugin:
	var _plugin:GDGistPlugin
	
	
	func _init(plugin:GDGistPlugin) -> void:
		_plugin = plugin


	func _popup_menu(paths:PackedStringArray) -> void:
		if paths.is_empty():
			return
		var node:Node = Engine.get_main_loop().root.get_node_or_null(paths[0])
		var code_edit:CodeEdit = node as CodeEdit
		if not code_edit:
			return
		if code_edit.has_selection():
			add_context_menu_item("Create Project Gist from Selection", _on_create_project_gist)
			if GdgistFeatureBroker.has_feature("p_global_gists"):
				add_context_menu_item("Create Global Gist from Selection", _on_create_global_gist)
			else:
				add_context_menu_item("Create Global Gist from Selection (Pro)", _on_pro_feature_clicked)
		if GdGistManager.get_total_cached_count() > 0:
			add_context_menu_item("Insert Gist here...", _on_insert_gist)
		if GdgistFeatureBroker.has_feature("p_extractor"):
			add_context_menu_item("Extract Interface as Gists...", _on_extract_interface)
		else:
			add_context_menu_item("Extract Interface as Gists... (Pro)", _on_pro_feature_clicked)


	func _on_pro_feature_clicked(_data:Variant) -> void:
		OS.alert(
			"This feature is part of the GDGist Pro Edition.\n\nUnlock Global Gists, Editor Scripts, and the Interface Extractor to supercharge your workflow!\n\nObtain it at https://coldrockgames.itch.io/gdgist", 
			"GDGist Pro Required"
		)


	func _on_create_project_gist(data:Variant) -> void:
		_handle_create(data, false)


	func _on_create_global_gist(data:Variant) -> void:
		_handle_create(data, true)


	func _on_extract_interface(data:Variant) -> void:
		var code_edit:CodeEdit = null
		if data is Array and data.size() > 0:
			code_edit = data[0] as CodeEdit
		elif data is CodeEdit:
			code_edit = data
		if not code_edit:
			return
		var selected_text:String = code_edit.text
		# dynamic call to the pro version
		var extractor_script := load(PRO_EXTRACTOR_PATH) as GDScript
		if not extractor_script:
			return
		var res:Array[Dictionary] = extractor_script.call("extract_virtuals", selected_text)
		var foldername:String = extractor_script.call("determine_extraction_folder", selected_text)
		if _plugin._extractor_dialog and _plugin._extractor_dialog.has_method("open_for_extraction"):
			await _plugin._extractor_dialog.call("open_for_extraction", res, foldername)
			_plugin._dock_content.refresh_tree()


	func _handle_create(data:Variant, is_global:bool) -> void:
		var code_edit:CodeEdit = null
		if data is Array and data.size() > 0:
			code_edit = data[0] as CodeEdit
		elif data is CodeEdit:
			code_edit = data
		if not code_edit:
			return
		var selected_text:String = code_edit.get_selected_text()
		var script:Script = EditorInterface.get_script_editor().get_current_script()
		var script_class:String = _get_script_context(script)
		var tree_folder:String = _plugin._dock_content.tree.get_active_folder_path()
		_plugin._editor_dialog.open_for_new(is_global, script_class, selected_text, tree_folder)


	func _get_script_context(script: Script) -> String:
		if not script:
			return ""
		var base_script: Script = script.get_base_script()
		if base_script:
			return base_script.get_global_name()
		return script.get_instance_base_type()


	func _on_insert_gist(data:Variant) -> void:
		_plugin._show_insert_gist_popup()
#endregion

#region --- Generic Settings Management ---
func _add_settings_listener() -> void:
	ProjectSettings.settings_changed.connect(_on_settings_changed)


func _remove_settings_listener() -> void:
	ProjectSettings.settings_changed.disconnect(_on_settings_changed)


# Runs through the SETTINGS struct and applies all settings and defaults
func _prepare_settings() -> void:
	var changed := false
	var editor_settings := EditorInterface.get_editor_settings()
	for key:String in SETTINGS:
		var def:Dictionary = SETTINGS[key]
		var full_path := CONFIG_BASE + key
		var default_val = def.get("default")
		# Auto-detect type if not explicit
		var type         = def.get("type", typeof(default_val)) 
		var hint         = def.get("hint", PROPERTY_HINT_NONE)
		var basic        = def.get("basic", true)
		var restart      = def.get("restart", false)
		var editor       = def.get("editor", false)
		var hint_string  = def.get("hint_string", "")
		var is_resource  = def.get("resource", false)
		var res_store    = def.get("res_store_in", "") as String
		# 1. Create/Set Default if missing
		var settings = editor_settings if editor else ProjectSettings
		if is_resource:
			if not res_store.is_empty():
				var loaded_resource = load(default_val)
				set(res_store, loaded_resource)
			else:
				push_warning(get_script().get_global_name(), ": \"resource\" is set, but no storage defined in \"res_store_in\"!")
		if not settings.has_setting(full_path):
			settings.set_setting(full_path, default_val)
			if not editor: changed = true
		# 2. Register for Editor UI
		var info_struct = {
			"name": full_path,
			"type": type,
			"hint": hint,
			"hint_string": hint_string
		}
		settings.add_property_info(info_struct)
		if editor:
			editor_settings.set_initial_value(full_path, default_val, false)
		else:
			settings.set_initial_value(full_path, default_val)
			settings.set_restart_if_changed(full_path, restart)
			settings.set_as_basic(full_path, basic)
	if changed:
		ProjectSettings.save()


func _remove_settings() -> void:
	var any_changed := false
	for key:String in SETTINGS:
		var s:String = CONFIG_BASE + key
		_remove_editor_setting(s)
		if _remove_project_setting(s):
			any_changed = true;
	if any_changed:
		ProjectSettings.save()


func _prepare_autoloads() -> void:
	for a:Array in AUTOLOADS:
		_add_autoload(a[0], a[1])


func _remove_autoloads() -> void:
	for a:Array in AUTOLOADS:
		remove_autoload_singleton(a[0])


# Safely add an autoload (avoiding to add it again if it exists)
func _add_autoload(name:String, path:String) -> void:
	var full_key:String = "autoload/" + name
	if ProjectSettings.has_setting(full_key):
		var current_val:String = str(ProjectSettings.get_setting(full_key)).trim_prefix("*")
		var resolved_path:String = current_val
		# Godot 4: Convert uid:// string back to a usable res:// path
		if current_val.begins_with("uid://"):
			var id:int = ResourceUID.text_to_id(current_val)
			if id != ResourceUID.INVALID_ID:
				resolved_path = ResourceUID.get_id_path(id)
		if resolved_path == path:
			return # Exit here if the autoload already exists and is the same path
	add_autoload_singleton(name, path)


func _remove_obsolete_settings() -> void:
	var any_changed:bool = false
	for s:String in OBSOLETE_SETTINGS:
		_remove_editor_setting(s)
		if _remove_project_setting(s):
			any_changed = true;
	if any_changed:
		ProjectSettings.save()


func _remove_project_setting(full_path:String) -> bool:
	if not full_path.begins_with(CONFIG_BASE):
		full_path = CONFIG_BASE + full_path
	if ProjectSettings.has_setting(full_path):
		ProjectSettings.set_setting(full_path, null)
		return true
	return false


func _remove_editor_setting(full_path:String) -> bool:
	if not full_path.begins_with(CONFIG_BASE):
		full_path = CONFIG_BASE + full_path
	var editor_settings := EditorInterface.get_editor_settings()
	if editor_settings.has_setting(full_path):
		editor_settings.erase(full_path)
		return true
	return false


## Get a value from the project settings.[br]
## [color=orange]NOTE:[/color] [code]path[/code] is the same as you specified in 
## [member SETTINGS]! The [member CONFIG_BASE] path is added for you.
func get_project_setting(path:String, default:Variant = null) -> Variant:
	var full_path := CONFIG_BASE + path
	return ProjectSettings.get_setting(full_path, default)


## Get a value from the project settings.[br]
## [color=orange]NOTE:[/color] [code]path[/code] is the same as you specified in 
## [member SETTINGS]! The [member CONFIG_BASE] path is added for you.
func get_editor_setting(path:String, default:Variant = null) -> Variant:
	var editor_settings := EditorInterface.get_editor_settings()
	var full_path := CONFIG_BASE + path
	if editor_settings.has_setting(full_path):
		return editor_settings.get_setting(full_path)
	return default


## Get a value from the project settings.[br]
## [color=orange]NOTE:[/color] [code]path[/code] is the same as you specified in 
## [member SETTINGS]! The [member CONFIG_BASE] path is added for you.
func set_project_setting(path:String, value:Variant = null, overwrite:bool = false) -> void:
	var full_path := path
	if not full_path.begins_with(CONFIG_BASE):
		full_path = CONFIG_BASE + full_path
	if overwrite or not ProjectSettings.has_setting(full_path):
		ProjectSettings.set_setting(full_path, value)


## Get a value from the project settings.[br]
## [color=orange]NOTE:[/color] [code]path[/code] is the same as you specified in 
## [member SETTINGS]! The [member CONFIG_BASE] path is added for you.
func set_editor_setting(path:String, value:Variant, overwrite:bool = false) -> void:
	var editor_settings := EditorInterface.get_editor_settings()
	var full_path := path
	if not full_path.begins_with(CONFIG_BASE):
		full_path = CONFIG_BASE + full_path
	if overwrite or not editor_settings.has_setting(full_path):
		editor_settings.set_setting(full_path, value)
#endregion

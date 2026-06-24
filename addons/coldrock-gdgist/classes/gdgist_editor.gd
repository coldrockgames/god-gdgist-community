@tool
class_name GdGistEditor
extends ConfirmationDialog

## Emitted when a gist was successfully saved so the dock can refresh.
signal gist_saved()

@onready var _edit_name: LineEdit = %GistName
@onready var _edit_class: LineEdit = %ClassName
@onready var _edit_code: CodeEdit = %CodeEdit
@onready var scope_info: Label = %ScopeInfo
@onready var console_wrapper: VBoxContainer = %ConsoleWrapper
@onready var console: TextEdit = %Console
@onready var console_clear: Button = %ConsoleClear
@onready var console_close: Button = %ConsoleClose

var _is_global_scope:bool
var _original_file_path:String
var _run_button: Button


func _ready() -> void:
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)
	_edit_name.text_changed.connect(_validate_save_button)
	_edit_name.text_submitted.connect(_on_text_submitted)
	_edit_class.text_submitted.connect(_on_text_submitted)
	_run_button = add_button("Run Script", false, "run_gist")
	_run_button.icon = get_theme_icon("Play", "EditorIcons")
	if not GdgistFeatureBroker.has_feature("p_editor_scripts"):
		_run_button.disabled = true
		_run_button.text += " (Pro)"
		_run_button.tooltip_text = "Requires the GDGist Pro Edition"
	custom_action.connect(_on_custom_action)
	_edit_code.text_changed.connect(_update_run_button_visibility)
	console_clear.icon = get_theme_icon("Clear", "EditorIcons")
	console_close.icon = get_theme_icon("Close", "EditorIcons")
	GdgistFeatureBroker.scan_ui(self)


func _on_text_submitted(_text:String) -> void:
	var ok_btn:Button = get_ok_button()
	if not ok_btn.disabled:
		ok_btn.pressed.emit()


func _on_console_close_pressed() -> void:
	console_wrapper.visible = false


func _validate_save_button(_text:String = "") -> void:
	get_ok_button().disabled = _edit_name.text.strip_edges().is_empty()


## Opens the editor for a brand new gist.
func open_for_new(is_global:bool, default_class:String = "", initial_code: String = "", folder_path:String = "") -> void:
	_is_global_scope = is_global
	_original_file_path = ""
	var name_suggest:String = initial_code.strip_edges()
	var lines := name_suggest.split("\n")
	var found := false
	for line in lines:
		if line.begins_with("#"): 
			continue
		if line.begins_with("var") or line.begins_with("func") or line.begins_with("const"):
			var split := line.split(" ", false)
			var type_strip := split[1]
			if type_strip.contains(":"): type_strip = type_strip.split(":", false)[0].strip_edges()
			if type_strip.contains("("): type_strip = type_strip.split("(", false)[0].strip_edges()
			if type_strip.contains("="): type_strip = type_strip.split("=", false)[0].strip_edges()
			type_strip = type_strip.replace("!>", "(").replace("<!", ")")
			name_suggest = split[0] + "_" + type_strip
			found = true
			break
	if not found:
		name_suggest = ""
	if folder_path != "":
		if name_suggest != "":
			_edit_name.text = folder_path + "/" + name_suggest
		else:
			_edit_name.text = folder_path + "/"
	else:
		_edit_name.text = name_suggest
	_edit_class.text = default_class
	_edit_code.text = initial_code
	scope_info.text = "GLOBAL GIST" if is_global else "Local To Project"
	_validate_save_button()
	_update_run_button_visibility()
	popup(GDGistPlugin.get_editor_dimensions())
	_edit_name.grab_focus()
	_edit_name.caret_column = _edit_name.text.length()
	console.clear()


## Opens the editor to modify an existing gist.
func open_for_edit(gist:Dictionary, is_global:bool) -> void:
	_is_global_scope = is_global
	_original_file_path = gist.get("file_path", "")
	var folder:String = gist.get("folder", "")
	if not folder.is_empty():
		folder += "/"
	_edit_name.text = folder + gist.get("name", "")
	_edit_class.text = gist.get("extends_class", "")
	_edit_code.text = gist.get("code", "")
	scope_info.text = "GLOBAL GIST" if is_global else "Local To Project"
	_validate_save_button()
	_update_run_button_visibility()
	popup(GDGistPlugin.get_editor_dimensions())
	_edit_code.grab_focus()
	console.clear()


func _on_confirmed() -> void:
	GDGistPlugin.set_editor_dimensions(self)
	var g_name:String = _edit_name.text.strip_edges()
	if g_name.is_empty():
		push_error("GdGist: Cannot save without a name.")
		return
	var success:bool = GdGistManager.save_gist(
		_is_global_scope, 
		_ensure_clean_filename(g_name), 
		_edit_class.text.strip_edges(), 
		_edit_code.text, 
		_original_file_path
	)
	if success:
		gist_saved.emit()


func _on_canceled() -> void:
	GDGistPlugin.set_editor_dimensions(self)


func _ensure_clean_filename(filename_suggest:String) -> String:
	var clean_name := filename_suggest.replace("\\", "/")
	clean_name = clean_name.replace(" ", "_")
	var regex := RegEx.new()
	regex.compile(r"[<>:\"|?*]")
	clean_name = regex.sub(clean_name, "_", true)
	while clean_name.contains("___"):
		clean_name = clean_name.replace("___", "__")
	return clean_name


#region script execution
func _update_run_button_visibility() -> void:
	if is_instance_valid(_run_button):
		var code: String = _edit_code.text
		_run_button.visible = code.contains("extends EditorScript") and code.contains("func _run")


func _on_custom_action(action: StringName) -> void:
	if action == "run_gist":
		var code: String = _edit_code.text
		if code != "":
			console_wrapper.visible = true
			console.text = ""
			# 1. Snapshot the Godot console BEFORE execution
			var rtb:RichTextLabel = _get_editor_log_label()
			var log_before:String = ""
			if rtb:
				log_before = rtb.get_parsed_text()
			# 2. Fire!
			GdGistManager.execute_editor_script(code)
			# 3. Snapshot AFTER execution and diff the results
			if rtb:
				var log_after:String = rtb.get_parsed_text()
				var new_output:String = log_after.trim_prefix(log_before).strip_edges()
				if new_output.is_empty():
					console.text += "Done. (No console output)"
				else:
					console.text += new_output
			console.scroll_vertical = INF


func _get_editor_log_label() -> RichTextLabel:
	var base_control:Control = EditorInterface.get_base_control()
	var logs:Array[Node] = base_control.find_children("*", "EditorLog", true, false)
	if logs.size() > 0:
		var rtbs:Array[Node] = logs[0].find_children("*", "RichTextLabel", true, false)
		if rtbs.size() > 0:
			return rtbs[0] as RichTextLabel
	return null
#endregion

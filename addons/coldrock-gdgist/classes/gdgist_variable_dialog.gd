@tool
class_name GdGistVariableDialog
extends ConfirmationDialog

## Emitted when the user either confirms or cancels the dialog.
## If canceled, the dictionary will be completely empty.
signal variables_resolved(replacements: Dictionary)

var _edits: Dictionary = {}
var _vbox: VBoxContainer
var _preview_edit: CodeEdit
var _original_code: String
var _fields_container: VBoxContainer


func _init() -> void:
	title = "Define Snippet Variables"
	_vbox = VBoxContainer.new()
	add_child(_vbox)
	_fields_container = VBoxContainer.new()
	_vbox.add_child(_fields_container)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	_vbox.add_child(sep)
	_preview_edit = CodeEdit.new()
	_preview_edit.editable = false
	_preview_edit.custom_minimum_size = Vector2(0, 240)
	_preview_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var highlighter := GDScriptSyntaxHighlighter.new()
	_preview_edit.syntax_highlighter = highlighter
	_vbox.add_child(_preview_edit)
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)


## Generates the UI dynamically and halts execution until the user acts.
func request_variables(vars: Array[String], code: String) -> Dictionary:
	_original_code = code
	for child in _fields_container.get_children():
		child.queue_free()
	_edits.clear()
	var first_edit: LineEdit = null
	for v in vars:
		var hbox := HBoxContainer.new()
		var lbl := Label.new()
		lbl.text = v + ":"
		lbl.custom_minimum_size = Vector2(180, 0)
		var edit := LineEdit.new()
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_submitted.connect(_on_text_submitted)
		edit.text_changed.connect(_on_edit_text_changed)
		hbox.add_child(lbl)
		hbox.add_child(edit)
		_fields_container.add_child(hbox)
		_edits[v] = edit
		if not first_edit:
			first_edit = edit
	_update_preview()
	reset_size()
	popup_centered(Vector2(600, 0))
	if first_edit:
		first_edit.grab_focus()
	var result: Dictionary = await variables_resolved
	return result


func _on_text_submitted(_text: String) -> void:
	var ok_btn: Button = get_ok_button()
	if not ok_btn.disabled:
		ok_btn.pressed.emit()


func _on_confirmed() -> void:
	var result := {}
	for v in _edits:
		var val: String = _edits[v].text.strip_edges()
		#if val.is_empty():
			#val = v
		result[v] = val
	variables_resolved.emit(result)


func _on_canceled() -> void:
	variables_resolved.emit({})


func _on_edit_text_changed(_new_text: String) -> void:
	_update_preview()


func _update_preview() -> void:
	var current_code := _original_code
	for v in _edits:
		var val: String = _edits[v].text.strip_edges()
		if val.is_empty():
			val = v
		current_code = current_code.replace("!>" + v + "<!", val)
	_preview_edit.text = current_code

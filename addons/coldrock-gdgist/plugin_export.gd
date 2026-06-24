@tool
extends EditorExportPlugin


func _get_name() -> String:
	return "GDGistExportPlugin"


func _export_file(path:String, type:String, features:PackedStringArray) -> void:
	if path.begins_with("res://addons/coldrock-gdgist/"):
		skip()
	if path.begins_with("res://.gdgist/"):
		skip()

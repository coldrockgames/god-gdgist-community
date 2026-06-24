## Manages feature availability between the Community and Pro editions of GDGist.
## Acts as a central registry and UI scanner.
class_name GdgistFeatureBroker
extends Object

const FEATURE_GLOBAL_GISTS   := "p_global_gists"
const FEATURE_EDITOR_SCRIPTS := "p_editor_scripts"

## Dictionary holding all currently active features.
static var _active_features:Dictionary = {}


## Registers a feature flag as active.
static func register_feature(feature_id:String) -> void:
	_active_features[feature_id] = true


## Checks if a specific feature flag is currently registered and active.
static func has_feature(feature_id:String) -> bool:
	return _active_features.has(feature_id)


## Recursively scans a node tree and disables UI elements missing their required feature tags.
static func scan_ui(node:Node) -> void:
	if node is Control:
		_evaluate_control(node)
	for child:Node in node.get_children():
		scan_ui(child)


## Evaluates a single control node against its metadata tags.
static func _evaluate_control(control:Control) -> void:
	var meta_list:Array[StringName] = control.get_meta_list()
	if meta_list.is_empty():
		return
	for meta_key:StringName in meta_list:
		var key_str:String = str(meta_key)
		if key_str.begins_with("p_") or key_str.begins_with("c_"):
			if not has_feature(key_str):
				if "disabled" in control:
					control.disabled = true
				elif "editable" in control:
					control.editable = false
				else:
					control.visible = false
				control.tooltip_text = "Requires the GDGist Pro Edition"
				if "text" in control and not control.text.ends_with(" (Pro)"):
					control.text += " (Pro)"

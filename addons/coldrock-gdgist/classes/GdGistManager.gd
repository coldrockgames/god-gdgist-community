class_name GdGistManager
extends Object

const EXTENSION:String = ".gdgist"
const SEPARATOR:String = "+-+ CODE +-+"

#region save and load plugin state
static var STATE_FILE:String:
	get: return get_project_path() + "gdgist_state.cfg"
static var _ui_state_inst:ConfigFile
static var ui_state:ConfigFile:
	get:
		if _ui_state_inst == null:
			_ui_state_inst = ConfigFile.new()
			_ui_state_inst.load(STATE_FILE)
		return _ui_state_inst


static func ui_state_store_filter(filter_edit:LineEdit) -> void:
	var filter = filter_edit.text
	var safe_text:String = filter.replace("\"", "")
	if safe_text != filter:
		filter_edit.text = filter
		filter_edit.caret_column = filter.length()
	GdGistManager.ui_state.set_value("gdgist", "filter_text", safe_text)
	save_ui_state()


static func ui_state_get_filter() -> String:
	return GdGistManager.ui_state.get_value("gdgist", "filter_text", "")


## Loads the UI state from disk or initializes defaults.
static func load_ui_state() -> void:
	if GdGistManager.ui_state.load(STATE_FILE) != OK:
		pass


## Saves the current UI state to disk.
static func save_ui_state() -> void:
	var dir_path:String = STATE_FILE.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	GdGistManager.ui_state.save(STATE_FILE)
#endregion

#region loading gists
static var _cache_project:Array[Dictionary] = []
static var _cache_global:Array[Dictionary] = []


## Get the count of existing Gists.
static func get_total_cached_count() -> int:
	return _cache_global.size() + _cache_project.size()


## Retrieves the configured project path or its default.
static func get_project_path() -> String:
	var path := GDGistPlugin.CONFIG_BASE + "paths/project_gists"
	return ProjectSettings.get_setting(path, GDGistPlugin.PROJECT_GIST_DEFAULT_PATH)


## Retrieves the configured global path or its default.
static func get_global_path() -> String:
	if GdgistFeatureBroker.has_feature(GdgistFeatureBroker.FEATURE_GLOBAL_GISTS):
		var pro_script := load(GDGistPlugin.PRO_MANAGER_PATH) as GDScript
		if pro_script and pro_script.has_method("get_global_path"):
			return pro_script.call("get_global_path")
	return ""


## Scans the directory recursively and loads all gists.
static func load_all_gists(is_global:bool, use_cache:bool = false) -> Array[Dictionary]:
	if is_global:
		if not GdgistFeatureBroker.has_feature(GdgistFeatureBroker.FEATURE_GLOBAL_GISTS):
			return []
		var pro_script := load(GDGistPlugin.PRO_MANAGER_PATH) as GDScript
		if pro_script and pro_script.has_method("load_global_gists"):
			return await pro_script.call("load_global_gists", use_cache)
		return []
	if use_cache and not _cache_project.is_empty():
		return _cache_project
	var base_path:String = get_project_path()
	var results:Array[Dictionary] = []
	if DirAccess.dir_exists_absolute(base_path):
		var task_id:int = WorkerThreadPool.add_task(_scan_dir_recursive.bind(base_path, "", results))
		while not WorkerThreadPool.is_task_completed(task_id):
			await Engine.get_main_loop().process_frame
		WorkerThreadPool.wait_for_task_completion(task_id)
	_cache_project = results
	return results


## Helper function to recursively traverse directories.
static func _scan_dir_recursive(current_path:String, relative_folder:String, results:Array[Dictionary]) -> void:
	var dir:DirAccess = DirAccess.open(current_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name:String = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var full_path:String = current_path.path_join(file_name)
		if dir.current_is_dir():
			var new_relative:String = relative_folder.path_join(file_name) if relative_folder != "" else file_name
			results.append({"is_empty_folder": true, "folder": new_relative})
			_scan_dir_recursive(full_path, new_relative, results)
		elif file_name.ends_with(EXTENSION):
			var gist:Dictionary = load_gist(full_path)
			if not gist.is_empty():
				gist["folder"] = relative_folder
				results.append(gist)
		file_name = dir.get_next()


## Loads and parses a single .gdgist file.
static func load_gist(file_path:String) -> Dictionary:
	var file:FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		push_error("GDGist: Failed to open file -> " + file_path)
		return {}
	var gist:Dictionary = {
		"file_path": file_path,
		"name": file_path.get_file().get_basename(),
		"extends_class": "",
		"code": ""
	}
	var parsing_frontmatter:bool = true
	var code_lines:PackedStringArray = []
	while not file.eof_reached():
		var line:String = file.get_line()
		if parsing_frontmatter and line.strip_edges() == SEPARATOR:
			parsing_frontmatter = false
			continue
		if parsing_frontmatter:
			var stripped_line:String = line.strip_edges()
			if stripped_line.begins_with("@"):
				var colon_idx:int = stripped_line.find(":")
				if colon_idx != -1:
					var key:String = stripped_line.substr(1, colon_idx - 1).strip_edges()
					var value:String = stripped_line.substr(colon_idx + 1).strip_edges()
					gist[key] = value
		else:
			code_lines.append(line)
	if code_lines.size() > 0 and code_lines[-1] == "":
		code_lines.remove_at(code_lines.size() - 1)
	gist["code"] = "\n".join(code_lines)
	return gist
#endregion

#region saving gists
## Saves a gist to the disk. Automatically creates the directory if it's missing.
static func save_gist(is_global:bool, gist_name:String, extends_class:String, code:String, old_file_path:String = "") -> bool:
	if is_global and not GdgistFeatureBroker.has_feature(GdgistFeatureBroker.FEATURE_GLOBAL_GISTS):
		push_error("GDGist: Global Gists require the Pro Edition.")
		return false
	var base_path:String = get_global_path() if is_global else get_project_path()
	var clean_input:String = gist_name.to_lower().replace(" ", "_").replace("\\", "/")
	var relative_dir:String = clean_input.get_base_dir()
	var safe_file_name:String = clean_input.get_file() + EXTENSION
	var target_dir:String = base_path.path_join(relative_dir)
	var file_path:String = target_dir.path_join(safe_file_name)
	if not DirAccess.dir_exists_absolute(target_dir):
		var err:Error = DirAccess.make_dir_recursive_absolute(target_dir)
		if err != OK:
			push_error("GdGist: Failed to create directory -> " + target_dir)
			return false
	if old_file_path != "" and FileAccess.file_exists(old_file_path):
		DirAccess.remove_absolute(old_file_path)
	var file:FileAccess = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		push_error("GdGist: Failed to write file -> " + file_path)
		return false
	var display_name:String = gist_name.get_file()
	file.store_line("@name:        " + display_name)
	if extends_class != "":
		file.store_line("@extends_class: " + extends_class)
	var a := GDGistPlugin.get_author_info("name")
	if not a.is_empty(): file.store_line("@author:      " + a)
	a = GDGistPlugin.get_author_info("copyright")
	if not a.is_empty(): file.store_line("@copyright:   " + a)
	a = GDGistPlugin.get_author_info("email")
	if not a.is_empty(): file.store_line("@email:       " + a)
	a = GDGistPlugin.get_author_info("www")
	if not a.is_empty(): file.store_line("@www:         " + a)
	a = GDGistPlugin.get_author_info("license", "license")
	if not a.is_empty(): file.store_line("@license:     " + a)
	a = GDGistPlugin.get_author_info("url", "license")
	if not a.is_empty(): file.store_line("@license_url: " + a)
	file.store_line(SEPARATOR)
	file.store_string(code)
	return true


## Moves a gist to a new scope or folder. Safely handles cross-drive moves and collisions.
static func move_gist(gist: Dictionary, target_is_global: bool, target_folder: String, new_name:String = "") -> bool:
	if target_is_global and not GdgistFeatureBroker.has_feature(GdgistFeatureBroker.FEATURE_GLOBAL_GISTS):
		push_error("GDGist: Moving to Global Gists requires the Pro Edition.")
		return false
	var old_path: String = gist.get("file_path", "")
	var base_path: String = get_global_path() if target_is_global else get_project_path()
	var final_dir: String = base_path.path_join(target_folder)
	if not DirAccess.dir_exists_absolute(final_dir):
		DirAccess.make_dir_recursive_absolute(final_dir)
	var file_name: String = new_name if not new_name.is_empty() else old_path.get_file()
	var base_name: String = file_name.get_basename()
	var target_path: String = final_dir.path_join(file_name)
	var counter: int = 1
	while FileAccess.file_exists(target_path):
		if target_path == old_path:
			return false
		target_path = final_dir.path_join(base_name + "_" + str(counter) + EXTENSION)
		counter += 1
	var err: Error = DirAccess.rename_absolute(old_path, target_path)
	if err != OK:
		err = DirAccess.copy_absolute(old_path, target_path)
		if err == OK:
			DirAccess.remove_absolute(old_path)
		else:
			push_error("GdGist: Failed to move file -> " + str(err))
			return false
	return true


## Renames a gist. Uses save_gist to automatically update the @name in the file content.
static func rename_gist(gist: Dictionary, is_global: bool, new_name: String) -> bool:
	var old_path: String = gist.get("file_path", "")
	var folder: String = gist.get("folder", "")
	var full_new_name: String = folder.path_join(new_name) if folder != "" else new_name
	return save_gist(is_global, full_new_name, gist.get("extends_class", ""), gist.get("code", ""), old_path)


## Duplicates a gist. Similar to rename, but keeps the old file.
static func duplicate_gist(gist: Dictionary, is_global: bool, duplicate_name: String) -> bool:
	var folder: String = gist.get("folder", "")
	var full_new_name: String = folder.path_join(duplicate_name) if folder != "" else duplicate_name
	return save_gist(is_global, full_new_name, gist.get("extends_class", ""), gist.get("code", ""), "")
#endregion

#region folder management
static func create_folder(is_global:bool, relative_path:String) -> bool:
	if is_global and not GdgistFeatureBroker.has_feature(GdgistFeatureBroker.FEATURE_GLOBAL_GISTS):
		return false
	var base_path:String = get_global_path() if is_global else get_project_path()
	var target_dir:String = base_path.path_join(relative_path)
	return DirAccess.make_dir_recursive_absolute(target_dir) == OK


static func delete_folder(is_global:bool, folder_path:String) -> bool:
	if is_global and not GdgistFeatureBroker.has_feature(GdgistFeatureBroker.FEATURE_GLOBAL_GISTS):
		return false
	var base_path:String = get_global_path() if is_global else get_project_path()
	var target_dir:String = base_path.path_join(folder_path)
	return _delete_dir_recursive(target_dir)


## Renames a folder physically on the disk.
static func rename_folder(is_global: bool, old_relative_path: String, new_folder_name: String) -> bool:
	if is_global and not GdgistFeatureBroker.has_feature(GdgistFeatureBroker.FEATURE_GLOBAL_GISTS):
		return false
	var base_path: String = get_global_path() if is_global else get_project_path()
	var old_dir: String = base_path.path_join(old_relative_path)
	if not DirAccess.dir_exists_absolute(old_dir):
		return false
	var parent_dir: String = old_dir.get_base_dir()
	var new_dir: String = parent_dir.path_join(new_folder_name)
	if DirAccess.dir_exists_absolute(new_dir):
		push_error("GDGist: Cannot rename. A folder with this name already exists.")
		return false
	return DirAccess.rename_absolute(old_dir, new_dir) == OK


static func _delete_dir_recursive(path:String) -> bool:
	var dir:DirAccess = DirAccess.open(path)
	if not dir:
		return false
	dir.list_dir_begin()
	var file_name:String = dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue
		var full_path:String = path.path_join(file_name)
		if dir.current_is_dir():
			_delete_dir_recursive(full_path)
		else:
			DirAccess.remove_absolute(full_path)
		file_name = dir.get_next()
	return DirAccess.remove_absolute(path) == OK


static func delete_gist(file_path: String) -> bool:
	if file_path != "" and FileAccess.file_exists(file_path):
		return DirAccess.remove_absolute(file_path) == OK
	return false
#endregion

#region script execution
# Executes a raw string as an EditorScript in memory
static func execute_editor_script(gist_code:String) -> void:
	if not GdgistFeatureBroker.has_feature(GdgistFeatureBroker.FEATURE_EDITOR_SCRIPTS):
		push_warning("GDGist: Editor Scripts require the Pro Edition.")
		return
	var runner_script := load(GDGistPlugin.PRO_RUNNER_PATH) as GDScript
	if not runner_script:
		push_error("GDGist: Pro Script Runner missing.")
		return
	var runner:Variant = runner_script.new()
	if runner.has_method("execute"):
		runner.execute(gist_code)
#endregion

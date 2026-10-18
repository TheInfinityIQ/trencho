extends RefCounted

static func arguments() -> Dictionary:
	var result := {}
	for argument in OS.get_cmdline_user_args():
		var pair := argument.trim_prefix("--").split("=",true,1)
		result[pair[0]] = pair[1] if pair.size() == 2 else true
	return result

static func write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(value))
	file.flush()
	var error := file.get_error()
	file.close()
	return error == OK and DirAccess.rename_absolute(path+".tmp",path) == OK

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty(): return {}
	var parser := JSON.new()
	if parser.parse(source) != OK: return {}
	return parser.data if parser.data is Dictionary else {}

static func launch(arguments: Array[String]) -> int:
	var flags: PackedStringArray = []
	if OS.has_feature("editor"): flags.append_array(["--path",ProjectSettings.globalize_path("res://")])
	flags.append_array(arguments)
	return OS.create_process(OS.get_executable_path(),flags)

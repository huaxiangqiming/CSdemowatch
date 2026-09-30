extends RefCounted
var path := ""
func _init() -> void:
	var folder: String = preload("res://scripts/application/AppInfo.gd").data_root().path_join("logs")
	DirAccess.make_dir_recursive_absolute(folder)
	path = folder.path_join("app-%s.log" % Time.get_datetime_string_from_system().replace(":","-"))
func record(stage: String, detail := "") -> void:
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file != null:
		file.seek_end(); file.store_line("%s [%s] %s" % [Time.get_datetime_string_from_system(),stage,detail])

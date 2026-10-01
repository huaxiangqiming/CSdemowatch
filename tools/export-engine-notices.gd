extends SceneTree
func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty(): quit(1); return
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	if file == null: quit(1); return
	file.store_string("Godot Engine\n\n" + Engine.get_license_text() + "\n\n")
	for entry in Engine.get_copyright_info():
		file.store_string(str(entry) + "\n\n")
	for name in Engine.get_license_info():
		file.store_string(name + "\n" + Engine.get_license_info()[name] + "\n\n")
	file.close()
	quit()

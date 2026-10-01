extends RefCounted
const TITLE := "CS2 Tactical Replay"
const SUBTITLE := "3D Tactical Demo Analyzer"
const VERSION := "0.9.2-beta.1"
const PARSER_VERSION := "0.9.0"
static func data_root() -> String:
	var override := OS.get_environment("CS2_REPLAY_DATA_ROOT")
	if not override.is_empty(): return override
	var local := OS.get_environment("LOCALAPPDATA")
	return local.path_join("CS2TacticalReplay") if not local.is_empty() else ProjectSettings.globalize_path("user://")
static func parser_path() -> String:
	if OS.has_feature("standalone"): return OS.get_executable_path().get_base_dir().path_join("cs2parser.exe")
	return ProjectSettings.globalize_path("res://../parser/bin/cs2parser.exe")

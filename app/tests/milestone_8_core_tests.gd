extends SceneTree
var checks:=0
var failures:Array=[]
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures.append(message);printerr(message)
func save_json(path:String,data:Dictionary)->void:
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
func _initialize()->void:run.call_deferred()
func run()->void:
	var directory:=ProjectSettings.globalize_path("res://../artifacts/m8-core-"+str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(directory)
	for mode in [0,2]:
		var settings=load("res://scripts/application/SettingsStore.gd").new()
		settings.path=directory.path_join("settings.json");save_json(settings.path,{"auto_prepare_maps":mode})
		settings.load_settings();check(int(settings.values.auto_prepare_maps)==mode,"Preserve explicit old mode "+str(mode))
	var settings=load("res://scripts/application/SettingsStore.gd").new();settings.path=directory.path_join("new.json");settings.load_settings()
	check(int(settings.values.auto_prepare_maps)==1,"New settings Auto")
	var source=load("res://scripts/map/MapAssetCache.gd").new()
	var cache=load("res://scripts/map/MapAssetCache.gd").new(directory)
	var folder:=directory.path_join("de_dust2");DirAccess.make_dir_recursive_absolute(folder)
	for file in ["map.glb","map.json","cache.json"]:
		check(DirAccess.copy_absolute(source.root.path_join("de_dust2").path_join(file),folder.path_join(file))==OK,"Copy cache fixture "+file)
	var definition:Dictionary=cache._json(folder.path_join("map.json"));definition.model_path="map.glb";save_json(folder.path_join("map.json"),definition)
	var manifest:Dictionary=cache._json(folder.path_join("cache.json"))
	check(cache.is_map_ready("de_dust2"),"Current cache valid")
	for field in ["converter_version","classifier_version"]:
		var changed:=manifest.duplicate(true);changed[field]="stale";save_json(folder.path_join("cache.json"),changed)
		check(not cache.is_map_ready("de_dust2"),field+" invalidates cache")
	var stamp:=directory.path_join("source.bin");var file:=FileAccess.open(stamp,FileAccess.WRITE);file.store_string("original");file.close()
	manifest.source_files=[{"path":stamp,"size":8,"mtime":FileAccess.get_modified_time(stamp)}];save_json(folder.path_join("cache.json"),manifest)
	check(cache.is_map_ready("de_dust2"),"Unchanged source accepted")
	file=FileAccess.open(stamp,FileAccess.WRITE);file.store_string("changed bytes");file.close()
	check(not cache.is_map_ready("de_dust2"),"Updated source invalidates cache")
	DirAccess.remove_absolute(stamp)
	check(cache.is_map_ready("de_dust2"),"Prepared cache works with CS2 absent")
	var queue=load("res://scripts/map/MapPreparationQueue.gd").new();queue.enqueue("invalid/name","")
	var result:Dictionary=queue.poll()
	check(not result.is_empty() and not result.result.ok,"Synchronous tool start failure reaches UI")
	check(queue.active==null and queue.pending.is_empty(),"Failed queue remains idle")
	check(cache.delete_map("de_dust2") and not cache.is_map_ready("de_dust2"),"Delete cache only removes generated map")
	check(not cache.delete_map("../escape"),"Delete rejects traversal")
	var report:={"checks":checks,"failures":failures};save_json(ProjectSettings.globalize_path("res://../artifacts/milestone-8-core-report.json"),report)
	print(JSON.stringify(report));quit(0 if failures.is_empty() else 1)

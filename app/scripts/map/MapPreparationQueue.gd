extends RefCounted
## Application-lifetime serial queue: switching Replay never starts a second exporter.
var active: RefCounted
var pending: Array[Dictionary] = []
var results := {}
var prepare_counts := {}
var completed_results: Array[Dictionary] = []
func enqueue(name: String, installation: String) -> void:
	if active != null and active.map_name == name:return
	for item in pending:
		if item.name == name:return
	pending.append({"name":name,"installation":installation});_start_next()
func _start_next() -> void:
	if active != null or pending.is_empty():return
	var item:Dictionary=pending.pop_front()
	active=preload("res://scripts/map/MapPreparationService.gd").new()
	var error:Error=active.prepare(item.name,item.installation)
	if error!=OK:
		results[item.name]={"ok":false,"error":"Map tool unavailable","error_code":"MAP_CONVERSION_FAILED"}
		completed_results.append({"name":item.name,"result":results[item.name]});active=null
	else:prepare_counts[item.name]=int(prepare_counts.get(item.name,0))+1
func poll() -> Dictionary:
	var completed:={}
	if active!=null and active.done():
		var name:String=active.map_name;var result:Dictionary=active.finish()
		result.output=active.output;results[name]=result;completed={"name":name,"result":result};active=null
	if not completed.is_empty():completed_results.append(completed)
	_start_next()
	return completed_results.pop_front() if not completed_results.is_empty() else {}
func state_for(name: String) -> String:
	if active!=null and active.map_name==name:return active.get_status()
	for item in pending:
		if item.name==name:return "Queued — " + name
	if results.has(name):return "Ready" if results[name].get("ok",false) else "Failed — Using fallback"
	return "Not Prepared"
func cancel(name: String) -> void:
	pending=pending.filter(func(item):return item.name!=name)
	if active!=null and active.map_name==name:active.cancel_request()
func finish() -> void:
	pending.clear()
	if active!=null:active.cancel_request();active.finish();active=null

extends RefCounted
## Immutable ordered snapshots. No dependency on the previous playback time.
var events: Array = []
var endings := {}
func build(all_events: Array) -> void:
	events.clear(); endings.clear()
	var planted: RefCounted
	for event in all_events:
		if not event.type.begins_with("bomb_"): continue
		events.append(event)
		if event.type == "bomb_plant": planted = event
		elif event.type in ["bomb_defuse", "bomb_explode"]:
			if planted != null: endings[planted.id] = {"time": event.time, "type": event.type}
			planted = null
		elif event.type == "bomb_reset": planted = null
func at(time: float) -> Dictionary:
	var lo := 0; var hi := events.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if events[mid].time <= time: lo = mid + 1
		else: hi = mid
	var result := {"state": "Unknown", "position": Vector3.ZERO, "has_position": false, "carrier": "", "remaining": -1.0, "outcome": ""}
	if lo == 0: return result
	var event = events[lo - 1]
	result.state = {"bomb_reset": "Unknown", "bomb_pickup": "Carried", "bomb_drop": "Dropped", "bomb_plant": "Planted", "bomb_defuse": "Defused", "bomb_explode": "Exploded"}[event.type]
	result.position = event.position; result.has_position = event.has_position
	result.carrier = event.actor_player_id if result.state == "Carried" else ""
	if result.state == "Dropped" and not event.position_frames.is_empty():
		var frames: Array = event.position_frames
		lo = 0; hi = frames.size()
		while lo < hi:
			var mid := (lo + hi) / 2
			if frames[mid].time <= time: lo = mid + 1
			else: hi = mid
		if lo > 0:
			var a = frames[lo - 1]
			result.position = a.position
			if lo < frames.size():
				var b = frames[lo]
				result.position = a.position.lerp(b.position, clampf((time - a.time) / (b.time - a.time), 0, 1))
	if result.state == "Planted" and endings.has(event.id):
		result.remaining = maxf(0, endings[event.id].time - time)
		result.outcome = endings[event.id].type.trim_prefix("bomb_")
	return result

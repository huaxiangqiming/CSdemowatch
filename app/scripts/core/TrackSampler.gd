extends RefCounted
## Stateless sampling makes backward seeking identical to forward playback.

static func sample(frames: Array, seconds: float) -> Dictionary:
	if seconds <= frames[0].time:
		return frames[0]
	if seconds >= frames[-1].time:
		return frames[-1]
	var low := 0
	var high := frames.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if frames[middle].time <= seconds:
			low = middle
		else:
			high = middle
	var a: Dictionary = frames[low]
	var b: Dictionary = frames[high]
	var weight: float = (seconds - a.time) / (b.time - a.time)
	var start: Vector3 = a.position
	# Left-hold discrete state; never blend across missing data or respawns.
	var result: Dictionary = a.duplicate()
	if a.get("available", true) and b.get("available", true) \
		and a.get("alive", true) == b.get("alive", true) \
		and a.get("team", "") == b.get("team", "") \
		and (not a.has("tick") or (b.time - a.time <= 0.25 and start.distance_to(b.position) <= 256.0)):
		result.position = start.lerp(b.position, weight)
		result.yaw = lerp_angle(a.yaw, b.yaw, weight)
	return result

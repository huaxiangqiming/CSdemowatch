extends RefCounted
var id := ""
var type := ""
var actor_player_id := ""
var actor_team := "UNKNOWN"
var throw_time := 0.0
var end_time := 0.0
var frames: Array = []

func decode(raw: Dictionary) -> void:
	for key in ["id", "type", "actor_player_id", "actor_team", "throw_time", "end_time"]: set(key, raw[key])
	for frame in raw.frames:
		frames.append({"time": float(frame.time), "position": Vector3(frame.position.x, frame.position.y, frame.position.z)})

func frame_index(time: float) -> int:
	var lo := 0
	var hi := frames.size()
	while lo < hi:
		var mid := (lo + hi) / 2
		if frames[mid].time <= time: lo = mid + 1
		else: hi = mid
	return maxi(0, lo - 1)

func position_at(time: float) -> Vector3:
	var i := frame_index(time)
	if i >= frames.size() - 1: return frames[-1].position
	var a: Dictionary = frames[i]
	var b: Dictionary = frames[i + 1]
	return a.position.lerp(b.position, clampf((time - a.time) / (b.time - a.time), 0, 1))

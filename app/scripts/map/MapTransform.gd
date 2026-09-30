extends RefCounted
## The sole CS2 -> Godot coordinate boundary. No parser-side conversion.
var scale_factor := 0.01
var rotation_degrees := 0.0
var offset := Vector3.ZERO

func position_to_godot(raw: Vector3) -> Vector3:
	return Basis(Vector3.UP, deg_to_rad(rotation_degrees)) * Vector3(raw.x, raw.z, -raw.y) * scale_factor + offset

func yaw_to_godot(raw_radians: float) -> float:
	# CS2 0 = +X. Godot marker 0 = -Z. CS2 +90 = +Y -> Godot -Z.
	return raw_radians - PI / 2.0 + deg_to_rad(rotation_degrees)

func state_to_godot(raw: Dictionary) -> Dictionary:
	var converted := raw.duplicate()
	converted.position = position_to_godot(raw.position)
	converted.yaw = yaw_to_godot(raw.yaw)
	return converted

func replay_bounds(replay: Dictionary) -> AABB:
	if replay.get("prepared_transform") == [scale_factor, rotation_degrees, offset] and replay.has("prepared_bounds"):
		return replay.prepared_bounds
	var bounds := AABB()
	var initialized := false
	for frames in replay.tracks.values():
		for frame in frames:
			if not frame.available or not frame.alive:
				continue
			var point := position_to_godot(frame.position)
			if not initialized:
				bounds = AABB(point, Vector3.ZERO)
				initialized = true
			else:
				bounds = bounds.expand(point)
	return bounds if initialized else AABB(Vector3(-16, 0, -16), Vector3(32, 0, 32))

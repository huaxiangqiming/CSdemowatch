extends RefCounted
## Validated domain record: vectors are raw Source coordinates.
var id := ""
var position_frames: Array = []
var has_position := false
var type := ""
var time := 0.0
var tick := 0
var actor_player_id := ""
var actor_team := "UNKNOWN"
var position := Vector3.ZERO
var projectile_id := ""
var grenade_type := ""
var throw_time := 0.0
var activate_time := 0.0
var expire_time := 0.0
var patches: Array = []
var affected_players: Array = []
var origin := Vector3.ZERO
var direction := Vector3.ZERO
var impact := Vector3.ZERO
var has_impact := false
var direction_source := ""
var victim_player_id := ""
var victim_team := "UNKNOWN"
var assister_player_id := ""
var weapon := ""
var headshot := false
var damage := 0
var health_remaining := 0
var damage_source := ""

static func point(raw: Dictionary) -> Vector3:
	return Vector3(raw.x, raw.y, raw.z)

func decode(raw: Dictionary) -> void:
	has_position = raw.has("position")
	for frame in raw.get("position_frames", []):
		position_frames.append({"time": float(frame.time), "position": point(frame.position)})
	for key in ["id", "type", "time", "tick", "actor_player_id", "actor_team", "projectile_id", "grenade_type", "throw_time", "activate_time", "expire_time", "direction_source", "victim_player_id", "victim_team", "assister_player_id", "weapon", "headshot", "damage", "health_remaining", "damage_source"]:
		if raw.has(key): set(key, raw[key])
	for key in ["position", "origin", "direction", "impact"]:
		if raw.has(key): set(key, point(raw[key]))
	has_impact = raw.has("impact")
	for patch in raw.get("patches", []):
		patches.append({"position": point(patch.position), "activate_time": float(patch.activate_time), "expire_time": float(patch.expire_time)})
	affected_players = raw.get("affected_players", []).duplicate(true)

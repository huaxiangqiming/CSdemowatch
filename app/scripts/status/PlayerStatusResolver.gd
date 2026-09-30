extends RefCounted
## Facts -> replay-time intervals. No UI nodes, wall-clock timers or proximity damage.
const Type = preload("res://scripts/status/PlayerStatusType.gd")
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
var buckets := {}
var event_index: RefCounted
var bomb_state: RefCounted
var damage_by_player := {}
var damage_count := 0
func build(index: RefCounted, bomb: RefCounted) -> void:
	event_index = index; bomb_state = bomb; buckets.clear(); damage_by_player.clear(); damage_count = 0
	for e in index.events:
		if e.type == "player_hurt":
			damage_count += 1
			if not damage_by_player.has(e.victim_player_id): damage_by_player[e.victim_player_id] = []
			damage_by_player[e.victim_player_id].append(e)
		if e.type == "flash":
			for affected in e.affected_players:
				_insert(affected.player_id, Type.FLASHED, e.time, e.time + affected.flash_duration)
		elif e.type == "player_hurt" and e.damage > 0:
			if e.damage_source == "hegrenade": _insert(e.victim_player_id, Type.HE_HIT, e.time, e.time + 0.8)
			elif e.damage_source in ["molotov", "incgrenade", "incendiary", "inferno"]: _insert(e.victim_player_id, Type.BURNING, e.time, e.time + 0.75)
func _insert(id: String, kind: String, start: float, end: float) -> void:
	for second in range(int(start), int(ceil(end)) + 1):
		if not buckets.has(second): buckets[second] = {}
		if not buckets[second].has(id): buckets[second][id] = []
		buckets[second][id].append({"kind": kind, "start": start, "end": end})
func is_inside_tactical_smoke(position: Vector3, time: float) -> bool:
	# Same abstract sphere as UtilityEffectView, not Source 2 voxel occupancy/LOS.
	# Player's body centre is 85 raw units above the tracked feet.
	for smoke in event_index.get_active_smoke(time):
		var center: Vector3 = smoke.position + Vector3(0, 0, Palette.SMOKE_RADIUS * 0.8)
		if (position + Vector3(0, 0, 85)).distance_squared_to(center) <= pow(Palette.SMOKE_RADIUS, 2): return true
	return false
func resolve(time: float, id: String, player: Dictionary) -> Array:
	if not player.get("available", false): return []
	var active := {}
	for interval in buckets.get(int(time), {}).get(id, []):
		if time >= interval.start and time < interval.end: active[interval.kind] = true
	if player.get("alive", false) and is_inside_tactical_smoke(player.position, time): active[Type.IN_SMOKE] = true
	var bomb: Dictionary = bomb_state.at(time)
	if bomb.state == "Carried" and bomb.carrier == id: active[Type.BOMB_CARRIER] = true
	var result := []
	for kind in Type.ORDER:
		if active.has(kind): result.append(kind)
	return result

func recent_damage(id: String, time: float, window := 5.0) -> Array:
	var events: Array = damage_by_player.get(id, [])
	var low := 0; var high := events.size()
	while low < high:
		var mid := (low + high) / 2
		if events[mid].time <= time: low = mid + 1
		else: high = mid
	var result := []
	for i in range(low - 1, -1, -1):
		if events[i].time < time - window or result.size() >= 4: break
		result.append(events[i])
	return result

extends RefCounted
const Event = preload("res://scripts/events/ReplayEvent.gd")
const Projectile = preload("res://scripts/events/ProjectileReplayState.gd")

func number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
func point(value: Variant) -> bool:
	return value is Dictionary and number(value.get("x")) and number(value.get("y")) and number(value.get("z"))
func valid_time(value: Variant, duration: float) -> bool:
	return number(value) and value >= 0 and value <= duration + 0.000001
func actor(value: Dictionary, ids: Dictionary) -> bool:
	return value.get("actor_player_id") is String and value.get("actor_team") in ["T", "CT", "UNKNOWN"] and (ids.has(value.actor_player_id) or (value.actor_player_id == "" and value.actor_team == "UNKNOWN"))
func error(message: String) -> Dictionary:
	return {"ok": false, "error": "Replay V2: " + message}
func tick_matches(frame: Dictionary, metadata: Dictionary) -> bool:
	return number(frame.get("tick")) and frame.tick == floor(frame.tick) and absf((frame.tick - metadata.source_start_tick) / metadata.source_tick_rate - frame.time) < 0.000001

func decode(raw: Dictionary, player_ids: Dictionary) -> Dictionary:
	if not raw.get("events") is Array or not raw.get("projectiles") is Array:
		return error("events and projectiles arrays are required")
	var duration: float = raw.metadata.duration
	var ids := {}
	var projectile_ids := {}
	var events: Array = []
	var projectiles: Array = []
	for p in raw.projectiles:
		if not p is Dictionary or not p.get("id") is String or p.id.is_empty() or ids.has(p.id): return error("invalid projectile ID")
		ids[p.id] = true
		projectile_ids[p.id] = true
		if p.get("type") not in ["smoke", "molotov", "incendiary", "he", "flash"] or not actor(p, player_ids): return error("invalid projectile type/actor")
		if not valid_time(p.get("throw_time"), duration) or not valid_time(p.get("end_time"), duration) or p.end_time < p.throw_time: return error("invalid projectile interval")
		if not p.get("frames") is Array or p.frames.is_empty(): return error("missing projectile frames")
		var previous := -1.0
		for f in p.frames:
			if not f is Dictionary or not valid_time(f.get("time"), duration): return error("invalid projectile frame")
			if f.time <= previous or f.time < p.throw_time or f.time > p.end_time + 0.000001 or not point(f.get("position")) or not tick_matches(f, raw.metadata): return error("invalid projectile frame time/tick/position")
			previous = f.time
		var state = Projectile.new()
		state.decode(p)
		projectiles.append(state)
	var previous := -1.0
	for e in raw.events:
		if not e is Dictionary or not e.get("id") is String or e.id.is_empty() or ids.has(e.id): return error("invalid event ID")
		ids[e.id] = true
		if not valid_time(e.get("time"), duration) or e.time < previous or not tick_matches(e, raw.metadata) or not actor(e, player_ids): return error("invalid event time/tick/actor")
		previous = e.time
		if e.get("type") not in ["smoke", "fire", "he", "flash", "shot", "kill", "player_hurt", "bomb_pickup", "bomb_drop", "bomb_plant", "bomb_defuse", "bomb_explode", "bomb_reset"]: return error("unknown event type")
		if e.has("position_frames"):
			if e.type != "bomb_drop" or not e.position_frames is Array: return error("position frames require bomb_drop")
			var last: float = e.time - 0.000001
			for frame in e.position_frames:
				if not frame is Dictionary or not valid_time(frame.get("time"), duration) or frame.time <= last or not point(frame.get("position")) or not tick_matches(frame, raw.metadata): return error("invalid bomb position frame")
				last = frame.time
		for key in ["projectile_id", "grenade_type", "direction_source", "victim_player_id", "victim_team", "assister_player_id", "weapon"]:
			if e.has(key) and not e[key] is String: return error("invalid string " + key)
		if e.has("projectile_id") and not projectile_ids.has(e.projectile_id): return error("unknown projectile reference")
		for key in ["position", "origin", "direction", "impact"]:
			if e.has(key) and not point(e[key]): return error("invalid vector " + key)
		for key in ["throw_time", "activate_time", "expire_time"]:
			if e.has(key) and not valid_time(e[key], duration): return error("invalid time " + key)
		if e.has("headshot") and not e.headshot is bool: return error("headshot must be boolean")
		if e.type in ["smoke", "fire", "he", "flash"]:
			if not point(e.get("position")) or not valid_time(e.get("throw_time"), duration) or not valid_time(e.get("activate_time"), duration) or not valid_time(e.get("expire_time"), duration): return error("invalid utility interval")
			if e.throw_time > e.time or e.activate_time != e.time or e.expire_time < e.time: return error("invalid utility order")
		if e.has("patches"):
			if not e.patches is Array or e.type != "fire": return error("patches require fire")
			for patch in e.patches:
				if not patch is Dictionary or not point(patch.get("position")) or not valid_time(patch.get("activate_time"), duration) or not valid_time(patch.get("expire_time"), duration): return error("invalid flame patch")
				if patch.activate_time < e.time or patch.expire_time > e.expire_time + 0.000001 or patch.expire_time < patch.activate_time: return error("invalid patch interval")
		if e.has("affected_players"):
			if not e.affected_players is Array or e.type != "flash": return error("invalid flash effects")
			for effect in e.affected_players:
				if not effect is Dictionary or not effect.get("player_id") is String or not player_ids.has(effect.player_id) or not number(effect.get("flash_duration")) or effect.flash_duration < 0: return error("invalid flashed player")
				if effect.has("flash_amount") and (not number(effect.flash_amount) or effect.flash_amount < 0 or effect.flash_amount > 1): return error("flash_amount must be between 0 and 1")
		if e.type == "shot":
			if not point(e.get("origin")) or not point(e.get("direction")): return error("shot needs origin and direction")
			if absf(Event.point(e.direction).length_squared() - 1.0) > 0.001: return error("shot direction must be normalized")
		if e.type == "player_hurt":
			if not player_ids.has(e.get("victim_player_id", "")) or e.get("victim_team") not in ["T", "CT", "UNKNOWN"] or not number(e.get("damage")) or e.damage < 0 or not number(e.get("health_remaining")) or e.health_remaining < 0 or not e.get("damage_source") is String or e.damage_source.is_empty(): return error("invalid player hurt")
		if e.type == "kill":
			if not player_ids.has(e.get("victim_player_id", "")) or e.get("victim_team") not in ["T", "CT", "UNKNOWN"] or not e.get("headshot") is bool or not e.get("weapon") is String: return error("invalid kill")
			if e.has("assister_player_id") and not player_ids.has(e.assister_player_id): return error("unknown assister")
		var event = Event.new()
		event.decode(e)
		events.append(event)
	return {"ok": true, "events": events, "projectiles": projectiles}

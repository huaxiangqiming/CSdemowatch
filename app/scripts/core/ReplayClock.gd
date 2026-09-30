extends RefCounted
## Sole source of replay time. Advance is explicit so tests need no wall clock.
signal time_changed(seconds: float)
signal state_changed

const SPEEDS := [0.5, 1.0, 2.0]
var current_time: float = 0.0
var duration: float = 0.0
var playback_speed: float = 1.0
var is_playing: bool = false


func configure(seconds: float) -> void:
	duration = maxf(0.0, seconds) if is_finite(seconds) else 0.0
	current_time = 0.0
	playback_speed = 1.0
	is_playing = false
	time_changed.emit(current_time)
	state_changed.emit()


func play() -> void:
	if duration <= 0.0:
		return
	if current_time >= duration:
		seek(0.0)
	is_playing = true
	state_changed.emit()


func pause() -> void:
	is_playing = false
	state_changed.emit()


func seek(seconds: float) -> void:
	if not is_finite(seconds):
		return
	current_time = clampf(seconds, 0.0, duration)
	if current_time >= duration:
		is_playing = false
	time_changed.emit(current_time)
	state_changed.emit()


func set_speed(speed: float) -> void:
	if speed in SPEEDS:
		playback_speed = speed
		state_changed.emit()


func advance(delta: float) -> void:
	if not is_playing or not is_finite(delta) or delta <= 0.0:
		return
	current_time = minf(current_time + delta * playback_speed, duration)
	if current_time >= duration:
		is_playing = false
		state_changed.emit()
	time_changed.emit(current_time)

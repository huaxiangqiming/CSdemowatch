extends Node3D
## Rig translates; Pivot owns yaw/pitch; Camera moves only along its local Z.
const DEFAULT_SIZE := 46.0
const MIN_SIZE := 12.0
const MAX_SIZE := 65.0
const MIN_PITCH := 15.0
const MAX_PITCH := 89.9
var target := Vector3.ZERO
var size := DEFAULT_SIZE
var yaw := 38.0
var pitch := 45.0
var perspective := false
var _panning := false
var _orbiting := false
var _ground := Plane(Vector3.UP, 0.0)
var _home_target := Vector3.ZERO
var _home_size := DEFAULT_SIZE
var _max_size := MAX_SIZE
var _pan_extent := 24.0
var clearance_height := 0.5
var home_yaw := 38.0
var home_pitch := 45.0
var pan_speed := 1.0
var zoom_speed := 1.0
var orbit_sensitivity := 1.0
@onready var pivot: Node3D = $Pivot
@onready var lens: Camera3D = $Pivot/Camera3D

func configure_bounds(bounds: AABB, is_mock: bool) -> void:
	_home_target = Vector3.ZERO if is_mock else bounds.get_center()
	_home_size = DEFAULT_SIZE if is_mock else maxf(DEFAULT_SIZE, maxf(bounds.size.x, bounds.size.z) * 1.9)
	_max_size = MAX_SIZE if is_mock else maxf(MAX_SIZE, _home_size * 2.0)
	_pan_extent = 24.0 if is_mock else maxf(bounds.size.x, bounds.size.z)
	_ground = Plane(Vector3.UP, 0 if is_mock else bounds.position.y - 0.05)
	lens.far = maxf(400, _home_size * 8.0)
	reset_view()

func _ready() -> void:
	reset_view()

func reset_view() -> void:
	target = _home_target
	size = _home_size
	yaw = home_yaw
	pitch = home_pitch
	perspective = false
	_update_pose()

func set_preset(index: int) -> void:
	if index == 1:
		yaw = 0
		pitch = MAX_PITCH
		perspective = false
	elif index == 2:
		yaw = 38
		pitch = 45
		perspective = false
	else:
		pitch = 35
		perspective = true
	_update_pose()

func toggle_projection() -> void:
	perspective = not perspective
	_update_pose()

func _update_pose() -> void:
	if not is_instance_valid(lens):
		return
	position = target
	pivot.rotation = Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0)
	lens.projection = Camera3D.PROJECTION_PERSPECTIVE if perspective else Camera3D.PROJECTION_ORTHOGONAL
	lens.size = size
	# Match the vertical view span when changing projection. Keep the camera
	# above the supplied scene ceiling; this conservative bound avoids walls.
	var distance := size / (2.0 * tan(deg_to_rad(lens.fov / 2.0)))
	var framing_offset := -size * (2.7 / DEFAULT_SIZE)
	distance = maxf(distance, (clearance_height - target.y + absf(framing_offset)) / sin(deg_to_rad(pitch)))
	lens.position = Vector3(0, 0, distance)
	lens.v_offset = framing_offset

func zoom(steps: float) -> void:
	size = clampf(size * pow(0.88, steps * zoom_speed), MIN_SIZE, _max_size)
	_update_pose()

func orbit_pixels(relative: Vector2) -> void:
	yaw = wrapf(yaw - relative.x * 0.3 * orbit_sensitivity, -180, 180)
	pitch = clampf(pitch + relative.y * 0.3 * orbit_sensitivity, MIN_PITCH, MAX_PITCH)
	_update_pose()

func pan_pixels(previous: Vector2, current: Vector2) -> void:
	var a: Variant = _ground.intersects_ray(lens.project_ray_origin(previous), lens.project_ray_normal(previous))
	var b: Variant = _ground.intersects_ray(lens.project_ray_origin(current), lens.project_ray_normal(current))
	if a != null and b != null:
		target += (a - b) * pan_speed
		target.x = clampf(target.x, _home_target.x - _pan_extent, _home_target.x + _pan_extent)
		target.z = clampf(target.z, _home_target.z - _pan_extent, _home_target.z + _pan_extent)
		_update_pose()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_HOME:
			reset_view()
		elif event.keycode in [KEY_1, KEY_2, KEY_3]:
			set_preset(event.keycode - KEY_0)
		elif event.keycode == KEY_P:
			toggle_projection()
		else:
			return
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = false
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_LEFT]:
			_orbiting = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_panning = false
		_orbiting = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and event.alt_pressed):
			_orbiting = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom(1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if _panning:
			pan_pixels(event.position - event.relative, event.position)
		elif _orbiting:
			orbit_pixels(event.relative)
		else:
			return
		get_viewport().set_input_as_handled()

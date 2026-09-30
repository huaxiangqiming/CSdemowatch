extends Node3D
## Display only: no file IO, clock, or interpolation here.

const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
const T_COLOR := Palette.T
const CT_COLOR := Palette.CT
var player_name := ""
var _material: StandardMaterial3D
var _appearance_key := ""
var _xray: MeshInstance3D
var _xray_material: StandardMaterial3D
var _alive := true
var _view_mode := 1
var _carrier := false
var name_size := 14.0
var _team := "T"
func set_carrier(value: bool) -> void:
	_carrier = value
	$Name.modulate = Palette.BOMB if value else (Palette.team_color(_team) if _alive else Palette.DEAD.darkened(0.25))

func configure(player: Dictionary) -> void:
	player_name = player.name
	_material = StandardMaterial3D.new()
	_material.roughness = 0.75
	$Body.material_override = _material
	$Facing/Shaft.material_override = _material
	$Facing/Tip.material_override = _material
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Segoe UI", "Microsoft YaHei UI"])
	$Name.font = font
	$Name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	$Name.outline_size = 4
	$Name.render_priority = 20
	$Name.outline_render_priority = 19
	_xray = MeshInstance3D.new()
	_xray.name = "XRay"
	_xray.mesh = $Body.mesh
	_xray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_xray_material = StandardMaterial3D.new()
	_xray_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_xray_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_xray_material.no_depth_test = true
	_xray_material.render_priority = 10
	_xray.material_override = _xray_material
	add_child(_xray)
	_update_appearance(player.team, true)


func apply_state(state: Dictionary) -> void:
	position = state.position
	$Facing.rotation.y = state.yaw
	visible = state.available
	_update_appearance(state.team, state.alive)

func _update_appearance(team: String, alive: bool) -> void:
	_team = team
	var key := team + str(alive) + Palette.team_color(team).to_html()
	if key == _appearance_key:
		return
	_appearance_key = key
	_alive = alive
	var color := Palette.team_color(team)
	if not alive:
		color = Palette.DEAD
	_material.albedo_color = color
	$Body.scale.y = 1.0 if alive else 0.25
	$Body.position.y = 0.85 if alive else 0.22
	$Facing.visible = alive
	$Name.text = "%s / %s%s" % [player_name, team, "" if alive else " (dead)"]
	$Name.modulate = color if alive else color.darkened(0.25)
	$Name.font_size = 56
	_xray.position = $Body.position
	_xray.scale = $Body.scale
	_xray_material.albedo_color = color
	set_view_mode(_view_mode)

func set_view_mode(mode: int) -> void:
	_view_mode = mode
	_xray.visible = mode != 0
	_xray_material.albedo_color.a = (0.5 if mode == 2 else 0.3) if _alive else 0.08
	$Name.no_depth_test = mode != 0

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var span := camera.size
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		span = 2.0 * camera.global_position.distance_to($Name.global_position) * tan(deg_to_rad(camera.fov * 0.5))
	# Keep text legible through zoom/projection changes; billboard handles orbit.
	$Name.pixel_size = (name_size if _alive else name_size * 0.8) * span / (maxf(1, get_viewport().get_visible_rect().size.y) * $Name.font_size)

extends RefCounted
const T := Color("ffb454")
const CT := Color("66b9ff")
const UNKNOWN := Color("b5bbc3")
const DEAD := Color("77808a")
const BOMB := Color("ff5b68")
const FLASH := Color("fff9e8")
const SMOKE_OPACITY := [0.35, 0.55, 0.75]
const SMOKE := Color(0.48, 0.51, 0.54, 0.20)
const FIRE := Color(0.95, 0.27, 0.08, 0.50)
const SMOKE_RADIUS := 145.0
const FIRE_PATCH_RADIUS := 55.0
const SHOT_LENGTH := 1200.0
const SHOT_LIFETIME := 0.12
static var t_accent := T
static var ct_accent := CT
static func set_colors(t: Color, ct: Color) -> void:
	t_accent = t; ct_accent = ct
static func team_color(team: String) -> Color:
	return t_accent if team == "T" else (ct_accent if team == "CT" else UNKNOWN)

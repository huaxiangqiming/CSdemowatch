extends MeshInstance3D
## Reusable batched line surface; no node per segment or per shot.
var _lines := ImmediateMesh.new()
var _material := StandardMaterial3D.new()
var _open := false
var line_count := 0
func _ready() -> void:
	mesh = _lines
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.no_depth_test = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.render_priority = 14
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
func begin() -> void:
	_lines.clear_surfaces()
	_open = false
	line_count = 0
func add_line(a: Vector3, b: Vector3, color: Color) -> void:
	if not _open:
		_lines.surface_begin(Mesh.PRIMITIVE_LINES, _material)
		_open = true
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(a)
	_lines.surface_set_color(color)
	_lines.surface_add_vertex(b)
	line_count += 1
func ring(center: Vector3, radius: float, color: Color) -> void:
	for i in 32:
		var a := TAU * i / 32.0
		var b := TAU * (i + 1) / 32.0
		add_line(center + Vector3(cos(a), 0, sin(a)) * radius, center + Vector3(cos(b), 0, sin(b)) * radius, color)
func finish() -> void:
	if _open: _lines.surface_end()
	_open = false

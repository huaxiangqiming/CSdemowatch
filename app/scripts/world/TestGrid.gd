extends MeshInstance3D
## Visual ruler on the test Plane; one simple unlit line mesh.

func _ready() -> void:
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-16, 17, 2):
		var color := Color("617180") if i == 0 else Color("3c4a57")
		lines.surface_set_color(color)
		lines.surface_add_vertex(Vector3(i, 0.015, -16))
		lines.surface_add_vertex(Vector3(i, 0.015, 16))
		lines.surface_add_vertex(Vector3(-16, 0.015, i))
		lines.surface_add_vertex(Vector3(16, 0.015, i))
	lines.surface_end()
	mesh = lines
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material_override = material

extends Node3D
## Small world-space reference; independent of map offset.
func _ready() -> void:
	name = "WorldAxes"
	for i in 3:
		var direction: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][i]
		var color: Color = [Color("ed6b68"), Color("6bdd91"), Color("6ea5ff")][i]
		var mesh := ImmediateMesh.new()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		material.render_priority = 5
		mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
		mesh.surface_add_vertex(Vector3.ZERO)
		mesh.surface_add_vertex(direction * 4)
		mesh.surface_end()
		var line := MeshInstance3D.new()
		line.mesh = mesh
		add_child(line)
		var label := Label3D.new()
		label.text = ["X", "Y", "Z"][i]
		label.position = direction * 4.3
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = color
		label.no_depth_test = true
		label.render_priority = 15
		label.font_size = 32
		add_child(label)
	var origin := Label3D.new()
	origin.text = "0"
	origin.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	origin.no_depth_test = true
	origin.render_priority = 15
	add_child(origin)

extends Node3D
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
var body: MeshInstance3D
var patches: MultiMeshInstance3D
var rings: MeshInstance3D
var material: StandardMaterial3D
var event_id := ""
var patch_count := 0
var options := {"smoke_tint": true, "smoke_marker": true, "smoke_opacity": 1}
var outline: MeshInstance3D
var outline_material: StandardMaterial3D
var star: MeshInstance3D
var star_material: StandardMaterial3D
func _ready() -> void:
	body = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1; sphere.height = 2; sphere.radial_segments = 16; sphere.rings = 8
	body.mesh = sphere
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = 2
	body.material_override = material
	add_child(body)
	outline = MeshInstance3D.new()
	var torus := TorusMesh.new(); torus.inner_radius = 0.97; torus.outer_radius = 1.03; torus.rings = 32; torus.ring_segments = 6
	outline.mesh = torus
	outline_material = StandardMaterial3D.new(); outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; outline_material.no_depth_test = true
	outline.material_override = outline_material; add_child(outline)
	star = MeshInstance3D.new()
	var star_mesh := ArrayMesh.new()
	var vertices := PackedVector3Array()
	for i in 8:
		var direction := Vector3(cos(i * TAU / 8), 0, sin(i * TAU / 8))
		var side := Vector3(-direction.z, 0, direction.x) * 0.16
		vertices.append(direction * 0.4 + side); vertices.append(direction * 2.2); vertices.append(direction * 0.4 - side)
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX] = vertices
	star_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays); star.mesh = star_mesh
	star_material = StandardMaterial3D.new(); star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; star_material.no_depth_test = true; star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; star_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	star.material_override = star_material; add_child(star)
	rings = preload("res://scripts/rendering/TacticalLines.gd").new()
	add_child(rings)
	patches = MultiMeshInstance3D.new()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var disc := CylinderMesh.new()
	disc.top_radius = 1; disc.bottom_radius = 1; disc.height = 0.06; disc.radial_segments = 12
	multimesh.mesh = disc
	multimesh.instance_count = 64
	multimesh.visible_instance_count = 0
	patches.multimesh = multimesh
	var fire_material := StandardMaterial3D.new()
	fire_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_material.no_depth_test = true
	fire_material.vertex_color_use_as_albedo = true
	fire_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_material.render_priority = 3
	patches.material_override = fire_material
	add_child(patches)

func show_event(event: RefCounted, time: float, transform: RefCounted) -> void:
	event_id = event.id
	position = transform.position_to_godot(event.position)
	var color := Palette.team_color(event.actor_team)
	var scale_factor: float = transform.scale_factor
	outline.visible = event.type == "smoke"
	star.visible = event.type == "flash"
	outline_material.albedo_color = color
	material.no_depth_test = true
	body.visible = event.type != "fire"
	patches.visible = event.type == "fire"
	patch_count = 0
	rings.begin()
	match event.type:
		"smoke":
			var radius: float = Palette.SMOKE_RADIUS * scale_factor
			body.position = Vector3.UP * radius * 0.8
			body.scale = Vector3.ONE * radius
			var tint := Palette.SMOKE.lerp(color, 0.22) if options.smoke_tint else Palette.SMOKE
			tint.a = Palette.SMOKE_OPACITY[options.smoke_opacity]
			material.albedo_color = tint
			outline.scale = Vector3(radius, 1, radius)
			outline.position.y = 0.06
			rings.ring(Vector3.UP * 0.04, radius, color)
			if options.smoke_marker:
				rings.ring(Vector3.UP * radius * 1.8, radius * 0.3, color)
				rings.add_line(Vector3(-0.25, radius * 1.8, 0), Vector3(0.25, radius * 1.8, 0), color)
		"fire":
			var source: Array = event.patches
			if source.is_empty(): source = [{"position": event.position, "activate_time": event.time, "expire_time": event.expire_time}]
			if patches.multimesh.instance_count < source.size(): patches.multimesh.instance_count = source.size()
			for patch in source:
				if time < patch.activate_time or time >= patch.expire_time: continue
				var center: Vector3 = transform.position_to_godot(patch.position) - position + Vector3.UP * 0.06
				var radius: float = Palette.FIRE_PATCH_RADIUS * scale_factor
				var pulse := 1.0 + 0.06 * sin((time - event.time) * 8.0 + patch_count)
				patches.multimesh.set_instance_transform(patch_count, Transform3D(Basis.from_scale(Vector3(radius * pulse, 1, radius * pulse)), center))
				patches.multimesh.set_instance_color(patch_count, Palette.FIRE)
				rings.ring(center + Vector3.UP * 0.03, radius, color)
				patch_count += 1
			patches.multimesh.visible_instance_count = patch_count
		"he", "flash":
			var fraction := clampf((time - event.time) / maxf(0.001, event.expire_time - event.time), 0, 1)
			var radius := lerpf(0.3, 0.65, fraction) if event.type == "he" else lerpf(0.2, 0.65, minf(fraction * 3, 1))
			body.position = Vector3.ZERO
			body.scale = Vector3.ONE * radius
			material.albedo_color = Color(1, 1, 1, (1 - fraction) * 0.65) if event.type == "flash" else Color(color, (1 - fraction) * 0.35)
			rings.ring(Vector3.UP * 0.03, radius, color)
			if event.type == "flash":
				var elapsed: float = time - event.time
				var brightness := 1.0 if elapsed <= 0.08 else clampf(1 - (elapsed - 0.08) / 0.17, 0, 1)
				material.albedo_color = Color(Palette.FLASH, brightness)
				star_material.albedo_color = Color(Palette.FLASH, brightness)
				star.scale = Vector3.ONE * lerpf(0.8, 1.4, fraction)
				var burst := lerpf(0.5, 2.2, fraction)
				rings.ring(Vector3.ZERO, burst, Color(Palette.FLASH, 1 - fraction))
				rings.ring(Vector3.ZERO, burst * 1.1, color)
				for i in 8:
					var direction := Vector3(cos(i * TAU / 8), 0, sin(i * TAU / 8))
					rings.add_line(direction * burst * 0.35, direction * burst * 1.4, Color(Palette.FLASH, 1 - fraction))
			else:
				rings.ring(Vector3.ZERO, lerpf(0.3, 2.5, fraction), Color(color, 1 - fraction))
				rings.ring(Vector3.UP * 0.08, lerpf(0.2, 1.8, fraction), Color(color, 1 - fraction))
	rings.finish()

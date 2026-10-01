extends Node3D
## Owns map selection, assets, gray materials, coordinate configuration and fallback.
const Definition = preload("res://scripts/map/MapDefinition.gd")
const Transform = preload("res://scripts/map/MapTransform.gd")
var definition: RefCounted
var map_transform: RefCounted = Transform.new()
var model: Node3D
var map_bounds := AABB()
var status := "Debug Plane"
var map_color := Color("929b93")
var ground_color := Color("a4ada5")
var opacity := 1.0
var view_mode := 1
var material: StandardMaterial3D
var fallback: MeshInstance3D
var loaded_map := ""
var assets = preload("res://scripts/map/MapAssetManager.gd").new()
var loading_ms := 0
var triangles := 0
var glb_bytes := 0
var roof_removed := 0
var preparation_state := "Not Prepared"
var source_metadata := {}
var cache_hit := false
var prepared_asset := {}
var cutaway_enabled := false
var cutaway_height := 0.0
var cutaway_material: ShaderMaterial
var cutaway_opaque: ShaderMaterial
var cutaway_transparent: ShaderMaterial
var cutaway_map := ""

func set_cutaway(enabled: bool, height: float) -> void:
	cutaway_enabled = enabled
	cutaway_height = height
	if cutaway_material != null:
		cutaway_material.set_shader_parameter("ceiling_height", height)
	if is_instance_valid(model):
		for node in model.find_children("*", "MeshInstance3D", true, false):
			node.material_override = cutaway_material if enabled else material

func configure(map_name: String, replay: Dictionary, plane: MeshInstance3D) -> void:
	var started := Time.get_ticks_msec()
	fallback = plane
	if loaded_map != map_name or (model == null and map_name != "test_plane"):
		if is_instance_valid(model):
			remove_child(model)
			model.queue_free()
		model = null
		triangles = 0; glb_bytes = 0; roof_removed = 0
		source_metadata = {}
		map_transform = Transform.new()
		definition = null
		status = "Debug Plane"
		loaded_map = map_name
		if map_name != "test_plane":
			var asset: Dictionary = prepared_asset if not prepared_asset.is_empty() else assets.prepare_map(map_name)
			prepared_asset = {}
			cache_hit = asset.get("cache_hit", false)
			var candidate = Definition.new()
			if asset.get("ok", false) and candidate.load_file(asset.path) and candidate.map_name == map_name:
				definition = candidate
				map_transform = definition.create_transform()
				_load_model()
			else:
				status = asset.get("error", "Tactical map unavailable") + " — Debug Plane"
	var bounds: AABB = map_transform.replay_bounds(replay)
	var is_mock := map_name == "test_plane"
	if cutaway_map != map_name:
		cutaway_map = map_name
		# Rendering-only trim above all recorded living player positions. Floors
		# remain in the asset and can always be restored with one toggle.
		set_cutaway(not is_mock, bounds.end.y + 2.0)
	plane.position = Vector3.ZERO if is_mock else Vector3(bounds.get_center().x, bounds.position.y - 0.05, bounds.get_center().z)
	plane.mesh.size = Vector2(32, 32) if is_mock else Vector2(maxf(32, bounds.size.x + 8), maxf(32, bounds.size.z + 8))
	plane.get_node("Grid").scale = Vector3(plane.mesh.size.x / 32, 1, plane.mesh.size.y / 32)
	plane.visible = model == null
	if model == null:
		map_bounds = bounds
	set_opacity(opacity)
	loading_ms = Time.get_ticks_msec() - started
	prepared_asset = {}

func _load_model() -> void:
	var metadata = JSON.parse_string(FileAccess.get_file_as_string(definition.file_path))
	if metadata is Dictionary: source_metadata=metadata; roof_removed = int(metadata.get("geometry_stats", {}).get("roof_removed_triangles", 0))
	if not FileAccess.file_exists(definition.model_path):
		status = "Map model missing — run tools/import-ancient.ps1"
		return
	var mesh_file := FileAccess.open(definition.model_path, FileAccess.READ)
	if mesh_file != null: glb_bytes = mesh_file.get_length(); mesh_file.close()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_file(definition.model_path, state)
	if result != OK:
		status = "Map GLB failed (%d) — Debug Plane" % result
		return
	model = document.generate_scene(state)
	if model == null:
		status = "Map GLB contains no scene — Debug Plane"
		return
	model.name = "TacticalGeometry"
	add_child(model)
	model.scale = Vector3.ONE * definition.scale
	model.rotation.y = deg_to_rad(definition.rotation)
	model.position = definition.offset
	material = StandardMaterial3D.new()
	material.roughness = 1
	material.render_priority = -10
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	cutaway_opaque = ShaderMaterial.new()
	cutaway_opaque.shader = preload("res://scripts/map/HeightCutaway.gdshader")
	cutaway_transparent = ShaderMaterial.new()
	cutaway_transparent.shader = preload("res://scripts/map/HeightCutawayTransparent.gdshader")
	cutaway_material = cutaway_opaque
	var initialized := false
	triangles = 0
	for node in model.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			var indices: int = node.mesh.surface_get_array_index_len(surface)
			triangles += (indices if indices > 0 else node.mesh.surface_get_array_len(surface)) / 3
		node.material_override = material
		var box: AABB = node.global_transform * node.get_aabb()
		map_bounds = map_bounds.merge(box) if initialized else box
		initialized = true
	status = "%s tactical geometry (local CS2)" % loaded_map
	definition.bounds = {"position": [map_bounds.position.x, map_bounds.position.y, map_bounds.position.z], "size": [map_bounds.size.x, map_bounds.size.y, map_bounds.size.z], "coordinate_system": "godot"}
	if definition.cache_version > 0:
		var data = JSON.parse_string(FileAccess.get_file_as_string(definition.file_path))
		if data is Dictionary and data.get("bounds") != definition.bounds:
			data.bounds = definition.bounds
			var file := FileAccess.open(definition.file_path, FileAccess.WRITE)
			if file != null: file.store_string(JSON.stringify(data, "  "))
	set_opacity(opacity)
	set_cutaway(cutaway_enabled, cutaway_height)

func set_palette(index: int) -> void:
	var palette: Dictionary = preload("res://scripts/config/ScenePalette.gd").preset(index)
	map_color = palette.map
	ground_color = palette.ground
	set_opacity(opacity)

func set_view_mode(mode: int) -> void:
	view_mode = mode
	set_opacity(opacity)

func set_opacity(value: float) -> void:
	opacity = clampf(value, 0.25, 1.0)
	var alpha := minf(opacity, 0.5) if view_mode == 2 else opacity
	if cutaway_material != null:
		cutaway_material = cutaway_opaque if alpha >= 0.999 else cutaway_transparent
		cutaway_material.set_shader_parameter("map_color", Color(map_color, alpha))
		set_cutaway(cutaway_enabled, cutaway_height)
	if material != null:
		material.albedo_color = Color(map_color, alpha)
		material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if alpha >= 0.999 else BaseMaterial3D.TRANSPARENCY_ALPHA
	if is_instance_valid(fallback):
		var mat: StandardMaterial3D = fallback.material_override
		mat.albedo_color = Color(ground_color, alpha)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED if alpha >= 0.999 else BaseMaterial3D.TRANSPARENCY_ALPHA

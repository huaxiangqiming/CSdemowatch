extends Node3D
## Shared low-poly utility geometry. Type is readable independently of team.
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
static var meshes := {}
static var materials := {}
var body := MeshInstance3D.new()
var band := MeshInstance3D.new()
var visual_type := ""
func _ready() -> void:
	if meshes.is_empty():
		var flash := CapsuleMesh.new(); flash.radius = 0.09; flash.height = 0.38; flash.radial_segments = 8; flash.rings = 3
		var smoke := CylinderMesh.new(); smoke.top_radius = 0.13; smoke.bottom_radius = 0.13; smoke.height = 0.25; smoke.radial_segments = 8
		var he := SphereMesh.new(); he.radius = 0.14; he.height = 0.28; he.radial_segments = 8; he.rings = 3
		var fire := CylinderMesh.new(); fire.top_radius = 0.045; fire.bottom_radius = 0.09; fire.height = 0.43; fire.radial_segments = 6
		var stripe := TorusMesh.new(); stripe.inner_radius = 0.095; stripe.outer_radius = 0.14; stripe.rings = 12; stripe.ring_segments = 6
		meshes = {"flash": flash, "smoke": smoke, "he": he, "molotov": fire, "incendiary": fire, "band": stripe}
	body.rotation.z = 0.65; band.rotation.z = 0.65
	add_child(body); add_child(band); band.mesh = meshes.band
func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not materials.has(key):
		var mat := StandardMaterial3D.new(); mat.albedo_color = color; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.no_depth_test = true
		materials[key] = mat
	return materials[key]
func configure(kind: String, team: String) -> void:
	visual_type = kind
	body.mesh = meshes.get(kind, meshes.he)
	body.material_override = _material(Palette.FLASH if kind == "flash" else (Palette.FIRE if kind in ["molotov", "incendiary"] else Palette.SMOKE.darkened(0.35)))
	band.material_override = _material(Palette.team_color(team))

extends Node3D
const Palette = preload("res://scripts/config/TeamVisualConfig.gd")
var state_model = preload("res://scripts/events/BombReplayState.gd").new()
var state := {}
var box: MeshInstance3D
var label: Label3D
var ring: MeshInstance3D
func _ready() -> void:
	box = MeshInstance3D.new()
	var mesh := BoxMesh.new(); mesh.size = Vector3(0.5, 0.28, 0.38); box.mesh = mesh
	var mat := StandardMaterial3D.new(); mat.albedo_color = Palette.BOMB; mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; mat.no_depth_test = true
	box.material_override = mat; add_child(box)
	label = Label3D.new(); label.text = "BOMB"; label.billboard = BaseMaterial3D.BILLBOARD_ENABLED; label.no_depth_test = true; label.modulate = Palette.BOMB; label.position.y = 0.8; label.font_size = 40; label.pixel_size = 0.009; add_child(label)
	ring = preload("res://scripts/rendering/TacticalLines.gd").new(); add_child(ring)
func update_state(time: float, controller: Node3D, enabled: bool) -> void:
	state = state_model.at(time)
	visible = enabled and state.state in ["Carried", "Dropped", "Planted"]
	var point: Vector3 = state.position
	if state.state == "Carried":
		var carrier: Dictionary = controller.current_states.get(state.carrier, {})
		visible = visible and carrier.get("available", false)
		point = carrier.get("position", Vector3.ZERO)
	else: visible = visible and state.has_position
	position = controller.map_transform.position_to_godot(point) + Vector3.UP * 0.2
	box.visible = state.state != "Carried"
	label.position.y = 2.2 if state.state == "Carried" else 0.8
	label.text = "C4" if state.state == "Carried" else "BOMB"
	label.visible = state.state != "Carried" # Unified PlayerStatusIndicator owns carrier UI.
	ring.begin()
	if visible and state.state == "Planted": ring.ring(Vector3.ZERO, 0.7 + 0.12 * sin(time * 5), Palette.BOMB)
	ring.finish()

extends Control
signal home_requested
signal log_requested
const Style = preload("res://scripts/application/ShellStyle.gd")
var heading: Label
var message: Label
var action: Label
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := Style.content(self)
	heading=Style.label("Unable to Open Demo",30);box.add_child(heading)
	message=Style.label("",18);message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(message)
	action=Style.label("",14);box.add_child(action)
	var buttons:=HBoxContainer.new();box.add_child(buttons)
	buttons.add_child(Style.button("Back to Home",func():home_requested.emit()))
	buttons.add_child(Style.button("View Log",func():log_requested.emit()))
func show_error(error: RefCounted) -> void:
	heading.text=error.title;message.text=error.message;action.text=error.suggested_action

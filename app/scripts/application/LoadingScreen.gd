extends Control
signal cancel_requested
const Style = preload("res://scripts/application/ShellStyle.gd")
var stage_label: Label
var detail: Label
var activity: ProgressBar
var elapsed := 0.0
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := Style.content(self)
	box.add_child(Style.label("Preparing your replay",30))
	stage_label=Style.label("Checking Replay Cache",22);box.add_child(stage_label)
	detail=Style.label("",16);box.add_child(detail)
	activity=ProgressBar.new();activity.indeterminate=true;activity.show_percentage=false;activity.custom_minimum_size.y=5;box.add_child(activity)
	box.add_child(Style.label("Processing locally. Larger matches may take a moment.",14))
	box.add_child(Style.button("Cancel / Back to Home",func():cancel_requested.emit()))
func stage(text: String) -> void: stage_label.text=text

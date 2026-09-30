extends VBoxContainer
signal prepare_requested
signal reload_requested
signal cancel_requested
var note: Label
var prepare_button: Button
var reload_button: Button
var cancel_button: Button
var activity: ProgressBar
func _ready() -> void:
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.custom_minimum_size.x=265;note.add_theme_font_size_override("font_size",12);add_child(note)
	prepare_button=Button.new();prepare_button.text="Prepare Tactical Map";prepare_button.pressed.connect(func():prepare_requested.emit());add_child(prepare_button)
	reload_button=Button.new();reload_button.text="Map ready — Reload Map";reload_button.pressed.connect(func():reload_requested.emit());add_child(reload_button);reload_button.hide()
	activity=ProgressBar.new();activity.indeterminate=true;activity.show_percentage=false;activity.custom_minimum_size.y=5;add_child(activity);activity.hide()
	cancel_button=Button.new();cancel_button.text="Cancel preparation";cancel_button.pressed.connect(func():cancel_requested.emit());add_child(cancel_button);cancel_button.hide()
func busy(text: String) -> void:
	note.text=text;prepare_button.disabled=true;activity.show();cancel_button.show();reload_button.hide()
func completed(ok: bool, message: String) -> void:
	note.text=message;prepare_button.disabled=false;activity.hide();cancel_button.hide();reload_button.visible=ok

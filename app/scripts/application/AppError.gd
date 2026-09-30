extends RefCounted
var code := ""
var title := "Unable to Open Demo"
var message := ""
var technical_details := ""
var recoverable := true
var suggested_action := "Choose another demo or return Home."
func _init(value := "", text := "", details := "") -> void:
	code = value; message = text; technical_details = details

extends Marker3D

@export var text: String = "Hello"

func set_text(new_text: String) -> void:
	text = new_text

func get_text() -> String:
	return text

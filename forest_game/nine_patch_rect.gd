extends NinePatchRect

@onready var dialogue_label: Label = $Text

@export var target_node: Node3D
@onready var cam: Camera3D = get_viewport().get_camera_3d()

func set_text(text: String) -> void:
	if dialogue_label.text and text == dialogue_label.text:
		return
	
	dialogue_label.text = text
	
	await get_tree().process_frame # let Label update
	update_box_size()

func update_box_size() -> void:
	var label_size = dialogue_label.get_minimum_size()
	var padding = Vector2(128, 128 * 2) # adjust for margins
	size = label_size + padding

func _process(delta: float) -> void:
	if not target_node or not cam:
		return
		
	if dialogue_label:
		set_text(target_node.get_text())

	# Get world position slightly above the character's head
	var world_pos = target_node.global_transform.origin

	# Project to screen position
	var screen_pos = cam.unproject_position(world_pos)

	# Move UI element to that screen position
	position = screen_pos

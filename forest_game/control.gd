extends Control

@export var button_data: Array[String] = ["..."]

@onready var hbox = $HBox

var button_scene = preload("res://Button.tscn")

func update_options(options: Array[String]) -> void:
	button_data = options
	update_buttons()

func _ready():
	create_custom_buttons()

func update_buttons():
	# Remove all existing button children from hbox
	for child in hbox.get_children():
		child.queue_free()
	
	# Create new buttons with updated data
	create_custom_buttons()

func create_custom_buttons():
	for i in range(button_data.size()):
		var button_instance = button_scene.instantiate()
		var data = button_data[i]
		
		# Agora button_instance JÁ É o TextureButton
		var label = button_instance.get_node("Text")
		
		# Configure the button
		label.text = data
		
		# Set size flags directly on the TextureButton
		button_instance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Connect directly
		button_instance.pressed.connect(_on_action_button_pressed.bind(data))
		
		hbox.add_child(button_instance)

func _on_action_button_pressed(action: String):
	print("Action selected: ", action)

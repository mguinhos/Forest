extends CanvasLayer
@onready var texturect: TextureRect = $TextureRect
@onready var node_3d: Node3D = get_node("../Tilt")

func _process(delta):
	# Get the current camera from the viewport
	var camera = get_viewport().get_camera_3d()
	
	if camera and node_3d:
		var world_pos = node_3d.global_position
		var screen_pos = camera.unproject_position(world_pos)
		texturect.position = screen_pos

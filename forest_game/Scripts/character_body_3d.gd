extends CharacterBody3D

# Movement speeds in m/s (meters per second)
var speed := 20.0  # 5 m/s = ~18 km/h (brisk walking/light jogging)
var jump_velocity := 10.0 # 4.5 m/s upward (realistic jump velocity)

# Physics constants
var gravity := 20.0  # Increased gravity for more intense falling (was 9.81)
var character_mass := 70.0  # Mass in kg (average human weight)
var terminal_velocity := -30.0  # Increased terminal velocity for faster falls

# Camera settings
@onready var camera: Camera3D = $Camera3D
var zoom_speed := 1.0
var min_zoom := 2.0
var max_zoom := 100.0

func get_effective_gravity() -> float:
	# Gravity affects all objects equally regardless of mass (F = ma, but a = F/m = mg/m = g)
	# Mass doesn't change gravitational acceleration, but we can simulate "heaviness" feel
	return gravity

func get_effective_jump_velocity() -> float:
	# Jump velocity - could be affected by character strength/mass ratio
	return jump_velocity

func get_input() -> void:
	var input_dir = Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("down") - Input.get_action_strength("up")
	).normalized()
	
	# Convert 2D input into 3D movement (x, z plane) - speeds in m/s
	velocity.x = input_dir.x * speed
	velocity.z = input_dir.y * speed

func _physics_process(delta: float) -> void:
	get_input()
	
	# Handle jumping
	if is_on_floor() and Input.is_action_just_pressed("top"):
		velocity.y = get_effective_jump_velocity()
	
	# Apply gravity with increasing intensity while falling
	if not is_on_floor():
		# Base gravity acceleration
		var fall_acceleration = get_effective_gravity()
		
		# Increase acceleration the longer we've been falling (more intense)
		if velocity.y < 0:  # If falling downward
			var fall_speed_ratio = abs(velocity.y) / abs(terminal_velocity)
			fall_acceleration *= (1.0 + fall_speed_ratio * 0.5)  # Up to 1.5x acceleration
		
		velocity.y -= fall_acceleration * delta
		# Clamp to terminal velocity
		velocity.y = max(velocity.y, terminal_velocity)
	
	# Move the character
	move_and_slide()
	
	# Handle zoom with mouse scroll
	if Input.is_action_just_pressed("scroll_up"):
		camera.size = max(min_zoom, camera.size - zoom_speed)
	elif Input.is_action_just_pressed("scroll_down"):
		camera.size = min(max_zoom, camera.size + zoom_speed)

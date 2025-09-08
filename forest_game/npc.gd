extends CharacterBody3D

@onready var open_ai = $OpenAI

@onready var npc_text: Label3D = $Avatar/Tilt/NPCText
@export var speed: float = 10
@export var gravity: float = 20.0
@export var patrol_points: Array[NodePath] = [] # arraste os pontos do editor
@export var wait_time: float = 0.1 # segundos em cada ponto

var current_point: int = 0
var waiting: bool = true
var wait_timer: float = 0.0
var messages: Array[Message] = []

func _ready() -> void:
	messages.append(Message.new())
	setup_message()

func setup_message():
	print(open_ai)
	
	open_ai.connect("gpt_response_completed", gpt_response_completed)
	open_ai.set_api(Globals.OPENROUTER_API_KEY)
	
	messages[0].set_role("user")
	messages[0].set_content("Crie uma questao de multipla escolha, de apenas a pergunta:")
	
	open_ai.prompt_gpt(messages, "llama-4-maverick", Globals.OPENROUTER_API_URL)

func gpt_response_completed(message: Message, response: Dictionary):
	messages.append(message)
	print(message.get_as_dict())
	
	# Update NPC text with the latest message
	if messages.size() > 1:
		npc_text.text = messages[messages.size() - 1].get_content()

func _physics_process(delta: float) -> void:
	# aplica gravidade
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	
	if patrol_points.size() == 0:
		move_and_slide()
		return
	
	if waiting:
		wait_timer -= delta
		if wait_timer <= 0:
			waiting = false
			current_point = (current_point + 1) % patrol_points.size()
	else:
		move_to_point(delta)
	
	move_and_slide()

func move_to_point(delta: float) -> void:
	var target_node = get_node_or_null(patrol_points[current_point])
	if target_node == null:
		return
	
	var target_pos: Vector3 = target_node.global_transform.origin
	var dir: Vector3 = (target_pos - global_transform.origin)
	dir.y = 0 # não inclina pra cima/baixo
	
	if dir.length() > 0.1:
		dir = dir.normalized()
		velocity.x = dir.x * speed
		velocity.z = dir.z * speed
		# gira o NPC na direção do movimento
		#look_at(Vector3(target_pos.x, global_transform.origin.y, target_pos.z), Vector3.UP)
	else:
		velocity.x = 0
		velocity.z = 0
		waiting = true
		wait_timer = wait_time

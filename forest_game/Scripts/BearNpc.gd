extends CharacterBody3D

@export var Speed: float = 10.0
@export var Gravity: float = 20.0
@export var PatrolPoints: Array[NodePath] = [] # Drag Marker3D nodes here
@export var WaitTime: float = 0.1

var npc_marker: Marker3D
var current_point: int = 0
var waiting: bool = false  # Start moving immediately
var wait_timer: float = 0.0
var http_request: HTTPRequest
var api_key: String = ""
var player_nearby: bool = false
var interaction_cooldown: float = 0.0
var is_generating_question: bool = false

func _ready():
	#print("BearNpc _ready() called")
	npc_marker = $Avatar/Tilt/DialogueMarker
	npc_marker.set_text("Hi from GDScript!")
	
	# Create HTTPRequest node
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_openai_response)
	
	# Debug patrol points
	#print("Patrol points count: ", PatrolPoints.size())
	for i in range(PatrolPoints.size()):
		var node = get_node_or_null(PatrolPoints[i])
	
	initialize_openai()

func initialize_openai():
	var globals = get_node_or_null("/root/Globals")
	if globals and globals.has_method("get"):
		api_key = globals.get("OPENROUTER_API_KEY")
	else:
		# Fallback - you can set your API key directly here for testing
		api_key = ""  # Put your OpenRouter API key here if Globals doesn't work
		print("Warning: Globals node not found, using fallback API key")
	
	if api_key == "":
		npc_marker.set_text("No API key found!")
		print("Error: No OpenRouter API key found")
	else:
		npc_marker.set_text("AI Ready!")
		print("OpenRouter initialized successfully")
	
	# Test AI immediately to verify it works
	await get_tree().create_timer(2.0).timeout
	print("Testing AI connection...")
	generate_question()

func generate_question():
	if is_generating_question:
		print("Already generating a question, please wait...")
		return
		
	is_generating_question = true
	var prompt = """Crie uma questão de múltipla escolha do 9º ano sobre matemática básica. 

Responda EXATAMENTE neste formato XML (copie exatamente):

<form><question>Qual é 2+2?</question><choices><a>3</a><b>4</b><c>5</c><d>6</d></choices><correct>b</correct></form>

Substitua apenas:
- A pergunta por uma questão de matemática do 9º ano
- As opções a, b, c, d pelas respostas
- O correct pela letra da resposta certa

NÃO adicione texto antes ou depois do XML."""
	
	ask_ai(prompt, true)  # true indica que é para gerar questão

func ask_ai(prompt: String, is_question_generation: bool = false):
	if api_key == "":
		print("Error: No API key available")
		npc_marker.set_text("No API key!")
		is_generating_question = false
		return
	
	if is_question_generation:
		npc_marker.set_text("Criando questão...")
	else:
		npc_marker.set_text("Thinking...")
	
	print("Sending request to OpenRouter: ", prompt)
	
	var headers = [
		"Content-Type: application/json",
		"Authorization: Bearer " + api_key,
		"HTTP-Referer: https://your-site.com",  # Replace with your site
		"X-Title: Godot Game"  # Replace with your app name
	]
	
	var system_prompt = ""
	if is_question_generation:
		system_prompt = """You are an educational assistant. Create high school level multiple choice questions in Portuguese. 
Always respond with ONLY the XML format requested, with no additional text or explanations."""
	else:
		system_prompt = """You are a friendly forest bear NPC in a video game. Respond naturally and conversationally in Portuguese. 
Keep responses short (1-2 sentences max). Sometimes ask simple questions to engage the player. 
Your responses should fit the character of a gentle, curious forest bear who lives peacefully in the woods."""
	
	var body = {
		"model": "meta-llama/llama-4-maverick:free",
		"messages": [
			{"role": "system", "content": system_prompt},
			{"role": "user", "content": prompt}
		],
		"max_tokens": 150,
		"temperature": 0.7
	}
	
	# Store whether this is a question generation request
	http_request.set_meta("is_question_generation", is_question_generation)
	
	var json_body = JSON.stringify(body)
	var error = http_request.request("https://openrouter.ai/api/v1/chat/completions", headers, HTTPClient.METHOD_POST, json_body)
	
	if error != OK:
		print("HTTP request failed: ", error)
		npc_marker.set_text("Request failed!")
		is_generating_question = false

func _on_openai_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	print("OpenRouter response - Code: ", response_code, " Result: ", result)
	
	var was_question_generation = http_request.get_meta("is_question_generation", false)
	
	if response_code != 200:
		print("HTTP Error: ", response_code)
		npc_marker.set_text("API Error: " + str(response_code))
		is_generating_question = false
		return
	
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		print("JSON parse error: ", json.get_error_message())
		npc_marker.set_text("Invalid response")
		is_generating_question = false
		return
	
	var response_data = json.data
	print("Full response: ", response_data)
	
	if response_data.has("choices") and response_data.choices.size() > 0:
		var ai_message = response_data.choices[0].message.content
		print("AI Response: ", ai_message)
		
		if was_question_generation:
			process_question_response(ai_message)
		else:
			update_npc_text(ai_message)
	elif response_data.has("error"):
		print("API Error: ", response_data.error)
		npc_marker.set_text("API Error: " + str(response_data.error.message))
		is_generating_question = false
	else:
		print("Unexpected response format")
		npc_marker.set_text("Unexpected response")
		is_generating_question = false

func process_question_response(response_text: String):
	print("Processing question response: ", response_text)
	
	var xml_content = extract_xml_content(response_text)
	if xml_content == "":
		print("No valid XML found in response")
		update_npc_text("Erro ao criar questão")
		is_generating_question = false
		return
	
	print("Extracted XML: ", xml_content)
	
	var parser = XMLParser.new()
	if parser.open_buffer(xml_content.to_utf8_buffer()) != OK:
		print("Failed to parse XML")
		update_npc_text("AI returned invalid XML")
		is_generating_question = false
		return
	
	var question_text = ""
	var choices = []
	var correct_answer = ""
	
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var node_name = parser.get_node_name()
			
			if node_name == "question":
				if parser.read() == OK and parser.get_node_type() == XMLParser.NODE_TEXT:
					question_text = parser.get_node_data().strip_edges()
			
			elif node_name == "choices":
				# Process all choice options within the choices tag
				while parser.read() == OK:
					if parser.get_node_type() == XMLParser.NODE_ELEMENT_END and parser.get_node_name() == "choices":
						break
					elif parser.get_node_type() == XMLParser.NODE_ELEMENT:
						var choice_letter = parser.get_node_name()
						if parser.read() == OK and parser.get_node_type() == XMLParser.NODE_TEXT:
							var choice_text = parser.get_node_data().strip_edges()
							choices.append(choice_text)
							print("Found choice ", choice_letter, ": ", choice_text)
			
			elif node_name == "correct":
				if parser.read() == OK and parser.get_node_type() == XMLParser.NODE_TEXT:
					correct_answer = parser.get_node_data().strip_edges()
	
	print("Parsed question: ", question_text)
	print("Parsed choices: ", choices)
	print("Correct answer: ", correct_answer)
	
	if question_text != "" and choices.size() >= 2:
		update_npc_text(question_text)
		show_question_options(choices, correct_answer)
		is_generating_question = false
	else:
		print("Invalid question format - missing question or choices")
		update_npc_text("Erro ao processar questão")
		is_generating_question = false

func show_question_options(choices: Array, correct_answer: String):
	print("Showing question options: ", choices)
	var button_options = get_node_or_null("/root/Main/UICanvas/ButtonOptions")
	if button_options:
		print("ButtonOptions found, updating options...")
		if button_options.has_method("update_options"):
			# Converter Array para Array[String] se necessário
			var string_choices: Array[String] = []
			for choice in choices:
				string_choices.append(str(choice))
			button_options.update_options(string_choices)
			# Armazenar a resposta correta para verificação posterior
			button_options.set_meta("correct_answer", correct_answer)
		else:
			print("ButtonOptions doesn't have update_options method")
	else:
		print("ButtonOptions node not found! Trying alternative paths...")
		# Try alternative paths
		var ui_canvas = get_node_or_null("/root/Main/UICanvas")
		if ui_canvas:
			print("UICanvas found. Children:")
			for child in ui_canvas.get_children():
				print("  - ", child.name)
		else:
			print("UICanvas not found either!")

func extract_xml_content(response: String) -> String:
	print("Extracting XML from response: ", response)
	
	# Primeiro, vamos tentar encontrar o XML mesmo se tiver texto extra
	var start_markers = ["<form>", "<form", "<?xml"]
	var start_idx = -1
	
	for marker in start_markers:
		start_idx = response.find(marker)
		if start_idx != -1:
			break
	
	if start_idx == -1:
		print("No XML markers found in response")
		return ""
	
	var end_idx = response.find("</form>", start_idx)
	if end_idx == -1:
		print("No </form> tag found in response")
		return ""
	
	end_idx += "</form>".length()
	var xml_content = response.substr(start_idx, end_idx - start_idx)
	
	# Limpar o XML se necessário
	xml_content = xml_content.strip_edges()
	
	print("Extracted and cleaned XML: ", xml_content)
	return xml_content

func update_npc_text(text: String):
	if npc_marker:
		npc_marker.set_text(text)

# Public function to be called by UI when player wants a new question
func request_new_question():
	if not is_generating_question:
		print("Player requested new question")
		generate_question()
	else:
		print("Already generating question, please wait...")

func _physics_process(delta: float) -> void:
	# Handle interaction cooldown
	if interaction_cooldown > 0:
		interaction_cooldown -= delta
	
	# Check for player nearby (alternative detection method)
	var player = get_node_or_null("/root/Main/Player")  # Adjust path to your player
	if not player:
		# Try different common player paths
		player = get_node_or_null("../Player")
		if not player:
			player = get_node_or_null("/root/Player")
		if not player:
			player = get_node_or_null("../../Player")
			
	if player:
		var distance_to_player = global_position.distance_to(player.global_position)

		if distance_to_player < 3.0 and not player_nearby and interaction_cooldown <= 0:
			player_nearby = true
			interaction_cooldown = 5.0  # 5 second cooldown
			ask_ai("O jogador se aproximou de você. Cumprimente-o como um urso amigável da floresta e pergunte se ele gostaria de responder uma questão educativa.")
		elif distance_to_player > 5.0:
			player_nearby = false
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= Gravity * delta
	else:
		velocity.y = 0
	
	# Patrol logic
	if PatrolPoints.is_empty():
		print("No patrol points set!")
		move_and_slide()
		return
	
	if waiting:
		wait_timer -= delta
		if wait_timer <= 0:
			waiting = false
			current_point = (current_point + 1) % PatrolPoints.size()
			print("Moving to patrol point: ", current_point)
	else:
		move_to_point(delta)
	
	move_and_slide()

func move_to_point(delta: float) -> void:
	var target_node = get_node_or_null(PatrolPoints[current_point])
	if not target_node:
		print("Target node not found for patrol point: ", current_point)
		return
	
	var target_pos = target_node.global_transform.origin
	var current_pos = global_transform.origin
	var dir = target_pos - current_pos
	dir.y = 0  # Only move on XZ plane
	
	var distance = dir.length()
	
	if distance > 0.5:  # Increased threshold for better reliability
		dir = dir.normalized()
		velocity.x = dir.x * Speed
		velocity.z = dir.z * Speed
	else:
		velocity.x = 0
		velocity.z = 0
		waiting = true
		wait_timer = WaitTime

func on_detection_area_body_entered(body: Node3D):
	#print("Detection area triggered by: ", body.name)
	if body.name == "Player":
		#print("Player detected! Calling AI...")
		ask_ai("O jogador se aproximou de você. Cumprimente-o como um urso amigável da floresta e pergunte se ele gostaria de responder uma questão educativa.")

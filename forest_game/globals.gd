extends Node

var OPENROUTER_API_URL: String = "https://forest-edu-is.fun/api/oai/v1"
var OPENROUTER_API_KEY: String = ""

var _setup_callback  = JavaScriptBridge.create_callback(_setup)

func _setup(args) -> void:
	# Remember to setup token here
	print(args)
	OPENROUTER_API_KEY = args[0]

func _ready():
	# Register a function so JS can call it
	var window = JavaScriptBridge.get_interface("window")
	
	if window:
		window.setup(_setup_callback)

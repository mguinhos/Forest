using Godot;
using System;
using System.ClientModel;
using System.Collections;
using OpenAI;
using OpenAI.Chat;
using System.Collections.Generic;
using System.Threading.Tasks;
using System.Xml;

public partial class BearNpc : CharacterBody3D
{
	[Export] public float Speed { get; set; } = 10f;
	[Export] public float Gravity { get; set; } = 20.0f;
	[Export] public NodePath[] PatrolPoints { get; set; } = new NodePath[0];
	[Export] public float WaitTime { get; set; } = 0.1f;
	
	private Marker3D npcMarker;
	private int _currentPoint = 0;
	private bool _waiting = true;
	private float _waitTimer = 0.0f;
	private ChatClient _chatClient;

	public override void _Ready()
	{
		GD.Print("BearNpc _Ready() called");
		npcMarker = GetNode<Marker3D>("Avatar/Tilt/DialogueMarker");
		npcMarker.Call("set_text", "Hi from C#!");
		
		InitializeOpenAI();
	}

	private async void InitializeOpenAI()
	{
		try
		{
			var globals = GetNode("/root/Globals");
			
			_chatClient = new ChatClient(
				model: "meta-llama/llama-4-scout",
				credential: new ApiKeyCredential(globals.Get("OPENROUTER_API_KEY").AsString()),
				options: new OpenAIClientOptions() 
				{ 
					Endpoint = new Uri("https://openrouter.ai/api/v1"),
				}
			);
			
			npcMarker.Call("set_text", "Connecting to AI...");
			
			// Make async call
			await CallOpenAI();
		}
		catch (Exception ex)
		{
			GD.PrintErr($"Error initializing OpenAI: {ex.Message}");
			
			npcMarker.Call("set_text", "AI Error");
		}
	}
	
	private async Task CallOpenAI()
	{
		try
		{
			// Create chat completion options with high temperature for creativity
			var chatCompletionOptions = new ChatCompletionOptions()
			{
				Temperature = 1.8f // High temperature for creative, varied responses
			};
			
			// Create the chat messages
			var messages = new List<ChatMessage>
			{
				new UserChatMessage("Elabore uma questão simples de múltipla escolha. Use pouco texto. Use o formato <form><question>[QUESTION HERE]</question><choices><a>[FIRST CHOICE]</a><b>[SECOND CHOICE]</b>...</choices></form>, give the answer in xml. Dont talk:\n")
			};
			
			// Use async version with options
			ChatCompletion completion = await _chatClient.CompleteChatAsync(messages, chatCompletionOptions);
			
			string rawResponse = completion.Content[0].Text;
			GD.Print($"[RAW ASSISTANT RESPONSE]: {rawResponse}");
			
			// Extract XML content from the response
			string xmlContent = ExtractXMLContent(rawResponse);
			GD.Print($"[EXTRACTED XML]: {xmlContent}");
			
			if (string.IsNullOrEmpty(xmlContent))
			{
				GD.PrintErr("No valid XML found in response");
				CallDeferred(nameof(UpdateNPCText), "No valid question found");
				return;
			}
			
			XmlDocument xmlDoc = new XmlDocument();
			xmlDoc.LoadXml(xmlContent);
			
			// Extract question text
			XmlNode questionNode = xmlDoc.SelectSingleNode("//form/question");
			if (questionNode != null)
			{
				CallDeferred(nameof(UpdateNPCText), questionNode.InnerText);
			}
			
			// Extract choices and update ButtonOptions
			XmlNodeList choiceNodes = xmlDoc.SelectNodes("//form/choices/*");
			if (choiceNodes != null && choiceNodes.Count > 0)
			{
				List<string> choices = new List<string>();
				foreach (XmlNode choice in choiceNodes)
				{
					choices.Add(choice.InnerText);
				}
				
				// Call ButtonOptions update_options function
				var buttonOptions = GetNodeOrNull("/root/Main/UICanvas/ButtonOptions");
				if (buttonOptions != null)
				{
					buttonOptions.Call("update_options", choices.ToArray());
				}
				else
				{
					GD.PrintErr("ButtonOptions node not found!");
				}
			}
			
			// Handle answer if present
			XmlNode answerNode = xmlDoc.SelectSingleNode("//form/answer");
			if (answerNode != null)
			{
				GD.Print($"Correct answer: {answerNode.InnerText}");
			}
		}
		catch (XmlException xmlEx)
		{
			GD.PrintErr($"XML Parsing Error: {xmlEx.Message}");
			GD.PrintErr($"XML Stack Trace: {xmlEx.StackTrace}");
			GD.PrintErr($"XML Line Number: {xmlEx.LineNumber}");
			GD.PrintErr($"XML Line Position: {xmlEx.LinePosition}");
			
			// Try a different prompt that's more explicit with high temperature
			try
			{
				GD.Print("Retrying with more explicit XML-only prompt...");
				
				var retryOptions = new ChatCompletionOptions()
				{
					Temperature = 1.2f
				};
				
				var retryMessages = new List<ChatMessage>
				{
					new UserChatMessage("ONLY output XML in this exact format, no other text: <form><question>What is 2+2?</question><choices><a>3</a><b>4</b><c>5</c></choices></form>")
				};
				
				ChatCompletion retryCompletion = await _chatClient.CompleteChatAsync(retryMessages, retryOptions);
				
				string retryResponse = retryCompletion.Content[0].Text;
				string retryXmlContent = ExtractXMLContent(retryResponse);
				
				if (!string.IsNullOrEmpty(retryXmlContent))
				{
					XmlDocument retryXmlDoc = new XmlDocument();
					retryXmlDoc.LoadXml(retryXmlContent);
					
					XmlNode retryQuestionNode = retryXmlDoc.SelectSingleNode("//form/question");
					if (retryQuestionNode != null)
					{
						CallDeferred(nameof(UpdateNPCText), retryQuestionNode.InnerText);
					}
				}
				else
				{
					CallDeferred(nameof(UpdateNPCText), "AI returned invalid format");
				}
			}
			catch (Exception retryEx)
			{
				GD.PrintErr($"Retry failed: {retryEx.Message}");
				CallDeferred(nameof(UpdateNPCText), "AI Unavailable");
			}
		}
		catch (Exception ex)
		{
			GD.PrintErr($"OpenAI API Error: {ex.Message}");
			GD.PrintErr($"Exception Type: {ex.GetType().Name}");
			GD.PrintErr($"Stack Trace: {ex.StackTrace}");
			GD.PrintErr($"Source: {ex.Source}");
			
			if (ex.InnerException != null)
			{
				GD.PrintErr($"Inner Exception: {ex.InnerException.Message}");
				GD.PrintErr($"Inner Exception Type: {ex.InnerException.GetType().Name}");
			}
			
			CallDeferred(nameof(UpdateNPCText), $"API Error: {ex.Message}");
		}
	}

	private string ExtractXMLContent(string response)
	{
		// Look for XML content between <form> tags
		int startIndex = response.IndexOf("<form");
		if (startIndex == -1) return null;
		
		int endIndex = response.IndexOf("</form>", startIndex);
		if (endIndex == -1) return null;
		
		endIndex += "</form>".Length;
		return response.Substring(startIndex, endIndex - startIndex);
	}
	
	private void UpdateNPCText(string text)
	{
		if (npcMarker != null)
		{
			npcMarker.Call("set_text", text);
		}
	}

	// Method to call AI during gameplay with high temperature for creative responses
	public async void AskAI(string question)
	{
		if (_chatClient == null)
		{
			GD.PrintErr("Chat client not initialized");
			return;
		}

		try
		{
			npcMarker.Call("set_text", "Thinking...");
			
			// Use high temperature for creative, varied responses
			var options = new ChatCompletionOptions()
			{
				Temperature = 1.3f // Very high for maximum creativity
			};
			
			var messages = new List<ChatMessage>
			{
				new UserChatMessage(question)
			};
			
			ChatCompletion completion = await _chatClient.CompleteChatAsync(messages, options);
			CallDeferred(nameof(UpdateNPCText), completion.Content[0].Text);
			
			GD.Print($"[AI Response]: {completion.Content[0].Text}");
		}
		catch (Exception ex)
		{
			GD.PrintErr($"AI Error: {ex.Message}");
			CallDeferred(nameof(UpdateNPCText), "Sorry, I can't respond right now.");
		}
	}

	public override void _PhysicsProcess(double delta)
	{
		float deltaF = (float)delta;
		Vector3 velocity = Velocity;
		
		if (!IsOnFloor())
		{
			velocity.Y -= Gravity * deltaF;
		}
		else
		{
			velocity.Y = 0;
		}

		if (PatrolPoints.Length == 0)
		{
			Velocity = velocity;
			MoveAndSlide();
			return;
		}
		
		if (_waiting)
		{
			_waitTimer -= deltaF;
			if (_waitTimer <= 0)
			{
				_waiting = false;
				_currentPoint = (_currentPoint + 1) % PatrolPoints.Length;
			}
		}
		else
		{
			MoveToPoint(deltaF, ref velocity);
		}

		Velocity = velocity;
		MoveAndSlide();
	}

	private void MoveToPoint(float delta, ref Vector3 velocity)
	{
		Node targetNode = GetNodeOrNull(PatrolPoints[_currentPoint]);
		if (targetNode == null)
			return;

		Vector3 targetPos = targetNode.Get("global_transform").AsTransform3D().Origin;
		Vector3 dir = targetPos - GlobalTransform.Origin;
		dir.Y = 0;

		if (dir.Length() > 0.1f)
		{
			dir = dir.Normalized();
			velocity.X = dir.X * Speed;
			velocity.Z = dir.Z * Speed;
		}
		else
		{
			velocity.X = 0;
			velocity.Z = 0;
			_waiting = true;
			_waitTimer = WaitTime;
		}
	}

	// Example: Call AI when player gets close
	private void _on_detection_area_body_entered(Node3D body)
	{
		if (body.Name == "Player")
		{
			AskAI("Greet the player as a friendly forest bear in Portuguese.");
		}
	}
}

class_name OllamaProvider
extends AIProvider
## Adaptateur local Ollama (aucune clé API). Configuration : user://ai_config.json
## {"provider": "ollama", "url": "http://localhost:11434", "model": "llama3.2"}

var url := "http://localhost:11434"
var model := "llama3.2"


func _init(cfg := {}) -> void:
	url = cfg.get("url", url)
	model = cfg.get("model", model)


func display_name() -> String:
	return "Ollama local · " + model


func complete(ctx: Dictionary, history: Array, cb: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = 90
	add_child(http)
	var ctx_small := ctx.duplicate(true)
	ctx_small.erase("question")
	var msgs := [{"role": "system", "content": "Tu es l'assistant de Knowledge World, un espace personnel de connaissances. Réponds en français, de façon concise. Contexte (JSON) : " + JSON.stringify(ctx_small).left(6000)}]
	for m in history.slice(-6):
		msgs.append({"role": m.role, "content": m.text})
	http.request_completed.connect(func(result, code, _h, body):
		http.queue_free()
		var text := "Erreur de connexion à Ollama (%s)." % url
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var j = JSON.parse_string(body.get_string_from_utf8())
			if j is Dictionary and j.has("message"):
				text = j.message.content
		cb.call({"text": text, "proposals": [{"kind": "note", "name": "Réponse IA", "text": text}] if code == 200 else []}))
	http.request(url + "/api/chat", ["Content-Type: application/json"], HTTPClient.METHOD_POST,
		JSON.stringify({"model": model, "messages": msgs, "stream": false}))

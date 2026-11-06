class_name OllamaProvider
extends AIProvider
## Adaptateur local Ollama (aucune clé API), réponses en streaming NDJSON (/api/chat).
## Configuration : user://ai_config.json (voir Assistant).

const CONNECT_TIMEOUT := 5.0
const FIRST_TOKEN_TIMEOUT := 180.0 # chargement du modèle en mémoire
const IDLE_TIMEOUT := 45.0

var url := "http://localhost:11434"
var model := ""
var temperature := 0.6
var num_predict := 700
var models: Array = [] # [{name, size}] triés par taille

var _http: HTTPClient
var _state := 0 # 0 inactif, 1 connexion, 2 requête, 3 lecture
var _payload := ""
var _buf := PackedByteArray()
var _err_body := ""
var _text := ""
var _code := 0
var _t := 0.0
var _got_token := false
var _cb := Callable()
var _on_chunk := Callable()


func _init(cfg := {}) -> void:
	configure(cfg)
	set_process(false)


func configure(cfg: Dictionary) -> void:
	url = str(cfg.get("url", url)).trim_suffix("/")
	model = str(cfg.get("model", model))
	temperature = float(cfg.get("temperature", temperature))
	num_predict = int(cfg.get("num_predict", num_predict))


func display_name() -> String:
	return "Ollama · " + (model if model != "" else "aucun modèle")


func is_busy() -> bool:
	return _state != 0


## GET /api/tags (timeout court). cb.call(ok: bool).
func refresh_models(cb: Callable) -> void:
	var http := HTTPRequest.new()
	http.timeout = 2.5
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _h, body: PackedByteArray):
		http.queue_free()
		var ok := false
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			var j = JSON.parse_string(body.get_string_from_utf8())
			if j is Dictionary and j.get("models") is Array:
				models = []
				for m in j.models:
					if m is Dictionary and m.has("name"):
						models.append({"name": str(m.name), "size": int(m.get("size", 0))})
				models.sort_custom(func(a, b): return a.size < b.size)
				ok = true
		cb.call(ok))
	if http.request(url + "/api/tags") != OK:
		http.queue_free()
		cb.call_deferred(false)


func model_names() -> Array:
	return models.map(func(m): return m.name)


func complete(ctx: Dictionary, history: Array, cb: Callable, on_chunk := Callable()) -> void:
	if _state != 0:
		cancel()
	_cb = cb
	_on_chunk = on_chunk
	_text = ""
	if model == "":
		_finish("Aucun modèle Ollama installé (essayez : ollama pull llama3.2:3b).")
		return
	var msgs := [{"role": "system", "content": str(ctx.get("_system", "Réponds en français."))}]
	for m in history:
		msgs.append({"role": "assistant" if m.role == "assistant" else "user", "content": str(m.text).left(2500)})
	_payload = JSON.stringify({"model": model, "messages": msgs, "stream": true,
		"options": {"temperature": temperature, "num_predict": num_predict, "num_ctx": 4096}})
	var tls := url.begins_with("https://")
	var hostport := url.trim_prefix("https://").trim_prefix("http://").get_slice("/", 0)
	var host := hostport.get_slice(":", 0)
	var port := int(hostport.get_slice(":", 1)) if ":" in hostport else (443 if tls else 80)
	_http = HTTPClient.new()
	_buf = PackedByteArray()
	_err_body = ""
	_text = ""
	_code = 0
	_t = 0.0
	_got_token = false
	var err := _http.connect_to_host(host, port, TLSOptions.client() if tls else null)
	if err != OK:
		_finish("Adresse Ollama invalide : %s" % url)
		return
	_state = 1
	set_process(true)


func cancel() -> void:
	if _state != 0:
		_finish("", true)


func _process(delta: float) -> void:
	if _state == 0:
		set_process(false)
		return
	_t += delta
	_http.poll()
	var st := _http.get_status()
	if st in [HTTPClient.STATUS_CANT_RESOLVE, HTTPClient.STATUS_CANT_CONNECT, HTTPClient.STATUS_CONNECTION_ERROR, HTTPClient.STATUS_TLS_HANDSHAKE_ERROR]:
		if _state == 3 and _got_token and _code == 200:
			_finish("") # connexion close après le dernier morceau
		else:
			_finish("Ollama est injoignable (%s). Lancez « ollama serve » puis réessayez." % url)
		return
	match _state:
		1:
			if st == HTTPClient.STATUS_CONNECTED:
				_http.request(HTTPClient.METHOD_POST, "/api/chat", ["Content-Type: application/json"], _payload)
				_state = 2
				_t = 0.0
			elif _t > CONNECT_TIMEOUT:
				_finish("Ollama ne répond pas (délai de connexion dépassé).")
		2:
			if _http.has_response():
				_code = _http.get_response_code()
				_state = 3
			elif _t > FIRST_TOKEN_TIMEOUT:
				_finish("Délai dépassé : le modèle « %s » met trop de temps à répondre." % model)
		3:
			if st == HTTPClient.STATUS_BODY:
				var chunk := _http.read_response_body_chunk()
				if chunk.size() > 0:
					_t = 0.0
					_consume(chunk)
			elif st == HTTPClient.STATUS_CONNECTED or st == HTTPClient.STATUS_DISCONNECTED:
				_end_of_body()
				return
			if _state == 3 and _t > (IDLE_TIMEOUT if _got_token else FIRST_TOKEN_TIMEOUT):
				_finish("Délai dépassé : plus de réponse d'Ollama." if _text == "" else "")


func _consume(chunk: PackedByteArray) -> void:
	if _code != 200:
		_err_body += chunk.get_string_from_utf8()
		return
	_buf.append_array(chunk)
	while _state == 3:
		var nl := _buf.find(10)
		if nl < 0:
			break
		var line := _buf.slice(0, nl).get_string_from_utf8().strip_edges()
		_buf = _buf.slice(nl + 1)
		if line != "":
			_handle_line(line)


func _handle_line(line: String) -> void:
	var j = JSON.parse_string(line)
	if not j is Dictionary:
		return
	if j.has("error"):
		_finish(_explain(str(j.error)))
		return
	var msg = j.get("message")
	if msg is Dictionary:
		var piece := str(msg.get("content", ""))
		if piece != "":
			_text += piece
			_got_token = true
			if _on_chunk.is_valid():
				_on_chunk.call(_text)
	if j.get("done", false):
		_finish("")


func _end_of_body() -> void:
	if _code != 200:
		var e := _err_body
		var j = JSON.parse_string(_err_body)
		if j is Dictionary and j.has("error"):
			e = str(j.error)
		_finish(_explain(e) if e != "" else "Ollama a renvoyé une erreur HTTP %d." % _code)
	else:
		if _buf.size() > 0:
			_handle_line(_buf.get_string_from_utf8())
		if _state != 0:
			_finish("")


func _explain(e: String) -> String:
	if "not found" in e:
		return "Le modèle « %s » est absent d'Ollama (ollama pull %s)." % [model, model]
	return "Erreur Ollama : " + e.left(300)


func _finish(error: String, stopped := false) -> void:
	_state = 0
	set_process(false)
	if _http != null:
		_http.close()
	var cb := _cb
	_cb = Callable()
	_on_chunk = Callable()
	if cb.is_valid():
		cb.call({"text": _text, "error": error, "stopped": stopped})

class_name BotDialogue
extends Node
## Répliques des bots : Ollama local (une génération à la fois) ou repli à trous.

const HOST := "http://localhost:11434"
const TIMEOUT := 20.0

var force_fallback := false
var model := ""
var _queue: Array = []
var _busy := false
var _ollama_ok := true
var _http_tags: HTTPRequest
var _http: HTTPRequest

func _init() -> void:
	force_fallback = "--kw-test" in OS.get_cmdline_user_args()

const T_TRAIT := {
	"bavard": ["Au fait, {topic}, tu savais ?", "Oh, j'ai tant à dire sur {topic} !"],
	"timide": ["Euh... {topic}, peut-être.", "Je ne sais pas trop... {topic}."],
	"grincheu": ["Bah, {topic}, quelle histoire.", "Hmpf. {topic}, comme d'habitude."],
	"joyeu": ["Quelle belle journée pour parler de {topic} !", "{topic}, j'adore ça !"],
	"curieu": ["Dis-moi, que sais-tu sur {topic} ?", "{topic}, ça m'intrigue."],
	"rêveu": ["Parfois je pense à {topic}...", "{topic}, comme un songe."],
	"sérieu": ["Parlons sérieusement de {topic}.", "{topic} mérite réflexion."],
}
const T_MOOD := {
	"joyeuse": "Je suis de bonne humeur !", "maussade": "Je n'ai pas le moral.",
	"fatiguée": "Je suis un peu épuisée.", "songeur": "Je suis perdu dans mes pensées.",
	"enthousiaste": "Je déborde d'énergie !", "inspirée": "J'ai plein d'idées en tête.",
}
const T_FRIEND := ["Content de te voir, {name} !", "{name} ! Ça fait plaisir.", "Ah, {name}, toujours un plaisir."]
const T_TENSION := ["Ah, c'est toi, {name}...", "Hmpf, pas maintenant, {name}.", "{name}, on ne va pas recommencer."]
const T_GENERIC := ["Intéressant, parle-m'en plus.", "Je vois, je vois.", "Hm, pourquoi pas.", "C'est bien possible."]

static func fallback_line(brain: BotBrain, topic := "", partner := "", rng: RandomNumberGenerator = null) -> String:
	if rng == null:
		rng = RandomNumberGenerator.new()
	if topic == "":
		topic = brain.interests[rng.randi() % brain.interests.size()] if not brain.interests.is_empty() else "la vie"
	var pool: Array = []
	for t in brain.traits:
		for k in T_TRAIT:
			if str(t).begins_with(k):
				pool.append_array(T_TRAIT[k])
	pool.append_array(T_GENERIC)
	var line: String = str(pool[rng.randi() % pool.size()]).replace("{topic}", topic)
	var af := brain.aff(partner) if partner != "" else 0.0
	if af <= -15.0 and rng.randf() < 0.6:
		return str(T_TENSION[rng.randi() % T_TENSION.size()]).replace("{name}", partner)
	if af >= 30.0 and rng.randf() < 0.5:
		line = str(T_FRIEND[rng.randi() % T_FRIEND.size()]).replace("{name}", partner) + " " + line
	if rng.randf() < 0.4 and T_MOOD.has(brain.mood):
		line += " " + T_MOOD[brain.mood]
	if partner != "" and rng.randf() < 0.3:
		line = partner + ", " + line.substr(0, 1).to_lower() + line.substr(1)
	return line

static func fallback_player(brain: BotBrain, text: String, rng: RandomNumberGenerator = null) -> String:
	var t := text.to_lower()
	var nt := BotDialogue.norm_text(text)
	var own: String = brain.world_info.call(brain, nt) if brain.world_info.is_valid() else brain.own_answer(nt)
	if own != "":
		return own
	if t.contains("entendu") or t.contains("ragot") or t.contains("nouvelle"):
		return brain.heard_summary()
	if t.contains("qui es") or t.contains("présente"):
		return "Je suis %s, %s." % [brain.bot_name, brain.job]
	return fallback_line(brain, "", "", rng)

static func norm_text(s: String) -> String:
	return BotDirector.norm(s)

## Réplique à `partner` ; cb(text: String). heard = dernière phrase du partenaire.
func say(brain: BotBrain, partner: String, heard: String, cb: Callable) -> void:
	_enqueue(brain, heard, partner, cb, "")

## Réponse au joueur ; cb(text: String).
func answer_player(brain: BotBrain, text: String, cb: Callable) -> void:
	var t := text.to_lower()
	if t.contains("entendu") or t.contains("ragot"):
		brain.remember("joueur", text)
		var r := brain.heard_summary()
		brain.remember(brain.bot_name, r)
		cb.call(r)
		return
	var nt := norm_text(text)
	var own: String = brain.world_info.call(brain, nt) if brain.world_info.is_valid() else brain.own_answer(nt)
	if own != "":
		brain.remember("joueur", text)
		brain.remember(brain.bot_name, own)
		cb.call(own)
		return
	if not text.contains("?") and text.strip_edges().length() > 8:
		brain.note_player(text)
	_enqueue(brain, text, "le joueur", cb, "joueur")

func _enqueue(brain: BotBrain, heard: String, partner: String, cb: Callable, kind: String) -> void:
	if force_fallback or not _ollama_ok or not is_inside_tree():
		_finish(brain, partner, heard, cb, kind, "")
		return
	_queue.append({"brain": brain, "heard": heard, "partner": partner, "cb": cb, "kind": kind})
	_next()

func _finish(brain: BotBrain, partner: String, heard: String, cb: Callable, kind: String, text: String) -> void:
	if text.strip_edges() == "":
		text = fallback_player(brain, heard) if kind == "joueur" else fallback_line(brain, "", partner)
	if heard != "":
		brain.remember(partner, heard)
	brain.remember(brain.bot_name, text)
	cb.call(text)

func _next() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	if model == "":
		_http_tags = HTTPRequest.new()
		_http_tags.timeout = 5.0
		add_child(_http_tags)
		_http_tags.request_completed.connect(_on_tags)
		if _http_tags.request(HOST + "/api/tags") != OK:
			_ollama_down()
		return
	_generate()

func _ollama_down() -> void:
	_ollama_ok = false
	_busy = false
	var q := _queue
	_queue = []
	for it in q:
		_finish(it["brain"], it["partner"], it["heard"], it["cb"], it["kind"], "")

func _on_tags(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_http_tags.queue_free()
	var d = JSON.parse_string(body.get_string_from_utf8())
	if code != 200 or typeof(d) != TYPE_DICTIONARY or d.get("models", []).is_empty():
		_ollama_down()
		return
	var best := ""
	var best_size := INF
	for m in d["models"]:
		var s: float = float(m.get("size", 1e18))
		if s < best_size:
			best_size = s
			best = str(m.get("name", ""))
	model = best
	_generate()

static func build_messages(brain: BotBrain, heard: String, partner: String) -> Array:
	var sys := brain.sheet() + " Réponds en français, UNE phrase courte (max 20 mots), sans guillemets."
	var known: Array = []
	for f in brain.facts:
		known.append(str(f["text"]))
	if not known.is_empty():
		sys += " Tu sais : " + " | ".join(known.slice(0, 4)) + "."
	if partner != "" and brain.affinity.has(partner):
		sys += " Avec %s : %s." % [partner, brain.relation_label(partner)]
	if brain.reason != "":
		sys += " En ce moment : " + brain.reason
	var msgs: Array = [{"role": "system", "content": sys}]
	for m in brain.memory:
		msgs.append({"role": "assistant" if m["who"] == brain.bot_name else "user", "content": str(m["text"])})
	var h := heard if heard != "" else "(%s te croise, lance la conversation)" % partner
	msgs.append({"role": "user", "content": h})
	return msgs

func _generate() -> void:
	var it: Dictionary = _queue[0]
	var body := {"model": model, "stream": false, "messages": build_messages(it["brain"], it["heard"], it["partner"]), "options": {"num_predict": 80, "temperature": 0.8}}
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_gen)
	var err := _http.request(HOST + "/api/chat", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_http.queue_free()
		_complete("")

func _on_gen(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	var text := ""
	if code == 200:
		var d = JSON.parse_string(body.get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY:
			text = str(d.get("message", {}).get("content", "")).strip_edges()
	_complete(text)

func _complete(text: String) -> void:
	var it: Dictionary = _queue.pop_front()
	_busy = false
	_finish(it["brain"], it["partner"], it["heard"], it["cb"], it["kind"], text)
	_next()

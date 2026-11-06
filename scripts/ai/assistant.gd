extends Node
## ASSISTANT (autoload) — orchestre fournisseur IA + mémoire contextuelle + RAG.
## Mémoire à 4 niveaux : globale, portail, salle, documentaire (selon le périmètre choisi).
## Le logiciel fonctionne sans IA : par défaut, MockProvider (local, simulé).

signal reply_ready(desk_id: String, result: Dictionary)
signal reply_chunk(desk_id: String, text: String)
signal busy_changed(desk_id: String, busy: bool)
signal provider_changed

const CONFIG_PATH := "user://ai_config.json"
const HISTORY := 8
const CONTEXT_CHARS := 3500
var provider: AIProvider
var mock: MockProvider
var ollama: OllamaProvider
var rag: RagBackend
## provider : "auto" (Ollama si disponible) | "ollama" | "mock". Jamais de clé API.
var cfg := {"provider": "auto", "url": "http://localhost:11434", "model": "", "temperature": 0.6, "num_predict": 700}
var test_mode := false
var ollama_ok := false
var detecting := false
var busy_desk := ""
var partial := ""


func _ready() -> void:
	rag = KeywordRag.new()
	if FileAccess.file_exists(CONFIG_PATH):
		var p = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if p is Dictionary:
			cfg.merge(p, true)
	mock = MockProvider.new()
	add_child(mock)
	provider = mock
	test_mode = "--kw-test" in OS.get_cmdline_user_args()
	ollama = OllamaProvider.new(cfg)
	add_child(ollama)
	if not test_mode:
		detect()


## Détection d'Ollama (GET /api/tags, timeout court) ; repli silencieux sur le MockProvider.
func detect() -> void:
	if detecting or test_mode:
		return
	detecting = true
	ollama.refresh_models(func(ok: bool):
		detecting = false
		ollama_ok = ok and not ollama.models.is_empty()
		if ollama_ok:
			var names := ollama.model_names()
			if not ollama.model in names:
				ollama.model = cfg.model if cfg.model in names else names[0] # le plus léger
		if busy_desk == "":
			provider = ollama if ollama_ok and cfg.provider != "mock" else mock
		provider_changed.emit())


func save_config() -> void:
	var f := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(cfg, "\t"))


## Choix d'un modèle Ollama (mémorisé) ou "" pour l'assistant simulé.
func set_model(model_name: String) -> void:
	if busy_desk != "":
		stop()
	if model_name == "" or not ollama_ok:
		cfg.provider = "mock"
		provider = mock
	else:
		cfg.provider = "ollama"
		cfg.model = model_name
		ollama.model = model_name
		provider = ollama
	save_config()
	provider_changed.emit()


func set_temperature(t: float) -> void:
	cfg.temperature = clampf(t, 0.0, 1.5)
	ollama.temperature = cfg.temperature
	save_config()


func is_busy(desk_id := "") -> bool:
	return busy_desk != "" and (desk_id == "" or busy_desk == desk_id)


func stop() -> void:
	if busy_desk != "":
		provider.cancel()


func provider_name() -> String:
	return provider.display_name()


func _obj_summary(o: Dictionary) -> Dictionary:
	return {"id": o.id, "type": o.type, "type_label": ObjectRegistry.get_def(o.type).label, "name": o.name, "text": ObjectRegistry.text_of(o).left(400)}


## scope : "room" | "portal" | "global"
func build_context(room_id: String, scope: String, question := "") -> Dictionary:
	var room: Dictionary = World.data.rooms.get(room_id, {})
	var pid: String = room.get("portal_id", "")
	var ctx := {"scope": scope, "question": question,
		"room": {"id": room_id, "name": room.get("name", ""), "objects": World.objects_in_room(room_id).filter(func(o): return not o.type in ["door", "portal", "lamp", "table"]).map(_obj_summary)},
		"room_documents": World.docs_for_room(room_id).map(func(d): return d.name),
		"portal": {}, "global": {"portals": World.data.portals.values().map(func(p): return p.name), "rooms": []}, "documents": []}
	var doc_ids := World.docs_for_room(room_id).map(func(d): return d.id)
	if pid != "" and scope != "room":
		var rooms: Array = World.data.rooms.values().filter(func(r): return r.portal_id == pid)
		ctx.portal = {"name": World.data.portals[pid].name, "rooms": rooms.map(func(r): return r.name)}
		for r in rooms:
			doc_ids.append_array(World.docs_for_room(r.id).map(func(d): return d.id))
	for r in World.data.rooms.values():
		if scope == "global" or r.id == room_id or (pid != "" and r.portal_id == pid):
			var txt := " ".join(PackedStringArray(World.objects_in_room(r.id).map(func(o): return o.name + " " + ObjectRegistry.text_of(o).left(200))))
			ctx.global.rooms.append({"id": r.id, "name": r.name, "text": txt})
	if scope == "global":
		doc_ids = []
	if question != "" and (scope == "global" or not doc_ids.is_empty()):
		ctx.documents = rag.search(question, doc_ids, 3)
	return ctx


func system_prompt(ctx: Dictionary) -> String:
	var small := {"périmètre": ctx.scope, "salle": {"nom": ctx.room.name, "objets": ctx.room.objects.map(func(o): return {"type": o.type_label, "nom": o.name, "texte": str(o.text).left(300)})},
		"documents_de_la_salle": ctx.room_documents, "portail": ctx.portal, "portails": ctx.global.portals,
		"salles": ctx.global.rooms.map(func(r): return {"nom": r.name, "contenu": str(r.text).left(160)}),
		"extraits_documents": ctx.documents.map(func(d): return str(d.snippet))}
	var scope_fr: String = {"room": "la salle courante", "portal": "le portail courant", "global": "tout le monde"}.get(ctx.scope, "la salle")
	return """Tu es l'assistant de Knowledge World, un espace de connaissances personnel en 3D : des portails (thèmes) mènent à des salles qui contiennent des objets (notes, post-it, fiches, tableaux blancs, Kanban) et des documents.
Contexte (JSON, tronqué, périmètre : %s) :
%s

Règles :
- Réponds en français, clairement et brièvement (moins de 200 mots sauf demande contraire), en t'appuyant sur le contexte. Si une information manque, dis-le.
- Quand tu proposes de créer une note, un Kanban, une salle ou une relation, ajoute À LA FIN un bloc exactement de cette forme (JSON valide, l'utilisateur validera) :
```actions
[{"kind":"note","name":"Titre court","text":"Contenu de la note"}]
```
- Types autorisés : {"kind":"note","name":"…","text":"…"} ; {"kind":"kanban","name":"…","cards":["tâche 1","tâche 2"]} ; {"kind":"room","name":"…"} ; {"kind":"relation","to_room_name":"nom d'une salle existante"}.
- Ne décris pas le bloc dans le texte ; s'il n'y a rien à proposer, pas de bloc.""" % [scope_fr, JSON.stringify(small).left(CONTEXT_CHARS)]


func ask(desk_id: String, room_id: String, question: String, scope: String) -> void:
	var o = World.data.objects.get(desk_id)
	if o == null or question.strip_edges() == "" or busy_desk != "":
		return
	var c: Dictionary = o.content.duplicate(true)
	if not c.get("messages") is Array:
		c.messages = []
	c.messages.append({"role": "user", "text": question})
	World.update_object(desk_id, {"content": c})
	var hist: Array = c.messages.filter(func(m): return not m.get("error", false)).slice(-HISTORY)
	var ctx := build_context(room_id, scope, question)
	ctx["_system"] = system_prompt(ctx)
	busy_desk = desk_id
	partial = ""
	busy_changed.emit(desk_id, true)
	provider.complete(ctx, hist, func(res: Dictionary): _on_result(desk_id, room_id, res),
		func(t: String): _on_chunk(desk_id, t))


func _on_chunk(desk_id: String, raw: String) -> void:
	partial = AIActions.visible_text(raw)
	reply_chunk.emit(desk_id, partial)


func _on_result(desk_id: String, room_id: String, res: Dictionary) -> void:
	busy_desk = ""
	partial = ""
	var raw: String = res.get("text", "")
	var out := {"text": raw, "proposals": res.get("proposals", []), "error": str(res.get("error", "")), "stopped": res.get("stopped", false)}
	if not res.has("proposals"):
		var parsed := AIActions.parse(raw, room_id)
		out.text = parsed.text
		out.proposals = parsed.proposals
	if out.stopped:
		out.text = (out.text + "\n\n" if out.text != "" else "") + "(interrompu)"
	if out.error != "":
		out.text = (out.text + "\n\n" if out.text != "" else "") + "⚠ " + out.error
	elif out.text.strip_edges() == "" and out.proposals.is_empty() and not out.stopped:
		out.text = "(réponse vide)"
	var o = World.data.objects.get(desk_id)
	if o != null:
		var c: Dictionary = o.content.duplicate(true)
		var props := []
		for p in out.proposals:
			var q: Dictionary = p.duplicate(true)
			q["state"] = "pending"
			props.append(q)
		c.messages.append({"role": "assistant", "text": out.text, "proposals": props, "error": out.error != "", "by": provider.display_name()})
		World.update_object(desk_id, {"content": c})
	busy_changed.emit(desk_id, false)
	reply_ready.emit(desk_id, out)


## Valide (accept = true) ou ignore une proposition stockée dans le message msg_index du bureau.
func resolve_proposal(desk_id: String, msg_index: int, prop_index: int, accept: bool) -> String:
	var o = World.data.objects.get(desk_id)
	if o == null:
		return ""
	var c: Dictionary = o.content.duplicate(true)
	if msg_index < 0 or msg_index >= c.messages.size():
		return ""
	var props: Array = c.messages[msg_index].get("proposals", [])
	if prop_index < 0 or prop_index >= props.size() or props[prop_index].get("state", "pending") != "pending":
		return ""
	var res := ""
	if accept:
		res = apply_proposal(props[prop_index], o.room_id)
	props[prop_index].state = "done" if accept else "ignored"
	World.update_object(desk_id, {"content": c})
	return res


## Appliquée uniquement après validation explicite de l'utilisateur.
func apply_proposal(p: Dictionary, room_id: String) -> String:
	var res := ""
	match p.kind:
		"note":
			var slot := World.find_wall_slot(room_id, 0.01, 1.2)
			res = World.create_object("note", room_id, slot.pos, Vector3(0, slot.rot, 0), Vector3.ONE, p.name, {"text": p.text, "color": "#d7e6f5"})
		"kanban":
			var slot := World.find_wall_slot(room_id, 0.03, 0.8)
			res = World.create_object("kanban", room_id, slot.pos, Vector3(0, slot.rot, 0), Vector3.ONE, p.name,
				{"columns": [{"title": "À faire", "cards": p.cards}, {"title": "En cours", "cards": []}, {"title": "Fait", "cards": []}]})
		"room":
			res = World.create_room(p.name, World.data.rooms[room_id].portal_id, room_id, [9.0, 4.0, 9.0])
		"relation":
			res = World.add_relation("room", room_id, "room", p.to_room, "thématique", "Proposée par l'assistant")
	World.data.history.append({"time": World.now(), "op": "assistant_" + p.kind, "source": room_id, "result": res})
	return res

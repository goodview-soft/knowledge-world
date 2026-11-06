extends Node
## ASSISTANT (autoload) — orchestre fournisseur IA + mémoire contextuelle + RAG.
## Mémoire à 4 niveaux : globale, portail, salle, documentaire (selon le périmètre choisi).
## Le logiciel fonctionne sans IA : par défaut, MockProvider (local, simulé).

signal reply_ready(desk_id: String, result: Dictionary)

const CONFIG_PATH := "user://ai_config.json"
var provider: AIProvider
var rag: RagBackend


func _ready() -> void:
	rag = KeywordRag.new()
	var cfg := {"provider": "mock"}
	if FileAccess.file_exists(CONFIG_PATH):
		var p = JSON.parse_string(FileAccess.get_file_as_string(CONFIG_PATH))
		if p is Dictionary:
			cfg.merge(p, true)
	match cfg.provider:
		"ollama": provider = OllamaProvider.new(cfg)
		_: provider = MockProvider.new()
	add_child(provider)


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


func ask(desk_id: String, room_id: String, question: String, scope: String) -> void:
	var o = World.data.objects.get(desk_id)
	if o == null:
		return
	var c: Dictionary = o.content.duplicate(true)
	c.messages.append({"role": "user", "text": question})
	World.update_object(desk_id, {"content": c})
	provider.complete(build_context(room_id, scope, question), c.messages, func(res): _on_result(desk_id, res))


func _on_result(desk_id: String, res: Dictionary) -> void:
	var o = World.data.objects.get(desk_id)
	if o != null:
		var c: Dictionary = o.content.duplicate(true)
		c.messages.append({"role": "assistant", "text": res.text})
		World.update_object(desk_id, {"content": c})
	reply_ready.emit(desk_id, res)


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

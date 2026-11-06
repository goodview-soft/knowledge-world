class_name OSData
extends RefCounted
## Requêtes et modifications pour KW OS, toujours sur les vraies données (World).
## Aucune donnée dupliquée : tout passe par l'API World / NoteLinks.

const KNOWLEDGE_TYPES := ["note", "postit", "card", "whiteboard", "kanban", "desk", "library", "poster", "orb"]
const DONE_TITLES := ["fait", "done", "terminé", "termine", "fini"]
static var _re_task: RegEx


static func room_name(rid: String) -> String:
	return str(World.data.rooms[rid].name) if World.data.rooms.has(rid) else "?"


## « Portail / Salle / Sous-salle » (le hub vaut « / »).
static func room_path(rid: String) -> String:
	if rid == World.data.hub:
		return "/"
	var parts := []
	var cur := rid
	var guard := 0
	while World.data.rooms.has(cur) and cur != World.data.hub and guard < 32:
		parts.push_front(str(World.data.rooms[cur].name))
		cur = str(World.data.rooms[cur].get("parent_id", ""))
		guard += 1
	return "/" + "/".join(PackedStringArray(parts))


## Salles enfants : sous-salles (parent_id) ; pour le hub, les entrées de portails
## et les salles sans parent.
static func child_rooms(rid: String) -> Array:
	var out := []
	for r in World.data.rooms.values():
		if r.id == World.data.hub:
			continue
		var p := str(r.get("parent_id", ""))
		if p == rid or (rid == World.data.hub and p == ""):
			out.append(r.id)
	out.sort_custom(func(a, b): return room_name(a).naturalnocasecmp_to(room_name(b)) < 0)
	return out


static func parent_room(rid: String) -> String:
	if not World.data.rooms.has(rid) or rid == World.data.hub:
		return World.data.hub
	var p := str(World.data.rooms[rid].get("parent_id", ""))
	return p if World.data.rooms.has(p) else World.data.hub


## Résout un nom de salle : d'abord parmi les enfants de `from`, puis partout
## (exact, puis préfixe, puis contient ; insensible à la casse).
static func find_room(query: String, from := "") -> String:
	var q := query.strip_edges().trim_suffix("/").to_lower()
	if q == "":
		return ""
	if q == "/" or q == "hub" or q == "~":
		return World.data.hub
	var pools := []
	if from != "":
		pools.append(child_rooms(from))
	pools.append(World.data.rooms.keys())
	for mode in 3:
		for pool in pools:
			for rid in pool:
				var n := room_name(rid).to_lower()
				if (mode == 0 and n == q) or (mode == 1 and n.begins_with(q)) or (mode == 2 and q in n):
					return rid
	return ""


static func objects_in(rid: String, knowledge_only := true) -> Array:
	var out := World.objects_in_room(rid).filter(func(o): return not knowledge_only or o.type in KNOWLEDGE_TYPES)
	out.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out


## Objet par nom : dans la salle `rid` d'abord, puis partout. notes_only = types note.
static func find_object(query: String, rid := "", notes_only := false) -> String:
	var q := query.strip_edges().to_lower()
	if q == "":
		return ""
	var all: Array = World.data.objects.values().filter(func(o):
		return World.data.rooms.has(o.room_id) and (not notes_only or NoteLinks.is_note(o)) and o.type not in ["door", "portal"])
	var local := all.filter(func(o): return o.room_id == rid)
	for mode in 3:
		for pool in [local, all]:
			for o in pool:
				var n := str(o.name).to_lower()
				if (mode == 0 and n == q) or (mode == 1 and n.begins_with(q)) or (mode == 2 and q in n):
					return o.id
	return ""


static func find_document(query: String) -> String:
	var q := query.strip_edges().to_lower()
	for d in World.data.documents.values():
		var n := str(d.name).to_lower()
		if n == q or n.get_basename() == q:
			return d.id
	for d in World.data.documents.values():
		if str(d.name).to_lower().begins_with(q):
			return d.id
	return ""


static func create_note(rid: String, title: String, text := "") -> String:
	if not World.data.rooms.has(rid):
		rid = World.data.hub
	return NoteLinks.create_note(rid, title, text if text != "" else "# %s\n\n" % title)


static func set_note_text(oid: String, text: String, new_name := "") -> void:
	if not World.data.objects.has(oid):
		return
	var o: Dictionary = World.data.objects[oid]
	var c: Dictionary = o.content.duplicate(true)
	c.text = text
	var f := {"content": c}
	if new_name.strip_edges() != "" and new_name != o.name:
		f.name = new_name.strip_edges()
	World.update_object(oid, f)
	NoteLinks.sync_relations(oid)


static func rename(kind: String, id: String, new_name: String) -> void:
	var n := new_name.strip_edges()
	if n == "":
		return
	match kind:
		"room":
			World.rename_room(id, n)
		"portal":
			if World.data.portals.has(id):
				World.rename_room(str(World.data.portals[id].entrance), n)
		"object":
			World.update_object(id, {"name": n})
		"document":
			if World.data.documents.has(id):
				World.data.documents[id].name = n
				World._touch("document", id, "updated")


static func delete(kind: String, id: String) -> bool:
	match kind:
		"room":
			return World.delete_room(id)
		"portal":
			return World.data.portals.has(id) and World.delete_room(str(World.data.portals[id].entrance))
		"object":
			if World.data.objects.has(id):
				World.delete_object(id)
				return true
		"document":
			if World.data.documents.has(id):
				World.delete_document(id)
				return true
	return false

# ------------------------------------------------------------------ tâches

## Toutes les tâches : cases « - [ ] » des notes et cartes Kanban.
## {kind: "check"|"kanban", source, room_id, text, done, line, col, card}
static func collect_tasks(room_filter := "") -> Array:
	if _re_task == null:
		_re_task = RegEx.create_from_string("^\\s*[-*+]\\s+\\[( |x|X)\\]\\s*(.*)$")
	var out := []
	for o in World.data.objects.values():
		if not World.data.rooms.has(o.room_id) or (room_filter != "" and o.room_id != room_filter):
			continue
		if NoteLinks.is_note(o):
			var lines := str(o.content.get("text", "")).split("\n")
			var in_code := false
			for i in lines.size():
				if lines[i].strip_edges().begins_with("```"):
					in_code = not in_code
					continue
				if in_code:
					continue
				var m := _re_task.search(lines[i])
				if m and m.get_string(2).strip_edges() != "":
					out.append({"kind": "check", "source": o.id, "room_id": o.room_id, "text": m.get_string(2).strip_edges(),
						"done": m.get_string(1) != " ", "line": i, "col": -1, "card": -1})
		elif o.type == "kanban":
			var cols: Array = o.content.get("columns", [])
			for ci in cols.size():
				var cards: Array = cols[ci].get("cards", [])
				for k in cards.size():
					out.append({"kind": "kanban", "source": o.id, "room_id": o.room_id, "text": str(cards[k]),
						"done": _col_done(cols, ci), "line": -1, "col": ci, "card": k})
	return out


static func _col_done(cols: Array, ci: int) -> bool:
	return cols.size() > 1 and (ci == cols.size() - 1 or str(cols[ci].get("title", "")).strip_edges().to_lower() in DONE_TITLES)


## Coche / décoche dans la donnée source. Kanban : carte → dernière colonne (ou première).
static func toggle_task(t: Dictionary) -> bool:
	var oid: String = t.get("source", "")
	if not World.data.objects.has(oid):
		return false
	var o: Dictionary = World.data.objects[oid]
	if t.kind == "check":
		var text := str(o.content.get("text", ""))
		var nt := NoteMarkdown.toggle_task(text, int(t.line))
		if nt == text:
			return false
		set_note_text(oid, nt)
		return true
	var c: Dictionary = o.content.duplicate(true)
	var cols: Array = c.get("columns", [])
	var ci := int(t.col)
	var k := int(t.card)
	if ci < 0 or ci >= cols.size() or k < 0 or k >= cols[ci].cards.size() or cols.size() < 2:
		return false
	var card = cols[ci].cards[k]
	cols[ci].cards.remove_at(k)
	var dest := 0 if _col_done(cols, ci) else cols.size() - 1
	for i in cols.size():
		if not _col_done(cols, ci) and str(cols[i].get("title", "")).strip_edges().to_lower() in DONE_TITLES:
			dest = i
	cols[dest].cards.append(card)
	World.update_object(oid, {"content": c})
	return true

# ------------------------------------------------------------------ statistiques

static func stats() -> Dictionary:
	var tasks := collect_tasks()
	var done := tasks.filter(func(t): return t.done).size()
	var objs: Array = World.data.objects.values().filter(func(o): return World.data.rooms.has(o.room_id) and o.type not in ["door", "portal"])
	return {"portals": World.data.portals.size(), "rooms": World.data.rooms.size(), "notes": NoteLinks.notes().size(),
		"objects": objs.size(), "documents": World.data.documents.size(), "relations": World.data.relations.size(),
		"tags": NoteLinks.all_tags().size(), "tasks": tasks.size(), "tasks_done": done}


## Notes sans aucun lien (ni relation, ni lien wiki).
static func orphans() -> Array:
	return NoteLinks.notes().filter(func(o):
		return World.data.rooms.has(o.room_id) and World.relations_of("object", o.id).is_empty() \
			and NoteLinks.parse_links(str(o.content.get("text", ""))).is_empty()).map(func(o): return o.id)


const OP_LABELS := {"note_to_card": "Note → fiche", "note_to_kanban": "Note → Kanban", "note_to_room": "Note → salle",
	"conversation_to_note": "Conversation → note", "doc_to_note": "Document → note", "duplicate": "Duplication"}


## Activité récente : objets modifiés/créés + historique des transformations.
static func recent_activity(limit := 14) -> Array:
	var out := []
	for o in World.data.objects.values():
		if not World.data.rooms.has(o.room_id) or o.type in ["door", "portal"]:
			continue
		var m := str(o.get("modified", o.get("created", "")))
		if m == "":
			continue
		var created := m == str(o.get("created", ""))
		out.append({"time": m, "kind": "object", "id": o.id,
			"label": "%s « %s »" % ["Créé" if created else "Modifié", o.name], "where": room_name(o.room_id)})
	for h in World.data.history:
		var op := str(h.get("op", ""))
		out.append({"time": str(h.get("time", "")), "kind": "object", "id": str(h.get("result", "")),
			"label": OP_LABELS.get(op, op.replace("_", " ")), "where": ""})
	out.sort_custom(func(a, b): return a.time > b.time)
	return out.slice(0, limit)


## Notes créées ou modifiées un jour donné (AAAA-MM-JJ).
static func notes_of_day(day: String) -> Array:
	return NoteLinks.notes().filter(func(o):
		return World.data.rooms.has(o.room_id) and (str(o.get("created", "")).begins_with(day) or str(o.get("modified", "")).begins_with(day) \
			or o.name == "Journal " + day or o.name == day)).map(func(o): return o.id)


static func journal_name(day: String) -> String:
	return "Journal " + day


## Note de journal du jour : ouverte si elle existe, créée dans le hub sinon.
static func journal_note(day: String) -> String:
	var n := journal_name(day)
	for o in NoteLinks.notes():
		if o.name == n and World.data.rooms.has(o.room_id):
			return o.id
	return create_note(World.data.hub, n, "# %s\n\n## Tâches\n- [ ] \n\n## Notes\n\n#journal\n" % n)


static func fmt_time(iso: String) -> String:
	if iso.length() < 16:
		return iso
	var today := Time.get_date_string_from_system()
	return ("aujourd'hui " if iso.left(10) == today else iso.substr(8, 2) + "/" + iso.substr(5, 2) + " ") + iso.substr(11, 5)

class_name NoteLinks
extends RefCounted
## Liens wiki [[Nom]] / [[Nom|alias]], #tags, résolution (note > salle > document),
## synchronisation en relations World (type « thématique », description "wikilink"),
## rétroliens, note du jour, ouverture d'une cible.

const NOTE_TYPES := ["note", "postit", "card"]
const WIKI_DESC := "wikilink"
const WIKI_TYPE := "thématique"
const TAG_CHARS := "[A-Za-z_\\x{00C0}-\\x{024F}][A-Za-z0-9_/\\-\\x{00C0}-\\x{024F}]*"

static var _re_link: RegEx
static var _re_tag: RegEx
static var _re_code: RegEx


static func _init_re() -> void:
	if _re_link != null:
		return
	_re_link = RegEx.create_from_string("\\[\\[([^\\[\\]\\n]+?)\\]\\]")
	_re_tag = RegEx.create_from_string("(?<![A-Za-z0-9_&/\\x{00C0}-\\x{024F}#])#(" + TAG_CHARS + ")")
	_re_code = RegEx.create_from_string("(?s)```.*?(```|$)|`[^`\\n]*`")


## Texte sans blocs/segments de code (où liens et tags ne comptent pas).
static func strip_code(text: String) -> String:
	_init_re()
	return _re_code.sub(text, " ", true)


## "Nom|alias" / "Nom#section" → "Nom".
static func link_target(inner: String) -> String:
	return inner.get_slice("|", 0).get_slice("#", 0).strip_edges()


static func parse_links(text: String) -> Array:
	_init_re()
	var out := []
	for m in _re_link.search_all(strip_code(text)):
		var t := link_target(m.get_string(1))
		if t != "" and not t in out:
			out.append(t)
	return out


static func parse_tags(text: String) -> Array:
	_init_re()
	var out := []
	for m in _re_tag.search_all(strip_code(text)):
		var t := m.get_string(1).to_lower().trim_suffix("/").trim_suffix("-")
		if t != "" and not t in out:
			out.append(t)
	return out


static func is_note(o) -> bool:
	return o is Dictionary and o.get("type", "") in NOTE_TYPES


static func notes() -> Array:
	return World.data.objects.values().filter(func(o): return o.type in NOTE_TYPES)


## {kind, id} ou {} si aucun élément ne porte ce nom (insensible à la casse).
static func resolve(target: String) -> Dictionary:
	var q := target.strip_edges().to_lower()
	if q == "":
		return {}
	for o in notes():
		if str(o.name).strip_edges().to_lower() == q:
			return {"kind": "object", "id": o.id}
	for r in World.data.rooms.values():
		if str(r.name).strip_edges().to_lower() == q:
			return {"kind": "room", "id": r.id}
	for d in World.data.documents.values():
		var n := str(d.name).strip_edges().to_lower()
		if n == q or n.get_basename() == q:
			return {"kind": "document", "id": d.id}
	return {}


## Noms proposés à l'autocomplétion : [[nom, libellé du type]].
static func candidates(query: String, limit := 8, exclude_id := "") -> Array:
	var q := query.strip_edges().to_lower()
	var out := []
	var seen := {}
	var pools := [["object", notes()], ["room", World.data.rooms.values()], ["document", World.data.documents.values()]]
	for pool in pools:
		for e in pool[1]:
			var n := str(e.name).strip_edges()
			if n == "" or e.id == exclude_id or seen.has(n.to_lower()):
				continue
			if q == "" or q in n.to_lower():
				seen[n.to_lower()] = true
				out.append([n, {"object": "note", "room": "salle", "document": "document"}[pool[0]]])
	out.sort_custom(func(a, b): return int(not a[0].to_lower().begins_with(q)) < int(not b[0].to_lower().begins_with(q)))
	return out.slice(0, limit)


static func _same(a: Dictionary, kind: String, id: String) -> bool:
	return a.kind == kind and a.id == id


## Relations wikilink sortantes de la note.
static func wiki_relations(obj_id: String) -> Array:
	return World.data.relations.values().filter(func(r):
		return r.get("description", "") == WIKI_DESC and r.from.kind == "object" and r.from.id == obj_id)


## Aligne les relations wikilink sur le texte ; ne duplique jamais une relation existante
## (manuelle ou non, dans un sens ou dans l'autre). Renvoie {added, removed}.
static func sync_relations(obj_id: String) -> Dictionary:
	var res := {"added": 0, "removed": 0}
	if not World.data.objects.has(obj_id):
		return res
	var want := []
	for t in parse_links(ObjectRegistry.text_of(World.data.objects[obj_id])):
		var ref := resolve(t)
		if not ref.is_empty() and not _same(ref, "object", obj_id):
			want.append(ref)
	for r in wiki_relations(obj_id):
		if not want.any(func(w): return _same(r.to, w.kind, w.id)):
			World.delete_relation(r.id)
			res.removed += 1
	for w in want:
		var linked := World.relations_of(w.kind, w.id).any(func(r):
			return _same(r.from, "object", obj_id) or _same(r.to, "object", obj_id))
		if not linked:
			World.add_relation("object", obj_id, w.kind, w.id, WIKI_TYPE, WIKI_DESC)
			res.added += 1
	return res


## Notes dont le texte pointe vers (kind, id).
static func backlinks(kind: String, id: String) -> Array:
	var out := []
	for o in notes():
		if kind == "object" and o.id == id:
			continue
		for t in parse_links(ObjectRegistry.text_of(o)):
			if resolve(t) == {"kind": kind, "id": id}:
				out.append(o.id)
				break
	return out


## Liens sortants : [[nom, ref ({} si inexistant)]].
static func outgoing(obj_id: String) -> Array:
	if not World.data.objects.has(obj_id):
		return []
	return parse_links(ObjectRegistry.text_of(World.data.objects[obj_id])).map(func(t): return [t, resolve(t)])


static func all_tags() -> Dictionary:
	var out := {}
	for o in notes():
		for t in parse_tags(ObjectRegistry.text_of(o)):
			out[t] = int(out.get(t, 0)) + 1
	return out


static func notes_with_tag(tag: String) -> Array:
	var t := tag.trim_prefix("#").to_lower()
	return notes().filter(func(o): return t in parse_tags(ObjectRegistry.text_of(o))).map(func(o): return o.id)


## Crée une note posée contre un mur de la salle.
static func create_note(room_id: String, note_name: String, text := "") -> String:
	var slot := World.find_wall_slot(room_id, 0.03, 1.25)
	var rot := Vector3(0, slot.rot, 0)
	var pos: Vector3 = slot.pos + Basis.from_euler(rot * PI / 180.0) * Vector3.RIGHT * randf_range(-1.2, 1.2)
	return World.create_object("note", room_id, pos, rot, Vector3.ONE, note_name, {"text": text, "color": "#f2efe6"})


static func daily_name() -> String:
	return Time.get_date_string_from_system()


## Note du jour (dans le hub) : la crée au besoin ; renvoie son id.
static func daily_note() -> String:
	var n := daily_name()
	for o in notes():
		if o.name == n and o.room_id == World.data.hub:
			return o.id
	var d := Time.get_date_dict_from_system()
	var days := ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
	var months := ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
	var title := "%s %d %s %d" % [days[d.weekday].capitalize(), d.day, months[d.month - 1], d.year]
	return create_note(World.data.hub, n, "# %s\n\n## Tâches\n- [ ] \n\n## Notes\n\n#journal\n" % title)


## Ouvre une cible : note (panneau, en voyageant si besoin), salle, document.
static func open_ref(main: Node, ref: Dictionary) -> void:
	if ref.is_empty() or not World.exists(ref.kind, ref.id):
		return
	match ref.kind:
		"object":
			var o: Dictionary = World.data.objects[ref.id]
			if o.room_id != main.current_room:
				await main.go_to_room(o.room_id, main.current_room, ref.id)
			if World.data.objects.has(ref.id):
				if is_note(o):
					main.open_panel(NotePanel.new(ref.id))
				else:
					main.interact(ref.id)
		"room":
			main.go_to_room(ref.id, main.current_room)
		"document":
			var lib := LibraryPanel.new()
			main.open_panel(lib)
			lib._show(ref.id)
		"portal":
			main.go_to_room(World.data.portals[ref.id].entrance, main.current_room)

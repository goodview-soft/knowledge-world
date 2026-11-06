extends Node
## WORLD (autoload) — magasin de données de Knowledge World.
## Portails, salles, objets, documents, relations, historique des transformations.
## Indépendant de la 3D : tout est référencé par identifiant stable ; la position
## 3D n'est qu'un attribut d'objet. Persistance JSON atomique (+ .bak).

signal changed(kind: String, id: String, action: String) # action : created | updated | deleted

const FORMAT_VERSION := 1
const RELATION_TYPES := ["thématique", "dépendance", "contradiction", "source", "complémentarité", "dérivé"]
const TEXT_EXT := ["txt", "md", "markdown", "csv", "tsv", "json", "log", "xml", "html", "ini", "cfg", "yaml", "yml", "gd", "py", "js", "rst"]
const MAX_DOC_CHARS := 2000000

var save_path := "user://knowledge_world.json"
var data: Dictionary = {}
var _dirty := false
var _save_in := 0.0
var _counter := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kw-save="):
			save_path = a.substr(10)
	if not load_world():
		seed_world()
		save_world()


func _process(delta: float) -> void:
	if _dirty:
		_save_in -= delta
		if _save_in <= 0.0:
			save_world()


func _notification(what: int) -> void:
	if (what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE) and _dirty:
		save_world()

# ------------------------------------------------------------------ persistance

func _empty() -> Dictionary:
	return {"version": FORMAT_VERSION, "hub": "", "portals": {}, "rooms": {}, "objects": {},
		"documents": {}, "relations": {}, "history": [], "favorites": [], "recent": []}


func save_world() -> bool:
	_dirty = false
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Sauvegarde impossible : %s" % tmp)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var abs_path := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.copy_absolute(abs_path, abs_path + ".bak")
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path)
	return true


func load_world() -> bool:
	for p in [save_path, save_path + ".bak"]:
		if not FileAccess.file_exists(p):
			continue
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
		if parsed is Dictionary and parsed.has("rooms") and parsed.get("hub", "") != "":
			data = _empty()
			data.merge(parsed, true)
			_migrate()
			return true
		push_warning("Fichier de sauvegarde illisible : %s" % p)
	return false

## Migrations douces des anciennes sauvegardes (rien n'est perdu).
func _migrate() -> void:
	# Le bureau central du hub devient la sphère de conscience (la conversation est conservée).
	if not data.get("orb_migrated", false):
		data.orb_migrated = true
		for o in objects_in_room(data.hub):
			if o.type == "desk" and vec(o.pos).length() < 2.5:
				o.type = "orb"
				o.name = "Conscience"
				_dirty = true
				break

# ------------------------------------------------------------------ utilitaires

static func vec(a) -> Vector3:
	if a is Vector3:
		return a
	if a is Array and a.size() >= 3:
		return Vector3(a[0], a[1], a[2])
	return Vector3.ZERO


static func v2a(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]


func now() -> String:
	return Time.get_datetime_string_from_system(false, true)


func new_id(prefix: String) -> String:
	_counter += 1
	var t := int(Time.get_unix_time_from_system() * 1000.0)
	return "%s_%s%s" % [prefix, String.num_int64(t, 36), String.num_int64(_counter * 1000 + randi() % 1000, 36)]


func _touch(kind: String, id: String, action: String) -> void:
	_dirty = true
	_save_in = 1.2
	changed.emit(kind, id, action)


func label_of(kind: String, id: String) -> String:
	match kind:
		"room":
			return "Salle · " + data.rooms[id].name if data.rooms.has(id) else "(salle supprimée)"
		"portal":
			return "Portail · " + data.portals[id].name if data.portals.has(id) else "(portail supprimé)"
		"object":
			if data.objects.has(id):
				var o = data.objects[id]
				return "%s · %s" % [ObjectRegistry.get_def(o.type).label, o.name]
			return "(objet supprimé)"
		"document":
			return "Document · " + data.documents[id].name if data.documents.has(id) else "(document supprimé)"
	return id


func exists(kind: String, id: String) -> bool:
	var col := {"room": "rooms", "portal": "portals", "object": "objects", "document": "documents"}
	return col.has(kind) and data[col[kind]].has(id)

# ------------------------------------------------------------------ salles & portails

func create_room(room_name: String, portal_id := "", parent_id := "", size := [10.0, 4.0, 10.0], color := "") -> String:
	var id := new_id("room")
	if color == "":
		color = data.portals[portal_id].color if data.portals.has(portal_id) else "#cfc8bc"
	data.rooms[id] = {"id": id, "name": room_name, "portal_id": portal_id, "parent_id": parent_id,
		"size": size, "color": color, "created": now()}
	_touch("room", id, "created")
	if parent_id != "" and data.rooms.has(parent_id):
		_add_door(parent_id, id)
		_add_door(id, parent_id)
	return id


func create_portal(portal_name: String, color := "#8fb3d9") -> String:
	var pid := new_id("portal")
	data.portals[pid] = {"id": pid, "name": portal_name, "color": color, "description": "", "entrance": "", "created": now()}
	var rid := create_room(portal_name, pid, "", [12.0, 4.5, 12.0], color)
	data.portals[pid].entrance = rid
	var oid := _add_door(data.hub, rid, "portal")
	data.objects[oid].params.portal_id = pid
	data.objects[oid].name = portal_name
	_add_door(rid, data.hub)
	_touch("portal", pid, "created")
	return pid


func rename_room(id: String, new_name: String) -> void:
	if not data.rooms.has(id) or new_name.strip_edges() == "":
		return
	data.rooms[id].name = new_name
	var pid: String = data.rooms[id].portal_id
	if pid != "" and data.portals.has(pid) and data.portals[pid].entrance == id:
		data.portals[pid].name = new_name
	_touch("room", id, "updated")


func delete_room(id: String) -> bool:
	if id == data.hub or not data.rooms.has(id):
		return false
	for r in data.rooms.values().duplicate():
		if r.parent_id == id and data.rooms.has(r.id):
			delete_room(r.id)
	for o in data.objects.values().duplicate():
		if o.room_id == id or o.params.get("target_room", "") == id:
			delete_object(o.id)
	for d in data.documents.values():
		d.rooms.erase(id)
	_remove_relations("room", id)
	data.favorites.erase(id)
	data.recent.erase(id)
	var pid: String = data.rooms[id].portal_id
	data.rooms.erase(id)
	if pid != "" and data.portals.has(pid) and data.portals[pid].entrance == id:
		data.portals.erase(pid)
		_remove_relations("portal", pid)
		_touch("portal", pid, "deleted")
	_touch("room", id, "deleted")
	return true


## Champs optionnels de personnalisation d'une salle (absents des anciennes sauvegardes) :
## wall_color, floor_color, ceil_color, floor_mat, light, light_energy. size = [w, h, d].
const FLOOR_MATS := ["bois", "beton", "moquette", "carrelage", "marbre", "uni"]
const LIGHT_MOODS := ["chaude", "neutre", "froide", "tamisee"]
const ROOM_PRESETS := {
	"Bibliothèque calme": {"wall_color": "#5d6b5a", "floor_color": "#6b4a32", "ceil_color": "#e8e1d4", "floor_mat": "bois", "light": "chaude", "light_energy": 0.85},
	"Atelier": {"wall_color": "#b9b4ab", "floor_color": "#7d7b77", "ceil_color": "#d8d6d2", "floor_mat": "beton", "light": "neutre", "light_energy": 1.1},
	"Studio lumineux": {"wall_color": "#f2f1ee", "floor_color": "#d9d6cf", "ceil_color": "#ffffff", "floor_mat": "carrelage", "light": "froide", "light_energy": 1.4},
	"Nuit": {"wall_color": "#232a3d", "floor_color": "#2c2f3a", "ceil_color": "#1b1f2b", "floor_mat": "moquette", "light": "tamisee", "light_energy": 0.7},
}


## Met à jour une salle (nom, couleurs, matériau, lumière, dimensions). Un redimensionnement
## garde les objets dans les murs : ceux accrochés à un mur suivent ce mur.
func update_room(id: String, fields: Dictionary) -> void:
	if not data.rooms.has(id):
		return
	var r: Dictionary = data.rooms[id]
	if fields.has("size"):
		var ns: Array = fields["size"]
		var nsz := [clampf(float(ns[0]), 4.0, 40.0), clampf(float(ns[1]), 2.6, 12.0), clampf(float(ns[2]), 4.0, 40.0)]
		_refit_objects(id, r["size"], nsz)
		r["size"] = nsz
	for k in fields:
		if k == "name":
			rename_room(id, fields.name)
		elif k != "size":
			r[k] = fields[k]
	_touch("room", id, "updated")


func _refit_objects(room_id: String, old_size: Array, new_size: Array) -> void:
	var ohw: float = float(old_size[0]) / 2.0
	var ohd: float = float(old_size[2]) / 2.0
	var nhw: float = float(new_size[0]) / 2.0
	var nhd: float = float(new_size[2]) / 2.0
	var nh: float = float(new_size[1])
	for o in objects_in_room(room_id):
		var p := vec(o.pos)
		var half: Vector3 = ObjectRegistry.get_def(o.type).size * vec(o.scale) / 2.0
		var reach := maxf(half.x, half.z)
		# Collé à un mur (à moins de 0,6 m) : on conserve la distance à ce mur.
		if absf(absf(p.x) - ohw) < 0.6:
			p.x = signf(p.x) * (nhw - (ohw - absf(p.x)))
		if absf(absf(p.z) - ohd) < 0.6:
			p.z = signf(p.z) * (nhd - (ohd - absf(p.z)))
		var mx := maxf(nhw - minf(reach, nhw * 0.5), 0.0)
		var mz := maxf(nhd - minf(reach, nhd * 0.5), 0.0)
		if absf(absf(p.x) - nhw) > 0.6:
			p.x = clampf(p.x, -mx, mx)
		if absf(absf(p.z) - nhd) > 0.6:
			p.z = clampf(p.z, -mz, mz)
		p.x = clampf(p.x, -nhw, nhw)
		p.z = clampf(p.z, -nhd, nhd)
		p.y = clampf(p.y, 0.0, maxf(nh - half.y * 2.0, 0.0))
		if not p.is_equal_approx(vec(o.pos)):
			o.pos = v2a(p)
			_touch("object", o.id, "updated")


func child_rooms(parent_id: String) -> Array:
	return data.rooms.values().filter(func(r): return r.parent_id == parent_id)


func visit_room(id: String) -> void:
	data.recent.erase(id)
	data.recent.push_front(id)
	if data.recent.size() > 8:
		data.recent.resize(8)
	_dirty = true
	_save_in = 1.2


func toggle_favorite(id: String) -> bool:
	if id in data.favorites:
		data.favorites.erase(id)
	else:
		data.favorites.append(id)
	_touch("room", id, "updated")
	return id in data.favorites


func _add_door(room_id: String, target_id: String, type := "door") -> String:
	var slot := find_wall_slot(room_id, ObjectRegistry.get_def(type).size.z / 2.0)
	return create_object(type, room_id, slot.pos, Vector3(0, slot.rot, 0), Vector3.ONE, "", {}, {"target_room": target_id})


## Cherche un emplacement libre le long des murs (portes, grands tableaux).
func find_wall_slot(room_id: String, inset := 0.05, y := 0.0) -> Dictionary:
	var s = data.rooms[room_id].size
	var hw: float = s[0] / 2.0
	var hd: float = s[2] / 2.0
	var walls := [[Vector3(0, y, -hd + inset), Vector3.RIGHT, 0.0, hw], [Vector3(-hw + inset, y, 0), Vector3.BACK, 90.0, hd],
		[Vector3(hw - inset, y, 0), Vector3.BACK, -90.0, hd], [Vector3(0, y, hd - inset), Vector3.RIGHT, 180.0, hw]]
	var cands := []
	for w in walls:
		var offs := [0.0]
		var k := 3.0
		while k < w[3] - 1.4:
			offs.append(-k)
			offs.append(k)
			k += 3.0
		for o in offs:
			cands.append({"pos": w[0] + w[1] * o, "rot": w[2]})
	var occupied := objects_in_room(room_id).filter(func(o): return o.type in ["door", "portal", "whiteboard", "kanban", "library"])
	for c in cands:
		var free := true
		for o in occupied:
			var p := vec(o.pos)
			if Vector2(p.x, p.z).distance_to(Vector2(c.pos.x, c.pos.z)) < 2.2:
				free = false
				break
		if free:
			return c
	return cands[0]

# ------------------------------------------------------------------ objets

func create_object(type: String, room_id: String, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE,
		obj_name := "", content := {}, params := {}) -> String:
	var id := new_id("obj")
	if obj_name == "":
		obj_name = ObjectRegistry.get_def(type).label
	if content.is_empty():
		content = ObjectRegistry.default_content(type)
	data.objects[id] = {"id": id, "type": type, "name": obj_name, "room_id": room_id,
		"pos": v2a(pos), "rot": v2a(rot), "scale": v2a(scl), "content": content, "params": params,
		"created": now(), "modified": now()}
	_touch("object", id, "created")
	return id


func update_object(id: String, fields: Dictionary) -> void:
	if not data.objects.has(id):
		return
	var o: Dictionary = data.objects[id]
	for k in fields:
		var v = fields[k]
		o[k] = v2a(v) if v is Vector3 else v
	o.modified = now()
	_touch("object", id, "updated")


func set_transform(id: String, pos: Vector3, rot: Vector3, scl: Vector3) -> void:
	update_object(id, {"pos": pos, "rot": rot, "scale": scl})


func delete_object(id: String) -> void:
	if not data.objects.has(id):
		return
	data.objects.erase(id)
	_remove_relations("object", id)
	_touch("object", id, "deleted")


func duplicate_object(id: String) -> String:
	if not data.objects.has(id):
		return ""
	var o: Dictionary = data.objects[id].duplicate(true)
	var right := Basis.from_euler(vec(o.rot) * PI / 180.0) * Vector3.RIGHT
	var nid := create_object(o.type, o.room_id, vec(o.pos) + right * 0.3, vec(o.rot), vec(o.scale), o.name, o.content, o.params)
	_record("duplicate", id, nid)
	return nid


func objects_in_room(room_id: String) -> Array:
	return data.objects.values().filter(func(o): return o.room_id == room_id)

# ------------------------------------------------------------------ relations

func add_relation(from_kind: String, from_id: String, to_kind: String, to_id: String, type: String, description := "") -> String:
	var id := new_id("rel")
	data.relations[id] = {"id": id, "from": {"kind": from_kind, "id": from_id}, "to": {"kind": to_kind, "id": to_id},
		"type": type, "description": description, "created": now()}
	_touch("relation", id, "created")
	return id


func delete_relation(id: String) -> void:
	if data.relations.erase(id):
		_touch("relation", id, "deleted")


func relations_of(kind: String, id: String) -> Array:
	return data.relations.values().filter(func(r):
		return (r.from.kind == kind and r.from.id == id) or (r.to.kind == kind and r.to.id == id))


func _remove_relations(kind: String, id: String) -> void:
	for r in relations_of(kind, id):
		delete_relation(r.id)

# ------------------------------------------------------------------ documents

func import_document(path: String, room_id := "") -> String:
	var ext := path.get_extension().to_lower()
	var text := ""
	if ext in TEXT_EXT:
		text = FileAccess.get_file_as_string(path)
	elif ext == "pdf":
		text = PdfText.extract(path)
	else:
		return ""
	var id := new_id("doc")
	data.documents[id] = {"id": id, "name": path.get_file(), "ext": ext, "source_path": path,
		"text": text.left(MAX_DOC_CHARS), "imported": now(), "rooms": [room_id] if room_id != "" else []}
	_touch("document", id, "created")
	return id


func add_text_document(doc_name: String, text: String, room_id := "") -> String:
	var id := new_id("doc")
	data.documents[id] = {"id": id, "name": doc_name, "ext": "md", "source_path": "", "text": text,
		"imported": now(), "rooms": [room_id] if room_id != "" else []}
	_touch("document", id, "created")
	return id


func link_document(doc_id: String, room_id: String, linked := true) -> void:
	var rooms: Array = data.documents[doc_id].rooms
	if linked and not room_id in rooms:
		rooms.append(room_id)
	elif not linked:
		rooms.erase(room_id)
	_touch("document", doc_id, "updated")


func delete_document(doc_id: String) -> void:
	if data.documents.erase(doc_id):
		_remove_relations("document", doc_id)
		_touch("document", doc_id, "deleted")


func docs_for_room(room_id: String) -> Array:
	return data.documents.values().filter(func(d): return room_id in d.rooms)

# ------------------------------------------------------------------ transformations
## Une transformation crée toujours un NOUVEL élément : la source n'est jamais
## modifiée. Chaque transformation est historisée et reliée par une relation « dérivé ».

func transform(op: String, source_id: String, extra := {}) -> Dictionary:
	var result := {}
	var src = data.objects.get(source_id, {})
	match op:
		"note_to_card":
			result = {"kind": "object", "id": create_object("card", src.room_id, _beside(src, 0.5), vec(src.rot), Vector3.ONE,
				src.name, {"text": src.content.get("text", ""), "color": "#ffffff"})}
		"note_to_kanban":
			var cards := []
			for l in str(src.content.get("text", "")).split("\n", false):
				var t := l.strip_edges().trim_prefix("-").trim_prefix("*").strip_edges()
				if t != "":
					cards.append(t)
			var slot := find_wall_slot(src.room_id, 0.04, 0.8)
			result = {"kind": "object", "id": create_object("kanban", src.room_id, slot.pos, Vector3(0, slot.rot, 0), Vector3.ONE,
				"Kanban · " + src.name, {"columns": [{"title": "À faire", "cards": cards}, {"title": "En cours", "cards": []}, {"title": "Fait", "cards": []}]})}
		"note_to_room":
			var room = data.rooms[src.room_id]
			var rid := create_room(src.name, room.portal_id, src.room_id, [9.0, 4.0, 9.0])
			create_object("note", rid, Vector3(0, 1.2, -4.45), Vector3.ZERO, Vector3.ONE, src.name, src.content.duplicate(true))
			result = {"kind": "room", "id": rid}
		"conversation_to_note":
			var lines := []
			for m in src.content.get("messages", []):
				lines.append(("Moi : " if m.role == "user" else "Assistant : ") + m.text)
			result = {"kind": "object", "id": create_object("note", src.room_id, _beside(src, 1.1) + Vector3(0, 0.78, 0), vec(src.rot),
				Vector3.ONE, "Conversation du " + now().left(10), {"text": "\n".join(lines), "color": "#f2efe6"})}
		"doc_to_note":
			var d = data.documents[source_id]
			result = {"kind": "object", "id": create_object("note", extra.room_id, extra.pos, extra.get("rot", Vector3.ZERO), Vector3.ONE,
				"Extrait · " + d.name, {"text": extra.text, "color": "#f2efe6"})}
			add_relation("document", source_id, "object", result.id, "source", "Extrait du document")
			_record(op, source_id, result.id)
			return result
	if not result.is_empty():
		add_relation("object", source_id, result.kind, result.id, "dérivé", op)
		_record(op, source_id, result.id)
	return result


func _beside(src: Dictionary, dist: float) -> Vector3:
	return vec(src.pos) + Basis.from_euler(vec(src.rot) * PI / 180.0) * Vector3.RIGHT * dist


func _record(op: String, source: String, target: String) -> void:
	data.history.append({"time": now(), "op": op, "source": source, "result": target})
	_dirty = true

# ------------------------------------------------------------------ recherche globale

func search(query: String, limit := 60) -> Array:
	var q := query.strip_edges().to_lower()
	var out := []
	if q == "":
		return out
	for p in data.portals.values():
		if q in p.name.to_lower():
			out.append({"kind": "portal", "id": p.id, "label": "Portail · " + p.name})
	for r in data.rooms.values():
		if q in r.name.to_lower():
			out.append({"kind": "room", "id": r.id, "label": "Salle · " + r.name})
	for o in data.objects.values():
		if q in (o.name + " " + ObjectRegistry.text_of(o)).to_lower():
			var rn = data.rooms[o.room_id].name if data.rooms.has(o.room_id) else "?"
			out.append({"kind": "object", "id": o.id, "label": "%s · %s   — %s" % [ObjectRegistry.get_def(o.type).label, o.name, rn]})
	for d in data.documents.values():
		if q in d.name.to_lower() or q in d.text.to_lower():
			out.append({"kind": "document", "id": d.id, "label": "Document · " + d.name})
	return out.slice(0, limit)

# ------------------------------------------------------------------ monde de démonstration

func seed_world() -> void:
	data = _empty()
	var hub := create_room("Hub central", "", "", [20.0, 6.0, 20.0], "#d9d2c5")
	data.hub = hub
	var p_info := create_portal("Informatique", "#7aa7d6")
	create_portal("Recherches", "#b3a3d6")
	create_portal("Projets personnels", "#8fc28a")
	var info: String = data.portals[p_info].entrance
	var sub := create_room("Godot & 3D", p_info, info, [9.0, 4.0, 11.0])

	data.orb_migrated = true
	create_object("orb", hub, Vector3(0, 0, 1.5), Vector3.ZERO, Vector3.ONE, "Conscience")
	create_object("whiteboard", hub, Vector3(-9.97, 0.9, -3.0), Vector3(0, 90, 0), Vector3.ONE, "Idées en vrac",
		{"strokes": [{"c": "#3b6ea5", "w": 6, "p": [120, 140, 300, 120, 480, 160, 640, 130]}], "texts": [{"x": 120, "y": 100, "t": "Mes grandes questions", "c": "#222222"}]})
	create_object("library", hub, Vector3(-9.78, 0, 4.0), Vector3(0, 90, 0))
	create_object("kanban", hub, Vector3(9.97, 0.8, 0.0), Vector3(0, -90, 0), Vector3.ONE, "Chantiers",
		{"columns": [{"title": "À faire", "cards": ["Importer mes notes", "Créer un portail Philosophie"]}, {"title": "En cours", "cards": ["Découvrir Knowledge World"]}, {"title": "Fait", "cards": []}]})
	var welcome := create_object("note", hub, Vector3(9.98, 1.3, 4.0), Vector3(0, -90, 0), Vector3.ONE, "Bienvenue",
		{"text": "E : interagir\nB : mode construction\nTab : carte & recherche\nN : note rapide\nF : relations\nH : retour au hub", "color": "#f2efe6"})
	create_object("postit", hub, Vector3(9.98, 1.45, 4.5), Vector3(0, -90, 0), Vector3.ONE, "À essayer", {"text": "Transforme une note en Kanban !", "color": "#ffe27a"})
	for c in [Vector3(-8.5, 0, -8.5), Vector3(8.5, 0, -8.5), Vector3(-8.5, 0, 8.5), Vector3(8.5, 0, 8.5)]:
		create_object("lamp", hub, c)
	create_object("table", hub, Vector3(5.0, 0, 6.0), Vector3(0, -30, 0))

	create_object("note", info, Vector3(-5.97, 1.2, -2.0), Vector3(0, 90, 0), Vector3.ONE, "Informatique",
		{"text": "Domaine : développement, outils, systèmes.\nLa porte mène à la salle « Godot & 3D ».", "color": "#a7c7e7"})
	create_object("whiteboard", info, Vector3(5.97, 0.9, 2.5), Vector3(0, -90, 0))
	create_object("kanban", sub, Vector3(-4.47, 0.8, 0.0), Vector3(0, 90, 0), Vector3.ONE, "Apprentissage Godot",
		{"columns": [{"title": "À faire", "cards": ["Shaders", "Navigation 3D"]}, {"title": "En cours", "cards": ["GDScript"]}, {"title": "Fait", "cards": ["Installer Godot"]}]})
	create_object("desk", sub, Vector3(1.5, 0, 2.0), Vector3(0, -90, 0))

	var guide := add_text_document("Guide Knowledge World.md", GUIDE_TEXT, hub)
	add_relation("object", welcome, "room", sub, "thématique", "Exemple de relation note → salle")
	add_relation("document", guide, "room", info, "source", "Guide d'utilisation")


const GUIDE_TEXT := """# Knowledge World — guide rapide

Déplacement : ZQSD (ou flèches), souris pour regarder, Maj pour aller plus vite.
E : interagir avec l'objet visé (notes, tableaux, bureau, bibliothèque, portes).
Échap : fermer un panneau / libérer la souris. Clic : reprendre la main.

Tab : carte du monde, recherche globale, favoris, récents, création de salles et portails.
H : retour au hub. N : note rapide devant soi. F : relations de l'objet visé (ou de la salle).

B : mode construction.
  1-0 : choisir un objet à poser, clic gauche pour poser.
  Clic sur un objet : sélection. G : déplacer. R / molette : pivoter. PgUp / PgDn : taille.
  Ctrl+D : dupliquer. Suppr : supprimer. X : alignement sur grille. Clic droit : annuler.

Bibliothèque : importer des fichiers texte (txt, md, csv…) ou PDF simples, ou les glisser-déposer
dans la fenêtre. Un document peut être associé à plusieurs salles sans être dupliqué.

Bureau : assistant contextuel (simulé par défaut). Il propose, vous validez.
"""

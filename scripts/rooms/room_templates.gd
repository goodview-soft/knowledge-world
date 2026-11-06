class_name RoomTemplates
extends RefCounted
## Modèles de salles : forme + matériaux + ambiance + mobilier (types de ObjectRegistry.DEFS).
## Un modèle s'applique à une nouvelle salle (dialogue « Nouvelle salle ») ou à une salle
## existante (onglet « Modèle » de la personnalisation).

const ORDER := ["vierge", "bibliotheque", "atelier", "observatoire", "jardin", "salon", "galerie", "reunion", "meditation"]
const DEFAULTS := {"shape": "rect", "mezzanine": false}
const T := {
	"vierge": {"label": "Salle vierge", "glyph": "□", "accent": "#b9b2a6", "size": [10.0, 4.0, 10.0],
		"desc": "Le volume d'origine, sobre : à vous de tout composer.",
		"fields": {"shape": "rect", "mezzanine": false}},
	"bibliotheque": {"label": "Bibliothèque", "glyph": "▥", "accent": "#c79a62", "size": [12.0, 5.6, 14.0],
		"desc": "Voûte, alcôves d'étagères, mezzanine de lecture, coucher de soleil sur les collines.",
		"fields": {"shape": "alcoves", "ceiling": "voute", "mezzanine": true, "wall_mat": "bois", "wall_color": "#8a6a4e", "floor_mat": "bois",
			"floor_color": "#6b4a32", "ceil_color": "#e8dccb", "light": "chaude", "light_energy": 0.85, "windows": "fenetres", "window_walls": "sud",
			"sky": "coucher", "horizon": "collines", "trim": true, "cove": true, "dust": true}},
	"atelier": {"label": "Atelier", "glyph": "⚒", "accent": "#d08a5c", "size": [12.0, 4.6, 10.0],
		"desc": "Brique, béton ciré et verrière : une grande table pour fabriquer, en pleine lumière.",
		"fields": {"shape": "rect", "ceiling": "verriere", "mezzanine": false, "wall_mat": "brique", "wall_color": "#b46a4c", "floor_mat": "beton",
			"floor_color": "#8c8a86", "ceil_color": "#d8d6d2", "light": "neutre", "light_energy": 1.0, "windows": "baies", "window_walls": "cotes",
			"sky": "jour", "horizon": "collines", "trim": true, "cove": false, "dust": true}},
	"observatoire": {"label": "Observatoire", "glyph": "✦", "accent": "#7d8fd6", "size": [12.0, 4.0, 12.0],
		"desc": "Salle ronde sous une coupole vitrée : nuit étoilée, pierre sombre, silence.",
		"fields": {"shape": "ronde", "ceiling": "coupole_vitree", "mezzanine": false, "wall_mat": "sombre", "wall_color": "#4a5470", "floor_mat": "pierre",
			"floor_color": "#5d606a", "ceil_color": "#20242e", "light": "tamisee", "light_energy": 0.7, "windows": "aucune",
			"sky": "nuit", "horizon": "collines", "trim": true, "cove": true, "dust": true}},
	"jardin": {"label": "Jardin zen", "glyph": "❀", "accent": "#8fc28a", "size": [14.0, 3.2, 14.0],
		"desc": "À ciel ouvert : herbe, muret et garde-corps vitré, plantes, estrade de méditation, forêt au loin.",
		"fields": {"shape": "octogone", "ceiling": "ouvert", "parapet": true, "mezzanine": false, "wall_mat": "beton", "wall_color": "#cfc8b8",
			"floor_mat": "herbe", "floor_color": "#6f9150", "light": "neutre", "light_energy": 0.8, "windows": "aucune",
			"sky": "jour", "horizon": "foret", "trim": false, "cove": false, "dust": true}},
	"salon": {"label": "Salon", "glyph": "◐", "accent": "#e0a87a", "size": [12.0, 3.4, 11.0],
		"desc": "Pièce en L, baies sur la mer au soleil couchant, canapé, tapis et lampes douces.",
		"fields": {"shape": "L", "ceiling": "plat", "mezzanine": false, "wall_mat": "enduit", "wall_color": "#e6dccd", "floor_mat": "bois",
			"floor_color": "#8a6446", "ceil_color": "#f1ece4", "light": "chaude", "light_energy": 1.0, "windows": "baies", "window_walls": "sud",
			"sky": "coucher", "horizon": "mer", "trim": true, "cove": true, "dust": false}},
	"galerie": {"label": "Galerie", "glyph": "▢", "accent": "#e8e6e1", "size": [16.0, 5.0, 8.0],
		"desc": "Murs blancs sous une voûte, tableaux et sculptures, bancs pour contempler.",
		"fields": {"shape": "rect", "ceiling": "voute", "mezzanine": false, "wall_mat": "enduit", "wall_color": "#f2f0ec", "floor_mat": "beton",
			"floor_color": "#cfccc6", "ceil_color": "#ffffff", "light": "froide", "light_energy": 1.25, "windows": "aucune",
			"trim": true, "cove": true, "dust": false}},
	"reunion": {"label": "Salle de réunion", "glyph": "◫", "accent": "#7aa7d6", "size": [10.0, 3.4, 8.0],
		"desc": "Grande table, tableau blanc et Kanban, tissu acoustique, fenêtres sur la vallée.",
		"fields": {"shape": "rect", "ceiling": "plat", "mezzanine": false, "wall_mat": "tissu", "wall_color": "#5f6b78", "floor_mat": "moquette",
			"floor_color": "#3c4048", "ceil_color": "#e9e9e6", "light": "neutre", "light_energy": 1.05, "windows": "fenetres", "window_walls": "nord",
			"sky": "jour", "horizon": "collines", "trim": true, "cove": true, "dust": false}},
	"meditation": {"label": "Méditation", "glyph": "◯", "accent": "#b48ad6", "size": [9.0, 4.5, 9.0],
		"desc": "Octogone sombre sous coupole, un bandeau d'étoiles, une seule lampe, coussins au sol.",
		"fields": {"shape": "octogone", "ceiling": "coupole", "mezzanine": false, "wall_mat": "sombre", "wall_color": "#3a3646", "floor_mat": "bois",
			"floor_color": "#3b2f28", "ceil_color": "#24222c", "light": "tamisee", "light_energy": 0.3, "windows": "bandeau", "window_walls": "tous",
			"sky": "nuit", "horizon": "collines", "trim": true, "cove": false, "dust": true}},
}


static func get_template(tid: String) -> Dictionary:
	return T.get(tid, T.vierge)


## Champs complets d'un modèle : les clés de style absentes reprennent leur valeur par défaut.
static func fields_of(tid: String) -> Dictionary:
	var f: Dictionary = get_template(tid).fields.duplicate()
	f["template"] = tid
	return f


## Crée une salle d'après un modèle (forme posée avant les portes) et la meuble.
static func create(room_name: String, tid: String, portal_id: String, parent_id: String) -> String:
	var t := get_template(tid)
	var rid := World.create_room(room_name, portal_id, parent_id, (t.size as Array).duplicate(), "", fields_of(tid))
	furnish(rid, tid)
	World._touch("room", rid, "updated")
	return rid


## Applique un modèle à une salle existante (style ; mobilier en option).
static func apply(room_id: String, tid: String, with_furniture := false, resize := false) -> void:
	if not World.data.rooms.has(room_id):
		return
	var r: Dictionary = World.data.rooms[room_id]
	var f := fields_of(tid)
	for k in RoomBuilder.STYLE_KEYS:
		if not f.has(k) and not k in ["shape", "mezzanine"]:
			r.erase(k)
	if resize:
		f["size"] = (get_template(tid).size as Array).duplicate()
	World.update_room(room_id, f)
	if with_furniture:
		furnish(room_id, tid)


## Pose le mobilier du modèle (positions relatives à la forme ; ignore ce qui gêne).
static func furnish(room_id: String, tid: String) -> int:
	var room: Dictionary = World.data.rooms[room_id]
	var items := _items(tid, room)
	var doors := World.objects_in_room(room_id).filter(func(o): return o.type in ["door", "portal"])
	var mz := RoomShape.mezzanine(room)
	var n := 0
	for it in items:
		var type: String = it[0]
		var pos: Vector3 = it[1]
		var rot: float = it[2]
		var on_wall: bool = it.size() > 3 and it[3]
		var size3: Vector3 = ObjectRegistry.get_def(type).size
		var reach := maxf(size3.x, size3.z) / 2.0
		if not on_wall and not RoomShape.contains(room, pos, minf(reach, 0.45)):
			continue
		var ok := true
		for d in doors:
			var dp := World.vec(d.pos)
			if Vector2(dp.x, dp.z).distance_to(Vector2(pos.x, pos.z)) < 1.5 + reach and pos.y < 2.0:
				ok = false
		if not mz.is_empty() and pos.y < 0.5 and (mz.stair as Rect2).grow(0.5 + reach).has_point(Vector2(pos.x, pos.z)):
			ok = false
		if ok:
			World.create_object(type, room_id, pos, Vector3(0, rot, 0))
			n += 1
	return n


static func _face(from: Vector3, to: Vector3) -> float:
	return rad_to_deg(atan2(to.x - from.x, to.z - from.z))


## Objets alignés le long des murs choisis (normale filtrée), hors fenêtres et portes.
static func _wall_row(room: Dictionary, filter: Callable, type: String, y: float, spacing: float, max_n := 99) -> Array:
	var out := []
	var size3: Vector3 = ObjectRegistry.get_def(type).size
	var ws := RoomShape.walls(room)
	var spans := RoomShape.window_spans(room, World.objects_in_room(str(room.get("id", ""))))
	for i in ws.size():
		var w: Dictionary = ws[i]
		if not filter.call(w.n) or float(w.len) < size3.x + 0.6:
			continue
		var k := mini(max_n, maxi(1, int((float(w.len) - 0.6) / spacing)))
		for j in k:
			var t := (j - (k - 1) / 2.0) * spacing
			var bad := false
			for sp in spans:
				if sp.wall == i and t + size3.x / 2.0 > sp.t0 - 0.2 and t - size3.x / 2.0 < sp.t1 + 0.2:
					bad = true
			if bad:
				continue
			var p2: Vector2 = w.mid + w.dir * t + w.n * (size3.z / 2.0 + 0.01)
			out.append([type, Vector3(p2.x, y, p2.y), float(w.rot), true])
	return out


static func _items(tid: String, room: Dictionary) -> Array:
	var s := RoomShape.dims(room)
	var hw := s.x / 2.0
	var hd := s.z / 2.0
	var it := []
	match tid:
		"bibliotheque":
			for z in RoomShape.alcove_centers(room):
				for dz in [-0.55, 0.55]:
					it.append(["shelf", Vector3(hw - 0.22, 0, z + dz), -90.0])
					it.append(["shelf", Vector3(-hw + 0.22, 0, z + dz), 90.0])
			var c := Vector3(0, 0, 1.6)
			it.append(["rug", c, 0.0])
			it.append(["coffee_table", c, 0.0])
			it.append(["book_stack", c + Vector3(0.2, 0.42, 0), 20.0])
			for a in [Vector3(-1.4, 0, 2.4), Vector3(1.4, 0, 2.4)]:
				it.append(["armchair", a, _face(a, c)])
			it.append(["sofa", Vector3(0, 0, 0.1), 0.0])
			it.append(["lamp", Vector3(2.3, 0, 0.5), 0.0])
			it.append(["globe", Vector3(-2.3, 0, 0.5), 0.0])
			it.append(["plant", Vector3(-hw + 1.8, 0, hd - 0.6), 0.0])
			it.append(["plant", Vector3(hw - 1.8, 0, hd - 0.6), 0.0])
			var mz := RoomShape.mezzanine(room)
			if not mz.is_empty():
				var r: Rect2 = mz.rect
				var y: float = mz.y
				it.append(["library", Vector3(0, y, r.position.y + 0.25), 0.0])
				for x in [-2.2, -1.1, 1.1, 2.2]:
					if absf(x) < r.size.x / 2.0 - 0.6:
						it.append(["shelf", Vector3(x, y, r.position.y + 0.22), 0.0])
				var ac := Vector3(-r.size.x / 2.0 + 1.2, y, r.end.y - 1.2)
				it.append(["armchair", ac, 180.0])
				it.append(["lamp", ac + Vector3(-0.8, 0, -0.3), 0.0])
		"atelier":
			var c := Vector3(0, 0, 0.6)
			it.append(["big_table", c, 0.0])
			it.append(["desk_lamp", c + Vector3(0.8, 0.76, -0.2), -30.0])
			it.append(["book_stack", c + Vector3(-0.7, 0.76, 0.1), 10.0])
			for x in [-0.75, 0.75]:
				it.append(["chair", c + Vector3(x, 0, -0.8), 0.0])
				it.append(["chair", c + Vector3(x, 0, 0.8), 180.0])
			for x in [-hw + 1.4, -hw + 2.5, -hw + 3.6]:
				it.append(["shelf", Vector3(x, 0, -hd + 0.2), 0.0])
			it.append(["whiteboard", Vector3(2.4, 0.9, -hd + 0.04), 0.0, true])
			it.append(["table", Vector3(hw - 2.0, 0, hd - 1.0), 180.0])
			it.append(["lamp", Vector3(hw - 0.6, 0, -hd + 0.6), 0.0])
			it.append(["plant", Vector3(-hw + 0.6, 0, hd - 0.6), 0.0])
			it.append(["plant", Vector3(hw - 0.6, 0, hd - 2.4), 0.0])
		"observatoire":
			it.append(["rug", Vector3.ZERO, 0.0])
			it.append(["coffee_table", Vector3(0, 0, 0), 0.0])
			it.append(["globe", Vector3(0, 0.42, 0), 0.0])
			for a in [Vector3(-1.3, 0, 0.9), Vector3(1.3, 0, 0.9), Vector3(0, 0, -1.4)]:
				it.append(["armchair", a, _face(a, Vector3.ZERO)])
			var rad := minf(hw, hd) - 1.3
			for k in 4:
				var ang := TAU * (k + 0.5) / 4.0
				var p := Vector3(sin(ang) * rad, 0, cos(ang) * rad)
				it.append(["bench", p, _face(p, Vector3.ZERO)])
			it.append(["lamp", Vector3(rad * 0.75, 0, -rad * 0.2), 0.0])
			it.append(["plant", Vector3(-rad * 0.8, 0, -rad * 0.55), 0.0])
			it.append(["sculpture", Vector3(0, 0, -rad - 0.2), 0.0])
		"jardin":
			it.append(["platform", Vector3(0, 0, 0), 0.0])
			it.append(["cushions", Vector3(-0.4, 0.2, 0.1), 15.0])
			it.append(["cushions", Vector3(0.45, 0.2, -0.1), -20.0])
			it.append(["vase", Vector3(0.75, 0.2, 0.4), 0.0])
			var rad := minf(hw, hd) - 1.2
			for k in 8:
				var ang := TAU * k / 8.0 + PI / 8.0
				it.append(["plant", Vector3(sin(ang) * rad, 0, cos(ang) * rad), 0.0])
			for p in [Vector3(-3.2, 0, 1.0), Vector3(3.2, 0, 1.0)]:
				it.append(["bench", p, _face(p, Vector3.ZERO)])
			for p in [Vector3(-2.2, 0, -3.0), Vector3(2.6, 0, -2.4), Vector3(0.6, 0, 3.4)]:
				it.append(["sculpture", p, 30.0])
			it.append(["column", Vector3(-rad * 0.55, 0, -rad * 0.55), 0.0])
			it.append(["column", Vector3(rad * 0.55, 0, -rad * 0.55), 0.0])
		"salon":
			var c := Vector3(-hw * 0.4, 0, hd * 0.3)
			it.append(["rug", c, 0.0])
			it.append(["sofa", c + Vector3(0, 0, -1.3), 0.0])
			it.append(["cushions", c + Vector3(-0.4, 0.45, -1.3), 0.0])
			it.append(["coffee_table", c, 0.0])
			it.append(["book_stack", c + Vector3(0.25, 0.42, 0), -15.0])
			it.append(["vase", c + Vector3(-0.3, 0.42, 0), 0.0])
			for a in [c + Vector3(-1.8, 0, 0.4), c + Vector3(1.8, 0, 0.4)]:
				it.append(["armchair", a, _face(a, c)])
			it.append(["lamp", c + Vector3(-1.6, 0, -1.4), 0.0])
			it.append(["pouf", c + Vector3(0.6, 0, 1.3), 0.0])
			it.append(["plant", Vector3(-hw + 0.6, 0, -hd + 0.6), 0.0])
			it.append(["plant", Vector3(-hw + 0.6, 0, hd - 0.6), 0.0])
			for x in [hw - 1.0, hw - 2.1]:
				it.append(["shelf", Vector3(x, 0, -hd + 0.2), 0.0])
			var nook := Vector3(hw - 1.6, 0, -hd + 2.4)
			it.append(["armchair", nook, -135.0])
			it.append(["lamp", nook + Vector3(0.7, 0, -0.5), 0.0])
			it.append(["frame", Vector3(-1.0, 1.4, -hd + 0.03), 0.0, true])
		"galerie":
			it.append_array(_wall_row(room, func(n: Vector2): return absf(n.y) > 0.7, "frame", 1.35, 2.6))
			for x in [-hw * 0.5, 0.0, hw * 0.5]:
				it.append(["sculpture", Vector3(x, 0, 0), 0.0])
			for x in [-hw * 0.25, hw * 0.25]:
				it.append(["bench", Vector3(x, 0, 0), 0.0])
			for p in [Vector3(-hw + 0.6, 0, -hd + 0.6), Vector3(hw - 0.6, 0, -hd + 0.6)]:
				it.append(["plant", p, 0.0])
		"reunion":
			it.append(["big_table", Vector3.ZERO, 0.0])
			for x in [-0.8, 0.0, 0.8]:
				it.append(["chair", Vector3(x, 0, -0.78), 0.0])
				it.append(["chair", Vector3(x, 0, 0.78), 180.0])
			it.append(["chair", Vector3(-1.6, 0, 0), 90.0])
			it.append(["chair", Vector3(1.6, 0, 0), -90.0])
			it.append(["whiteboard", Vector3(-hw + 0.04, 0.9, 0), 90.0, true])
			it.append(["kanban", Vector3(hw - 0.04, 0.8, 0), -90.0, true])
			for x in [-0.7, 0.7]:
				it.append(["ceiling_light", Vector3(x, s.y - 0.06, 0), 0.0, true])
			it.append(["plant", Vector3(-hw + 0.6, 0, hd - 0.6), 0.0])
			it.append(["plant", Vector3(hw - 0.6, 0, hd - 0.6), 0.0])
			it.append(["desk_lamp", Vector3(0.9, 0.76, 0.2), 0.0])
		"meditation":
			it.append(["rug", Vector3.ZERO, 0.0])
			it.append(["cushions", Vector3(0, 0.012, 0.2), 0.0])
			for p in [Vector3(-1.1, 0, -0.6), Vector3(1.1, 0, -0.6)]:
				it.append(["pouf", p, 0.0])
			it.append(["lamp", Vector3(1.6, 0, 1.2), 0.0])
			it.append(["sculpture", Vector3(0, 0, -hd + 1.0), 0.0])
			it.append(["plant", Vector3(-hw + 1.4, 0, -hd + 1.4), 0.0])
			it.append(["vase", Vector3(-0.4, 0.012, 1.2), 0.0])
	return it

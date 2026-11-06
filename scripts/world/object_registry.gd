class_name ObjectRegistry
extends RefCounted
## Catalogue des types d'objets. Ajouter un type = ajouter une entrée dans DEFS,
## un contenu par défaut, un constructeur visuel (build) et éventuellement un panneau.
## size : (largeur, hauteur, profondeur) en mètres ; origine = bas-centre, face avant = +Z.

const DEFS := {
	"note": {"label": "Note", "size": Vector3(0.32, 0.42, 0.02), "panel": "note"},
	"postit": {"label": "Post-it", "size": Vector3(0.16, 0.16, 0.01), "panel": "note"},
	"card": {"label": "Fiche", "size": Vector3(0.44, 0.3, 0.02), "panel": "note"},
	"whiteboard": {"label": "Tableau blanc", "size": Vector3(2.0, 1.2, 0.06), "panel": "whiteboard"},
	"kanban": {"label": "Kanban", "size": Vector3(2.4, 1.4, 0.06), "panel": "kanban"},
	"desk": {"label": "Bureau", "size": Vector3(1.6, 1.25, 0.8), "panel": "chat"},
	"library": {"label": "Bibliothèque", "size": Vector3(1.6, 2.2, 0.42), "panel": "library"},
	"table": {"label": "Table de travail", "size": Vector3(1.8, 0.76, 0.9), "panel": ""},
	"lamp": {"label": "Lampe", "size": Vector3(0.34, 1.6, 0.34), "panel": ""},
	"door": {"label": "Porte", "size": Vector3(1.3, 2.4, 0.16), "panel": "travel"},
	"portal": {"label": "Portail", "size": Vector3(2.4, 3.4, 0.3), "panel": "travel"},
}
## Ordre de la palette du mode construction (touches 1..0).
const PALETTE := ["note", "postit", "card", "whiteboard", "kanban", "desk", "library", "table", "lamp", "door"]


static func get_def(type: String) -> Dictionary:
	return DEFS.get(type, {"label": type, "size": Vector3(0.5, 0.5, 0.5), "panel": ""})


static func default_content(type: String) -> Dictionary:
	match type:
		"note": return {"text": "", "color": "#f2efe6"}
		"postit": return {"text": "", "color": "#ffe27a"}
		"card": return {"text": "", "color": "#ffffff"}
		"whiteboard": return {"strokes": [], "texts": []}
		"kanban": return {"columns": [{"title": "À faire", "cards": []}, {"title": "En cours", "cards": []}, {"title": "Fait", "cards": []}]}
		"desk": return {"messages": []}
	return {}


## Représentation texte d'un objet (recherche, contexte IA, RAG).
static func text_of(o: Dictionary) -> String:
	var c: Dictionary = o.get("content", {})
	match o.type:
		"note", "postit", "card":
			return str(c.get("text", ""))
		"kanban":
			var parts := []
			for col in c.get("columns", []):
				parts.append("%s : %s" % [col.title, ", ".join(PackedStringArray(col.cards))])
			return "\n".join(parts)
		"whiteboard":
			return " ".join(PackedStringArray(c.get("texts", []).map(func(t): return t.t)))
		"desk":
			return "\n".join(PackedStringArray(c.get("messages", []).map(func(m): return m.text)))
	return ""

# ------------------------------------------------------------------ visuels

static func mat(color: Color, emission := 0.0, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


static func box(parent: Node3D, size: Vector3, center: Vector3, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = center
	parent.add_child(mi)
	return mi


static func label(parent: Node3D, text: String, pos: Vector3, width_m: float, font := 28, color := Color(0.12, 0.12, 0.12)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = font
	l.outline_size = 0
	l.modulate = color
	l.pixel_size = width_m / 480.0
	l.width = 480.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.double_sided = false
	parent.add_child(l)
	return l


static func build(o: Dictionary, extra := {}) -> Node3D:
	var root := Node3D.new()
	var s: Vector3 = get_def(o.type).size
	var c: Dictionary = o.get("content", {})
	var front := s.z / 2.0 + 0.004
	match o.type:
		"note", "postit", "card":
			box(root, s, Vector3(0, s.y / 2, 0), mat(Color(c.get("color", "#f2efe6")), 0.0, 0.95))
			var limit: int = {"note": 220, "postit": 60, "card": 160}[o.type]
			var l := label(root, "%s\n%s" % [o.name, str(c.get("text", "")).left(limit)], Vector3(0, s.y / 2, front), s.x * 0.88, 26)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		"whiteboard":
			box(root, s, Vector3(0, s.y / 2, 0), mat(Color(0.55, 0.56, 0.58), 0.0, 0.4))
			var face := box(root, Vector3(s.x - 0.08, s.y - 0.08, 0.01), Vector3(0, s.y / 2, s.z / 2), null)
			var fm := mat(Color.WHITE, 0.0, 0.5)
			fm.albedo_texture = whiteboard_texture(c)
			face.material_override = fm
			var fw := s.x - 0.08
			var fh := s.y - 0.08
			for t in c.get("texts", []):
				var tl := label(root, t.t, Vector3(-fw / 2 + t.x / 1000.0 * fw, s.y / 2 + fh / 2 - t.y / 600.0 * fh, front + 0.003), 1.2, 40, Color(t.get("c", "#222222")))
				tl.autowrap_mode = TextServer.AUTOWRAP_OFF
				tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			label(root, o.name, Vector3(0, -0.06, s.z / 2), 1.0, 24, Color(0.8, 0.8, 0.8))
		"kanban":
			box(root, s, Vector3(0, s.y / 2, 0), mat(Color(0.18, 0.2, 0.23), 0.0, 0.7))
			label(root, o.name, Vector3(0, s.y - 0.07, front), 1.6, 34, Color(0.92, 0.92, 0.9))
			var cols: Array = c.get("columns", [])
			var n := maxi(1, cols.size())
			var cw := (s.x - 0.1) / n
			for i in cols.size():
				var cx := -s.x / 2 + 0.05 + cw * (i + 0.5)
				box(root, Vector3(cw - 0.05, s.y - 0.25, 0.01), Vector3(cx, (s.y - 0.15) / 2, s.z / 2), mat(Color(0.26, 0.29, 0.33)))
				label(root, cols[i].title, Vector3(cx, s.y - 0.2, front + 0.006), cw * 0.9, 30, Color(0.85, 0.88, 0.95))
				var cards: Array = cols[i].cards
				for k in mini(cards.size(), 6):
					var cy := s.y - 0.34 - k * 0.17
					box(root, Vector3(cw - 0.12, 0.14, 0.012), Vector3(cx, cy, s.z / 2 + 0.008), mat(Color(0.96, 0.93, 0.82)))
					label(root, str(cards[k]).left(40), Vector3(cx, cy, s.z / 2 + 0.016), cw * 0.8, 28)
				if cards.size() > 6:
					label(root, "+%d" % (cards.size() - 6), Vector3(cx, 0.1, front + 0.006), cw * 0.5, 28, Color(0.85, 0.85, 0.85))
		"desk":
			var wood := mat(Color(0.55, 0.42, 0.31), 0.0, 0.6)
			box(root, Vector3(s.x, 0.05, s.z), Vector3(0, 0.745, 0), wood)
			for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				box(root, Vector3(0.05, 0.72, 0.05), Vector3(p.x * (s.x / 2 - 0.06), 0.36, p.y * (s.z / 2 - 0.06)), mat(Color(0.2, 0.2, 0.22)))
			box(root, Vector3(0.82, 0.48, 0.03), Vector3(0, 1.0, -0.22), mat(Color(0.12, 0.14, 0.17), 0.0, 0.3))
			box(root, Vector3(0.78, 0.44, 0.005), Vector3(0, 1.0, -0.203), mat(Color(0.18, 0.3, 0.42), 0.8))
			label(root, "%s\nAssistant · E" % o.name, Vector3(0, 1.0, -0.198), 0.6, 30, Color(0.85, 0.93, 1.0))
		"library":
			var w2 := mat(Color(0.48, 0.37, 0.28), 0.0, 0.7)
			for x in [-1, 1]:
				box(root, Vector3(0.04, s.y, s.z), Vector3(x * (s.x / 2 - 0.02), s.y / 2, 0), w2)
			box(root, Vector3(s.x, s.y, 0.02), Vector3(0, s.y / 2, -s.z / 2 + 0.01), w2)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(o.id)
			var books := int(extra.get("doc_count", 0))
			for k in 5:
				var y := 0.05 + k * 0.5
				box(root, Vector3(s.x - 0.08, 0.03, s.z - 0.02), Vector3(0, y, 0), w2)
				var x := -s.x / 2 + 0.08
				var shown := clampi(books - k * 12, 0, 12) if k < 4 else 0
				for b in (shown if books > 0 else rng.randi_range(3, 9)):
					var bw := rng.randf_range(0.04, 0.08)
					var bh := rng.randf_range(0.26, 0.4)
					var col := Color.from_hsv(rng.randf(), 0.35, rng.randf_range(0.45, 0.8))
					box(root, Vector3(bw, bh, 0.24), Vector3(x + bw / 2, y + 0.015 + bh / 2, 0.02), mat(col))
					x += bw + 0.012
			label(root, "%s\n%d document(s) · E" % [o.name, books], Vector3(0, s.y + 0.15, 0.1), 1.4, 30, Color(0.95, 0.93, 0.88))
		"table":
			var t := mat(Color(0.62, 0.6, 0.56), 0.0, 0.5)
			box(root, Vector3(s.x, 0.05, s.z), Vector3(0, s.y - 0.025, 0), t)
			box(root, Vector3(0.08, s.y - 0.05, s.z * 0.7), Vector3(-s.x / 2 + 0.2, (s.y - 0.05) / 2, 0), t)
			box(root, Vector3(0.08, s.y - 0.05, s.z * 0.7), Vector3(s.x / 2 - 0.2, (s.y - 0.05) / 2, 0), t)
		"lamp":
			box(root, Vector3(0.3, 0.03, 0.3), Vector3(0, 0.015, 0), mat(Color(0.2, 0.2, 0.2)))
			box(root, Vector3(0.025, 1.4, 0.025), Vector3(0, 0.72, 0), mat(Color(0.2, 0.2, 0.2)))
			box(root, Vector3(0.32, 0.22, 0.32), Vector3(0, 1.48, 0), mat(Color(1.0, 0.86, 0.66), 2.2))
			var light := OmniLight3D.new()
			light.position = Vector3(0, 1.45, 0)
			light.light_color = Color(1.0, 0.83, 0.62)
			light.light_energy = 0.9
			light.omni_range = 5.0
			root.add_child(light)
		"door", "portal":
			var col := Color(extra.get("color", "#cfc8bc"))
			var frame := mat(Color(0.22, 0.22, 0.24), 0.0, 0.5)
			var post := 0.12 if o.type == "door" else 0.22
			box(root, Vector3(post, s.y, s.z), Vector3(-s.x / 2 + post / 2, s.y / 2, 0), frame)
			box(root, Vector3(post, s.y, s.z), Vector3(s.x / 2 - post / 2, s.y / 2, 0), frame)
			box(root, Vector3(s.x, post, s.z), Vector3(0, s.y - post / 2, 0), frame)
			var inner_m := mat(col, 1.6 if o.type == "portal" else 0.7, 0.3)
			box(root, Vector3(s.x - post * 2, s.y - post, 0.02), Vector3(0, (s.y - post) / 2, 0), inner_m)
			var txt: String = extra.get("target_name", "")
			var lbl := label(root, txt if txt != "" else "(porte sans destination)", Vector3(0, s.y + 0.22, front), s.x * 1.6, 34, Color(0.95, 0.94, 0.9))
			lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			if o.type == "portal":
				var pl := OmniLight3D.new()
				pl.position = Vector3(0, 1.4, 0.8)
				pl.light_color = col
				pl.light_energy = 0.8
				pl.omni_range = 4.0
				root.add_child(pl)
	return root


## Rasterise les traits du tableau blanc (canevas logique 1000×600) en texture.
static func whiteboard_texture(c: Dictionary) -> ImageTexture:
	var w := 500
	var h := 300
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.97, 0.97, 0.95))
	for st in c.get("strokes", []):
		var col := Color(st.get("c", "#222222"))
		var r := maxi(1, int(st.get("w", 4)) / 4)
		var p: Array = st.get("p", [])
		if p.size() == 2:
			img.fill_rect(Rect2i(int(p[0] / 2) - r, int(p[1] / 2) - r, r * 2 + 1, r * 2 + 1), col)
		for i in range(0, p.size() - 3, 2):
			var a := Vector2(p[i], p[i + 1]) / 2.0
			var b := Vector2(p[i + 2], p[i + 3]) / 2.0
			var steps := maxi(1, int(a.distance_to(b)))
			for k in steps + 1:
				var q := a.lerp(b, float(k) / steps)
				img.fill_rect(Rect2i(int(q.x) - r, int(q.y) - r, r * 2 + 1, r * 2 + 1), col)
	return ImageTexture.create_from_image(img)

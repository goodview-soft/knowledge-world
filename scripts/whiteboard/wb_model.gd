class_name WBModel
extends RefCounted
## Modèle du tableau blanc : éléments typés, migration de l'ancien format, géométrie, hit-test.
## content = {"elements": [...], "view": {cx, cy, zoom}, "texts": [{t}]}  (texts : pour la recherche)
## Élément = {id, type, x, y, w, h, points[x0,y0,...], stroke, fill, width, rough, seed, text, fs}

const FRAME := Rect2(0, 0, 1000, 600)
const BOARD_RATIO := 1.92 / 1.12
const POINTLIKE := ["freedraw", "line", "arrow"]
const SHAPES := ["rect", "ellipse", "diamond"]
const NOTE_PAD := 14.0

static var _counter := 0


static func new_id() -> String:
	_counter += 1
	return "e%x%x%d" % [int(Time.get_unix_time_from_system()), randi() % 0xffff, _counter]


static func make(type: String, stroke := "#1e1e1e", fill := "", width := 4.0, rough := false, fs := 28) -> Dictionary:
	return {"id": new_id(), "type": type, "x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0, "points": [],
		"stroke": stroke, "fill": fill, "width": width, "rough": rough, "seed": randi() % 100000, "text": "", "fs": fs}


static func normalize(e: Dictionary) -> Dictionary:
	var d := make(str(e.get("type", "rect")))
	for k in d:
		if e.has(k):
			d[k] = e[k]
	if str(d.id) == "":
		d.id = new_id()
	if not (d.points is Array):
		d.points = []
	# Types stables (le JSON rend tout en float) : comparaisons d'état fiables.
	d.points = d.points.map(func(v): return float(v))
	for k in ["x", "y", "w", "h", "width"]:
		d[k] = float(d[k])
	d.seed = int(d.seed)
	d.fs = int(d.fs)
	d.rough = bool(d.rough)
	d.text = str(d.text)
	d.stroke = str(d.stroke)
	d.fill = str(d.fill)
	if d.type in SHAPES or d.type == "note":
		var r := Rect2(float(d.x), float(d.y), float(d.w), float(d.h)).abs()
		d.x = r.position.x
		d.y = r.position.y
		d.w = r.size.x
		d.h = r.size.y
	return d


## Convertit n'importe quel contenu (ancien {strokes, texts} 1000×600 ou nouveau) au format éléments.
static func migrate(c: Dictionary) -> Dictionary:
	var out := {"elements": [], "view": {}}
	var els: Array = out.elements
	if c.has("elements"):
		for e in c.get("elements", []):
			if e is Dictionary:
				els.append(normalize(e))
		var v = c.get("view", {})
		if v is Dictionary:
			out.view = v.duplicate()
	else:
		for st in c.get("strokes", []):
			var p: Array = st.get("p", [])
			if p.size() < 2:
				continue
			var e := make("freedraw", str(st.get("c", "#222222")), "", float(st.get("w", 6)))
			e.points = p.map(func(v): return float(v))
			els.append(e)
		for t in c.get("texts", []):
			var e := make("text", str(t.get("c", "#222222")), "", 2.0, false, 36)
			e.x = float(t.get("x", 0))
			e.y = float(t.get("y", 0))
			e.text = str(t.get("t", ""))
			els.append(e)
	out.texts = texts_of(els)
	return out


static func to_content(elements: Array, view: Dictionary) -> Dictionary:
	return {"elements": elements.duplicate(true), "view": view.duplicate(), "texts": texts_of(elements)}


static func texts_of(elements: Array) -> Array:
	var out := []
	for e in elements:
		if e.type in ["text", "note"] and str(e.text).strip_edges() != "":
			out.append({"t": str(e.text)})
	return out


static func find(elements: Array, id: String) -> Dictionary:
	for e in elements:
		if e.id == id:
			return e
	return {}


static func pts(e: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var p: Array = e.points
	for i in range(0, p.size() - 1, 2):
		out.append(Vector2(p[i], p[i + 1]))
	return out


## Contour en coordonnées monde (fermé pour les formes).
static func outline(e: Dictionary) -> PackedVector2Array:
	var t: String = e.type
	if t in POINTLIKE:
		return pts(e)
	var r := Rect2(float(e.x), float(e.y), float(e.w), float(e.h)).abs()
	var out := PackedVector2Array()
	match t:
		"ellipse":
			var c := r.get_center()
			var rad := r.size / 2.0
			for i in 49:
				var a := TAU * i / 48.0
				out.append(c + Vector2(cos(a) * rad.x, sin(a) * rad.y))
		"diamond":
			var c := r.get_center()
			out.append_array([Vector2(c.x, r.position.y), Vector2(r.end.x, c.y), Vector2(c.x, r.end.y), Vector2(r.position.x, c.y), Vector2(c.x, r.position.y)])
		_:
			out.append_array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), r.position])
	return out


static func raw_bbox(e: Dictionary) -> Rect2:
	var t: String = e.type
	if t == "text":
		return Rect2(Vector2(float(e.x), float(e.y)), WBDraw.text_size(str(e.text), int(e.fs)))
	if t in POINTLIKE:
		var p := pts(e)
		if p.is_empty():
			return Rect2()
		var r := Rect2(p[0], Vector2.ZERO)
		for q in p:
			r = r.expand(q)
		return r
	return Rect2(float(e.x), float(e.y), float(e.w), float(e.h)).abs()


static func bbox(e: Dictionary) -> Rect2:
	var r := raw_bbox(e)
	if e.type in POINTLIKE or e.type in SHAPES:
		r = r.grow(float(e.width) / 2.0)
	return r


static func content_bounds(elements: Array) -> Rect2:
	if elements.is_empty():
		return FRAME
	var r := bbox(elements[0])
	for e in elements:
		r = r.merge(bbox(e))
	return r


## Zone affichée sur le tableau 3D : le cadre 1000×600 étendu au contenu, au ratio donné.
static func render_region(elements: Array, ratio: float) -> Rect2:
	var r := FRAME
	for e in elements:
		r = r.merge(bbox(e).grow(16))
	var c := r.get_center()
	var w := r.size.x
	var h := r.size.y
	if w / h < ratio:
		w = h * ratio
	else:
		h = w / ratio
	return Rect2(c - Vector2(w, h) / 2.0, Vector2(w, h))


static func dist_to_poly(p: Vector2, pl: PackedVector2Array) -> float:
	if pl.is_empty():
		return INF
	if pl.size() == 1:
		return p.distance_to(pl[0])
	var d := INF
	for i in pl.size() - 1:
		d = minf(d, p.distance_to(Geometry2D.get_closest_point_to_segment(p, pl[i], pl[i + 1])))
	return d


static func hit(e: Dictionary, p: Vector2, tol: float) -> bool:
	var t: String = e.type
	if t == "text" or t == "note":
		return raw_bbox(e).grow(tol).has_point(p)
	var ol := outline(e)
	if t in SHAPES and str(e.fill) != "" and Geometry2D.is_point_in_polygon(p, ol):
		return true
	return dist_to_poly(p, ol) <= tol + float(e.width) / 2.0


static func translate(e: Dictionary, d: Vector2) -> void:
	e.x = float(e.x) + d.x
	e.y = float(e.y) + d.y
	var p: Array = e.points
	for i in range(0, p.size() - 1, 2):
		p[i] = float(p[i]) + d.x
		p[i + 1] = float(p[i + 1]) + d.y


## Transforme l'élément pour que sa boîte a devienne b.
static func resize(e: Dictionary, a: Rect2, b: Rect2) -> void:
	var sx := b.size.x / a.size.x if a.size.x > 0.001 else 1.0
	var sy := b.size.y / a.size.y if a.size.y > 0.001 else 1.0
	var t: String = e.type
	if t == "text":
		e.fs = clampi(roundi(float(e.fs) * sy), 6, 400)
		e.x = b.position.x
		e.y = b.position.y
	elif t in POINTLIKE:
		var p: Array = e.points
		for i in range(0, p.size() - 1, 2):
			p[i] = b.position.x + (float(p[i]) - a.position.x) * sx
			p[i + 1] = b.position.y + (float(p[i + 1]) - a.position.y) * sy
	else:
		e.x = b.position.x + (float(e.x) - a.position.x) * sx
		e.y = b.position.y + (float(e.y) - a.position.y) * sy
		e.w = float(e.w) * sx
		e.h = float(e.h) * sy


static func assign(dst: Dictionary, src: Dictionary) -> void:
	for k in src:
		dst[k] = src[k].duplicate() if src[k] is Array else src[k]

class_name KWGraphView
extends Control
## Graphe 2D force-dirigé du monde (salles, notes, documents) dessiné en _draw.
## Molette : zoom · glisser le fond : panoramique · glisser un nœud : le déplacer ·
## survol : nom + voisins · clic : signal node_clicked(kind, id).

signal node_clicked(kind: String, id: String)

const COLORS := {"room": Color("#8ea8ff"), "note": Color("#8fd6a8"), "document": Color("#f0c674"), "portal": Color("#d7a6ff")}

var nodes := [] # {key, kind, id, label, type, pos, vel, deg}
var index := {} # key -> i
var edges := [] # [i, j, weak]
var neighbors := {} # i -> {j: true}
var zoom := 1.0
var pan := Vector2.ZERO
var hovered := -1
var highlight := {} # i -> true (filtre tag)
var _drag_node := -1
var _drag_pan := false
var _moved := 0.0
var _alpha := 1.0
var auto_fit := true


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


## mode : "all" (salles + notes + documents) ou "notes". tag : met en évidence les notes taguées.
func build(mode := "all", tag := "") -> void:
	nodes.clear()
	index.clear()
	edges.clear()
	neighbors.clear()
	highlight.clear()
	hovered = -1
	if mode == "all":
		for r in World.data.rooms.values():
			_add("room", r.id, r.name, "room")
		for d in World.data.documents.values():
			_add("document", d.id, d.name, "document")
	for o in NoteLinks.notes():
		_add("object", o.id, o.name, "note")
	for r in World.data.relations.values():
		_edge(r.from.kind + ":" + r.from.id, r.to.kind + ":" + r.to.id, false)
	if mode == "all":
		for r in World.data.rooms.values():
			if str(r.get("parent_id", "")) != "":
				_edge("room:" + r.parent_id, "room:" + r.id, false)
		for o in NoteLinks.notes():
			_edge("room:" + o.room_id, "object:" + o.id, true)
		for d in World.data.documents.values():
			for rid in d.rooms:
				_edge("room:" + rid, "document:" + d.id, true)
	if tag != "":
		for nid in NoteLinks.notes_with_tag(tag):
			if index.has("object:" + nid):
				highlight[index["object:" + nid]] = true
	for e in edges:
		if not e[2]:
			nodes[e[0]].deg += 1
			nodes[e[1]].deg += 1
	_alpha = 1.0
	auto_fit = true
	zoom = 1.0
	pan = Vector2.ZERO
	queue_redraw()


func _add(kind: String, id: String, label: String, type: String) -> void:
	var key := kind + ":" + id
	if index.has(key):
		return
	var h := hash(key)
	var ang := float(h % 6283) / 1000.0
	var rad := 60.0 + float((h / 7) % 300)
	index[key] = nodes.size()
	nodes.append({"key": key, "kind": kind, "id": id, "label": label, "type": type,
		"pos": Vector2(cos(ang), sin(ang)) * rad, "vel": Vector2.ZERO, "deg": 0})


func _edge(a: String, b: String, weak: bool) -> void:
	if not index.has(a) or not index.has(b) or a == b:
		return
	var i: int = index[a]
	var j: int = index[b]
	if neighbors.get(i, {}).has(j):
		return
	edges.append([i, j, weak])
	if not neighbors.has(i):
		neighbors[i] = {}
	if not neighbors.has(j):
		neighbors[j] = {}
	neighbors[i][j] = true
	neighbors[j][i] = true


func radius(n: Dictionary) -> float:
	return (7.0 if n.type == "room" else 5.0) + 2.4 * sqrt(float(n.deg))


func _process(delta: float) -> void:
	if _alpha < 0.005 or nodes.is_empty():
		return
	step(minf(delta, 0.05))
	if auto_fit:
		fit()
	queue_redraw()


## Une itération de simulation (répulsion, ressorts, gravité, amortissement).
func step(dt := 0.016) -> void:
	var n := nodes.size()
	var f := []
	f.resize(n)
	for i in n:
		f[i] = -nodes[i].pos * 0.6 # gravité vers le centre
	for i in n:
		var pa: Vector2 = nodes[i].pos
		for j in range(i + 1, n):
			var d: Vector2 = pa - nodes[j].pos
			var l2 := maxf(d.length_squared(), 25.0)
			var push := d / sqrt(l2) * (5200.0 / l2) * 60.0
			f[i] += push
			f[j] -= push
	for e in edges:
		var a: Dictionary = nodes[e[0]]
		var b: Dictionary = nodes[e[1]]
		var d: Vector2 = b.pos - a.pos
		var rest := 110.0 if e[2] else 80.0
		var k := 1.2 if e[2] else 3.0
		var pull := d.normalized() * (d.length() - rest) * k
		f[e[0]] += pull
		f[e[1]] -= pull
	for i in n:
		if i == _drag_node:
			continue
		var nd: Dictionary = nodes[i]
		nd.vel = (nd.vel + f[i] * dt * _alpha) * 0.82
		nd.vel = nd.vel.limit_length(900.0)
		nd.pos += nd.vel * dt
	_alpha *= 0.995


func to_screen(p: Vector2) -> Vector2:
	return size / 2 + pan + p * zoom


func to_world(s: Vector2) -> Vector2:
	return (s - size / 2 - pan) / zoom


func node_at(s: Vector2) -> int:
	var w := to_world(s)
	var best := -1
	var bd := INF
	for i in nodes.size():
		var d: float = nodes[i].pos.distance_to(w)
		if d < radius(nodes[i]) + 6.0 / zoom and d < bd:
			bd = d
			best = i
	return best


func _focus_set() -> Dictionary:
	if hovered >= 0:
		var s := {hovered: true}
		for j in neighbors.get(hovered, {}):
			s[j] = true
		return s
	return highlight


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(KWTheme.BG, 0.9))
	var focus := _focus_set()
	var font := get_theme_default_font()
	for e in edges:
		var on: bool = focus.is_empty() or (focus.has(e[0]) and focus.has(e[1]))
		var c := Color(1, 1, 1, 0.06 if e[2] else 0.22)
		if not focus.is_empty():
			c = Color(KWTheme.ACCENT, 0.75) if on else Color(1, 1, 1, 0.03)
		draw_line(to_screen(nodes[e[0]].pos), to_screen(nodes[e[1]].pos), c, 1.5 if on and not focus.is_empty() else 1.0, true)
	for i in nodes.size():
		var nd: Dictionary = nodes[i]
		var c: Color = COLORS.get(nd.type, Color.WHITE)
		if not focus.is_empty() and not focus.has(i):
			c = Color(c, 0.18)
		var p := to_screen(nd.pos)
		var r := radius(nd) * clampf(zoom, 0.6, 2.0)
		if i == hovered:
			draw_circle(p, r + 5, Color(c, 0.25))
		draw_circle(p, r, c)
		var show_label: bool = zoom > 1.3 or focus.has(i) or nd.type == "room" and zoom > 0.8
		if show_label:
			var fs := 13 if i != hovered else 15
			var txt: String = nd.label
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var col := Color(KWTheme.TEXT, 1.0 if focus.is_empty() or focus.has(i) else 0.25)
			draw_string(font, p + Vector2(-tw / 2, r + fs + 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and mb.pressed:
			var before := to_world(mb.position)
			zoom = clampf(zoom * (1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.12), 0.2, 5.0)
			pan += mb.position - to_screen(before)
			auto_fit = false
			queue_redraw()
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_moved = 0.0
				_drag_node = node_at(mb.position)
				_drag_pan = _drag_node < 0
			else:
				if _moved < 5.0 and _drag_node >= 0:
					var nd: Dictionary = nodes[_drag_node]
					node_clicked.emit(nd.kind, nd.id)
				_drag_node = -1
				_drag_pan = false
			accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_moved += mm.relative.length()
			if _drag_node >= 0:
				nodes[_drag_node].pos = to_world(mm.position)
				nodes[_drag_node].vel = Vector2.ZERO
				_alpha = maxf(_alpha, 0.3)
			elif _drag_pan:
				pan += mm.relative
				auto_fit = false
		else:
			var h := node_at(mm.position)
			if h != hovered:
				hovered = h
				tooltip_text = ""
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h >= 0 else Control.CURSOR_ARROW
		queue_redraw()


## Recentre la vue sur l'ensemble des nœuds.
func fit() -> void:
	if nodes.is_empty() or size.x < 10:
		return
	var r := Rect2(nodes[0].pos, Vector2.ZERO)
	for nd in nodes:
		r = r.expand(nd.pos)
	r = r.grow(40)
	zoom = clampf(minf(size.x / r.size.x, size.y / r.size.y), 0.2, 2.5)
	pan = -r.get_center() * zoom
	queue_redraw()

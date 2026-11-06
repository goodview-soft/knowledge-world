class_name WBCanvas
extends Control
## Canevas interactif infini du tableau blanc (façon Excalidraw) : outils, sélection, zoom, panoramique.

const TOOL_KEYS := {KEY_V: "select", KEY_1: "select", KEY_H: "hand", KEY_P: "freedraw", KEY_L: "line", KEY_A: "arrow",
	KEY_R: "rect", KEY_O: "ellipse", KEY_D: "diamond", KEY_T: "text", KEY_N: "note", KEY_E: "eraser"}

var board: WhiteboardPanel
var origin := Vector2.ZERO
var zoom := 1.0
var view_ready := false
var mode := ""          # create, move, resize, pan, box, erase
var pre: Array = []      # état avant le geste (pour l'annulation)
var drag_start := Vector2.ZERO
var last_world := Vector2.ZERO
var active: Dictionary = {}
var handle := -1
var grab_off := Vector2.ZERO
var start_rect := Rect2()
var start_el: Dictionary = {}
var box_rect := Rect2()
var space_down := false
var editor: TextEdit
var editing: Dictionary = {}
var edit_pre: Array = []


func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	editor = TextEdit.new()
	editor.visible = false
	for st in ["normal", "focus", "read_only"]:
		var sb := StyleBoxEmpty.new()
		editor.add_theme_stylebox_override(st, sb)
	editor.add_theme_font_override("font", WBDraw.font())
	editor.add_theme_color_override("caret_color", WBDraw.ACCENT)
	editor.add_theme_color_override("selection_color", Color(0.41, 0.4, 0.86, 0.3))
	editor.add_theme_color_override("background_color", Color(0, 0, 0, 0))
	editor.add_theme_constant_override("line_spacing", 0)
	editor.scroll_fit_content_height = true
	add_child(editor)
	editor.text_changed.connect(_on_edit_changed)
	editor.focus_exited.connect(end_edit)
	editor.gui_input.connect(_on_edit_input)
	resized.connect(_on_resized)


func to_world(p: Vector2) -> Vector2:
	return (p - origin) / zoom


func to_screen(p: Vector2) -> Vector2:
	return p * zoom + origin


func _on_resized() -> void:
	if not view_ready and size.x > 10 and size.y > 10:
		view_ready = true
		var v: Dictionary = board.view
		if v.has("zoom"):
			zoom = clampf(float(v.zoom), 0.1, 8.0)
			origin = size / 2.0 - Vector2(float(v.get("cx", 500)), float(v.get("cy", 300))) * zoom
		else:
			fit()
	board.layout_floats()
	if not editing.is_empty():
		_layout_editor()


func get_view() -> Dictionary:
	if not view_ready:
		return board.view
	var c := to_world(size / 2.0)
	return {"cx": snappedf(c.x, 0.1), "cy": snappedf(c.y, 0.1), "zoom": snappedf(zoom, 0.001)}


func fit() -> void:
	var r := WBModel.render_region(board.elements, maxf(0.2, size.x / maxf(size.y, 1.0)))
	zoom = clampf(minf(size.x / r.size.x, size.y / r.size.y) * 0.86, 0.1, 8.0)
	origin = size / 2.0 - r.get_center() * zoom
	_view_changed()


func zoom_at(p: Vector2, f: float) -> void:
	var wp := to_world(p)
	zoom = clampf(zoom * f, 0.1, 8.0)
	origin = p - wp * zoom
	_view_changed()


func set_zoom(z: float) -> void:
	var wp := to_world(size / 2.0)
	zoom = clampf(z, 0.1, 8.0)
	origin = size / 2.0 - wp * zoom
	_view_changed()


func _view_changed() -> void:
	if not editing.is_empty():
		_layout_editor()
	board.update_zoom_label()
	queue_redraw()


# ------------------------------------------------------------------ dessin

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WBDraw.BG)
	_draw_grid()
	var fr := WBModel.render_region(board.elements, WBModel.BOARD_RATIO)
	var sr := Rect2(to_screen(fr.position), fr.size * zoom)
	var fc := Color("#c8c7d8")
	for seg in [[sr.position, Vector2(sr.end.x, sr.position.y)], [Vector2(sr.end.x, sr.position.y), sr.end],
			[sr.end, Vector2(sr.position.x, sr.end.y)], [Vector2(sr.position.x, sr.end.y), sr.position]]:
		draw_dashed_line(seg[0], seg[1], fc, 1.5, 7.0)
	draw_string(WBDraw.font(), sr.position + Vector2(2, -6), "Zone visible sur le tableau 3D", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fc)
	WBDraw.draw_all(self, board.elements, origin, zoom, str(editing.get("id", "")))
	if editing.is_empty():
		for id in board.selection:
			var e := board.find(id)
			if not e.is_empty():
				draw_rect(_screen_rect(e), WBDraw.ACCENT, false, 1.2)
		for h in _handles():
			var p: Vector2 = h[1]
			if h[0] >= 10:
				draw_circle(p, 5.0, Color.WHITE, true, -1.0, true)
				draw_circle(p, 5.0, WBDraw.ACCENT, false, 1.5, true)
			else:
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), Color.WHITE)
				draw_rect(Rect2(p - Vector2(4, 4), Vector2(8, 8)), WBDraw.ACCENT, false, 1.5)
	if mode == "box":
		var br := Rect2(to_screen(box_rect.position), box_rect.size * zoom).abs()
		draw_rect(br, Color(WBDraw.ACCENT, 0.08))
		draw_rect(br, WBDraw.ACCENT, false, 1.0)


func _draw_grid() -> void:
	var g := 20.0
	while g * zoom < 14.0:
		g *= 5.0
	var step := g * zoom
	var col := Color("#dcdcd4")
	var s := clampf(zoom * 1.6, 1.2, 2.2)
	var y := fposmod(origin.y, step)
	while y < size.y:
		var x := fposmod(origin.x, step)
		while x < size.x:
			draw_rect(Rect2(x - s / 2.0, y - s / 2.0, s, s), col)
			x += step
		y += step


func _screen_rect(e: Dictionary) -> Rect2:
	var b := WBModel.bbox(e)
	return Rect2(to_screen(b.position), b.size * zoom).grow(5)


func _handles() -> Array:
	if board.selection.size() != 1 or not editing.is_empty() or mode == "move":
		return []
	var e := board.find(board.selection[0])
	if e.is_empty():
		return []
	if e.type in ["line", "arrow"]:
		var p := WBModel.pts(e)
		if p.size() < 2:
			return []
		return [[10, to_screen(p[0])], [11, to_screen(p[p.size() - 1])]]
	var r := _screen_rect(e)
	return [[0, r.position], [1, Vector2(r.end.x, r.position.y)], [2, r.end], [3, Vector2(r.position.x, r.end.y)]]


static func _corner(r: Rect2, i: int) -> Vector2:
	match i:
		0: return r.position
		1: return Vector2(r.end.x, r.position.y)
		2: return r.end
	return Vector2(r.position.x, r.end.y)


func _handle_at(p: Vector2) -> int:
	for h in _handles():
		if (h[1] as Vector2).distance_to(p) < 9.0:
			return h[0]
	return -1


func _hit(wp: Vector2) -> Dictionary:
	var els: Array = board.elements
	for i in range(els.size() - 1, -1, -1):
		if WBModel.hit(els[i], wp, 6.0 / zoom):
			return els[i]
	return {}


# ------------------------------------------------------------------ entrées

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		_mouse_button(ev)
	elif ev is InputEventMouseMotion:
		_mouse_motion(ev)
	elif ev is InputEventPanGesture:
		origin -= ev.delta * 24.0
		_view_changed()
	elif ev is InputEventMagnifyGesture:
		zoom_at(ev.position, ev.factor)
	elif ev is InputEventKey:
		_key(ev)


func _mouse_button(ev: InputEventMouseButton) -> void:
	var b := ev.button_index
	if b in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		if ev.pressed:
			var up := b == MOUSE_BUTTON_WHEEL_UP
			if b in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT] or ev.shift_pressed:
				origin.x += (40.0 if up or b == MOUSE_BUTTON_WHEEL_LEFT else -40.0)
				_view_changed()
			else:
				zoom_at(ev.position, 1.1 if up else 1.0 / 1.1)
		accept_event()
		return
	if b == MOUSE_BUTTON_MIDDLE or (b == MOUSE_BUTTON_LEFT and (space_down or board.tool == "hand") and (ev.pressed or mode == "pan")):
		mode = "pan" if ev.pressed else ""
		mouse_default_cursor_shape = Control.CURSOR_DRAG if ev.pressed or board.tool == "hand" else _tool_cursor()
		accept_event()
		return
	if b != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	var wp := to_world(ev.position)
	if ev.pressed:
		if not editing.is_empty():
			end_edit()
		grab_focus()
		if ev.double_click:
			_double_click(wp)
		else:
			_press(wp, ev)
	else:
		_release()
	queue_redraw()


func _press(wp: Vector2, ev: InputEventMouseButton) -> void:
	pre = board.snapshot()
	drag_start = wp
	last_world = wp
	var tool: String = board.tool
	match tool:
		"select":
			var h := _handle_at(ev.position)
			if h >= 0:
				var e := board.find(board.selection[0])
				mode = "resize"
				handle = h
				start_el = e.duplicate(true)
				start_rect = WBModel.raw_bbox(e)
				var p := WBModel.pts(e)
				var anchor: Vector2 = (p[0] if h == 10 else p[p.size() - 1]) if h >= 10 else _corner(start_rect, h)
				grab_off = anchor - wp
				return
			var hit := _hit(wp)
			if hit.is_empty():
				if not ev.shift_pressed:
					board.set_selection([])
				mode = "box"
				box_rect = Rect2(wp, Vector2.ZERO)
			else:
				if ev.shift_pressed:
					var sel: Array = board.selection.duplicate()
					if sel.has(hit.id):
						sel.erase(hit.id)
					else:
						sel.append(hit.id)
					board.set_selection(sel)
				elif not board.selection.has(hit.id):
					board.set_selection([hit.id])
				mode = "move"
		"eraser":
			mode = "erase"
			_erase_at(wp)
		"text":
			var hit := _hit(wp)
			if not hit.is_empty() and hit.type in ["text", "note"]:
				begin_edit(hit, pre)
			else:
				var e := board.new_element("text")
				e.x = wp.x
				e.y = wp.y - WBDraw.font().get_height(int(e.fs)) / 2.0
				board.elements.append(e)
				begin_edit(e, pre)
		"hand":
			pass
		_:
			var e := board.new_element(tool)
			e.x = wp.x
			e.y = wp.y
			if tool == "freedraw":
				e.points = [wp.x, wp.y]
			elif tool in WBModel.POINTLIKE:
				e.points = [wp.x, wp.y, wp.x, wp.y]
			board.elements.append(e)
			active = e
			mode = "create"


func _double_click(wp: Vector2) -> void:
	var hit := _hit(wp)
	pre = board.snapshot()
	if not hit.is_empty() and hit.type in ["text", "note"]:
		begin_edit(hit, pre)
	elif board.tool == "select":
		var e := board.new_element("text")
		e.x = wp.x
		e.y = wp.y - WBDraw.font().get_height(int(e.fs)) / 2.0
		board.elements.append(e)
		begin_edit(e, pre)


func _mouse_motion(ev: InputEventMouseMotion) -> void:
	var wp := to_world(ev.position)
	match mode:
		"pan":
			origin += ev.relative
			_view_changed()
			return
		"create":
			_update_create(wp, ev.shift_pressed)
		"move":
			var d := wp - last_world
			for id in board.selection:
				var e := board.find(id)
				if not e.is_empty():
					WBModel.translate(e, d)
			last_world = wp
		"resize":
			_update_resize(wp, ev.shift_pressed)
		"box":
			box_rect = Rect2(drag_start, wp - drag_start)
		"erase":
			_erase_at(wp)
		_:
			if board.tool == "select":
				var cs := Control.CURSOR_ARROW
				var h := _handle_at(ev.position)
				if h >= 10:
					cs = Control.CURSOR_CROSS
				elif h >= 0:
					cs = Control.CURSOR_FDIAGSIZE if h % 2 == 0 else Control.CURSOR_BDIAGSIZE
				elif not _hit(wp).is_empty():
					cs = Control.CURSOR_MOVE
				mouse_default_cursor_shape = cs
			return
	queue_redraw()


func _update_create(wp: Vector2, shift: bool) -> void:
	var e := active
	var t: String = e.type
	if t == "freedraw":
		var p: Array = e.points
		if Vector2(p[p.size() - 2], p[p.size() - 1]).distance_to(wp) > 2.0 / zoom:
			p.append(wp.x)
			p.append(wp.y)
	elif t in ["line", "arrow"]:
		var q := wp
		if shift:
			var d := wp - drag_start
			q = drag_start + Vector2.RIGHT.rotated(snappedf(d.angle(), PI / 12.0)) * d.length()
		e.points = [drag_start.x, drag_start.y, q.x, q.y]
	else:
		var d := wp - drag_start
		if shift:
			var m := maxf(absf(d.x), absf(d.y))
			d = Vector2(m if d.x >= 0 else -m, m if d.y >= 0 else -m)
		var r := Rect2(drag_start, d).abs()
		e.x = r.position.x
		e.y = r.position.y
		e.w = r.size.x
		e.h = r.size.y


func _update_resize(wp: Vector2, shift: bool) -> void:
	var e := board.find(board.selection[0])
	if e.is_empty():
		return
	WBModel.assign(e, start_el)
	var q := wp + grab_off
	if handle >= 10:
		var p: Array = e.points
		if handle == 10:
			p[0] = q.x
			p[1] = q.y
		else:
			p[p.size() - 2] = q.x
			p[p.size() - 1] = q.y
		return
	var fixed := _corner(start_rect, (handle + 2) % 4)
	var d := q - fixed
	if shift or e.type == "text":
		var k := maxf(absf(d.x) / maxf(start_rect.size.x, 1.0), absf(d.y) / maxf(start_rect.size.y, 1.0))
		d = Vector2(1.0 if d.x >= 0 else -1.0, 1.0 if d.y >= 0 else -1.0) * start_rect.size * k
	var nr := Rect2(fixed, d).abs()
	nr.size = nr.size.max(Vector2(4, 4))
	WBModel.resize(e, start_rect, nr)


func _release() -> void:
	match mode:
		"create":
			var e := active
			var r := WBModel.raw_bbox(e)
			if e.type == "note":
				if r.size.x < 30 or r.size.y < 30:
					e.w = 220.0
					e.h = 160.0
				mode = ""
				active = {}
				begin_edit(e, pre)
				return
			if e.type != "freedraw" and r.size.length() < 4.0:
				board.elements.erase(e)
			else:
				board.record(pre)
				board.save()
				if e.type != "freedraw":
					board.set_tool("select")
					board.set_selection([e.id])
		"move", "resize", "erase":
			if board.elements != pre:
				board.record(pre)
				board.save()
		"box":
			var r := box_rect.abs()
			var sel: Array = board.selection.duplicate()
			if r.size.length() > 2.0:
				for e in board.elements:
					if r.encloses(WBModel.bbox(e)) and not sel.has(e.id):
						sel.append(e.id)
			board.set_selection(sel)
	mode = ""
	active = {}
	queue_redraw()


func _erase_at(wp: Vector2) -> void:
	var els: Array = board.elements
	for i in range(els.size() - 1, -1, -1):
		if WBModel.hit(els[i], wp, 8.0 / zoom):
			board.selection.erase(els[i].id)
			els.remove_at(i)


func _key(ev: InputEventKey) -> void:
	if ev.keycode == KEY_SPACE:
		space_down = ev.pressed
		mouse_default_cursor_shape = Control.CURSOR_DRAG if ev.pressed else _tool_cursor()
		accept_event()
		return
	if not ev.pressed:
		return
	var ctrl := ev.ctrl_pressed or ev.meta_pressed
	accept_event()
	if ctrl:
		match ev.keycode:
			KEY_Z:
				if ev.shift_pressed:
					board.redo()
				else:
					board.undo()
			KEY_Y: board.redo()
			KEY_A: board.set_selection(board.elements.map(func(e): return e.id))
			KEY_D: board.duplicate_selection()
			KEY_0: set_zoom(1.0)
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD: zoom_at(size / 2.0, 1.2)
			KEY_MINUS, KEY_KP_SUBTRACT: zoom_at(size / 2.0, 1.0 / 1.2)
		return
	if ev.echo and not (ev.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]):
		return
	if ev.shift_pressed and ev.keycode == KEY_1:
		fit()
		return
	match ev.keycode:
		KEY_DELETE, KEY_BACKSPACE:
			board.delete_selection()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if board.selection.is_empty():
				return
			var d: Vector2 = {KEY_LEFT: Vector2.LEFT, KEY_RIGHT: Vector2.RIGHT, KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN}[ev.keycode]
			var p := board.snapshot()
			for id in board.selection:
				WBModel.translate(board.find(id), d * (10.0 if ev.shift_pressed else 1.0))
			board.record(p)
			board.save()
		_:
			if TOOL_KEYS.has(ev.keycode):
				board.set_tool(TOOL_KEYS[ev.keycode])


func _tool_cursor() -> Control.CursorShape:
	match board.tool:
		"select": return Control.CURSOR_ARROW
		"hand": return Control.CURSOR_DRAG
		"text": return Control.CURSOR_IBEAM
	return Control.CURSOR_CROSS


func update_cursor() -> void:
	mouse_default_cursor_shape = _tool_cursor()


# ------------------------------------------------------------------ édition de texte

func begin_edit(e: Dictionary, before: Array) -> void:
	editing = e
	edit_pre = before
	board.selection = [e.id]
	editor.text = str(e.text)
	editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY if e.type == "note" else TextEdit.LINE_WRAPPING_NONE
	editor.visible = true
	_layout_editor()
	editor.grab_focus()
	editor.select_all()
	queue_redraw()


func _layout_editor() -> void:
	var e := editing
	editor.add_theme_font_size_override("font_size", maxi(6, roundi(float(e.fs) * zoom)))
	editor.add_theme_color_override("font_color", Color(str(e.stroke)))
	if e.type == "note":
		var pad := WBModel.NOTE_PAD * zoom
		editor.position = to_screen(Vector2(float(e.x), float(e.y))) + Vector2(pad, pad)
		editor.size = Vector2(float(e.w), float(e.h)) * zoom - Vector2(pad, pad) * 2.0
	else:
		editor.position = to_screen(Vector2(float(e.x), float(e.y)))
		editor.size = WBDraw.text_size(str(e.text) + "MM", int(e.fs)) * zoom + Vector2(4, 4)


func _on_edit_changed() -> void:
	if editing.is_empty():
		return
	editing.text = editor.text
	_layout_editor()
	queue_redraw()


func _on_edit_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode in [KEY_ENTER, KEY_KP_ENTER] and (ev.ctrl_pressed or ev.meta_pressed):
		grab_focus()
		editor.accept_event()


func end_edit() -> void:
	if editing.is_empty():
		return
	var e := editing
	editing = {}
	e.text = editor.text
	editor.visible = false
	if e.type == "text":
		if str(e.text).strip_edges() == "":
			board.elements.erase(e)
			board.selection.erase(e.id)
		else:
			var s := WBDraw.text_size(str(e.text), int(e.fs))
			e.w = s.x
			e.h = s.y
	if board.elements != edit_pre:
		board.record(edit_pre)
		board.save()
	if board.tool in ["text", "note"]:
		board.set_tool("select")
	if board.elements.has(e):
		board.set_selection([e.id])
	queue_redraw()

class_name WhiteboardPanel
extends KWPanel
## Tableau blanc : dessin à main levée, textes, gomme, annulation.

var id: String
var content: Dictionary
var pen_color := "#222222"
var pen_width := 6
var name_edit: LineEdit
var text_input: LineEdit
var text_mode: CheckButton
var canvas: Canvas


class Canvas extends Control:
	var board: WhiteboardPanel
	var current := {}

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.97, 0.97, 0.95))
		var k := size / Vector2(1000, 600)
		var all: Array = board.content.strokes.duplicate()
		if not current.is_empty():
			all.append(current)
		for st in all:
			var pts := PackedVector2Array()
			var p: Array = st.p
			for i in range(0, p.size() - 1, 2):
				pts.append(Vector2(p[i], p[i + 1]) * k)
			if pts.size() >= 2:
				draw_polyline(pts, Color(st.c), st.w * k.x, true)
			elif pts.size() == 1:
				draw_circle(pts[0], st.w * k.x / 2.0, Color(st.c))
		for t in board.content.texts:
			draw_string(get_theme_default_font(), Vector2(t.x, t.y + 30) * k, t.t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(36 * k.x), Color(t.get("c", "#222222")))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			var pos: Vector2 = e.position / size * Vector2(1000, 600)
			if e.pressed:
				if board.text_mode.button_pressed and board.text_input.text.strip_edges() != "":
					board.content.texts.append({"x": roundi(pos.x), "y": roundi(pos.y), "t": board.text_input.text, "c": board.pen_color})
					board.text_input.clear()
					board.save()
				else:
					current = {"c": board.pen_color, "w": board.pen_width, "p": [roundi(pos.x), roundi(pos.y)]}
			elif not current.is_empty():
				board.content.strokes.append(current)
				current = {}
				board.save()
			queue_redraw()
		elif e is InputEventMouseMotion and not current.is_empty():
			var pos: Vector2 = e.position / size * Vector2(1000, 600)
			var p: Array = current.p
			if Vector2(p[-2], p[-1]).distance_to(pos) > 3.0:
				p.append(roundi(pos.x))
				p.append(roundi(pos.y))
				queue_redraw()


func _init(obj_id: String) -> void:
	id = obj_id
	var o: Dictionary = World.data.objects[id]
	super("Tableau blanc", Vector2(1080, 800))
	content = o.content.duplicate(true)
	if not content.has("strokes"):
		content.strokes = []
	if not content.has("texts"):
		content.texts = []
	name_edit = line(body, o.name, "Nom du tableau")
	var tools := hbox(body)
	for c in [["Noir", "#222222"], ["Bleu", "#2f6db5"], ["Rouge", "#c0392b"], ["Vert", "#2e8b57"], ["Orange", "#e67e22"]]:
		var b := btn(tools, c[0], func(): pen_color = c[1]; pen_width = maxi(3, pen_width if pen_width < 20 else 6))
		b.add_theme_color_override("font_color", Color(c[1]).lightened(0.3))
	btn(tools, "Fin", func(): pen_width = 3)
	btn(tools, "Moyen", func(): pen_width = 6)
	btn(tools, "Épais", func(): pen_width = 12)
	btn(tools, "Gomme", func(): pen_color = "#f7f7f2"; pen_width = 30)
	btn(tools, "Annuler", func():
		if not content.strokes.is_empty(): content.strokes.pop_back()
		save())
	btn(tools, "Retirer texte", func():
		if not content.texts.is_empty(): content.texts.pop_back()
		save())
	btn(tools, "Tout effacer", func(): content.strokes.clear(); content.texts.clear(); save())
	var trow := hbox(body)
	text_input = line(trow, "", "Texte à placer…")
	text_mode = CheckButton.new()
	text_mode.text = "Mode texte (clic pour placer)"
	trow.add_child(text_mode)
	canvas = Canvas.new()
	canvas.board = self
	canvas.custom_minimum_size = Vector2(1000, 600)
	canvas.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	canvas.mouse_default_cursor_shape = Control.CURSOR_CROSS
	body.add_child(canvas)


func save() -> void:
	canvas.queue_redraw()
	World.update_object(id, {"name": name_edit.text, "content": content.duplicate(true)})


func on_close() -> void:
	if World.data.objects.has(id):
		save()

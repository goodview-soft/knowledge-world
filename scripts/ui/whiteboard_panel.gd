class_name WhiteboardPanel
extends KWPanel
## Tableau blanc façon Excalidraw : canevas infini, formes, texte, post-it, sélection,
## annuler/rétablir, zoom/panoramique, export PNG. Données : scripts/whiteboard/wb_model.gd.

const STROKES := ["#1e1e1e", "#e03131", "#2f9e44", "#1971c2", "#f08c00", "#9c36b5"]
const FILLS := ["", "#ffc9c9", "#b2f2bb", "#a5d8ff", "#ffec99", "#eebefa"]
const TOOLS := [["select", "Sélection — V"], ["hand", "Main (déplacer la vue) — H"], ["freedraw", "Crayon — P"],
	["line", "Ligne — L"], ["arrow", "Flèche — A"], ["rect", "Rectangle — R"], ["ellipse", "Ellipse — O"],
	["diamond", "Losange — D"], ["text", "Texte — T"], ["note", "Post-it — N"], ["eraser", "Gomme — E"]]
const MAX_UNDO := 100

var id: String
var elements: Array = []
var view: Dictionary = {}
var selection: Array = []
var tool := "select"
var style := {"stroke": "#1e1e1e", "fill": "", "width": 4.0, "rough": true, "fs": 28}
var undo_stack: Array = []
var redo_stack: Array = []
var name_edit: LineEdit
var canvas: WBCanvas
var toolbar: PanelContainer
var props: PanelContainer
var bottom: PanelContainer
var hint: Label
var zoom_label: Button
var undo_btn: WBIconButton
var redo_btn: WBIconButton
var tool_buttons := {}
var prop_buttons := {}   # clé de style -> [[bouton, valeur], ...]


func _init(obj_id: String) -> void:
	id = obj_id
	var o: Dictionary = World.data.objects[id]
	super("Tableau blanc", Vector2(960, 640))
	var c := WBModel.migrate(o.get("content", {}))
	elements = c.elements
	view = c.view
	var top := hbox(body)
	name_edit = line(top, str(o.name), "Nom du tableau")
	name_edit.text_submitted.connect(func(_t): save())
	btn(top, "Exporter PNG", export_png)
	btn(top, "Tout effacer", clear_all)
	canvas = WBCanvas.new()
	canvas.board = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(canvas)
	_build_toolbar()
	_build_props()
	_build_bottom()
	set_tool("select")
	_sync_props()


func _ready() -> void:
	super()
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 18
	offset_top = 18
	offset_right = -18
	offset_bottom = -18
	canvas.grab_focus.call_deferred()


# ------------------------------------------------------------------ interface

func _float_panel() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(10)
	sb.border_color = Color("#e7e6ee")
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0, 0, 0, 0.14)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	sb.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(p)
	return p


func _icon(parent: Control, kind: String, tip: String, cb: Callable, toggle := true, sz := 34) -> WBIconButton:
	var b := WBIconButton.new(kind, tip, toggle, sz)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _caption(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color("#7a7986"))
	parent.add_child(l)


func _build_toolbar() -> void:
	toolbar = _float_panel()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	toolbar.add_child(h)
	for t in TOOLS:
		var k: String = t[0]
		tool_buttons[k] = _icon(h, k, t[1], func(): set_tool(k))
		if k in ["hand", "freedraw", "diamond", "note"]:
			var sep := VSeparator.new()
			sep.add_theme_constant_override("separation", 6)
			h.add_child(sep)


func _build_props() -> void:
	props = _float_panel()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	props.add_child(v)
	_caption(v, "Trait")
	var r := HBoxContainer.new()
	v.add_child(r)
	for col in STROKES:
		_prop(r, "stroke", col, "swatch", col, col)
	_caption(v, "Fond")
	r = HBoxContainer.new()
	v.add_child(r)
	for col in FILLS:
		_prop(r, "fill", col, "swatch", col, "Transparent" if col == "" else col)
	_caption(v, "Épaisseur · style")
	r = HBoxContainer.new()
	v.add_child(r)
	_prop(r, "width", 2.0, "w2", "", "Fin")
	_prop(r, "width", 4.0, "w4", "", "Moyen")
	_prop(r, "width", 8.0, "w8", "", "Épais")
	r.add_child(VSeparator.new())
	_prop(r, "rough", false, "smooth", "", "Trait net")
	_prop(r, "rough", true, "rough", "", "Trait dessiné à la main")
	_caption(v, "Taille du texte")
	r = HBoxContainer.new()
	v.add_child(r)
	_prop(r, "fs", 20, "fsS", "", "Petit")
	_prop(r, "fs", 28, "fsM", "", "Moyen")
	_prop(r, "fs", 44, "fsL", "", "Grand")
	r.add_child(VSeparator.new())
	_icon(r, "duplicate", "Dupliquer — Ctrl+D", duplicate_selection, false, 30)
	_icon(r, "delete", "Supprimer — Suppr", delete_selection, false, 30)


func _prop(parent: Control, key: String, value: Variant, kind: String, swatch: String, tip: String) -> void:
	var b := _icon(parent, kind, tip, func(): set_style(key, value), true, 30)
	b.swatch = swatch
	if not prop_buttons.has(key):
		prop_buttons[key] = []
	prop_buttons[key].append([b, value])


func _build_bottom() -> void:
	bottom = _float_panel()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	bottom.add_child(h)
	undo_btn = _icon(h, "undo", "Annuler — Ctrl+Z", undo, false, 32)
	redo_btn = _icon(h, "redo", "Rétablir — Ctrl+Y", redo, false, 32)
	h.add_child(VSeparator.new())
	_icon(h, "minus", "Zoom arrière", func(): canvas.zoom_at(canvas.size / 2.0, 1.0 / 1.2), false, 32)
	zoom_label = Button.new()
	zoom_label.flat = true
	zoom_label.focus_mode = Control.FOCUS_NONE
	zoom_label.custom_minimum_size = Vector2(58, 32)
	zoom_label.tooltip_text = "Revenir à 100 % — Ctrl+0"
	zoom_label.add_theme_color_override("font_color", Color("#1e1e1e"))
	zoom_label.add_theme_color_override("font_hover_color", WBDraw.ACCENT)
	zoom_label.add_theme_font_size_override("font_size", 13)
	for st in ["normal", "hover", "pressed", "focus"]:
		zoom_label.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	zoom_label.pressed.connect(func(): canvas.set_zoom(1.0))
	h.add_child(zoom_label)
	_icon(h, "plus", "Zoom avant", func(): canvas.zoom_at(canvas.size / 2.0, 1.2), false, 32)
	_icon(h, "fit", "Tout afficher — Maj+1", func(): canvas.fit(), false, 32)
	hint = Label.new()
	hint.text = "Molette : zoom · Espace / clic milieu : déplacer · Double-clic : texte · Maj : contraindre"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color("#9b9aa6"))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(hint)
	_update_history_buttons()


func layout_floats() -> void:
	if toolbar == null:
		return
	var s := canvas.size
	for p in [toolbar, props, bottom, hint]:
		p.reset_size()
	toolbar.position = Vector2(roundf((s.x - toolbar.size.x) / 2.0), 12)
	props.position = Vector2(12, 12)
	if s.x < toolbar.size.x + props.size.x * 2 + 40:
		props.position.y = toolbar.size.y + 24
	bottom.position = Vector2(12, s.y - bottom.size.y - 12)
	hint.position = Vector2(s.x - hint.size.x - 14, s.y - hint.size.y - 16)
	hint.visible = s.x > bottom.size.x + hint.size.x + 60
	update_zoom_label()


func update_zoom_label() -> void:
	if zoom_label != null:
		zoom_label.text = "%d %%" % roundi(canvas.zoom * 100.0)


func _update_history_buttons() -> void:
	if undo_btn != null:
		undo_btn.disabled = undo_stack.is_empty()
		redo_btn.disabled = redo_stack.is_empty()
		undo_btn.queue_redraw()
		redo_btn.queue_redraw()


func _sync_props() -> void:
	for key in prop_buttons:
		for pair in prop_buttons[key]:
			var b: WBIconButton = pair[0]
			b.set_pressed_no_signal(pair[1] == style[key])
			b.queue_redraw()


# ------------------------------------------------------------------ état

func set_tool(t: String) -> void:
	tool = t
	for k in tool_buttons:
		var b: WBIconButton = tool_buttons[k]
		b.set_pressed_no_signal(k == t)
		b.queue_redraw()
	if t != "select":
		set_selection([])
	canvas.update_cursor()
	canvas.queue_redraw()


func set_selection(ids: Array) -> void:
	selection = ids
	if ids.size() == 1:
		var e := find(ids[0])
		if not e.is_empty():
			style.stroke = str(e.stroke)
			if e.type in WBModel.SHAPES or e.type == "note":
				style.fill = str(e.fill)
			if e.type in WBModel.SHAPES or e.type in WBModel.POINTLIKE:
				style.width = float(e.width)
				style.rough = bool(e.rough)
			if e.type in ["text", "note"]:
				style.fs = int(e.fs)
			_sync_props()
	canvas.queue_redraw()


func set_style(key: String, value: Variant) -> void:
	style[key] = value
	_sync_props()
	if selection.is_empty():
		return
	var p := snapshot()
	for sid in selection:
		var e := find(sid)
		if e.is_empty():
			continue
		var t: String = e.type
		var ok := key == "stroke" \
			or (key == "fill" and (t in WBModel.SHAPES or t == "note")) \
			or (key in ["width", "rough"] and (t in WBModel.SHAPES or t in WBModel.POINTLIKE)) \
			or (key == "fs" and t in ["text", "note"])
		if ok:
			e[key] = value
	if not canvas.editing.is_empty():
		canvas._layout_editor()
	if elements != p:
		record(p)
		save()


func new_element(type: String) -> Dictionary:
	var fill: String = style.fill if type in WBModel.SHAPES or type == "note" else ""
	var e := WBModel.make(type, style.stroke, fill, style.width, style.rough, style.fs)
	if type == "note":
		e.stroke = "#1e1e1e" if style.stroke == "#1e1e1e" else style.stroke
		e.fs = mini(int(style.fs), 28)
	return e


func find(eid: String) -> Dictionary:
	return WBModel.find(elements, eid)


func snapshot() -> Array:
	return elements.duplicate(true)


func record(before: Array) -> void:
	undo_stack.append(before)
	if undo_stack.size() > MAX_UNDO:
		undo_stack.pop_front()
	redo_stack.clear()
	_update_history_buttons()


func undo() -> void:
	canvas.end_edit()
	if undo_stack.is_empty():
		return
	redo_stack.append(snapshot())
	elements = undo_stack.pop_back()
	_after_history()


func redo() -> void:
	canvas.end_edit()
	if redo_stack.is_empty():
		return
	undo_stack.append(snapshot())
	elements = redo_stack.pop_back()
	_after_history()


func _after_history() -> void:
	selection = selection.filter(func(s): return not find(s).is_empty())
	_update_history_buttons()
	save()


func delete_selection() -> void:
	if selection.is_empty():
		return
	var p := snapshot()
	elements = elements.filter(func(e): return not selection.has(e.id))
	selection = []
	record(p)
	save()


func duplicate_selection() -> void:
	if selection.is_empty():
		return
	var p := snapshot()
	var ids := []
	for sid in selection:
		var e := find(sid)
		if e.is_empty():
			continue
		var d: Dictionary = e.duplicate(true)
		d.id = WBModel.new_id()
		WBModel.translate(d, Vector2(16, 16))
		elements.append(d)
		ids.append(d.id)
	record(p)
	set_selection(ids)
	save()


func clear_all() -> void:
	if elements.is_empty():
		return
	canvas.end_edit()
	var p := snapshot()
	elements = []
	selection = []
	record(p)
	save()


func save() -> void:
	canvas.queue_redraw()
	if not World.data.objects.has(id):
		return
	World.update_object(id, {"name": name_edit.text, "content": WBModel.to_content(elements, canvas.get_view())})


func on_close() -> void:
	canvas.end_edit()
	if World.data.objects.has(id):
		save()


# ------------------------------------------------------------------ export

func export_png() -> void:
	if elements.is_empty():
		_toast("Tableau vide : rien à exporter.")
		return
	if DisplayServer.get_name() == "headless":
		_toast("Export indisponible sans affichage.")
		return
	var r := WBModel.content_bounds(elements).grow(40)
	var sc := minf(2.0, 4096.0 / maxf(r.size.x, r.size.y))
	var px := Vector2i(maxi(1, int(r.size.x * sc)), maxi(1, int(r.size.y * sc)))
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		dir = OS.get_user_data_dir()
	var fname := name_edit.text.strip_edges().validate_filename().replace(" ", "_")
	var path := dir.path_join("%s_%s.png" % [fname if fname != "" else "tableau", Time.get_datetime_string_from_system().replace(":", "-")])
	var snap := WBSnapshot.make(elements.duplicate(true), r, px, func(img: Image):
		var err := img.save_png(path)
		_toast(("Exporté : " + path) if err == OK else "Échec de l'export PNG."))
	add_child(snap)


func _toast(t: String) -> void:
	var h = main.get("hud") if main != null else null
	if h != null and h.has_method("toast"):
		h.toast(t)
	else:
		print(t)

class_name OSPanel
extends KWPanel
## KW OS : bureau virtuel plein écran ouvert depuis un objet « desk ».
## Fenêtres multiples (déplacer, redimensionner, réduire, agrandir, focus), dock,
## lanceur (Ctrl+Espace / Ctrl+K), horloge. Disposition mémorisée dans obj.content.os
## (content.messages, utilisé par le chat, n'est jamais touché).

const APPS := [
	{"id": "explorer", "name": "Explorateur", "glyph": "▦", "color": Color("#8ea8ff"), "desc": "Portails, salles, objets et documents", "size": Vector2(920, 580)},
	{"id": "notes", "name": "Notes", "glyph": "✎", "color": Color("#8fd6a8"), "desc": "Éditeur Markdown, liens [[wiki]]", "size": Vector2(1040, 660)},
	{"id": "terminal", "name": "Terminal", "glyph": ">_", "color": Color("#c9d1d9"), "desc": "Shell du monde : ls, cd, cat, find…", "size": Vector2(800, 500)},
	{"id": "assistant", "name": "Assistant", "glyph": "✦", "color": Color("#d7a6ff"), "desc": "Chat IA contextuel (Ollama local)", "size": Vector2(900, 660)},
	{"id": "tasks", "name": "Tâches", "glyph": "✓", "color": Color("#f0c674"), "desc": "Cases à cocher et cartes Kanban", "size": Vector2(780, 580)},
	{"id": "dashboard", "name": "Tableau de bord", "glyph": "▥", "color": Color("#7fd1d8"), "desc": "Statistiques, activité, orphelines", "size": Vector2(1000, 640)},
	{"id": "journal", "name": "Journal", "glyph": "◷", "color": Color("#f2918a"), "desc": "Calendrier et notes du jour", "size": Vector2(920, 600)},
	{"id": "documents", "name": "Documents", "glyph": "❏", "color": Color("#e8c9a0"), "desc": "Bibliothèque : lecture des documents", "size": Vector2(980, 640)},
]
const TOP_H := 44.0
const DOCK_H := 92.0

var id: String
var root: Control
var layer: Control
var windows := {} # key -> OSWindow
var active_key := ""
var dock_box: HBoxContainer
var dock_btns := {} # app id -> {btn, dot}
var clock_lbl: Label
var date_lbl: Label
var big_clock: Label
var big_date: Label
var room_lbl: Label
var launcher: Control
var launch_input: LineEdit
var launch_list: VBoxContainer
var _launch_first := Callable()
var toast_box: PanelContainer
var toast_lbl: Label
var _toast_tw: Tween
var _refresh_pending := false
var _save_in := -1.0
var _tick := 1.0


func _init(desk_id: String) -> void:
	id = desk_id
	super("KW OS", Vector2.ZERO)
	header.visible = false
	var outer := body.get_parent() as VBoxContainer
	outer.add_theme_constant_override("separation", 0)
	outer.get_child(1).visible = false
	add_theme_stylebox_override("panel", KWTheme.box(KWTheme.BG, 0, Vector4(0, 0, 0, 0)))
	body.add_theme_constant_override("separation", 0)
	root = Control.new()
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.clip_contents = true
	body.add_child(root)
	_build_background()
	layer = Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.offset_top = TOP_H + 8
	layer.offset_bottom = -DOCK_H
	layer.offset_left = 12
	layer.offset_right = -12
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.resized.connect(func():
		for w in windows.values():
			w.fit_area())
	root.add_child(layer)
	_build_topbar()
	_build_dock()
	_build_toast()
	_build_launcher()


func _ready() -> void:
	main = get_tree().current_scene
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.2)
	World.changed.connect(_on_world_changed)
	_update_clock()
	await get_tree().process_frame
	if is_inside_tree():
		_restore_layout()


func _exit_tree() -> void:
	if World.changed.is_connected(_on_world_changed):
		World.changed.disconnect(_on_world_changed)


func on_close() -> void:
	for w in windows.values():
		if is_instance_valid(w.app):
			w.app.flush()
	_save_layout()


func desk_room() -> String:
	var o = World.data.objects.get(id)
	return str(o.room_id) if o != null else ""

# ------------------------------------------------------------------ construction

func _build_background() -> void:
	var base := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color("#161c2c"))
	g.set_color(1, KWTheme.BG)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 1)
	base.texture = gt
	base.stretch_mode = TextureRect.STRETCH_SCALE
	base.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(base)
	for glow in [[Vector2(-0.15, -0.2), Vector2(0.75, 0.85), KWTheme.ACCENT, 0.16], [Vector2(0.45, 0.35), Vector2(1.25, 1.3), Color("#d7a6ff"), 0.10]]:
		var t := TextureRect.new()
		var gg := Gradient.new()
		gg.set_color(0, Color(glow[2], glow[3]))
		gg.set_color(1, Color(glow[2], 0.0))
		var rt := GradientTexture2D.new()
		rt.gradient = gg
		rt.fill = GradientTexture2D.FILL_RADIAL
		rt.fill_from = Vector2(0.5, 0.5)
		rt.fill_to = Vector2(1.0, 0.5)
		t.texture = rt
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.anchor_left = glow[0].x
		t.anchor_top = glow[0].y
		t.anchor_right = glow[1].x
		t.anchor_bottom = glow[1].y
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(t)
	# Horloge centrale (visible quand le bureau est dégagé).
	var c := VBoxContainer.new()
	c.set_anchors_preset(Control.PRESET_CENTER)
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_theme_constant_override("separation", 2)
	root.add_child(c)
	big_clock = Label.new()
	big_clock.add_theme_font_size_override("font_size", 112)
	big_clock.add_theme_color_override("font_color", Color(KWTheme.TEXT, 0.92))
	big_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(big_clock)
	big_date = Label.new()
	big_date.add_theme_font_size_override("font_size", 22)
	big_date.add_theme_color_override("font_color", KWTheme.TEXT_DIM)
	big_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(big_date)
	var hint := Label.new()
	hint.text = "Ctrl+Espace pour rechercher · Échap pour revenir au monde"
	hint.theme_type_variation = "Dim"
	hint.modulate.a = 0.7
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(hint)


func _build_topbar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = TOP_H
	bar.add_theme_stylebox_override("panel", KWTheme.box(Color(KWTheme.BG, 0.72), 0, Vector4(18, 0, 12, 0)))
	root.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	bar.add_child(h)
	var logo := Label.new()
	logo.text = "◆  KW OS"
	logo.add_theme_color_override("font_color", KWTheme.ACCENT)
	logo.add_theme_font_size_override("font_size", 15)
	h.add_child(logo)
	var search := KWPanel.styled_btn(h, "⌕  Rechercher une app, une note, une salle…", open_launcher, "Chip")
	search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	search.custom_minimum_size.x = 340
	search.alignment = HORIZONTAL_ALIGNMENT_LEFT
	room_lbl = Label.new()
	room_lbl.theme_type_variation = "Dim"
	room_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	room_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(room_lbl)
	date_lbl = Label.new()
	date_lbl.theme_type_variation = "Dim"
	h.add_child(date_lbl)
	clock_lbl = Label.new()
	clock_lbl.add_theme_font_size_override("font_size", 16)
	h.add_child(clock_lbl)
	var off := KWPanel.icon_btn(h, "⏻", func(): closed.emit(), "Quitter KW OS (Échap)")
	off.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_update_room_label()


func _build_dock() -> void:
	var wrap := CenterContainer.new()
	wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wrap.offset_top = -DOCK_H + 6
	wrap.offset_bottom = -10
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(wrap)
	var dock := PanelContainer.new()
	var sb := KWTheme.box(Color(KWTheme.SURFACE, 0.82), 20, Vector4(12, 8, 12, 6), KWTheme.BORDER_STRONG, 1)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 18
	dock.add_theme_stylebox_override("panel", sb)
	wrap.add_child(dock)
	dock_box = HBoxContainer.new()
	dock_box.add_theme_constant_override("separation", 6)
	dock.add_child(dock_box)
	_dock_button("launcher", "⌕", KWTheme.TEXT_DIM, "Lanceur (Ctrl+Espace)", open_launcher)
	var vs := VSeparator.new()
	dock_box.add_child(vs)
	for a in APPS:
		var aid: String = a.id
		_dock_button(aid, a.glyph, a.color, "%s — %s" % [a.name, a.desc], func(): _dock_click(aid))


func _dock_button(aid: String, glyph: String, tint: Color, tip: String, cb: Callable) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(56, 62)
	for st in ["normal", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", KWTheme.box(Color(1, 1, 1, 0.06), 12, Vector4(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover_pressed", KWTheme.box(Color(1, 1, 1, 0.06), 12, Vector4(0, 0, 0, 0)))
	b.pressed.connect(cb)
	dock_box.add_child(b)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 5)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var t := OSWindow.tile(glyph, tint, 42, 17)
	t.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(t)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(5, 5)
	dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dot.color = Color(0, 0, 0, 0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(dot)
	dock_btns[aid] = {"btn": b, "dot": dot}


func _build_toast() -> void:
	toast_box = PanelContainer.new()
	toast_box.theme_type_variation = "Toast"
	toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toast_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	toast_box.offset_top = TOP_H + 12
	toast_box.offset_right = -18
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.visible = false
	root.add_child(toast_box)
	toast_lbl = Label.new()
	toast_box.add_child(toast_lbl)


func _build_launcher() -> void:
	launcher = Control.new()
	launcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	launcher.visible = false
	root.add_child(launcher)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.03, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			close_launcher())
	launcher.add_child(shade)
	var p := PanelContainer.new()
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.16
	p.offset_left = -330
	p.offset_right = 330
	p.theme_type_variation = "Backdrop"
	launcher.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	launch_input = LineEdit.new()
	launch_input.placeholder_text = "Rechercher une application, une note, une salle, un document…"
	launch_input.add_theme_font_size_override("font_size", 18)
	launch_input.text_changed.connect(func(_t): _fill_launcher())
	launch_input.text_submitted.connect(func(_t):
		if _launch_first.is_valid():
			_launch_first.call())
	v.add_child(launch_input)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size.y = 380
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	launch_list = VBoxContainer.new()
	launch_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	launch_list.add_theme_constant_override("separation", 2)
	sc.add_child(launch_list)

# ------------------------------------------------------------------ boucle

func _process(delta: float) -> void:
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_update_clock()
	if _refresh_pending:
		_refresh_pending = false
		for w in windows.values():
			if is_instance_valid(w.app):
				w.app.refresh()
		_update_room_label()
	if _save_in > 0.0:
		_save_in -= delta
		if _save_in <= 0.0:
			_save_layout()


func _on_world_changed(kind: String, oid: String, _action: String) -> void:
	if kind == "object" and oid == id:
		return
	_refresh_pending = true


const DAYS := ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
const MONTHS := ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]


func _update_clock() -> void:
	var t := Time.get_time_string_from_system().left(5)
	var d := Time.get_date_dict_from_system()
	clock_lbl.text = t
	big_clock.text = t
	date_lbl.text = "%s %d %s" % [DAYS[d.weekday].left(3) + ".", d.day, MONTHS[d.month - 1].left(4).trim_suffix(".")]
	big_date.text = "%s %d %s %d" % [DAYS[d.weekday].capitalize(), d.day, MONTHS[d.month - 1], d.year]


func _update_room_label() -> void:
	var r := desk_room()
	room_lbl.text = ("Bureau · " + OSData.room_path(r)) if World.data.rooms.has(r) else "Bureau de l'assistant"


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and launcher.visible:
			close_launcher()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode in [KEY_SPACE, KEY_K]:
			if launcher.visible:
				close_launcher()
			else:
				open_launcher()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_W and windows.has(active_key):
			close_window(windows[active_key])
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not launcher.visible:
		# Focus au clic n'importe où dans une fenêtre (sans consommer l'événement).
		var kids := layer.get_children()
		for i in range(kids.size() - 1, -1, -1):
			var w: OSWindow = kids[i]
			if w.visible and w.get_global_rect().has_point(event.global_position):
				if w.key != active_key:
					focus(w)
				break

# ------------------------------------------------------------------ fenêtres

static func app_def(aid: String) -> Dictionary:
	for a in APPS:
		if a.id == aid:
			return a
	return {}


func _make_app(aid: String) -> OSApp:
	match aid:
		"explorer": return OSExplorer.new()
		"notes": return OSNotes.new()
		"terminal": return OSTerminal.new()
		"assistant": return OSAssistant.new(id)
		"tasks": return OSTasks.new()
		"dashboard": return OSDashboard.new()
		"journal": return OSJournal.new()
		"documents": return OSDocuments.new()
	return null


func open_app(aid: String, args := {}) -> OSWindow:
	if windows.has(aid):
		var ew: OSWindow = windows[aid]
		if ew.minimized:
			_set_minimized(ew, false)
		focus(ew)
		ew.app.open_args(args)
		return ew
	var def := app_def(aid)
	if def.is_empty():
		return null
	var app := _make_app(aid)
	app.os = self
	var w := OSWindow.new(aid, def.name, def.glyph, def.color, app)
	layer.add_child(w)
	w.close_requested.connect(close_window)
	w.minimize_requested.connect(func(win): _set_minimized(win, true))
	w.layout_changed.connect(func(_w): _queue_save())
	var lay: Dictionary = _os_data().get("windows", {}).get(aid, {})
	var r: Array = lay.get("rect", [])
	if r.size() == 4:
		w.set_rect(Rect2(r[0], r[1], r[2], r[3]))
	else:
		var a := layer.size if layer.size.x > 100 else Vector2(1576, 750)
		var s: Vector2 = def.size
		s = Vector2(minf(s.x, a.x), minf(s.y, a.y))
		var off := Vector2(32, 28) * float(windows.size() % 6)
		w.set_rect(Rect2(((a - s) / 2.0 + off - Vector2(80, 40)).max(Vector2.ZERO), s))
	windows[aid] = w
	if lay.get("max", false):
		w.set_maximized(true)
	w.modulate.a = 0.0
	create_tween().tween_property(w, "modulate:a", 1.0, 0.14)
	focus(w)
	app.open_args(args)
	_queue_save()
	return w


func focus(w: OSWindow) -> void:
	for o in windows.values():
		if o != w:
			o.set_active(false)
	w.set_active(true)
	layer.move_child(w, -1)
	active_key = w.key
	_refresh_dock()


func _set_minimized(w: OSWindow, on: bool) -> void:
	w.minimized = on
	w.visible = not on
	if on:
		w.set_active(false)
		active_key = ""
		_focus_top()
	_refresh_dock()
	_queue_save()


func _focus_top() -> void:
	var kids := layer.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var w: OSWindow = kids[i]
		if w.visible and not w.is_queued_for_deletion():
			focus(w)
			return
	_refresh_dock()


func close_window(w: OSWindow) -> void:
	if w == null or not windows.has(w.key):
		return
	if is_instance_valid(w.app):
		w.app.flush()
	windows.erase(w.key)
	if active_key == w.key:
		active_key = ""
	_save_layout(w)
	layer.remove_child(w)
	w.queue_free()
	_focus_top()


func close_app(aid: String) -> void:
	if windows.has(aid):
		close_window(windows[aid])


func get_app(aid: String) -> OSApp:
	return windows[aid].app if windows.has(aid) else null


func _dock_click(aid: String) -> void:
	if not windows.has(aid):
		open_app(aid)
		return
	var w: OSWindow = windows[aid]
	if w.minimized:
		_set_minimized(w, false)
		focus(w)
	elif active_key == aid:
		_set_minimized(w, true)
	else:
		focus(w)


func _refresh_dock() -> void:
	for aid in dock_btns:
		var dot: ColorRect = dock_btns[aid].dot
		if not windows.has(aid):
			dot.color = Color(0, 0, 0, 0)
		else:
			dot.color = KWTheme.ACCENT if aid == active_key else Color(KWTheme.TEXT_DIM, 0.6)

# ------------------------------------------------------------------ disposition (content.os)

func _os_data() -> Dictionary:
	var o = World.data.objects.get(id)
	if o == null:
		return {}
	var d = o.content.get("os", {})
	return d if d is Dictionary else {}


func _queue_save() -> void:
	_save_in = 0.6


## Écrit content.os en conservant le reste du contenu (messages du chat…).
func _save_layout(closing: OSWindow = null) -> void:
	_save_in = -1.0
	if not World.data.objects.has(id):
		return
	var o: Dictionary = World.data.objects[id]
	var old: Dictionary = _os_data()
	var d: Dictionary = old.duplicate(true)
	var wins: Dictionary = d.get("windows", {})
	for k in wins:
		wins[k].open = windows.has(k)
	if closing != null:
		var cl := closing.to_layout()
		cl.open = false
		cl.min = false
		wins[closing.key] = cl
	for k in windows:
		var l: Dictionary = windows[k].to_layout()
		l.open = true
		wins[k] = l
	d.windows = wins
	var order := []
	for w in layer.get_children():
		if w is OSWindow and windows.has(w.key):
			order.append(w.key)
	d.order = order
	if JSON.stringify(d) == JSON.stringify(old):
		return
	var c: Dictionary = o.content.duplicate(true)
	c.os = d
	World.update_object(id, {"content": c})


## Valeur persistante libre dans content.os (ex. historique du terminal).
func set_os_value(k: String, v) -> void:
	if not World.data.objects.has(id):
		return
	var c: Dictionary = World.data.objects[id].content.duplicate(true)
	var d = c.get("os", {})
	if not d is Dictionary:
		d = {}
	d[k] = v
	c.os = d
	World.update_object(id, {"content": c})


func get_os_value(k: String, def = null):
	return _os_data().get(k, def)


func _restore_layout() -> void:
	var d := _os_data()
	var wins: Dictionary = d.get("windows", {})
	var order: Array = d.get("order", [])
	for k in wins.keys():
		if not k in order:
			order.append(k)
	for k in order:
		if wins.has(k) and wins[k].get("open", false) and not windows.has(k):
			var w := open_app(k)
			if w != null and wins[k].get("min", false):
				_set_minimized(w, true)

# ------------------------------------------------------------------ lanceur

func open_launcher() -> void:
	launcher.visible = true
	launch_input.text = ""
	_fill_launcher()
	launch_input.grab_focus()


func close_launcher() -> void:
	launcher.visible = false


func _fill_launcher() -> void:
	OSApp.clear(launch_list)
	_launch_first = Callable()
	var q := launch_input.text.strip_edges().to_lower()
	var any := false
	for a in APPS:
		if q == "" or q in str(a.name).to_lower() or q in str(a.desc).to_lower():
			var aid: String = a.id
			_launch_row(a.glyph, a.color, a.name, a.desc, func():
				close_launcher()
				open_app(aid))
			any = true
	if q.length() >= 2:
		var res := World.search(q, 10)
		if not res.is_empty():
			KWPanel.section(launch_list, "Dans le monde")
		for r in res:
			var ref := {"kind": r.kind, "id": r.id}
			var glyph: String = {"room": "▦", "portal": "◆", "document": "❏"}.get(r.kind, "✎")
			_launch_row(glyph, KWTheme.TEXT_DIM, str(r.label).get_slice("   — ", 0), str(r.label).get_slice("   — ", 1), func():
				close_launcher()
				open_ref(ref))
			any = true
	if not any:
		KWPanel.dim(launch_list, "Aucun résultat.")


func _launch_row(glyph: String, tint: Color, title: String, sub: String, cb: Callable) -> void:
	var b := Button.new()
	b.theme_type_variation = "MenuItem"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 52
	b.pressed.connect(cb)
	launch_list.add_child(b)
	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 10
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	var t := OSWindow.tile(glyph, tint, 32, 14)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(t)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var l := Label.new()
	l.text = title
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.theme_type_variation = "Dim"
		s.add_theme_font_size_override("font_size", 12)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(s)
	if not _launch_first.is_valid():
		_launch_first = cb

# ------------------------------------------------------------------ navigation / divers

## Ouvre une référence {kind, id} dans l'application adaptée.
func open_ref(ref: Dictionary) -> void:
	if ref.is_empty() or not World.exists(ref.kind, ref.id):
		return
	match ref.kind:
		"object":
			if NoteLinks.is_note(World.data.objects[ref.id]):
				open_app("notes", {"note": ref.id})
			else:
				open_app("explorer", {"select": ref})
		"document":
			open_app("documents", {"doc": ref.id})
		_:
			open_app("explorer", {"select": ref})


## Quitte l'OS et voyage vers la salle (Main ferme le panneau).
func go_to_room(rid: String) -> void:
	if main != null and World.data.rooms.has(rid):
		_save_layout()
		main.go_to_room(rid, main.current_room)


func go_to_object(oid: String) -> void:
	if main != null and World.data.objects.has(oid):
		_save_layout()
		if World.data.objects[oid].room_id == main.current_room:
			closed.emit()
		else:
			main.go_to_object(oid)


func notify(msg: String) -> void:
	toast_lbl.text = msg
	toast_box.visible = true
	toast_box.modulate.a = 1.0
	if _toast_tw:
		_toast_tw.kill()
	_toast_tw = create_tween()
	_toast_tw.tween_interval(2.4)
	_toast_tw.tween_property(toast_box, "modulate:a", 0.0, 0.4)
	_toast_tw.tween_callback(func(): toast_box.visible = false)

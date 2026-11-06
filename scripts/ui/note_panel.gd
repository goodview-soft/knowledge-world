class_name NotePanel
extends KWPanel
## Éditeur de notes inspiré d'Obsidian : Markdown (Édition / Partagé / Aperçu), liens wiki
## [[Nom]] avec autocomplétion, #tags, rétroliens / liens sortants, note du jour.
## Les liens wiki sont synchronisés en relations World à chaque sauvegarde (NoteLinks).

const COLORS := ["#f2efe6", "#ffe27a", "#ffb3a7", "#a8d8b9", "#a7c7e7", "#d7bde2", "#ffffff"]
const MODES := [["edit", "Édition"], ["split", "Partagé"], ["view", "Aperçu"]]
static var last_mode := "split"

var id: String
var name_edit: LineEdit
var text_edit: TextEdit
var preview: RichTextLabel
var preview_card: PanelContainer
var color: String
var mode := "split"
var ac: ItemList # autocomplétion [[
var ac_items := []
var tags_box: HFlowContainer
var out_box: VBoxContainer
var back_box: VBoxContainer
var create_bar: PanelContainer
var create_label: Label
var pending_create := ""
var _timer: Timer


func _init(obj_id: String) -> void:
	id = obj_id
	var o: Dictionary = World.data.objects[id]
	super(ObjectRegistry.get_def(o.type).label, Vector2(1240, 760))
	color = o.content.get("color", "#f2efe6")
	var rn: String = World.data.rooms[o.room_id].name if World.data.rooms.has(o.room_id) else "?"
	set_subtitle("%s  ·  modifiée le %s" % [rn, str(o.get("modified", "")).left(16).replace("T", " ")])
	# Barre du haut : titre, mode, actions rapides.
	var top := hbox(body)
	name_edit = line(top, o.name, "Titre")
	name_edit.custom_minimum_size.y = 40
	name_edit.add_theme_font_size_override("font_size", 19)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 4)
	top.add_child(modes)
	var group := ButtonGroup.new()
	mode = last_mode if str(o.content.get("text", "")) != "" else "edit"
	for m in MODES:
		var key: String = m[0]
		var b := chip(modes, m[1], func(): set_mode(key))
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = key == mode
	ghost(top, "Note du jour", func(): _save(); NoteLinks.open_ref(main, {"kind": "object", "id": NoteLinks.daily_note()}))
	ghost(top, "Graphe", func(): _save(); main.open_panel(GraphPanel.new()))
	# Zone principale : éditeur | aperçu | colonne latérale.
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 14)
	body.add_child(mid)
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(split)
	text_edit = TextEdit.new()
	text_edit.text = o.content.get("text", "")
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_edit.custom_minimum_size.x = 300
	text_edit.placeholder_text = "Écrivez en Markdown…\n# Titre   **gras**   *italique*   - [ ] tâche\n[[Lien vers une note, une salle ou un document]]   #tag"
	text_edit.add_theme_constant_override("line_spacing", 6)
	text_edit.syntax_highlighter = _highlighter()
	text_edit.text_changed.connect(_on_text_changed)
	text_edit.caret_changed.connect(_update_ac)
	text_edit.gui_input.connect(_editor_input)
	split.add_child(text_edit)
	preview_card = PanelContainer.new()
	preview_card.theme_type_variation = "Card"
	preview_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_card.custom_minimum_size.x = 300
	split.add_child(preview_card)
	preview = RichTextLabel.new()
	preview.bbcode_enabled = true
	preview.selection_enabled = true
	preview.meta_underlined = false
	preview.add_theme_constant_override("line_separation", 6)
	preview.add_theme_font_size_override("normal_font_size", 17)
	preview.add_theme_font_size_override("bold_font_size", 17)
	preview.add_theme_font_size_override("italics_font_size", 17)
	preview.meta_clicked.connect(_on_meta)
	preview_card.add_child(preview)
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = 270
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 12)
	side_scroll.add_child(side)
	var c1 := card(side, "Tags")
	tags_box = HFlowContainer.new()
	c1.add_child(tags_box)
	var c2 := card(side, "Liens sortants")
	out_box = VBoxContainer.new()
	c2.add_child(out_box)
	var c3 := card(side, "Rétroliens")
	back_box = VBoxContainer.new()
	c3.add_child(back_box)
	# Autocomplétion.
	ac = ItemList.new()
	ac.visible = false
	ac.custom_minimum_size = Vector2(320, 0)
	ac.auto_height = true
	ac.focus_mode = Control.FOCUS_NONE
	ac.item_activated.connect(func(i): _accept_ac(i))
	ac.item_clicked.connect(func(i, _p, _b): _accept_ac(i))
	text_edit.add_child(ac)
	# Barre « créer la note ? » pour un lien inexistant.
	create_bar = PanelContainer.new()
	create_bar.theme_type_variation = "Card"
	create_bar.visible = false
	body.add_child(create_bar)
	var cb := hbox(create_bar)
	create_label = lbl(cb, "")
	create_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary(cb, "Créer la note", _create_pending)
	ghost(cb, "Annuler", func(): create_bar.visible = false)
	# Bas : couleur, transformations, relations, suppression.
	var acts := hbox(body)
	dim(acts, "Papier").autowrap_mode = TextServer.AUTOWRAP_OFF
	for c in COLORS:
		var b := icon_btn(acts, "●", func(): color = c; _save(), c)
		b.add_theme_color_override("font_color", Color(c))
		b.add_theme_color_override("font_hover_color", Color(c).lightened(0.2))
	spacer(acts)
	ghost(acts, "→ Fiche", func(): _transform("note_to_card", "Fiche créée à côté."))
	ghost(acts, "→ Kanban", func(): _transform("note_to_kanban", "Kanban créé (une carte par ligne)."))
	ghost(acts, "→ Salle", func(): _transform("note_to_room", "Salle créée : une porte a été ajoutée ici."))
	btn(acts, "Relations…", func(): _save(); main.open_relations("object", id))
	danger(acts, "Supprimer", func(): World.delete_object(id); closed.emit())
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = 0.35
	_timer.timeout.connect(_refresh_side)
	add_child(_timer)
	set_mode(mode)
	_render()
	_refresh_side()


func _ready() -> void:
	super()
	if text_edit.visible:
		text_edit.grab_focus()


func set_mode(m: String) -> void:
	mode = m
	last_mode = m
	text_edit.visible = m != "view"
	preview_card.visible = m != "edit"
	if m != "edit":
		_render()


func _highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = KWTheme.TEXT
	h.symbol_color = KWTheme.TEXT
	h.function_color = KWTheme.TEXT
	h.member_variable_color = KWTheme.TEXT
	h.add_color_region("[[", "]]", KWTheme.ACCENT)
	h.add_color_region("`", "`", Color("#e8c9a0"))
	h.add_color_region("**", "**", Color.WHITE)
	h.add_color_region("> ", "", KWTheme.TEXT_DIM, true)
	h.add_color_region("# ", "", Color.WHITE, true)
	h.add_color_region("## ", "", Color.WHITE, true)
	h.add_color_region("### ", "", Color.WHITE, true)
	return h


func _on_text_changed() -> void:
	if preview_card.visible:
		_render()
	_timer.start()
	_update_ac()


func _render() -> void:
	var sc := preview.get_v_scroll_bar().value
	preview.text = NoteMarkdown.to_bbcode(text_edit.text, func(t): return not NoteLinks.resolve(t).is_empty())
	preview.get_v_scroll_bar().set_deferred("value", sc)

# ------------------------------------------------------------------ colonne latérale

func _refresh_side() -> void:
	for box in [tags_box, out_box, back_box]:
		for ch in box.get_children():
			ch.queue_free()
	var tags := NoteLinks.parse_tags(text_edit.text)
	for t in tags:
		chip(tags_box, "#" + t, func(): _open_tag(t))
	if tags.is_empty():
		dim(tags_box, "Aucun — écrivez #idée")
	var links := NoteLinks.parse_links(text_edit.text)
	for t in links:
		var ref := NoteLinks.resolve(t)
		if ref.is_empty():
			var b := ghost(out_box, "+  " + t, func(): _ask_create(t))
			b.tooltip_text = "N'existe pas encore : cliquer pour créer la note"
			b.modulate.a = 0.6
		else:
			_ref_btn(out_box, ref, t)
	if links.is_empty():
		dim(out_box, "Aucun — tapez [[")
	var back := NoteLinks.backlinks("object", id)
	for nid in back:
		_ref_btn(back_box, {"kind": "object", "id": nid}, World.data.objects[nid].name)
	if back.is_empty():
		dim(back_box, "Aucune note ne pointe ici.")


func _ref_btn(parent: Control, ref: Dictionary, text: String) -> Button:
	var glyph: String = {"object": "◆", "room": "▣", "document": "▤"}.get(ref.kind, "•")
	var b := ghost(parent, "%s  %s" % [glyph, text], func(): _save(); NoteLinks.open_ref(main, ref))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = World.label_of(ref.kind, ref.id)
	if ref.kind == "object" and World.data.objects.has(ref.id) and World.data.objects[ref.id].room_id != World.data.objects[id].room_id:
		var r: String = World.data.objects[ref.id].room_id
		b.tooltip_text += "  — salle « %s »" % (World.data.rooms[r].name if World.data.rooms.has(r) else "?")
	return b


func _open_tag(t: String) -> void:
	_save()
	main.open_panel(GraphPanel.new("notes", t))

# ------------------------------------------------------------------ liens

func _on_meta(meta) -> void:
	var m := str(meta)
	if m.begins_with("task:"):
		var cl := text_edit.get_caret_line()
		var cc := text_edit.get_caret_column()
		text_edit.text = NoteMarkdown.toggle_task(text_edit.text, int(m.substr(5)))
		text_edit.set_caret_line(cl)
		text_edit.set_caret_column(cc)
		_save()
		_render()
	elif m.begins_with("wiki:"):
		follow_link(m.substr(5).uri_decode())
	elif m.begins_with("tag:"):
		_open_tag(m.substr(4))
	elif m.begins_with("http"):
		OS.shell_open(m)


func follow_link(target: String) -> void:
	var ref := NoteLinks.resolve(target)
	if ref.is_empty():
		_ask_create(target)
	elif not (ref.kind == "object" and ref.id == id):
		_save()
		NoteLinks.open_ref(main, ref)


func _ask_create(target: String) -> void:
	pending_create = target
	create_label.text = "« %s » n'existe pas encore. Créer une note dans cette salle ?" % target
	create_bar.visible = true


func _create_pending() -> void:
	if pending_create == "" or not World.data.objects.has(id):
		return
	var nid := NoteLinks.create_note(World.data.objects[id].room_id, pending_create, "# %s\n\n" % pending_create)
	pending_create = ""
	create_bar.visible = false
	_save()
	main.open_panel(NotePanel.new(nid))

# ------------------------------------------------------------------ autocomplétion [[

func _ac_query() -> Dictionary:
	var ln := text_edit.get_caret_line()
	var before := text_edit.get_line(ln).substr(0, text_edit.get_caret_column())
	var i := before.rfind("[[")
	if i < 0:
		return {}
	var q := before.substr(i + 2)
	if "]]" in q or "|" in q or "[" in q:
		return {}
	return {"line": ln, "start": i, "q": q}


func _update_ac() -> void:
	if ac == null:
		return
	var aq := _ac_query()
	if aq.is_empty() or not text_edit.has_focus():
		ac.visible = false
		return
	ac_items = NoteLinks.candidates(aq.q, 8, id)
	ac.clear()
	for c in ac_items:
		ac.add_item("%s   ·  %s" % [c[0], c[1]])
	if ac_items.is_empty():
		ac.visible = false
		return
	ac.select(0)
	ac.visible = true
	var p := text_edit.get_caret_draw_pos() + Vector2(0, 8)
	p.x = clampf(p.x, 0, maxf(0, text_edit.size.x - ac.custom_minimum_size.x))
	if p.y + 260 > text_edit.size.y:
		p.y -= 300
	ac.position = p
	ac.size = Vector2(ac.custom_minimum_size.x, 0)


func _accept_ac(i: int) -> void:
	var aq := _ac_query()
	if aq.is_empty() or i < 0 or i >= ac_items.size():
		ac.visible = false
		return
	var ln: int = aq.line
	var line_text := text_edit.get_line(ln)
	var col := text_edit.get_caret_column()
	var after := line_text.substr(col)
	if after.begins_with("]]"):
		after = after.substr(2)
	var ins := "[[" + str(ac_items[i][0]) + "]]"
	text_edit.begin_complex_operation()
	text_edit.set_line(ln, line_text.substr(0, aq.start) + ins + after)
	text_edit.set_caret_line(ln)
	text_edit.set_caret_column(aq.start + ins.length())
	text_edit.end_complex_operation()
	ac.visible = false
	_on_text_changed()
	ac.visible = false


func _editor_input(event: InputEvent) -> void:
	if not ac.visible or not (event is InputEventKey and event.pressed):
		return
	var sel := ac.get_selected_items()
	var cur: int = sel[0] if sel.size() > 0 else 0
	match event.keycode:
		KEY_DOWN:
			ac.select(mini(cur + 1, ac.item_count - 1))
		KEY_UP:
			ac.select(maxi(cur - 1, 0))
		KEY_ENTER, KEY_KP_ENTER, KEY_TAB:
			_accept_ac(cur)
		_:
			return
	text_edit.accept_event()


func _input(event: InputEvent) -> void:
	if ac != null and ac.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		ac.visible = false
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ sauvegarde

func _save() -> void:
	if not World.data.objects.has(id):
		return
	var c: Dictionary = World.data.objects[id].content.duplicate(true)
	c.text = text_edit.text
	c.color = color
	World.update_object(id, {"name": name_edit.text, "content": c})
	NoteLinks.sync_relations(id)


func _transform(op: String, msg: String) -> void:
	_save()
	World.transform(op, id)
	main.hud.toast(msg + " L'original est conservé.")
	closed.emit()


func on_close() -> void:
	_save()

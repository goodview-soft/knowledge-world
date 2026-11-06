class_name OSNotes
extends OSApp
## Éditeur de notes Markdown de KW OS : toutes les notes du monde, rendu NoteMarkdown,
## liens [[wiki]] (NoteLinks), cases à cocher, création dans la salle courante.

var search: LineEdit
var here_only: CheckBox
var list: ItemList
var ids := []
var current := ""
var title_edit: LineEdit
var text_edit: TextEdit
var preview: RichTextLabel
var footer: Label
var mode := "split"
var mode_btns := {}
var editor_box: HBoxContainer
var empty_lbl: Label
var del_btn: Button
var _dirty := false
var _save_in := -1.0
var _confirm_del := false


func _init() -> void:
	super()
	var split := OSApp.split_list(290)
	add_child(split)
	# Colonne : recherche + liste.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	split.add_child(left)
	search = KWPanel.line(left, "", "Rechercher (#tag possible)…")
	search.text_changed.connect(func(_t): refresh())
	here_only = CheckBox.new()
	here_only.text = "Salle courante"
	here_only.toggled.connect(func(_b): refresh())
	left.add_child(here_only)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.item_selected.connect(func(i: int): open_note(ids[i]))
	left.add_child(list)
	KWPanel.primary(left, "+ Nouvelle note", func(): new_note("Nouvelle note"))
	# Éditeur.
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var top := KWPanel.hbox(right)
	title_edit = KWPanel.line(top, "", "Titre")
	title_edit.add_theme_font_size_override("font_size", 18)
	title_edit.text_submitted.connect(func(_t): save())
	title_edit.focus_exited.connect(save)
	for m in [["edit", "Édition"], ["split", "Partagé"], ["view", "Aperçu"]]:
		var key: String = m[0]
		var b := KWPanel.chip(top, m[1], func(): set_mode(key))
		b.toggle_mode = true
		mode_btns[key] = b
	KWPanel.icon_btn(top, "⌖", _show_in_world, "Voir dans le monde")
	del_btn = KWPanel.icon_btn(top, "✕", _delete, "Supprimer la note")
	editor_box = HBoxContainer.new()
	editor_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_box.add_theme_constant_override("separation", 12)
	right.add_child(editor_box)
	text_edit = TextEdit.new()
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_edit.placeholder_text = "Markdown : # titre, **gras**, - [ ] tâche, [[lien]], #tag"
	text_edit.text_changed.connect(_on_text_changed)
	editor_box.add_child(text_edit)
	var pv := PanelContainer.new()
	pv.theme_type_variation = "Card"
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_box.add_child(pv)
	preview = RichTextLabel.new()
	preview.bbcode_enabled = true
	preview.selection_enabled = true
	preview.meta_underlined = false
	preview.meta_clicked.connect(_on_meta)
	pv.add_child(preview)
	empty_lbl = KWPanel.dim(right, "Choisissez une note à gauche ou créez-en une.")
	empty_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer = KWPanel.dim(right, "")
	set_mode("split")
	refresh()
	_show_editor(false)


func open_args(args: Dictionary) -> void:
	if args.has("note"):
		open_note(args.note)


func _process(delta: float) -> void:
	if _save_in > 0.0:
		_save_in -= delta
		if _save_in <= 0.0:
			save()


func set_mode(m: String) -> void:
	mode = m
	for k in mode_btns:
		mode_btns[k].set_pressed_no_signal(k == m)
	text_edit.get_parent().visible = true
	text_edit.visible = m != "view"
	preview.get_parent().visible = m != "edit"


func _show_editor(on: bool) -> void:
	editor_box.visible = on
	empty_lbl.visible = not on
	title_edit.editable = on
	del_btn.disabled = not on


func refresh() -> void:
	var q := search.text.strip_edges().to_lower()
	var tag := q.substr(1) if q.begins_with("#") else ""
	var room := current_room()
	var notes := NoteLinks.notes().filter(func(o):
		if not World.data.rooms.has(o.room_id):
			return false
		if here_only.button_pressed and o.room_id != room:
			return false
		if tag != "":
			return NoteLinks.parse_tags(str(o.content.get("text", ""))).any(func(t): return t.begins_with(tag))
		return q == "" or q in str(o.name).to_lower() or q in str(o.content.get("text", "")).to_lower())
	notes.sort_custom(func(a, b): return str(a.get("modified", "")) > str(b.get("modified", "")))
	list.clear()
	ids.clear()
	for o in notes:
		var i := list.add_item("%s\n%s" % [o.name, OSData.room_name(o.room_id)])
		list.set_item_tooltip(i, OSData.room_path(o.room_id))
		ids.append(o.id)
		if o.id == current:
			list.select(i)
	if current != "" and not World.data.objects.has(current):
		current = ""
		_dirty = false
		_show_editor(false)
	elif current != "" and not _dirty:
		# Modifiée ailleurs (ex. tâche cochée) : recharger sans perdre le curseur.
		var t := str(World.data.objects[current].content.get("text", ""))
		if t != text_edit.text:
			_set_text_keep_caret(t)
		_render()


func new_note(title: String, text := "") -> String:
	save()
	var nid := OSData.create_note(current_room(), title, text)
	open_note(nid)
	title_edit.grab_focus.call_deferred()
	title_edit.select_all.call_deferred()
	toast("Note créée dans « %s »." % OSData.room_name(current_room()))
	return nid


func open_note(nid: String) -> void:
	if not World.data.objects.has(nid):
		return
	if nid != current:
		save()
	current = nid
	_confirm_del = false
	var o: Dictionary = World.data.objects[nid]
	title_edit.text = o.name
	text_edit.text = str(o.content.get("text", ""))
	text_edit.clear_undo_history()
	_dirty = false
	_show_editor(true)
	_render()
	for i in ids.size():
		if ids[i] == nid:
			list.select(i)
			list.ensure_current_is_visible()


func _set_text_keep_caret(t: String) -> void:
	var cl := text_edit.get_caret_line()
	var cc := text_edit.get_caret_column()
	var sv := text_edit.scroll_vertical
	text_edit.text = t
	text_edit.set_caret_line(mini(cl, text_edit.get_line_count() - 1))
	text_edit.set_caret_column(cc)
	text_edit.scroll_vertical = sv


func _on_text_changed() -> void:
	_dirty = true
	_save_in = 0.8
	_render()


func _render() -> void:
	if current == "" or not World.data.objects.has(current):
		return
	preview.text = NoteMarkdown.to_bbcode(text_edit.text, func(t): return not NoteLinks.resolve(t).is_empty())
	var o: Dictionary = World.data.objects[current]
	var tags := NoteLinks.parse_tags(text_edit.text)
	footer.text = "%s  ·  %d lien(s) · %d rétrolien(s)%s" % [OSData.room_path(o.room_id), NoteLinks.parse_links(text_edit.text).size(),
		NoteLinks.backlinks("object", current).size(), ("  ·  #" + "  #".join(PackedStringArray(tags))) if not tags.is_empty() else ""]


func save() -> void:
	_save_in = -1.0
	if current == "" or not World.data.objects.has(current):
		return
	var o: Dictionary = World.data.objects[current]
	var changed_text := str(o.content.get("text", "")) != text_edit.text
	var changed_name: bool = title_edit.text.strip_edges() != "" and title_edit.text.strip_edges() != o.name
	if not changed_text and not changed_name:
		_dirty = false
		return
	_dirty = false
	OSData.set_note_text(current, text_edit.text, title_edit.text)


func flush() -> void:
	save()


func _on_meta(meta) -> void:
	var m := str(meta)
	if m.begins_with("task:"):
		_set_text_keep_caret(NoteMarkdown.toggle_task(text_edit.text, int(m.substr(5))))
		_dirty = true
		save()
		_render()
	elif m.begins_with("wiki:"):
		follow_link(m.substr(5).uri_decode())
	elif m.begins_with("tag:"):
		search.text = "#" + m.substr(4)
		refresh()
	elif m.begins_with("http"):
		OS.shell_open(m)


func follow_link(target: String) -> void:
	save()
	var ref := NoteLinks.resolve(target)
	if ref.is_empty():
		var room: String = World.data.objects[current].room_id if World.data.objects.has(current) else current_room()
		var nid := OSData.create_note(room, target)
		toast("Note « %s » créée." % target)
		open_note(nid)
	elif ref.kind == "object" and NoteLinks.is_note(World.data.objects[ref.id]):
		open_note(ref.id)
	else:
		open_ref(ref)


func _delete() -> void:
	if current == "":
		return
	if not _confirm_del:
		_confirm_del = true
		toast("Cliquez à nouveau sur ✕ pour supprimer la note.")
		return
	var n: String = title_edit.text
	OSData.delete("object", current)
	current = ""
	_dirty = false
	_show_editor(false)
	toast("Note supprimée : " + n)


func _show_in_world() -> void:
	save()
	if os != null and current != "":
		os.go_to_object(current)

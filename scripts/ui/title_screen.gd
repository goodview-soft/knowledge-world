class_name TitleScreen
extends Control
## Écran d'accueil : liste des mondes (sauvegardes), continuer, créer, renommer,
## dupliquer, supprimer. Le hub du dernier monde tourne doucement en fond.

var main: Node
var list_box: VBoxContainer
var name_edit: LineEdit
var demo_chk: CheckBox
var _pending_delete := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.03, 0.05, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 80
	root.offset_right = -80
	root.offset_top = 70
	root.offset_bottom = -60
	root.add_theme_constant_override("separation", 48)
	add_child(root)
	# Colonne titre.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 14)
	root.add_child(left)
	var t := Label.new()
	t.text = "Knowledge World"
	t.add_theme_font_size_override("font_size", 58)
	left.add_child(t)
	var sub := Label.new()
	sub.text = "Votre univers de connaissances"
	sub.add_theme_font_size_override("font_size", 20)
	sub.modulate.a = 0.7
	left.add_child(sub)
	KWPanel.spacer(left)
	var cont := KWPanel.primary(left, "▶   Continuer", func(): _open(World.save_path))
	cont.custom_minimum_size = Vector2(320, 52)
	cont.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cont.add_theme_font_size_override("font_size", 20)
	var hint := Label.new()
	hint.text = "Dernier monde : %s" % World.data.get("world_name", "Mon monde")
	hint.modulate.a = 0.6
	left.add_child(hint)
	KWPanel.spacer(left)
	var q := KWPanel.ghost(left, "Quitter", func(): World.save_world(); get_tree().quit())
	q.custom_minimum_size = Vector2(160, 40)
	q.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Colonne mondes.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	root.add_child(panel)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	panel.add_child(right)
	KWPanel.lbl(right, "Mondes", 24)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(list_box)
	KWPanel.sep(right)
	KWPanel.lbl(right, "Nouveau monde", 18)
	var row := KWPanel.hbox(right)
	name_edit = KWPanel.line(row, "", "Nom du monde…")
	name_edit.text_submitted.connect(func(_t): _create())
	demo_chk = CheckBox.new()
	demo_chk.text = "Contenu de démo"
	demo_chk.button_pressed = false
	row.add_child(demo_chk)
	KWPanel.primary(row, "Créer", _create)


func _ready() -> void:
	main = get_tree().current_scene
	_refresh()


func _process(delta: float) -> void:
	if main != null and main.player != null:
		main.player.rotate_y(delta * 0.04)


func _refresh() -> void:
	for c in list_box.get_children():
		c.queue_free()
	for w in World.list_worlds():
		var card := PanelContainer.new()
		card.theme_type_variation = "Card"
		list_box.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		card.add_child(h)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var current: bool = w.path == World.save_path
		var nm := LineEdit.new()
		nm.text = w.name
		nm.flat = true
		nm.add_theme_font_size_override("font_size", 19)
		nm.tooltip_text = "Cliquer pour renommer (Entrée pour valider)"
		var path: String = w.path
		nm.text_submitted.connect(func(t: String):
			if t.strip_edges() != "":
				World.rename_world(path, t.strip_edges())
			_refresh())
		info.add_child(nm)
		var date := Time.get_datetime_string_from_unix_time(int(w.modified), true).left(16)
		var meta := Label.new()
		meta.text = "%s%d salles · %d objets · %d documents · modifié le %s" % ["● ouvert · " if current else "", w.rooms, w.objects, w.documents, date]
		meta.modulate.a = 0.65
		meta.add_theme_font_size_override("font_size", 14)
		info.add_child(meta)
		KWPanel.primary(h, "Ouvrir", func(): _open(path))
		KWPanel.ghost(h, "Copier", func(): World.duplicate_world(path); _refresh())
		if not current:
			var del_text := "Confirmer ?" if _pending_delete == path else "Supprimer"
			KWPanel.danger(h, del_text, func():
				if _pending_delete == path:
					World.delete_world(path)
					_pending_delete = ""
				else:
					_pending_delete = path
				_refresh())


func _create() -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "Nouveau monde"
	var path := World.create_world(n, demo_chk.button_pressed)
	_open(path)


func _open(path: String) -> void:
	main.start_world(path)

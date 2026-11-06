class_name KWHud
extends Control
## Affichage tête haute : réticule, indication d'interaction, titre de salle, toasts,
## feuille de raccourcis (F1), barre d'outils du mode construction.

const HELP_SECTIONS := [
	["Déplacement", [["ZQSD", "Se déplacer"], ["Souris", "Regarder"], ["Maj (maintenu)", "Courir"], ["Maj (appui court)", "Entrer / sortir du palais mental"], ["Espace", "Sauter"], ["Ctrl · C", "S'accroupir (maintenir · bascule)"], ["E", "Interagir"], ["Entrée", "Parler à la conscience (maintenir : chat complet)"], ["Clic", "Reprendre la main"]]],
	["Navigation", [["Tab", "Carte & recherche"], ["H", "Retour au hub"], ["L", "Bibliothèque"], ["F", "Relations"], ["G", "Graphe des connaissances"], ["Échap", "Fermer / menu"], ["Ctrl+S", "Sauvegarder"]]],
	["Création", [["N", "Note rapide"], ["P", "Personnaliser la salle"], ["B", "Mode construction"], ["F1", "Cette aide"]]],
	["Construction", [["I · Tab", "Inventaire"], ["1 – 0", "Barre rapide"], ["Clic", "Poser / sélectionner"], ["G", "Déplacer"], ["R · Molette", "Pivoter"], ["PgUp/PgDn", "Taille (murs : largeur)"], ["Maj+PgUp/Dn", "Largeur seule"], ["T", "Style de l'objet"], ["Ctrl+D", "Dupliquer"], ["Suppr", "Supprimer"], ["X", "Grille"], ["Clic droit", "Annuler"]]],
]

var hint: Label
var hint_key: Label
var hint_box: PanelContainer
var title: Label
var subtitle: Label
var toasts: VBoxContainer
var foot: HBoxContainer
var build_box: VBoxContainer
var build_label: Label
var build_status: Label
var build_slots: Array[PanelContainer] = []
var help: PanelContainer
var crosshair: Panel
var _last_hint := ""


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair = Panel.new()
	crosshair.add_theme_stylebox_override("panel", KWTheme.box(Color(1, 1, 1, 0.85), 3, Vector4.ZERO, Color(0, 0, 0, 0.35), 1))
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE # sinon il capte la souris (centrée quand capturée)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -3
	crosshair.offset_top = -3
	crosshair.offset_right = 3
	crosshair.offset_bottom = 3
	add_child(crosshair)
	# Indication d'interaction : pastille sous le réticule.
	var hc := CenterContainer.new()
	hc.set_anchors_preset(Control.PRESET_CENTER)
	hc.offset_top = 22
	hc.offset_bottom = 70
	hc.offset_left = -500
	hc.offset_right = 500
	hc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hc)
	hint_box = PanelContainer.new()
	hint_box.theme_type_variation = "Pill"
	hint_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_box.visible = false
	hc.add_child(hint_box)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 10)
	hint_box.add_child(hh)
	hint_key = _kbd(hh, "E")
	hint = Label.new()
	hint.add_theme_font_size_override("font_size", 15)
	hh.add_child(hint)
	title = _label(36, Control.PRESET_CENTER_TOP)
	title.offset_top = 48
	title.offset_left = -500
	title.offset_right = 500
	subtitle = _label(15, Control.PRESET_CENTER_TOP)
	subtitle.offset_top = 98
	subtitle.offset_left = -500
	subtitle.offset_right = 500
	subtitle.add_theme_color_override("font_color", KWTheme.TEXT_DIM)
	# Pied : quelques raccourcis discrets.
	foot = HBoxContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 20
	foot.offset_top = -44
	foot.offset_bottom = -16
	foot.offset_right = 900
	foot.add_theme_constant_override("separation", 6)
	foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	foot.modulate.a = 0.75
	add_child(foot)
	_keys(foot, [["F1", "Aide"], ["Tab", "Carte"], ["B", "Construire"], ["P", "Salle"], ["Échap", "Menu"]])
	# Toasts : en haut à droite.
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toasts.offset_left = -440
	toasts.offset_top = 20
	toasts.offset_right = -20
	toasts.offset_bottom = 400
	toasts.add_theme_constant_override("separation", 8)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toasts)
	_build_toolbar()
	_build_help()


func _label(size: int, preset: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.set_anchors_preset(preset)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


static func _kbd(parent: Control, t: String) -> Label:
	var k := Label.new()
	k.text = t
	k.theme_type_variation = "Kbd"
	k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(k)
	return k


## Paires [touche, description] en ligne.
static func _keys(parent: Control, pairs: Array) -> void:
	for p in pairs:
		_kbd(parent, p[0])
		var d := Label.new()
		d.text = p[1]
		d.theme_type_variation = "Dim"
		d.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		parent.add_child(d)
		var gap := Control.new()
		gap.custom_minimum_size.x = 10
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(gap)


func _build_toolbar() -> void:
	build_box = VBoxContainer.new()
	build_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	build_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build_box.offset_bottom = -18
	build_box.alignment = BoxContainer.ALIGNMENT_END
	build_box.add_theme_constant_override("separation", 8)
	build_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_box.visible = false
	add_child(build_box)
	var top := CenterContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_box.add_child(top)
	var pill := PanelContainer.new()
	pill.theme_type_variation = "Pill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(pill)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 12)
	pill.add_child(ph)
	var tag := Label.new()
	tag.text = "CONSTRUCTION"
	tag.add_theme_font_size_override("font_size", 12)
	tag.add_theme_color_override("font_color", KWTheme.ACCENT)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(tag)
	build_status = Label.new()
	build_status.add_theme_font_size_override("font_size", 14)
	build_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ph.add_child(build_status)
	var slots := HBoxContainer.new()
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.add_theme_constant_override("separation", 6)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	build_box.add_child(slots)
	for i in KWHotbar.SIZE:
		var pc := PanelContainer.new()
		pc.theme_type_variation = "Slot"
		pc.custom_minimum_size = Vector2(98, 0)
		pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slots.add_child(pc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 2)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(v)
		var top_row := HBoxContainer.new()
		top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(top_row)
		var n := Label.new()
		n.text = KWHotbar.key_label(i)
		n.add_theme_font_size_override("font_size", 12)
		n.add_theme_color_override("font_color", KWTheme.TEXT_FAINT)
		n.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		top_row.add_child(n)
		var ic := KWItemIcon.new("", Vector2(40, 40))
		ic.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
		top_row.add_child(ic)
		var name_l := Label.new()
		name_l.add_theme_font_size_override("font_size", 13)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_l.custom_minimum_size.x = 78
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(name_l)
		build_slots.append(pc)
	refresh_hotbar()
	var keys := HBoxContainer.new()
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	keys.add_theme_constant_override("separation", 4)
	keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keys.modulate.a = 0.8
	build_box.add_child(keys)
	_keys(keys, [["I", "Inventaire"], ["Clic", "Poser / choisir"], ["G", "Déplacer"], ["R", "Pivoter"], ["PgUp/Dn", "Taille"], ["T", "Style"], ["Ctrl+D", "Dupliquer"], ["Suppr", "Supprimer"], ["X", "Grille"], ["B", "Quitter"]])
	build_label = build_status # compatibilité : set_build() écrit ici


func _build_help() -> void:
	help = PanelContainer.new()
	help.set_anchors_preset(Control.PRESET_CENTER)
	help.offset_left = -560
	help.offset_right = 560
	help.offset_top = -300
	help.offset_bottom = 300
	help.visible = false
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(help)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	help.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	var t := Label.new()
	t.text = "Raccourcis"
	t.theme_type_variation = "Header"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	var cl := Label.new()
	cl.text = "F1 ou Échap pour fermer"
	cl.theme_type_variation = "Dim"
	h.add_child(cl)
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 28)
	v.add_child(grid)
	for sec in HELP_SECTIONS:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 10)
		grid.add_child(col)
		KWPanel.section(col, sec[0])
		for row in sec[1]:
			var r := HBoxContainer.new()
			col.add_child(r)
			var d := Label.new()
			d.text = row[1]
			d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			d.add_theme_font_size_override("font_size", 15)
			r.add_child(d)
			_kbd(r, row[0])
	KWPanel.dim(v, "Bibliothèque : importez des fichiers texte ou PDF (bouton ou glisser-déposer). Bureau : l'assistant propose, vous validez.")


func set_hint(t: String) -> void:
	if t == _last_hint:
		return
	_last_hint = t
	var key := ""
	var txt := t
	var i := t.find(" : ")
	if i > 0 and i <= 6:
		key = t.left(i)
		txt = t.substr(i + 3)
	hint_key.text = key
	hint_key.visible = key != ""
	hint.text = txt
	hint_box.visible = t != ""


func show_room_title(t: String, sub: String) -> void:
	title.text = t
	subtitle.text = sub.to_upper()
	title.modulate.a = 0.0
	subtitle.modulate.a = 0.0
	var tw := create_tween().set_parallel()
	tw.tween_property(title, "modulate:a", 1.0, 0.6)
	tw.tween_property(subtitle, "modulate:a", 0.9, 0.6)
	tw.chain().tween_interval(2.0)
	tw.chain().tween_property(title, "modulate:a", 0.0, 1.2)
	tw.parallel().tween_property(subtitle, "modulate:a", 0.0, 1.2)


func toast(t: String) -> void:
	var pc := PanelContainer.new()
	pc.theme_type_variation = "Toast"
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.size_flags_horizontal = Control.SIZE_SHRINK_END
	var l := Label.new()
	l.text = t
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = mini(380, 12 + t.length() * 8)
	l.add_theme_font_size_override("font_size", 15)
	pc.add_child(l)
	toasts.add_child(pc)
	while toasts.get_child_count() > 5:
		toasts.get_child(0).free()
	pc.modulate.a = 0.0
	var tw := pc.create_tween()
	tw.tween_property(pc, "modulate:a", 1.0, 0.18)
	tw.tween_interval(3.5)
	tw.tween_property(pc, "modulate:a", 0.0, 0.6)
	tw.tween_callback(pc.queue_free)


## Compatibilité : affiche la barre de construction avec un texte d'état libre.
func set_build(active: bool, text: String) -> void:
	build_box.visible = active
	foot.visible = not active
	build_status.text = text


## Met à jour vignettes et noms de la barre rapide (KWHotbar).
func refresh_hotbar() -> void:
	var s := KWHotbar.slots()
	for i in build_slots.size():
		var v := build_slots[i].get_child(0)
		(v.get_child(0).get_child(1) as KWItemIcon).set_type(s[i])
		(v.get_child(1) as Label).text = ObjectRegistry.get_def(s[i]).label if s[i] != "" else "—"
		build_slots[i].modulate.a = 1.0 if s[i] != "" else 0.55


## Barre d'outils : slot actif, état de la grille, sélection, emplacement occupé.
func set_build_state(active: bool, placing: String, snap: bool, selection: String, grabbing: bool, blocked := false) -> void:
	build_box.visible = active
	foot.visible = not active
	if not active:
		return
	var s := KWHotbar.slots()
	for i in build_slots.size():
		build_slots[i].theme_type_variation = "SlotActive" if placing != "" and s[i] == placing else "Slot"
	var parts := ["Grille " + ("activée" if snap else "libre")]
	if placing != "":
		parts.append("Pose : " + ObjectRegistry.get_def(placing).label + ("  (emplacement occupé)" if blocked else ""))
	if selection != "":
		parts.append(("Déplacement : " if grabbing else "Sélection : ") + selection)
	elif placing == "":
		parts.append("I : inventaire · 1 – 0 : barre rapide · clic : sélectionner")
	build_status.text = "   ·   ".join(PackedStringArray(parts))

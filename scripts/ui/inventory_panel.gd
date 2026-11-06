class_name InventoryPanel
extends KWPanel
## Inventaire du mode construction (I ou Tab) : vignettes par catégories, recherche,
## détails au survol, barre rapide 1-0 personnalisable (clic, glisser, clic droit, 1-0 au survol).

const COLS := 6

var build: Node
var search: LineEdit
var grid: GridContainer
var empty_label: Label
var cat := ""
var tiles := {} # type -> Button
var slot_boxes: Array[PanelContainer] = []
var target_slot := 0
var _hover := ""
var _shown := ""
var d_icon: KWItemIcon
var d_name: Label
var d_cat: Label
var d_desc: Label
var d_dims: Label
var d_assign: Button
var _menu: PopupMenu
var _menu_type := ""


func _init(build_mode: Node = null) -> void:
	build = build_mode
	super("Inventaire", Vector2(1200, 760))
	set_subtitle("Clic : poser · glisser vers la barre, clic droit ou 1-0 au survol : assigner un slot")
	if build != null:
		var cur := KWHotbar.index_of(str(build.placing))
		target_slot = cur if cur >= 0 else int(build.current_slot)
	# Recherche + catégories
	var top := hbox(body)
	top.add_theme_constant_override("separation", 8)
	search = line(top, "", "Rechercher un objet…")
	search.custom_minimum_size.x = 300
	search.clear_button_enabled = true
	search.text_changed.connect(func(_t): _filter())
	var group := ButtonGroup.new()
	for c in [["", "Tout"]] + ObjectRegistry.CATEGORIES:
		var b := chip(top, c[1], func(): cat = c[0]; _filter())
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = c[0] == ""
	# Grille + détails
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 14)
	body.add_child(mid)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(sc)
	var gv := VBoxContainer.new()
	gv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(gv)
	grid = GridContainer.new()
	grid.columns = COLS
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	gv.add_child(grid)
	empty_label = dim(gv, "Aucun objet ne correspond.")
	for t in ObjectRegistry.inventory_types():
		_make_tile(t)
	var det := card(mid, "Détails")
	det.get_parent().custom_minimum_size.x = 300
	var ic := CenterContainer.new()
	det.add_child(ic)
	d_icon = KWItemIcon.new("", Vector2(150, 150))
	ic.add_child(d_icon)
	d_name = lbl(det, "", 22)
	d_cat = dim(det, "")
	d_desc = lbl(det, "Survolez un objet pour voir sa description.")
	d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d_desc.custom_minimum_size.x = 260
	d_dims = dim(det, "")
	spacer(det)
	primary(det, "Poser maintenant", func(): if _shown != "": choose(_shown))
	d_assign = ghost(det, "", func(): if _shown != "": assign(target_slot, _shown))
	# Barre rapide
	var bar_head := hbox(body)
	section(bar_head, "Barre rapide")
	var hint := dim(bar_head, "clic : slot cible · clic droit : vider · glisser : échanger")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ghost(bar_head, "Réinitialiser", func(): KWHotbar.reset(); _refresh_slots())
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 6)
	body.add_child(bar)
	for i in KWHotbar.SIZE:
		slot_boxes.append(_make_slot(bar, i))
	_menu = PopupMenu.new()
	for i in KWHotbar.SIZE:
		_menu.add_item("Assigner au slot %s" % KWHotbar.key_label(i), i)
	_menu.id_pressed.connect(func(i): if _menu_type != "": assign(i, _menu_type))
	add_child(_menu)
	_filter()
	_refresh_slots()
	_show(KWHotbar.type_at(target_slot) if KWHotbar.type_at(target_slot) != "" else "note")


func _make_tile(t: String) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(122, 128)
	b.theme_type_variation = "GhostButton"
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = ""
	grid.add_child(b)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ic := KWItemIcon.new(t, Vector2(72, 72))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var l := Label.new()
	l.text = ObjectRegistry.get_def(t).label
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size.x = 108
	l.add_theme_font_size_override("font_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	var key := Label.new()
	key.theme_type_variation = "Kbd"
	key.position = Vector2(6, 6)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.name = "Key"
	b.add_child(key)
	b.mouse_entered.connect(func(): _hover = t; _show(t))
	b.mouse_exited.connect(func(): if _hover == t: _hover = "")
	b.pressed.connect(func(): choose(t))
	b.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			_menu_type = t
			_menu.position = Vector2i(get_viewport().get_mouse_position())
			_menu.popup()
			b.accept_event())
	b.set_drag_forwarding(func(_p): return _drag(b, t, -1), Callable(), Callable())
	tiles[t] = b


func _make_slot(parent: Control, i: int) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.theme_type_variation = "Slot"
	pc.custom_minimum_size = Vector2(98, 0)
	parent.add_child(pc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(v)
	var n := Label.new()
	n.text = KWHotbar.key_label(i)
	n.add_theme_font_size_override("font_size", 12)
	n.add_theme_color_override("font_color", KWTheme.TEXT_FAINT)
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var ic := KWItemIcon.new("", Vector2(44, 44))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var name_l := Label.new()
	name_l.add_theme_font_size_override("font_size", 13)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.custom_minimum_size.x = 78
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	pc.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_LEFT:
				target_slot = i
				var t := KWHotbar.type_at(i)
				if t != "":
					_show(t)
				_refresh_slots()
			elif e.button_index == MOUSE_BUTTON_RIGHT:
				KWHotbar.clear(i)
				_refresh_slots()
			pc.accept_event())
	pc.set_drag_forwarding(func(_p): return _drag(pc, KWHotbar.type_at(i), i),
		func(_p, data): return data is Dictionary and data.has("kw_type"),
		func(_p, data): assign(i, str(data.kw_type)))
	return pc


func _drag(from: Control, t: String, slot: int):
	if t == "":
		return null
	var ic := KWItemIcon.new(t, Vector2(64, 64))
	ic.modulate.a = 0.85
	from.set_drag_preview(ic)
	return {"kw_type": t, "from_slot": slot}


func _filter() -> void:
	var q := search.text.strip_edges().to_lower()
	var n := 0
	for t in tiles:
		var d: Dictionary = ObjectRegistry.get_def(t)
		var hay := ("%s %s %s %s" % [d.label, d.get("desc", ""), ObjectRegistry.category_label(str(d.get("cat", ""))), t]).to_lower()
		var ok: bool = (cat == "" or d.get("cat", "") == cat) and (q == "" or q in hay)
		tiles[t].visible = ok
		if ok:
			n += 1
	empty_label.visible = n == 0


func _refresh_slots() -> void:
	var s := KWHotbar.slots()
	for i in slot_boxes.size():
		var pc := slot_boxes[i]
		pc.theme_type_variation = "SlotActive" if i == target_slot else "Slot"
		var v := pc.get_child(0)
		(v.get_child(1) as KWItemIcon).set_type(s[i])
		(v.get_child(2) as Label).text = ObjectRegistry.get_def(s[i]).label if s[i] != "" else "—"
	for t in tiles:
		var k: Label = tiles[t].get_node("Key")
		var idx := s.find(t)
		k.text = KWHotbar.key_label(idx) if idx >= 0 else ""
		k.visible = idx >= 0
	d_assign.text = "Assigner au slot %s" % KWHotbar.key_label(target_slot)
	if build != null and build.main != null:
		build.main.hud.refresh_hotbar()


func _show(t: String) -> void:
	_shown = t
	var d: Dictionary = ObjectRegistry.get_def(t)
	d_icon.set_type(t)
	d_name.text = d.label
	d_cat.text = ObjectRegistry.category_label(str(d.get("cat", ""))).to_upper()
	d_desc.text = str(d.get("desc", ""))
	var s: Vector3 = d.size
	var extra := []
	if not ObjectRegistry.is_solid(t):
		extra.append("non bloquant")
	match str(d.get("mount", "")):
		"floor": extra.append("au sol")
		"wall": extra.append("au mur")
		"ceiling": extra.append("au plafond")
	if d.get("width_resize", false):
		extra.append("largeur réglable")
	d_dims.text = "%.2f × %.2f × %.2f m" % [s.x, s.y, s.z] + ("  ·  " + ", ".join(PackedStringArray(extra)) if not extra.is_empty() else "")


## Assigne un type à un slot de la barre rapide (persisté).
func assign(i: int, t: String) -> void:
	KWHotbar.assign(i, t)
	target_slot = i
	_refresh_slots()
	if main != null and main.hud != null:
		main.hud.toast("%s → slot %s" % [ObjectRegistry.get_def(t).label, KWHotbar.key_label(i)])


## Choisit un objet : il rejoint la barre (slot cible s'il n'y est pas) puis on passe en pose.
func choose(t: String) -> void:
	var idx := KWHotbar.index_of(t)
	if idx < 0:
		KWHotbar.assign(target_slot, t)
		idx = target_slot
	var b := build
	closed.emit()
	if b != null:
		b.current_slot = idx
		b.main.hud.refresh_hotbar()
		b._start_placing(t)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_TAB or (event.keycode == KEY_I and not search.has_focus()):
		get_viewport().set_input_as_handled()
		closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or _hover == "":
		return
	var pk: int = event.physical_keycode
	if pk >= KEY_0 and pk <= KEY_9:
		assign((pk - KEY_1) if pk != KEY_0 else 9, _hover)
		get_viewport().set_input_as_handled()

class_name OSJournal
extends OSApp
## Journal / calendrier : vue mois, jours avec journal ou activité marqués,
## notes du jour, ouverture / création de « Journal AAAA-MM-JJ ».

const WEEK := ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]

var year: int
var month: int
var selected := ""
var month_lbl: Label
var grid: GridContainer
var day_title: Label
var day_box: VBoxContainer
var open_btn: Button


func _init() -> void:
	super()
	var d := Time.get_date_dict_from_system()
	year = d.year
	month = d.month
	selected = Time.get_date_string_from_system()
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 16)
	add_child(cols)
	var cal := VBoxContainer.new()
	cal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cal.size_flags_stretch_ratio = 1.3
	cols.add_child(cal)
	var nav := KWPanel.hbox(cal)
	KWPanel.icon_btn(nav, "‹", func(): shift(-1), "Mois précédent")
	month_lbl = Label.new()
	month_lbl.theme_type_variation = "Header"
	month_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	month_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(month_lbl)
	KWPanel.icon_btn(nav, "›", func(): shift(1), "Mois suivant")
	KWPanel.ghost(nav, "Aujourd'hui", _today)
	var head := GridContainer.new()
	head.columns = 7
	cal.add_child(head)
	for w in WEEK:
		var l := Label.new()
		l.text = w
		l.theme_type_variation = "Section"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
	grid = GridContainer.new()
	grid.columns = 7
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	cal.add_child(grid)
	var right := PanelContainer.new()
	right.theme_type_variation = "Card"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	day_title = Label.new()
	day_title.theme_type_variation = "Header"
	day_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(day_title)
	open_btn = KWPanel.primary(rv, "", open_journal)
	KWPanel.section(rv, "Notes du jour")
	day_box = OSApp.scroll_v(rv)
	refresh()


static func days_in(y: int, m: int) -> int:
	if m == 2:
		return 29 if (y % 4 == 0 and y % 100 != 0) or y % 400 == 0 else 28
	return 30 if m in [4, 6, 9, 11] else 31


static func iso(y: int, m: int, d: int) -> String:
	return "%04d-%02d-%02d" % [y, m, d]


func shift(delta: int) -> void:
	month += delta
	while month < 1:
		month += 12
		year -= 1
	while month > 12:
		month -= 12
		year += 1
	refresh()


func _today() -> void:
	var d := Time.get_date_dict_from_system()
	year = d.year
	month = d.month
	selected = Time.get_date_string_from_system()
	refresh()


func select_day(day: String) -> void:
	selected = day
	refresh()


func refresh() -> void:
	month_lbl.text = "%s %d" % [OSPanel.MONTHS[month - 1].capitalize(), year]
	# Jours marqués : journal (accent) ou activité (point discret).
	var journal := {}
	var activity := {}
	var prefix := "%04d-%02d" % [year, month]
	for o in NoteLinks.notes():
		if not World.data.rooms.has(o.room_id):
			continue
		var n := str(o.name)
		if n.begins_with("Journal ") and n.substr(8).begins_with(prefix):
			journal[n.substr(8, 10)] = true
		elif n.begins_with(prefix) and n.length() == 10:
			journal[n] = true
		for k in ["created", "modified"]:
			var t := str(o.get(k, ""))
			if t.begins_with(prefix):
				activity[t.left(10)] = true
	OSApp.clear(grid)
	var first := Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_dict({"year": year, "month": month, "day": 1, "hour": 12}))
	var offset := (int(first.weekday) + 6) % 7
	for i in offset:
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(sp)
	var today := Time.get_date_string_from_system()
	for d in range(1, days_in(year, month) + 1):
		var day := iso(year, month, d)
		var b := Button.new()
		b.text = str(d) + ("\n●" if journal.has(day) else ("\n·" if activity.has(day) else "\n "))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(52, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.theme_type_variation = "PrimaryButton" if day == selected else ("Chip" if day == today else "GhostButton")
		if journal.has(day) and day != selected:
			b.add_theme_color_override("font_color", KWTheme.ACCENT)
		b.pressed.connect(func(): select_day(day))
		grid.add_child(b)
	# Panneau du jour.
	var p := selected.split("-")
	var title := selected
	if p.size() == 3:
		var u := Time.get_unix_time_from_datetime_dict({"year": int(p[0]), "month": int(p[1]), "day": int(p[2]), "hour": 12})
		var dd := Time.get_datetime_dict_from_unix_time(u)
		title = "%s %d %s %d" % [OSPanel.DAYS[dd.weekday].capitalize(), dd.day, OSPanel.MONTHS[dd.month - 1], dd.year]
	day_title.text = title
	var exists := _find_journal(selected) != ""
	open_btn.text = ("Ouvrir le journal" if exists else "Créer le journal") + "  ·  " + OSData.journal_name(selected)
	OSApp.clear(day_box)
	var ids := OSData.notes_of_day(selected)
	if ids.is_empty():
		KWPanel.dim(day_box, "Aucune note créée ou modifiée ce jour-là.")
	for oid in ids:
		var o: Dictionary = World.data.objects[oid]
		var ref := {"kind": "object", "id": oid}
		var b := KWPanel.ghost(day_box, "✎  %s   — %s" % [o.name, OSData.room_name(o.room_id)], func(): open_ref(ref))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT


func _find_journal(day: String) -> String:
	var n := OSData.journal_name(day)
	for o in NoteLinks.notes():
		if o.name == n and World.data.rooms.has(o.room_id):
			return o.id
	return ""


## Ouvre (ou crée) la note de journal du jour sélectionné ; renvoie son id.
func open_journal() -> String:
	var nid := OSData.journal_note(selected)
	open_ref({"kind": "object", "id": nid})
	return nid

class_name OSTasks
extends OSApp
## Tâches : toutes les cases « - [ ] » des notes et cartes Kanban du monde,
## filtrables par salle. Cocher modifie la donnée source (note ou Kanban).

var room_pick: OptionButton
var hide_done: CheckBox
var progress: ProgressBar
var count_lbl: Label
var list: VBoxContainer
var tasks := []
var _rooms := [""]


func _init() -> void:
	super()
	var top := KWPanel.hbox(self)
	room_pick = OptionButton.new()
	room_pick.custom_minimum_size.x = 240
	room_pick.item_selected.connect(func(_i): refresh())
	top.add_child(room_pick)
	hide_done = CheckBox.new()
	hide_done.text = "Masquer terminées"
	hide_done.toggled.connect(func(_b): refresh())
	top.add_child(hide_done)
	KWPanel.spacer(top)
	count_lbl = KWPanel.dim(top, "")
	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 6)
	add_child(progress)
	list = OSApp.scroll_v(self)
	list.add_theme_constant_override("separation", 6)
	refresh()


func room_filter() -> String:
	var i := room_pick.selected
	return _rooms[i] if i >= 0 and i < _rooms.size() else ""


func refresh() -> void:
	var keep := room_filter()
	var all := OSData.collect_tasks()
	# Filtre par salle (seules les salles ayant des tâches).
	var rooms := {}
	for t in all:
		rooms[t.room_id] = true
	room_pick.clear()
	_rooms = [""]
	room_pick.add_item("Toutes les salles")
	var rids := rooms.keys()
	rids.sort_custom(func(a, b): return OSData.room_path(a) < OSData.room_path(b))
	for r in rids:
		room_pick.add_item(OSData.room_path(r))
		_rooms.append(r)
	var sel := _rooms.find(keep)
	room_pick.select(maxi(sel, 0))
	var rf := room_filter()
	tasks = all.filter(func(t): return rf == "" or t.room_id == rf)
	var done := tasks.filter(func(t): return t.done).size()
	count_lbl.text = "%d / %d faites" % [done, tasks.size()]
	progress.max_value = maxi(tasks.size(), 1)
	progress.value = done
	OSApp.clear(list)
	if tasks.is_empty():
		KWPanel.dim(list, "Aucune tâche. Ajoutez « - [ ] » dans une note ou des cartes dans un Kanban.")
		return
	var by_src := {}
	var order := []
	for t in tasks:
		if hide_done.button_pressed and t.done:
			continue
		if not by_src.has(t.source):
			by_src[t.source] = []
			order.append(t.source)
		by_src[t.source].append(t)
	for src in order:
		var o: Dictionary = World.data.objects[src]
		var head := KWPanel.hbox(list)
		var title := Label.new()
		title.text = "%s  %s" % ["▥" if o.type == "kanban" else "✎", o.name]
		head.add_child(title)
		var where := KWPanel.dim(head, OSData.room_path(o.room_id))
		where.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sid: String = src
		KWPanel.ghost(head, "Ouvrir", func(): _open_source(sid))
		for t in by_src[src]:
			var cb := CheckBox.new()
			cb.text = t.text + ("" if t.kind == "check" else "   · " + str(o.content.columns[t.col].get("title", "")))
			cb.button_pressed = t.done
			cb.focus_mode = Control.FOCUS_NONE
			cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if t.done:
				cb.modulate = Color(1, 1, 1, 0.55)
			var task: Dictionary = t
			cb.toggled.connect(func(_on): toggle(task))
			var pad := MarginContainer.new()
			pad.add_theme_constant_override("margin_left", 22)
			pad.add_child(cb)
			list.add_child(pad)
		KWPanel.sep(list)


## Coche / décoche une tâche dans sa source (note ou Kanban).
func toggle(t: Dictionary) -> bool:
	var ok := OSData.toggle_task(t)
	if ok:
		toast(("Fait : " if not t.done else "À refaire : ") + str(t.text))
	return ok


func _open_source(oid: String) -> void:
	if not World.data.objects.has(oid):
		return
	if NoteLinks.is_note(World.data.objects[oid]):
		open_ref({"kind": "object", "id": oid})
	elif os != null:
		os.go_to_object(oid)

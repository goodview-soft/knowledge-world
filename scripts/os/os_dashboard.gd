class_name OSDashboard
extends OSApp
## Tableau de bord : chiffres clés, progression des tâches, activité récente,
## notes orphelines, tags, salles les plus fournies.

var content: VBoxContainer


func _init() -> void:
	super()
	content = OSApp.scroll_v(self)
	content.add_theme_constant_override("separation", 14)
	refresh()


func refresh() -> void:
	OSApp.clear(content)
	var s := OSData.stats()
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	content.add_child(grid)
	for kv in [["Portails", s.portals, Color("#d7a6ff")], ["Salles", s.rooms, KWTheme.ACCENT], ["Notes", s.notes, KWTheme.SUCCESS],
			["Documents", s.documents, Color("#e8c9a0")], ["Relations", s.relations, Color("#7fd1d8")], ["Tags", s.tags, Color("#f0c674")]]:
		var pc := PanelContainer.new()
		pc.theme_type_variation = "Card"
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(pc)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		pc.add_child(v)
		var n := Label.new()
		n.text = str(kv[1])
		n.add_theme_font_size_override("font_size", 30)
		n.add_theme_color_override("font_color", kv[2])
		v.add_child(n)
		KWPanel.section(v, kv[0])
	# Progression des tâches.
	var tc := KWPanel.card(content, "Tâches")
	var th := KWPanel.hbox(tc)
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.custom_minimum_size.y = 8
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.max_value = maxi(s.tasks, 1)
	pb.value = s.tasks_done
	th.add_child(pb)
	KWPanel.dim(th, "%d / %d faites" % [s.tasks_done, s.tasks])
	KWPanel.ghost(th, "Ouvrir", func(): _app("tasks"))
	# Deux colonnes.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	content.add_child(cols)
	var act := KWPanel.card(cols, "Activité récente")
	act.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var acts := OSData.recent_activity(14)
	if acts.is_empty():
		KWPanel.dim(act, "Rien pour l'instant.")
	for a in acts:
		var h := KWPanel.hbox(act)
		var tl := KWPanel.dim(h, OSData.fmt_time(a.time))
		tl.custom_minimum_size.x = 150
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		var ref := {"kind": a.kind, "id": a.id}
		var b := KWPanel.ghost(h, a.label + ("   — " + a.where if a.where != "" else ""), func(): open_ref(ref))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not World.exists(a.kind, a.id)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 14)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 0.8
	cols.add_child(side)
	var orph := OSData.orphans()
	var oc := KWPanel.card(side, "Notes orphelines (%d)" % orph.size())
	if orph.is_empty():
		KWPanel.dim(oc, "Toutes les notes sont reliées.")
	var of := HFlowContainer.new()
	oc.add_child(of)
	for oid in orph.slice(0, 24):
		var r := {"kind": "object", "id": oid}
		KWPanel.chip(of, str(World.data.objects[oid].name), func(): open_ref(r))
	var tags := NoteLinks.all_tags()
	var tg := KWPanel.card(side, "Tags")
	var tf := HFlowContainer.new()
	tg.add_child(tf)
	var keys := tags.keys()
	keys.sort_custom(func(a, b): return tags[a] > tags[b])
	if keys.is_empty():
		KWPanel.dim(tg, "Aucun #tag.")
	for k in keys.slice(0, 20):
		var tag: String = k
		KWPanel.chip(tf, "#%s  %d" % [tag, tags[k]], func(): _tag(tag))
	# Salles les plus fournies.
	var counts := {}
	for o in NoteLinks.notes():
		if World.data.rooms.has(o.room_id):
			counts[o.room_id] = int(counts.get(o.room_id, 0)) + 1
	var rk := counts.keys()
	rk.sort_custom(func(a, b): return counts[a] > counts[b])
	var rc := KWPanel.card(side, "Notes par salle")
	var mx := float(counts[rk[0]]) if not rk.is_empty() else 1.0
	for r in rk.slice(0, 6):
		var h := KWPanel.hbox(rc)
		var l := KWPanel.dim(h, OSData.room_name(r))
		l.custom_minimum_size.x = 150
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size.y = 6
		bar.max_value = mx
		bar.value = counts[r]
		h.add_child(bar)
		KWPanel.dim(h, str(counts[r]))


func _app(aid: String) -> void:
	if os != null:
		os.open_app(aid)


func _tag(tag: String) -> void:
	if os == null:
		return
	var w = os.open_app("notes")
	if w != null:
		w.app.search.text = "#" + tag
		w.app.refresh()

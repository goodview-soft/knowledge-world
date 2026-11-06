class_name LockerPanel
extends KWPanel
## CASIER (K, ou menu Échap) — personnalisation purement cosmétique, façon « casier » :
## grande prévisualisation 3D (SubViewport own_world_3d) qui tourne, aperçu des particules,
## grille d'items par catégorie (bordure de rareté, badges Équipé / Possédé / Verrouillé),
## essayage des items verrouillés, équiper / déséquiper, tenues sauvegardables.
## Aucun paiement réel : les items premium affichent un prix indicatif et « Bientôt disponible ».

const ICONS := {"beanie": "◓", "halo": "◯", "helmet": "◍", "crown": "♛", "scarf": "§", "wings": "❦",
	"wave": "✋", "sit": "◡", "dance": "♪", "bow": "⌒"}

var cm # autoload Cosmetics
var category := "skin"
var selected := {} # catégorie -> id sélectionné (essayage)
var _tabs := {}
var _grid: GridContainer
var _detail: VBoxContainer
var _presets: HFlowContainer
var _preset_name: LineEdit
var _count: Label
var _message := ""
# Aperçu 3D
var viewport: SubViewport
var preview_avatar: KWAvatar
var _turn: Node3D
var _fx_root: Node3D
var _drag := false
var _spin := 0.0


func _init() -> void:
	super("Casier", Vector2(1300, 780))
	cm = Engine.get_main_loop().root.get_node("Cosmetics")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	_build_preview(row)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	row.add_child(right)
	# Onglets de catégories.
	var tabs := HFlowContainer.new()
	right.add_child(tabs)
	var group := ButtonGroup.new()
	for c in cm.catalog.categories:
		var cid: String = c.id
		var b := chip(tabs, str(c.name), func(): set_category(cid))
		b.toggle_mode = true
		b.button_group = group
		_tabs[cid] = b
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 14)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(mid)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	sc.add_child(_grid)
	var dpc := PanelContainer.new()
	dpc.theme_type_variation = "Card"
	dpc.custom_minimum_size.x = 300
	mid.add_child(dpc)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 10)
	dpc.add_child(_detail)
	# Tenues sauvegardées.
	var pc := card(right, "Tenues")
	var ph := hbox(pc)
	_preset_name = line(ph, "", "Nom de la tenue…")
	primary(ph, "Sauvegarder la tenue", func():
		cm.save_preset(_preset_name.text)
		_preset_name.text = "")
	_presets = HFlowContainer.new()
	pc.add_child(_presets)
	var foot := hbox(right)
	_count = dim(foot, "")
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var note := dim(foot, "Purement cosmétique · aucun avantage · K pour fermer")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _ready() -> void:
	super()
	cm.changed.connect(_refresh)
	cm.entitlements_changed.connect(_refresh)
	cm.provider.purchase_finished.connect(_on_purchase)
	for c in cm.catalog.categories:
		selected[c.id] = cm.get_equipped(c.id)
	set_category(category)


func on_close() -> void:
	if cm.changed.is_connected(_refresh):
		cm.changed.disconnect(_refresh)
	if cm.entitlements_changed.is_connected(_refresh):
		cm.entitlements_changed.disconnect(_refresh)
	if cm.provider.purchase_finished.is_connected(_on_purchase):
		cm.provider.purchase_finished.disconnect(_on_purchase)


func set_category(cid: String) -> void:
	category = cid
	if _tabs.has(cid):
		(_tabs[cid] as Button).set_pressed_no_signal(true)
	_message = ""
	_refresh()


func select(id: String) -> void:
	selected[category] = id
	_message = ""
	_refresh()
	var it: Dictionary = cm.item(id)
	if category == "emote" and not it.is_empty():
		preview_avatar.play_emote(str(it.params.get("anim", "wave")))

# ------------------------------------------------------------------ rendu

func _refresh() -> void:
	if not is_instance_valid(_grid):
		return
	for c in _grid.get_children():
		c.queue_free()
	var cat: Dictionary = cm.catalog.category(category)
	if cat.get("optional", false):
		_grid.add_child(_tile({}))
	for it in cm.catalog.by_category(category):
		_grid.add_child(_tile(it))
	_build_detail()
	_build_presets()
	var owned: int = cm.provider.list_owned().size()
	_count.text = "Possédés : %d / %d" % [owned, cm.catalog.order.size()]
	_update_preview()


func _tile(it: Dictionary) -> Button:
	var id: String = it.get("id", "")
	var rc: Color = cm.catalog.rarity_color(str(it.get("rarity", "common"))) if id != "" else KWTheme.TEXT_FAINT
	var is_sel: bool = selected.get(category, "") == id
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 156)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = str(it.get("description", "Ne rien porter dans cet emplacement."))
	var bg := KWTheme.SURFACE_2.lerp(rc, 0.08)
	b.add_theme_stylebox_override("normal", _tile_style(bg, rc, is_sel))
	b.add_theme_stylebox_override("hover", _tile_style(bg.lightened(0.06), rc, true))
	b.add_theme_stylebox_override("pressed", _tile_style(bg.lightened(0.1), rc, true))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func(): select(id))
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 10
	v.offset_right = -10
	v.offset_top = 10
	v.offset_bottom = -12
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	b.add_child(v)
	var icon := _icon(it)
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(icon)
	var n := Label.new()
	n.text = str(it.get("name", "Aucun"))
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(n)
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cm.get_equipped(category) == id:
		badge.text = "✓ ÉQUIPÉ"
		badge.add_theme_color_override("font_color", KWTheme.SUCCESS)
	elif id == "" or cm.owns(id):
		badge.text = "POSSÉDÉ"
		badge.add_theme_color_override("font_color", KWTheme.TEXT_FAINT)
	else:
		badge.text = "🔒 " + CosmeticCatalog.price_text(it)
		badge.add_theme_color_override("font_color", rc.lightened(0.2))
	v.add_child(badge)
	return b


func _tile_style(bg: Color, rc: Color, strong: bool) -> StyleBoxFlat:
	var s := KWTheme.box(bg, 12, Vector4(8, 8, 8, 8), Color(rc, 0.95 if strong else 0.45), 2)
	s.border_width_bottom = 5
	if strong:
		s.shadow_color = Color(rc, 0.25)
		s.shadow_size = 8
	return s


## Vignette : silhouette (tenue), glyphe (accessoire / emote) ou forme de particule teintée.
func _icon(it: Dictionary) -> Control:
	var p: Dictionary = it.get("params", {})
	if it.is_empty():
		return _glyph("∅", KWTheme.TEXT_FAINT)
	match str(it.category):
		"skin":
			var c := Control.new()
			c.custom_minimum_size = Vector2(0, 70)
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var parts := [[Vector2(-11, 0), Vector2(22, 20), p.get("skin", "#e2b894")],
				[Vector2(-11, 0), Vector2(22, 5), p.get("hair", "#4a3426")],
				[Vector2(-11, 21), Vector2(22, 26), p.get("shirt", "#5b7cfa")],
				[Vector2(-20, 21), Vector2(8, 24), p.get("shirt", "#5b7cfa")],
				[Vector2(12, 21), Vector2(8, 24), p.get("shirt", "#5b7cfa")],
				[Vector2(-11, 48), Vector2(22, 18), p.get("pants", "#2e3440")],
				[Vector2(-11, 64), Vector2(22, 5), p.get("shoes", "#1d1f24")]]
			c.resized.connect(func():
				for i in c.get_child_count():
					var r: ColorRect = c.get_child(i)
					r.position = Vector2(c.size.x / 2.0, (c.size.y - 70) / 2.0) + parts[i][0])
			for pt in parts:
				var r := ColorRect.new()
				r.color = Color(str(pt[2]))
				r.size = pt[1]
				r.mouse_filter = Control.MOUSE_FILTER_IGNORE
				c.add_child(r)
			return c
		"head", "back":
			return _glyph(ICONS.get(str(p.get("model", "")), "◆"), Color(str(p.get("color", "#ffffff"))))
		"emote":
			return _glyph(ICONS.get(str(p.get("anim", "")), "☺"), KWTheme.TEXT)
	var cols := CosmeticFX.colors_of(p, KWTheme.ACCENT)
	var t := TextureRect.new()
	t.texture = CosmeticFX.texture(str(p.get("shape", "dot")))
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(0, 70)
	t.modulate = cols[0]
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _glyph(g: String, col: Color) -> Label:
	var l := Label.new()
	l.text = g
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 46)
	l.add_theme_color_override("font_color", col)
	l.custom_minimum_size = Vector2(0, 70)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	var id: String = selected.get(category, "")
	var it: Dictionary = cm.item(id)
	var cat: Dictionary = cm.catalog.category(category)
	if it.is_empty():
		lbl(_detail, "Aucun", 22)
		dim(_detail, "Ne rien porter dans l'emplacement « %s »." % cat.get("name", category))
		spacer(_detail)
		if cm.get_equipped(category) != "":
			primary(_detail, "Retirer", func(): cm.unequip(category))
		else:
			_state_btn("✓ Équipé")
		return
	var rc: Color = cm.catalog.rarity_color(str(it.rarity))
	var r := Label.new()
	r.text = cm.catalog.rarity_name(str(it.rarity)).to_upper()
	r.add_theme_color_override("font_color", rc)
	r.add_theme_font_size_override("font_size", 13)
	_detail.add_child(r)
	lbl(_detail, str(it.name), 24)
	dim(_detail, str(it.description))
	var tags := HFlowContainer.new()
	_detail.add_child(tags)
	for tg in it.tags:
		var tl := Label.new()
		tl.text = "#" + str(tg)
		tl.theme_type_variation = "Kbd"
		tags.add_child(tl)
	if category == "aura" and cm.get_equipped("aura") == id:
		_aura_tuning()
	spacer(_detail)
	if _message != "":
		var m := dim(_detail, _message)
		m.add_theme_color_override("font_color", KWTheme.ACCENT)
	if category == "emote":
		ghost(_detail, "▶  Essayer", func(): preview_avatar.play_emote(str(it.params.get("anim", "wave"))))
	if not cm.owns(id):
		var price := lbl(_detail, "🔒  Verrouillé · prix indicatif " + CosmeticCatalog.price_text(it), 14)
		price.add_theme_color_override("font_color", rc.lightened(0.2))
		var b := ghost(_detail, "Bientôt disponible", func(): cm.provider.purchase(id))
		b.tooltip_text = "Aucun paiement n'est possible pour l'instant."
		dim(_detail, "Vous pouvez l'essayer dans l'aperçu.")
	elif cm.get_equipped(category) == id:
		if cat.get("optional", false):
			ghost(_detail, "Déséquiper", func(): cm.unequip(category))
		else:
			_state_btn("✓ Équipé")
	else:
		primary(_detail, "Équiper", func(): cm.equip(id))


func _state_btn(t: String) -> void:
	var b := ghost(_detail, t, func(): pass)
	b.disabled = true


func _aura_tuning() -> void:
	section(_detail, "Réglages de l'aura")
	slider(_detail, "Densité", cm.aura_density, 0.3, 2.0, 0.1, func(x: float):
		cm.aura_density = x
		_debounce_save(), "%.1f×")
	var h := field(_detail, "Couleur", 150)
	var cp := ColorPickerButton.new()
	cp.color = Color(cm.aura_tint) if cm.aura_tint != "" else Color(CosmeticFX.colors_of(cm.params_of("aura"), Color.WHITE)[0])
	cp.edit_alpha = false
	cp.custom_minimum_size = Vector2(70, 30)
	cp.color_changed.connect(func(c: Color):
		cm.aura_tint = "#" + c.to_html(false)
		_debounce_save())
	h.add_child(cp)
	icon_btn(h, "↺", func(): cm.set_aura_tuning(cm.aura_density, ""), "Couleurs d'origine")


var _save_timer: SceneTreeTimer


## Les curseurs changent souvent : on applique après un court délai.
func _debounce_save() -> void:
	_update_preview()
	_save_timer = get_tree().create_timer(0.35)
	var t := _save_timer
	t.timeout.connect(func():
		if t == _save_timer and is_instance_valid(self):
			cm.set_aura_tuning(cm.aura_density, cm.aura_tint))


func _build_presets() -> void:
	for c in _presets.get_children():
		c.queue_free()
	if cm.presets.is_empty():
		dim(_presets, "Aucune tenue sauvegardée.")
		return
	for i in cm.presets.size():
		var idx: int = i
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 0)
		_presets.add_child(h)
		var pb := chip(h, str(cm.presets[i].name), func(): cm.apply_preset(idx))
		pb.tooltip_text = "Porter cette tenue"
		icon_btn(h, "✕", func(): cm.delete_preset(idx), "Supprimer la tenue")


func _on_purchase(_id: String, _ok: bool, message: String) -> void:
	_message = message
	_build_detail()

# ------------------------------------------------------------------ aperçu 3D

func _build_preview(parent: Control) -> void:
	var box := PanelContainer.new()
	box.theme_type_variation = "Card"
	box.custom_minimum_size = Vector2(440, 0)
	parent.add_child(box)
	var v := VBoxContainer.new()
	box.add_child(v)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.custom_minimum_size = Vector2(400, 560)
	svc.gui_input.connect(_on_preview_input)
	svc.mouse_default_cursor_shape = Control.CURSOR_DRAG
	v.add_child(svc)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	svc.add_child(viewport)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = KWTheme.SURFACE.darkened(0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	we.environment = env
	viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, 205, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	viewport.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.2, 2.2, 1.4)
	rim.light_color = KWTheme.ACCENT
	rim.light_energy = 2.0
	rim.omni_range = 5.0
	viewport.add_child(rim)
	var floor_mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.15
	cyl.height = 0.06
	floor_mi.mesh = cyl
	var fm := StandardMaterial3D.new()
	fm.albedo_color = KWTheme.SURFACE_3
	fm.roughness = 0.6
	floor_mi.material_override = fm
	floor_mi.position.y = -0.03
	viewport.add_child(floor_mi)
	_turn = Node3D.new()
	_turn.rotation.y = PI + 0.5
	viewport.add_child(_turn)
	preview_avatar = KWAvatar.new()
	_turn.add_child(preview_avatar)
	_fx_root = Node3D.new()
	viewport.add_child(_fx_root)
	var cam := Camera3D.new()
	cam.fov = 38
	cam.position = Vector3(0, 1.25, 4.6)
	cam.rotation_degrees.x = -6
	viewport.add_child(cam)
	cam.current = true
	var hint := Label.new()
	hint.text = "Glisser pour tourner"
	hint.theme_type_variation = "Dim"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


func _on_preview_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		_drag = ev.pressed
	elif ev is InputEventMouseMotion and _drag:
		_turn.rotation.y += ev.relative.x * 0.01
		_spin = 0.0


func _process(delta: float) -> void:
	if _turn == null:
		return
	_spin = minf(_spin + delta, 3.0)
	if not _drag and _spin >= 2.0:
		_turn.rotation.y += delta * 0.35
	if preview_avatar:
		preview_avatar.speed = 2.6 if category == "trail" else 0.0


## Équipement d'essai : l'équipement courant + l'item sélectionné dans chaque catégorie visitée.
func preview_equip() -> Dictionary:
	var eq: Dictionary = cm.equipped.duplicate()
	eq[category] = selected.get(category, eq.get(category, ""))
	return eq


func _update_preview() -> void:
	if preview_avatar == null:
		return
	var eq := preview_equip()
	preview_avatar.apply_look(cm.look(eq))
	for c in _fx_root.get_children():
		c.queue_free()
	var aura: Dictionary = cm.item(str(eq.get("aura", ""))).get("params", {})
	if not aura.is_empty():
		var same: bool = eq.get("aura", "") == cm.get_equipped("aura")
		var tint := Color(cm.aura_tint) if same and cm.aura_tint != "" else Color(0, 0, 0, 0)
		var a := CosmeticFX.make_aura(aura, tint, cm.aura_density if same else 1.0)
		a.position = Vector3(0, 1.0, 0)
		_fx_root.add_child(a)
	if category == "trail":
		var tp: Dictionary = cm.item(str(eq.get("trail", ""))).get("params", {})
		if not tp.is_empty():
			var t := CosmeticFX.make_trail(tp)
			var pm := t.process_material as ParticleProcessMaterial
			pm.direction = Vector3(0, 0.5, 1) # le sol « défile » vers l'arrière
			pm.spread = 25.0
			pm.initial_velocity_min = 0.5
			pm.initial_velocity_max = 0.9
			t.emitting = true
			t.position = Vector3(0, 0.05, 0)
			_fx_root.add_child(t)
	if category == "portal":
		_fx_root.add_child(_portal_preview(cm.item(str(eq.get("portal", ""))).get("params", {})))


## Arche de passage derrière l'avatar, avec les émissions du style choisi.
func _portal_preview(params: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0, 0, -1.3)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = KWTheme.SURFACE_3.lightened(0.15)
	for x in [-0.75, 0.75]:
		var post := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.12, 2.2, 0.12)
		post.mesh = b
		post.material_override = fm
		post.position = Vector3(x, 1.1, 0)
		root.add_child(post)
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(1.62, 0.12, 0.12)
	top.mesh = tb
	top.material_override = fm
	top.position = Vector3(0, 2.2, 0)
	root.add_child(top)
	var e := GPUParticles3D.new()
	e.amount = 70
	e.lifetime = 4.0
	e.local_coords = false
	e.visibility_aabb = AABB(Vector3(-2, -0.5, -1), Vector3(4, 4, 5))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.6, 0.95, 0.02)
	pm.emission_shape_offset = Vector3(0, 1.05, 0.05)
	pm.direction = Vector3(0, 0.25, 1)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.08
	pm.initial_velocity_max = 0.35
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	e.process_material = pm
	CosmeticFX.style_portal(e, pm, params, KWTheme.ACCENT, 1.0, 0.035)
	root.add_child(e)
	return root

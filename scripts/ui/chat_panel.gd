class_name ChatPanel
extends KWPanel
## Bureau : messagerie avec l'assistant contextuel (Ollama local ou assistant simulé).
## L'IA propose, l'utilisateur valide. La conversation vit dans l'objet bureau
## (Assistant persiste la réponse même si le panneau est fermé pendant la génération).

const SCOPES := [["Salle", "room"], ["Portail", "portal"], ["Global", "global"]]
const SUGGESTIONS := [["Synthèse", "Fais une synthèse de ce contexte."],
	["Questions", "Quelles questions complémentaires faudrait-il se poser ?"],
	["Connexions", "Quelles connexions vois-tu avec le reste du monde ?"],
	["Plan Kanban", "Propose un plan Kanban avec des tâches concrètes."]]
const BUBBLE_MAX := 600.0
const C_USER := Color("#3d6fa8")
const C_BOT := Color(0.17, 0.19, 0.23)
const C_ERR := Color(0.38, 0.17, 0.17)
const C_CARD := Color(0.22, 0.26, 0.21)
const KIND_LABEL := {"note": "Créer la note", "kanban": "Créer le Kanban", "room": "Créer la salle", "relation": "Relier à la salle"}
static var last_scope := 0

var id: String
var models: OptionButton
var scope: OptionButton
var temp: SpinBox
var status_dot: Label
var scroll: ScrollContainer
var list: VBoxContainer
var stream_label: RichTextLabel
var thinking: Label
var stop_btn: Button
var send_btn: Button
var input: TextEdit
var sugg_box: HFlowContainer
var _dots := 0.0


func _init(obj_id: String) -> void:
	id = obj_id
	super("Bureau · Assistant", Vector2(980, 720))
	# En-tête : fournisseur / modèle, périmètre, température.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	body.add_child(top)
	status_dot = Label.new()
	top.add_child(status_dot)
	models = OptionButton.new()
	models.custom_minimum_size.x = 260
	models.tooltip_text = "Fournisseur / modèle (mémorisé)"
	models.item_selected.connect(_on_model_selected)
	top.add_child(models)
	var refresh := _small_btn(top, "↻", Assistant.detect)
	refresh.tooltip_text = "Détecter Ollama à nouveau"
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_muted(top, "Périmètre")
	scope = OptionButton.new()
	for s in SCOPES:
		scope.add_item(s[0])
	scope.select(last_scope)
	scope.item_selected.connect(func(i: int): last_scope = i)
	top.add_child(scope)
	_muted(top, "Température")
	temp = SpinBox.new()
	temp.min_value = 0.0
	temp.max_value = 1.5
	temp.step = 0.1
	temp.value = float(Assistant.cfg.get("temperature", 0.6))
	temp.value_changed.connect(func(v: float): Assistant.set_temperature(v))
	top.add_child(temp)
	# Fil de messages.
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.10, 0.12, 0.6)
	bg.set_corner_radius_all(10)
	bg.set_content_margin_all(12)
	scroll.add_theme_stylebox_override("panel", bg)
	body.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_child(list)
	scroll.add_child(pad)
	# Indicateur + Stop.
	var st := HBoxContainer.new()
	body.add_child(st)
	thinking = _muted(st, "")
	thinking.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stop_btn = _small_btn(st, "■ Stop", Assistant.stop)
	# Suggestions rapides.
	sugg_box = HFlowContainer.new()
	sugg_box.add_theme_constant_override("h_separation", 6)
	body.add_child(sugg_box)
	for s in SUGGESTIONS:
		var q: String = s[1]
		_small_btn(sugg_box, s[0], func(): _ask(q))
	# Saisie multi-ligne : Entrée = envoyer, Maj+Entrée = nouvelle ligne.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	input = TextEdit.new()
	input.placeholder_text = "Écrivez à l'assistant…  (Entrée : envoyer · Maj+Entrée : nouvelle ligne)"
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.custom_minimum_size = Vector2(0, 64)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.gui_input.connect(_on_input_key)
	row.add_child(input)
	send_btn = Button.new()
	send_btn.text = "Envoyer"
	send_btn.custom_minimum_size.x = 110
	send_btn.pressed.connect(_send)
	row.add_child(send_btn)
	# Actions de conversation.
	var acts := HBoxContainer.new()
	body.add_child(acts)
	_small_btn(acts, "Conversation → Note", _conversation_to_note)
	_small_btn(acts, "Effacer", _clear)
	var hint := _muted(acts, "  L'assistant propose, vous validez.")
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Assistant.reply_ready.connect(_on_reply)
	Assistant.reply_chunk.connect(_on_chunk)
	Assistant.busy_changed.connect(_on_busy)
	Assistant.provider_changed.connect(_refresh_models)
	_refresh_models()
	_render()


func _ready() -> void:
	super()
	input.grab_focus()
	_scroll_bottom()


func _exit_tree() -> void:
	for s in [[Assistant.reply_ready, _on_reply], [Assistant.reply_chunk, _on_chunk],
			[Assistant.busy_changed, _on_busy], [Assistant.provider_changed, _refresh_models]]:
		if s[0].is_connected(s[1]):
			s[0].disconnect(s[1])


func _process(delta: float) -> void:
	if not Assistant.is_busy():
		return
	_dots = fmod(_dots + delta * 2.5, 4.0)
	var base := "Réfléchit" if Assistant.partial == "" else "Écrit"
	thinking.text = "  " + base + ".".repeat(int(_dots))


# --- En-tête -----------------------------------------------------------------

func _refresh_models() -> void:
	if not is_instance_valid(models):
		return
	models.clear()
	models.add_item("Assistant simulé (sans IA)")
	var sel := 0
	if Assistant.ollama_ok:
		var names: Array = Assistant.ollama.model_names()
		for i in names.size():
			models.add_item("Ollama · " + names[i])
			if Assistant.provider == Assistant.ollama and names[i] == Assistant.ollama.model:
				sel = i + 1
	models.select(sel)
	var on: bool = Assistant.provider == Assistant.ollama
	status_dot.text = "●"
	status_dot.add_theme_color_override("font_color", Color("#5fd38a") if on else Color("#9aa3ad"))
	status_dot.tooltip_text = "IA locale Ollama active" if on else ("Détection d'Ollama…" if Assistant.detecting else "Ollama non détecté : assistant simulé")
	temp.editable = on


func _on_model_selected(i: int) -> void:
	Assistant.set_model("" if i == 0 else Assistant.ollama.model_names()[i - 1])


# --- Rendu -------------------------------------------------------------------

func _messages() -> Array:
	var o = World.data.objects.get(id)
	return o.content.get("messages", []) if o != null else []


func _render() -> void:
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	stream_label = null
	var msgs := _messages()
	if msgs.is_empty() and not Assistant.is_busy(id):
		var empty := _muted(list, "Posez une question sur cette salle, ce portail ou tout votre monde.\nL'assistant s'appuie sur vos notes et documents.")
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for i in msgs.size():
		_add_message(i, msgs[i])
	if Assistant.is_busy(id):
		stream_label = _bubble(false, Assistant.partial if Assistant.partial != "" else "…", C_BOT, true)
	_update_busy_ui()
	_scroll_bottom()


func _add_message(i: int, m: Dictionary) -> void:
	var user: bool = m.get("role", "") == "user"
	var err: bool = m.get("error", false)
	var text := str(m.get("text", ""))
	var rtl := _bubble(user, text, C_USER if user else (C_ERR if err else C_BOT))
	if user:
		return
	var box: VBoxContainer = rtl.get_parent().get_parent()
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	box.add_child(tools)
	if m.has("by"):
		_muted(tools, str(m.by), 12)
	if not err and text.strip_edges() != "":
		var b := _small_btn(tools, "→ Note", func():
			Assistant.apply_proposal({"kind": "note", "name": "Assistant · " + text.get_slice("\n", 0).left(40), "text": text}, _room())
			_toast("Note créée à partir de la réponse."))
		b.flat = true
		var cp := _small_btn(tools, "Copier", func(): DisplayServer.clipboard_set(text))
		cp.flat = true
	var props: Array = m.get("proposals", [])
	for j in props.size():
		var p: Dictionary = props[j]
		var state: String = p.get("state", "pending")
		if state == "ignored":
			continue
		box.add_child(_proposal_card(i, j, p, state))


func _proposal_card(i: int, j: int, p: Dictionary, state: String) -> Control:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	card.add_child(h)
	var label: String = KIND_LABEL.get(p.get("kind", ""), "Appliquer")
	var detail := ""
	if p.get("kind") == "kanban":
		detail = " (%d cartes)" % p.get("cards", []).size()
	var l := Label.new()
	l.text = ("✓ " if state == "done" else "") + "%s « %s »%s" % [label, p.get("name", ""), detail]
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if p.get("kind") == "note":
		l.tooltip_text = str(p.get("text", "")).left(600)
	h.add_child(l)
	if state == "pending":
		_small_btn(h, "Valider", func():
			Assistant.resolve_proposal(id, i, j, true)
			_toast("Validé : %s « %s »" % [label, p.get("name", "")])
			_render.call_deferred())
		_small_btn(h, "Ignorer", func():
			Assistant.resolve_proposal(id, i, j, false)
			_render.call_deferred())
	else:
		l.modulate = Color(1, 1, 1, 0.6)
	return card


## Crée une bulle et renvoie son RichTextLabel (grand-parent = colonne VBox).
func _bubble(user: bool, text: String, color: Color, streaming := false) -> RichTextLabel:
	var row := HBoxContainer.new()
	list.add_child(row)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(14)
	if user:
		sb.corner_radius_bottom_right = 4
	else:
		sb.corner_radius_bottom_left = 4
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", sb)
	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.selection_enabled = true
	rtl.context_menu_enabled = true
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rtl.text = _to_bbcode(text)
	rtl.custom_minimum_size.x = BUBBLE_MAX if streaming else _text_width(rtl, text)
	panel.add_child(rtl)
	col.add_child(panel)
	if user:
		row.add_child(spacer)
		row.add_child(col)
	else:
		row.add_child(col)
		row.add_child(spacer)
	return rtl


func _text_width(ctrl: Control, text: String) -> float:
	var font := ctrl.get_theme_default_font()
	var fs := ctrl.get_theme_default_font_size()
	var w := 40.0
	for ln in text.split("\n"):
		w = maxf(w, font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12.0)
	return minf(w, BUBBLE_MAX)


## Markdown léger → BBCode, en échappant le texte du modèle.
static func _to_bbcode(text: String) -> String:
	var t := text.replace("[", "[lb]")
	var re := RegEx.new()
	re.compile("\\*\\*(.+?)\\*\\*")
	t = re.sub(t, "[b]$1[/b]", true)
	re.compile("`([^`\\n]+)`")
	t = re.sub(t, "[code]$1[/code]", true)
	re.compile("(?m)^#{1,4}\\s*(.+)$")
	t = re.sub(t, "[b]$1[/b]", true)
	re.compile("(?m)^\\s*[-*]\\s+")
	t = re.sub(t, "  • ", true)
	return t


func _scroll_bottom() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if is_instance_valid(scroll) and scroll.is_inside_tree():
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _update_busy_ui() -> void:
	var busy: bool = Assistant.is_busy()
	stop_btn.visible = Assistant.is_busy(id)
	send_btn.disabled = busy
	for b in sugg_box.get_children():
		(b as Button).disabled = busy
	if not busy:
		thinking.text = ""
	elif not Assistant.is_busy(id):
		thinking.text = "  L'assistant répond sur un autre bureau…"


# --- Événements --------------------------------------------------------------

func _on_input_key(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER) and not e.shift_pressed:
		input.accept_event()
		_send()


func _send() -> void:
	var q := input.text.strip_edges()
	if q == "" or Assistant.is_busy():
		return
	input.text = ""
	_ask(q)


func _ask(q: String) -> void:
	if Assistant.is_busy():
		return
	Assistant.ask(id, _room(), q, SCOPES[scope.selected][1])
	_render()


func _on_chunk(desk_id: String, text: String) -> void:
	if desk_id != id or not is_instance_valid(stream_label):
		return
	stream_label.text = _to_bbcode(text)
	_scroll_bottom()


func _on_busy(_desk_id: String, _busy: bool) -> void:
	_update_busy_ui()


func _on_reply(desk_id: String, _res: Dictionary) -> void:
	if desk_id == id:
		_render()


func _room() -> String:
	var o = World.data.objects.get(id)
	if o != null and o.get("room_id", "") != "":
		return o.room_id
	return main.current_room if main != null else ""


func _conversation_to_note() -> void:
	if _messages().is_empty():
		return
	World.transform("conversation_to_note", id)
	_toast("Note créée à partir de la conversation.")


func _clear() -> void:
	if Assistant.is_busy(id):
		Assistant.stop()
	World.update_object(id, {"content": {"messages": []}})
	_render()


func _toast(msg: String) -> void:
	if main != null and "hud" in main and main.hud != null:
		main.hud.toast(msg)


# --- Petits helpers locaux (indépendants du thème) ---------------------------

func _small_btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _muted(parent: Control, text: String, size := 14) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if text.length() > 40 else TextServer.AUTOWRAP_OFF
	l.add_theme_font_size_override("font_size", size)
	l.modulate = Color(1, 1, 1, 0.6)
	parent.add_child(l)
	return l

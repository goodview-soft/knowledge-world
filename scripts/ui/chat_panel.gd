class_name ChatPanel
extends KWPanel
## Bureau : discussion avec l'assistant contextuel. L'IA propose, l'utilisateur valide.

const SCOPES := [["Salle", "room"], ["Portail", "portal"], ["Global", "global"]]
var id: String
var log_view: RichTextLabel
var input: LineEdit
var scope: OptionButton
var proposals_box: HFlowContainer


func _init(obj_id: String) -> void:
	id = obj_id
	super("Bureau · Assistant", Vector2(960, 680))
	var top := hbox(body)
	var info := lbl(top, "Fournisseur : %s — l'assistant propose, vous validez." % Assistant.provider_name(), 15)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl(top, "Périmètre :")
	scope = OptionButton.new()
	for s in SCOPES:
		scope.add_item(s[0])
	top.add_child(scope)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.selection_enabled = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(log_view)
	proposals_box = HFlowContainer.new()
	body.add_child(proposals_box)
	var row := hbox(body)
	input = line(row, "", "Demandez : synthèse, questions, connexions, plan kanban, nouvelle salle : <nom>…")
	input.text_submitted.connect(func(_t): _send())
	btn(row, "Envoyer", _send)
	var acts := hbox(body)
	btn(acts, "Conversation → Note", func():
		World.transform("conversation_to_note", id)
		main.hud.toast("Note créée à partir de la conversation."))
	btn(acts, "Effacer la conversation", func():
		World.update_object(id, {"content": {"messages": []}})
		_render())
	Assistant.reply_ready.connect(_on_reply)
	_render()


func _ready() -> void:
	super()
	input.grab_focus()


func _render() -> void:
	var o = World.data.objects.get(id)
	if o == null:
		return
	log_view.clear()
	for m in o.content.get("messages", []):
		var who := "[b]Vous[/b]" if m.role == "user" else "[color=#9fc5e8][b]Assistant[/b][/color]"
		log_view.append_text("%s : %s\n\n" % [who, str(m.text).replace("[", "[lb]")])


func _send() -> void:
	var q := input.text.strip_edges()
	if q == "":
		return
	input.clear()
	for c in proposals_box.get_children():
		c.queue_free()
	Assistant.ask(id, main.current_room, q, SCOPES[scope.selected][1])
	_render()


func _on_reply(desk_id: String, res: Dictionary) -> void:
	if desk_id != id:
		return
	_render()
	for p in res.get("proposals", []):
		var label: String = {"note": "Créer la note", "kanban": "Créer le Kanban", "room": "Créer la salle", "relation": "Relier à la salle"}.get(p.kind, "Appliquer")
		var b := btn(proposals_box, "✓ %s « %s »" % [label, p.name], func(): pass)
		b.pressed.connect(func():
			Assistant.apply_proposal(p, main.current_room)
			main.hud.toast("Validé : %s « %s »" % [label, p.name])
			b.queue_free())
	if not res.get("proposals", []).is_empty():
		btn(proposals_box, "✗ Ignorer", func():
			for c in proposals_box.get_children(): c.queue_free())

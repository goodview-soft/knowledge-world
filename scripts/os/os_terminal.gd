class_name OSTerminal
extends OSApp
## Terminal de KW OS : sortie défilante, invite, historique (↑↓, persistant dans
## content.os.term_history), complétion Tab. Logique dans OSShell.

var shell: OSShell
var out: RichTextLabel
var input: LineEdit
var prompt_lbl: Label
var _hist_i := -1
var _asking := false


func _init() -> void:
	super()
	add_theme_constant_override("separation", 0)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["JetBrains Mono", "DejaVu Sans Mono", "Liberation Mono", "Noto Sans Mono", "monospace"])
	var bg := PanelContainer.new()
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg.add_theme_stylebox_override("panel", KWTheme.box(Color("#0a0c10"), 10, Vector4(14, 12, 14, 12), KWTheme.BORDER, 1))
	add_child(bg)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	bg.add_child(v)
	out = RichTextLabel.new()
	out.bbcode_enabled = true
	out.scroll_following = true
	out.selection_enabled = true
	out.context_menu_enabled = true
	out.size_flags_vertical = Control.SIZE_EXPAND_FILL
	out.add_theme_font_override("normal_font", mono)
	out.add_theme_font_size_override("normal_font_size", 15)
	out.add_theme_color_override("default_color", Color("#d6dbe6"))
	out.focus_mode = Control.FOCUS_NONE
	v.add_child(out)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	prompt_lbl = Label.new()
	prompt_lbl.add_theme_font_override("font", mono)
	prompt_lbl.add_theme_font_size_override("font_size", 15)
	prompt_lbl.add_theme_color_override("font_color", KWTheme.ACCENT)
	row.add_child(prompt_lbl)
	input = LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.flat = true
	input.add_theme_font_override("font", mono)
	input.add_theme_font_size_override("font_size", 15)
	input.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	input.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	input.caret_blink = true
	input.keep_editing_on_text_submit = true
	input.text_submitted.connect(func(t: String): submit(t))
	input.gui_input.connect(_on_key)
	row.add_child(input)


func _ready() -> void:
	shell = OSShell.new(current_room())
	if os != null:
		var h = os.get_os_value("term_history", [])
		if h is Array:
			shell.history = h.duplicate()
	_print(OSShell.c("KW OS — terminal du monde des connaissances. Tapez ", KWTheme.TEXT_DIM) + OSShell.c("help", KWTheme.ACCENT) + OSShell.c(".", KWTheme.TEXT_DIM))
	_update_prompt()
	input.grab_focus.call_deferred()
	Assistant.reply_ready.connect(_on_reply)


func _exit_tree() -> void:
	if Assistant.reply_ready.is_connected(_on_reply):
		Assistant.reply_ready.disconnect(_on_reply)


func _update_prompt() -> void:
	prompt_lbl.text = shell.prompt()


func _print(bb: String) -> void:
	if bb != "":
		out.append_text(bb + "\n")


## Exécute une ligne comme si elle était tapée ; renvoie la sortie (BBCode).
func submit(line: String) -> String:
	input.text = ""
	_hist_i = -1
	_print(OSShell.c(shell.prompt(), KWTheme.ACCENT) + " " + OSShell.e(line))
	var n := shell.history.size()
	var res := shell.run(line)
	_print(res)
	var a := shell.action
	if a.has("clear"):
		out.clear()
	elif a.has("open"):
		open_ref(a.open)
	elif a.has("goto") and os != null:
		os.go_to_room(a.goto)
	elif a.has("ask"):
		_ask(a.ask)
	_update_prompt()
	if os != null and shell.history.size() != n:
		os.set_os_value("term_history", shell.history.slice(-50))
	return res


func _ask(q: String) -> void:
	if Assistant.is_busy():
		_print(OSShell.c("L'assistant est occupé, réessayez.", KWTheme.DANGER))
		return
	var desk: String = os.id if os != null else ""
	if desk == "":
		return
	_asking = true
	Assistant.ask(desk, shell.cwd, q, "room")


func _on_reply(desk_id: String, res: Dictionary) -> void:
	if not _asking or os == null or desk_id != os.id:
		return
	_asking = false
	_print(OSShell.c("assistant ›", Color("#d7a6ff")) + " " + OSShell.e(str(res.get("text", ""))))
	var props: Array = res.get("proposals", [])
	if not props.is_empty():
		_print(OSShell.c("%d proposition(s) à valider dans l'app Assistant." % props.size(), KWTheme.TEXT_DIM))


func _on_key(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_TAB:
			input.accept_event()
			var r := shell.complete(input.text)
			var opts: Array = r.options
			if opts.size() > 1:
				_print(OSShell.c("  ".join(PackedStringArray(opts.map(func(x): return str(x)))), KWTheme.TEXT_DIM))
			input.text = r.line
			input.caret_column = input.text.length()
		KEY_UP, KEY_DOWN:
			input.accept_event()
			var h := shell.history
			if h.is_empty():
				return
			if e.keycode == KEY_UP:
				_hist_i = h.size() - 1 if _hist_i < 0 else maxi(_hist_i - 1, 0)
			elif _hist_i >= 0:
				_hist_i += 1
				if _hist_i >= h.size():
					_hist_i = -1
			input.text = h[_hist_i] if _hist_i >= 0 else ""
			input.caret_column = input.text.length()
		KEY_L:
			if e.ctrl_pressed:
				input.accept_event()
				out.clear()

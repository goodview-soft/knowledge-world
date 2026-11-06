class_name NoteMarkdown
extends RefCounted
## Markdown (sous-ensemble Obsidian) → BBCode pour RichTextLabel.
## Méta des liens : "wiki:Nom", "task:<n° de ligne>", "tag:nom", ou URL externe.

static var _re_inline: RegEx
static var _re_list: RegEx
static var _re_num: RegEx


static func _init_re() -> void:
	if _re_inline != null:
		return
	_re_inline = RegEx.create_from_string(
		"`[^`\\n]+`|\\[\\[[^\\[\\]\\n]+?\\]\\]|\\[[^\\]\\n]+\\]\\([^)\\s]+\\)|\\*\\*[^*\\n]+?\\*\\*|__[^_\\n]+?__|~~[^~\\n]+?~~|==[^=\\n]+?==" +
		"|(?<![\\w*])\\*[^*\\n]+?\\*(?!\\w)|(?<![\\w])_[^_\\n]+?_(?![\\w])|https?://[^\\s)\\]]+" +
		"|(?<![A-Za-z0-9_&/\\x{00C0}-\\x{024F}#])#" + NoteLinks.TAG_CHARS)
	_re_list = RegEx.create_from_string("^(\\s*)[-*+]\\s+(\\[( |x|X)\\]\\s*)?(.*)$")
	_re_num = RegEx.create_from_string("^(\\s*)(\\d+)[.)]\\s+(.*)$")


static func esc(s: String) -> String:
	return s.replace("[", "[lb]")


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


## Rend une ligne de texte inline (gras, italique, code, liens, tags).
static func inline(s: String, resolver := Callable()) -> String:
	_init_re()
	var out := ""
	var pos := 0
	for m in _re_inline.search_all(s):
		out += esc(s.substr(pos, m.get_start() - pos))
		out += _token(m.get_string(), resolver)
		pos = m.get_end()
	return out + esc(s.substr(pos))


static func _token(t: String, resolver: Callable) -> String:
	var accent := _hex(KWTheme.ACCENT)
	if t.begins_with("`"):
		return "[bgcolor=%s][color=#e8c9a0][code] %s [/code][/color][/bgcolor]" % [_hex(KWTheme.SURFACE_3), esc(t.substr(1, t.length() - 2))]
	if t.begins_with("[["):
		var inner := t.substr(2, t.length() - 4)
		var target := NoteLinks.link_target(inner)
		var shown := inner.get_slice("|", 1).strip_edges() if "|" in inner else inner.strip_edges()
		var ok: bool = resolver.call(target) if resolver.is_valid() else true
		var col := accent if ok else _hex(KWTheme.TEXT_FAINT)
		return "[url=wiki:%s][color=%s]%s[/color][/url]" % [target.uri_encode(), col, esc(shown)]
	if t.begins_with("[") and "](" in t:
		var label := t.substr(1, t.find("](") - 1)
		var url := t.substr(t.find("](") + 2).trim_suffix(")")
		return "[url=%s][color=%s]%s[/color][/url]" % [url, accent, esc(label)]
	if t.begins_with("http"):
		return "[url=%s][color=%s]%s[/color][/url]" % [t, accent, esc(t)]
	if t.begins_with("**") or t.begins_with("__"):
		return "[b]%s[/b]" % inline(t.substr(2, t.length() - 4), resolver)
	if t.begins_with("~~"):
		return "[s][color=%s]%s[/color][/s]" % [_hex(KWTheme.TEXT_DIM), inline(t.substr(2, t.length() - 4), resolver)]
	if t.begins_with("=="):
		return "[bgcolor=#5a4b1e]%s[/bgcolor]" % inline(t.substr(2, t.length() - 4), resolver)
	if t.begins_with("#"):
		return "[url=tag:%s][bgcolor=%s][color=%s] %s [/color][/bgcolor][/url]" % [t.substr(1).to_lower(), _hex(KWTheme.SURFACE_2.blend(Color(KWTheme.ACCENT, 0.2))), accent, esc(t)]
	if t.begins_with("*") or t.begins_with("_"):
		return "[i]%s[/i]" % inline(t.substr(1, t.length() - 2), resolver)
	return esc(t)


## Document complet. resolver(nom) -> bool indique si un lien wiki existe.
static func to_bbcode(text: String, resolver := Callable()) -> String:
	_init_re()
	var lines := text.split("\n")
	var out := PackedStringArray()
	var in_code := false
	var code := PackedStringArray()
	var dim := _hex(KWTheme.TEXT_DIM)
	var faint := _hex(KWTheme.TEXT_FAINT)
	var sizes := [30, 25, 21, 19, 17, 16]
	for i in lines.size():
		var l: String = lines[i]
		var st := l.strip_edges()
		if st.begins_with("```"):
			if in_code:
				out.append("[bgcolor=%s][color=#d6dbe6][code]%s[/code][/color][/bgcolor]" % [_hex(KWTheme.BG), esc("\n".join(code))])
				code.clear()
			in_code = not in_code
			continue
		if in_code:
			code.append("  " + l + "  ")
			continue
		if st == "":
			out.append("")
			continue
		if st in ["---", "***", "___"]:
			out.append("[color=%s]%s[/color]" % [faint, "─".repeat(48)])
			continue
		var h := 0
		while h < st.length() and h < 6 and st[h] == "#":
			h += 1
		if h > 0 and st.length() > h and st[h] == " ":
			var col := "#ffffff" if h <= 2 else _hex(KWTheme.TEXT)
			out.append("[font_size=%d][b][color=%s]%s[/color][/b][/font_size]" % [sizes[h - 1], col, inline(st.substr(h + 1), resolver)])
			continue
		if st.begins_with(">"):
			var q := st.trim_prefix(">").strip_edges()
			out.append("[color=%s]▍[/color] [i][color=%s]%s[/color][/i]" % [_hex(KWTheme.ACCENT), dim, inline(q, resolver)])
			continue
		var m := _re_list.search(l)
		if m:
			var ind := "    ".repeat(m.get_string(1).replace("\t", "  ").length() / 2)
			if m.get_string(2) != "":
				var done := m.get_string(3).to_lower() == "x"
				var box := "[url=task:%d][color=%s]%s[/color][/url]" % [i, _hex(KWTheme.SUCCESS) if done else dim, "☑" if done else "☐"]
				var body := inline(m.get_string(4), resolver)
				if done:
					body = "[s][color=%s]%s[/color][/s]" % [faint, body]
				out.append("%s%s  %s" % [ind, box, body])
			else:
				out.append("%s[color=%s]•[/color]  %s" % [ind, _hex(KWTheme.ACCENT), inline(m.get_string(4), resolver)])
			continue
		m = _re_num.search(l)
		if m:
			var ind2 := "    ".repeat(m.get_string(1).length() / 2)
			out.append("%s[color=%s]%s.[/color]  %s" % [ind2, dim, m.get_string(2), inline(m.get_string(3), resolver)])
			continue
		out.append(inline(l, resolver))
	if in_code:
		out.append("[bgcolor=%s][code]%s[/code][/bgcolor]" % [_hex(KWTheme.BG), esc("\n".join(code))])
	return "\n".join(out)


## Bascule la case à cocher de la ligne n ; renvoie le nouveau texte.
static func toggle_task(text: String, line_no: int) -> String:
	var lines := text.split("\n")
	if line_no < 0 or line_no >= lines.size():
		return text
	var l: String = lines[line_no]
	_init_re()
	var m := _re_list.search(l)
	if m == null or m.get_string(2) == "":
		return text
	var at := m.get_start(2)
	var done := m.get_string(3).to_lower() == "x"
	lines[line_no] = l.substr(0, at) + ("[ ]" if done else "[x]") + l.substr(at + 3)
	return "\n".join(lines)

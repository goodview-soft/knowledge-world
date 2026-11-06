class_name PdfText
extends RefCounted
## Extraction de texte PDF « au mieux » (flux FlateDecode, opérateurs Tj/TJ).
## Suffisant pour des PDF simples ; l'extraction complète est prévue côté backend RAG.

static func extract(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	var out := PackedStringArray()
	var re := RegEx.new()
	re.compile("\\[((?:[^\\]\\\\]|\\\\.)*)\\]\\s*TJ|\\(((?:[^()\\\\]|\\\\.)*)\\)\\s*(?:Tj|'|\")|(T\\*|\\bTd\\b|\\bTD\\b|\\bET\\b)")
	var inner := RegEx.new()
	inner.compile("\\(((?:[^()\\\\]|\\\\.)*)\\)|(-?\\d+\\.?\\d*)")
	var from := 0
	while true:
		var s := _find(bytes, "stream", from)
		if s < 0:
			break
		var e := _find(bytes, "endstream", s + 6)
		if e < 0:
			break
		var dict := bytes.slice(maxi(0, s - 300), s).get_string_from_ascii()
		from = e + 9
		if not "FlateDecode" in dict or "/Image" in dict:
			continue
		var start := s + 6
		if start < bytes.size() and bytes[start] == 13:
			start += 1
		if start < bytes.size() and bytes[start] == 10:
			start += 1
		var raw := bytes.slice(start, e).decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
		if raw.is_empty():
			continue
		var content := raw.get_string_from_ascii()
		var line := ""
		for m in re.search_all(content):
			if m.get_string(3) != "":
				if line.strip_edges() != "":
					out.append(line.strip_edges())
				line = ""
			elif m.get_start(2) >= 0:
				line += _unescape(m.get_string(2))
			else:
				for p in inner.search_all(m.get_string(1)):
					if p.get_string(2) != "":
						if float(p.get_string(2)) < -150.0:
							line += " "
					else:
						line += _unescape(p.get_string(1))
		if line.strip_edges() != "":
			out.append(line.strip_edges())
	var txt := "\n".join(out)
	if txt.strip_edges().length() < 10:
		return "(Texte non extractible : PDF scanné ou police encodée. L'extraction complète est prévue via le backend RAG.)"
	return txt


static func _find(bytes: PackedByteArray, word: String, from: int) -> int:
	var w := word.to_ascii_buffer()
	var i := bytes.find(w[0], from)
	while i >= 0 and i + w.size() <= bytes.size():
		if bytes.slice(i, i + w.size()) == w:
			return i
		i = bytes.find(w[0], i + 1)
	return -1


static func _unescape(s: String) -> String:
	var r := ""
	var i := 0
	while i < s.length():
		var c := s[i]
		if c == "\\" and i + 1 < s.length():
			var n := s[i + 1]
			i += 2
			match n:
				"n": r += "\n"
				"r": pass
				"t": r += " "
				"(", ")", "\\": r += n
				_:
					if n >= "0" and n <= "7":
						var oct := n
						while oct.length() < 3 and i < s.length() and s[i] >= "0" and s[i] <= "7":
							oct += s[i]
							i += 1
						r += char(_oct(oct))
			continue
		r += c
		i += 1
	return r


static func _oct(s: String) -> int:
	var v := 0
	for ch in s:
		v = v * 8 + int(ch)
	return v

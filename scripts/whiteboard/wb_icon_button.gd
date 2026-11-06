class_name WBIconButton
extends Button
## Bouton d'outil plat à icône vectorielle (pas de dépendance aux glyphes de police).

const INK := Color("#1e1e1e")
const INK_ON := Color("#3d3aa8")

var kind := ""
var swatch := ""


func _init(k: String, tip: String, toggle := true, sz := 34) -> void:
	kind = k
	tooltip_text = tip
	toggle_mode = toggle
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(sz, sz)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(8)
		sb.bg_color = {"normal": Color(0, 0, 0, 0), "hover": Color("#f1f0ff"), "pressed": Color("#e0dfff"),
			"hover_pressed": Color("#d6d4ff"), "disabled": Color(0, 0, 0, 0)}[st]
		add_theme_stylebox_override(st, sb)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


func _draw() -> void:
	var c := size / 2.0
	var ink := INK_ON if button_pressed else INK
	if disabled:
		ink = Color(0.6, 0.6, 0.6)
	var P := func(arr: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for v in arr:
			out.append(c + v)
		return out
	match kind:
		"select":
			draw_polyline(P.call([Vector2(-4, -8), Vector2(-4, 6), Vector2(-0.5, 2.5), Vector2(2, 8), Vector2(4, 7), Vector2(1.5, 1.5), Vector2(6, 1.5), Vector2(-4, -8)]), ink, 1.6, true)
		"hand":
			for x in [-4.5, -1.5, 1.5, 4.5]:
				draw_line(c + Vector2(x, -6 + absf(x) * 0.4), c + Vector2(x, 2), ink, 2.2, true)
			draw_polyline(P.call([Vector2(-6, 0), Vector2(-5.5, 5), Vector2(-2, 8), Vector2(3, 8), Vector2(6, 4), Vector2(6, 0)]), ink, 1.8, true)
		"freedraw":
			draw_line(c + Vector2(-4, 4), c + Vector2(5, -5), ink, 4.0, true)
			draw_colored_polygon(P.call([Vector2(-7.5, 7.5), Vector2(-6.2, 3.2), Vector2(-3.2, 6.2)]), ink)
		"line":
			draw_line(c + Vector2(-7, 7), c + Vector2(7, -7), ink, 2.0, true)
		"arrow":
			draw_line(c + Vector2(-7, 7), c + Vector2(7, -7), ink, 2.0, true)
			draw_polyline(P.call([Vector2(0, -7), Vector2(7, -7), Vector2(7, 0)]), ink, 2.0, true)
		"rect":
			draw_rect(Rect2(c - Vector2(7, 6), Vector2(14, 12)), ink, false, 2.0)
		"ellipse":
			draw_arc(c, 7.5, 0, TAU, 32, ink, 2.0, true)
		"diamond":
			draw_polyline(P.call([Vector2(0, -8), Vector2(8, 0), Vector2(0, 8), Vector2(-8, 0), Vector2(0, -8)]), ink, 2.0, true)
		"text":
			draw_line(c + Vector2(-6, -6), c + Vector2(6, -6), ink, 2.2, true)
			draw_line(c + Vector2(0, -6), c + Vector2(0, 7), ink, 2.2, true)
		"note":
			draw_polyline(P.call([Vector2(-7, -7), Vector2(7, -7), Vector2(7, 3), Vector2(3, 7), Vector2(-7, 7), Vector2(-7, -7)]), ink, 1.8, true)
			draw_polyline(P.call([Vector2(3, 7), Vector2(3, 3), Vector2(7, 3)]), ink, 1.8, true)
		"eraser":
			var pts := [Vector2(-7, -3), Vector2(7, -3), Vector2(7, 3), Vector2(-7, 3), Vector2(-7, -3)].map(func(v): return v.rotated(-0.7))
			draw_polyline(P.call(pts), ink, 1.8, true)
			draw_line(c + Vector2(-1, -3).rotated(-0.7), c + Vector2(-1, 3).rotated(-0.7), ink, 1.8, true)
		"swatch":
			var r := Rect2(c - Vector2(9, 9), Vector2(18, 18))
			if swatch == "":
				draw_rect(r, Color.WHITE)
				draw_line(r.position + Vector2(2, 16), r.position + Vector2(16, 2), Color("#e03131"), 1.6, true)
			else:
				draw_rect(r, Color(swatch))
			draw_rect(r, Color(0, 0, 0, 0.18), false, 1.0)
		"w2", "w4", "w8":
			draw_line(c + Vector2(-8, 0), c + Vector2(8, 0), ink, float(kind.substr(1)) * 0.7, true)
		"smooth":
			draw_line(c + Vector2(-8, 4), c + Vector2(8, -4), ink, 1.8, true)
		"rough":
			draw_polyline(P.call([Vector2(-8, 4), Vector2(-4, 1), Vector2(-1, 2.5), Vector2(3, -2), Vector2(5, -1.5), Vector2(8, -4)]), ink, 1.8, true)
			draw_polyline(P.call([Vector2(-8, 5), Vector2(-3, 2.5), Vector2(1, 1), Vector2(4, -1), Vector2(8, -3)]), ink, 1.2, true)
		"fsS", "fsM", "fsL":
			var fs: int = {"fsS": 11, "fsM": 15, "fsL": 20}[kind]
			var f := WBDraw.font()
			var sz := f.get_string_size("A", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(f, c + Vector2(-sz.x / 2.0, f.get_ascent(fs) - sz.y / 2.0), "A", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink)
		"undo", "redo":
			var sx := 1.0 if kind == "undo" else -1.0
			var arc := []
			for i in 13:
				var a := PI + PI * i / 12.0
				arc.append(Vector2(cos(a) * 6.0 * sx, sin(a) * 6.0 + 3.0))
			arc.append(Vector2(6.0 * sx, 6.0))
			draw_polyline(P.call(arc), ink, 1.8, true)
			draw_polyline(P.call([Vector2(-9.0 * sx, 0), Vector2(-6.0 * sx, 3.5), Vector2(-2.5 * sx, 0.5)]), ink, 1.8, true)
		"minus", "plus":
			draw_line(c + Vector2(-6, 0), c + Vector2(6, 0), ink, 1.8, true)
			if kind == "plus":
				draw_line(c + Vector2(0, -6), c + Vector2(0, 6), ink, 1.8, true)
		"fit":
			for s in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				draw_polyline(P.call([Vector2(7, 3) * s, Vector2(7, 7) * s, Vector2(3, 7) * s]), ink, 1.8, true)
		"delete":
			draw_line(c + Vector2(-7, -5), c + Vector2(7, -5), ink, 1.8, true)
			draw_line(c + Vector2(-2, -7), c + Vector2(2, -7), ink, 1.8, true)
			draw_polyline(P.call([Vector2(-5, -5), Vector2(-4, 7), Vector2(4, 7), Vector2(5, -5)]), ink, 1.8, true)
		"duplicate":
			draw_rect(Rect2(c + Vector2(-7, -3), Vector2(10, 10)), ink, false, 1.6)
			draw_polyline(P.call([Vector2(-3, -3), Vector2(-3, -7), Vector2(7, -7), Vector2(7, 3), Vector2(3, 3)]), ink, 1.6, true)

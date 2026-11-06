class_name KWTheme
extends RefCounted
## Thème UI global (appliqué à toute l'interface par Main).

static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.11, 0.12, 0.94)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	t.set_stylebox("panel", "PanelContainer", sb)
	return t

class_name KWItemIcon
extends Control
## Vignette dessinée (Control._draw) d'un type d'objet : silhouette simple et lisible,
## aucune ressource externe, aucun rendu 3D (fiable en headless).

var type := ""


func _init(t := "", min_size := Vector2(56, 56)) -> void:
	type = t
	custom_minimum_size = min_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_type(t: String) -> void:
	type = t
	queue_redraw()


# coordonnées normalisées 0..1 dans le carré centré
var _o := Vector2.ZERO
var _k := 1.0


func _p(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _k


func _r(x: float, y: float, w: float, h: float, c: Color) -> void:
	draw_rect(Rect2(_p(x, y), Vector2(w, h) * _k), c)


func _c(x: float, y: float, rad: float, c: Color) -> void:
	draw_circle(_p(x, y), rad * _k, c)


func _l(x1: float, y1: float, x2: float, y2: float, c: Color, w := 0.04) -> void:
	draw_line(_p(x1, y1), _p(x2, y2), c, maxf(1.0, w * _k), true)


func _poly(pts: Array, c: Color) -> void:
	var pv := PackedVector2Array()
	for q in pts:
		pv.append(_p(q.x, q.y))
	draw_colored_polygon(pv, c)


func _draw() -> void:
	var side := minf(size.x, size.y)
	_k = side
	_o = (size - Vector2(side, side)) / 2.0
	if type == "":
		_l(0.35, 0.5, 0.65, 0.5, Color(1, 1, 1, 0.15), 0.03)
		return
	var wood := Color(0.62, 0.47, 0.33)
	var dark := Color(0.22, 0.23, 0.26)
	var paper := Color(0.95, 0.93, 0.87)
	var fab := Color(0.47, 0.54, 0.6)
	var stone := Color(0.85, 0.83, 0.79)
	var warm := Color(1.0, 0.85, 0.6)
	match type:
		"note":
			_r(0.28, 0.16, 0.44, 0.66, paper)
			for i in 4: _r(0.34, 0.3 + i * 0.1, 0.32 - (i % 2) * 0.1, 0.03, Color(0.4, 0.4, 0.42))
		"postit":
			_r(0.24, 0.24, 0.52, 0.52, Color(1.0, 0.87, 0.42))
			_poly([Vector2(0.6, 0.76), Vector2(0.76, 0.6), Vector2(0.76, 0.76)], Color(0.85, 0.7, 0.3))
		"card":
			_r(0.14, 0.28, 0.72, 0.46, Color.WHITE)
			_r(0.14, 0.28, 0.72, 0.08, Color(0.55, 0.66, 0.95))
			for i in 3: _r(0.2, 0.44 + i * 0.09, 0.5, 0.025, Color(0.5, 0.5, 0.52))
		"whiteboard":
			_r(0.08, 0.2, 0.84, 0.52, dark)
			_r(0.11, 0.23, 0.78, 0.46, Color(0.97, 0.97, 0.97))
			_l(0.2, 0.55, 0.35, 0.35, Color(0.3, 0.5, 0.9))
			_l(0.35, 0.35, 0.5, 0.5, Color(0.3, 0.5, 0.9))
			_c(0.68, 0.42, 0.08, Color(0.95, 0.5, 0.45))
			_l(0.3, 0.72, 0.25, 0.86, dark); _l(0.7, 0.72, 0.75, 0.86, dark)
		"kanban":
			_r(0.06, 0.2, 0.88, 0.6, Color(0.2, 0.22, 0.26))
			for i in 3:
				_r(0.1 + i * 0.28, 0.25, 0.24, 0.5, Color(0.3, 0.33, 0.38))
				for k in 3 - i: _r(0.12 + i * 0.28, 0.3 + k * 0.13, 0.2, 0.09, Color(0.96, 0.92, 0.8))
		"desk":
			_r(0.1, 0.52, 0.8, 0.06, wood)
			_r(0.14, 0.58, 0.05, 0.3, dark); _r(0.81, 0.58, 0.05, 0.3, dark)
			_r(0.3, 0.2, 0.4, 0.28, dark); _r(0.33, 0.23, 0.34, 0.22, Color(0.3, 0.5, 0.7))
			_r(0.47, 0.48, 0.06, 0.04, dark)
		"library", "shelf":
			var frame := wood.darkened(0.15) if type == "library" else dark
			_r(0.2, 0.1, 0.6, 0.8, frame)
			_r(0.24, 0.13, 0.52, 0.74, Color(0.2, 0.16, 0.13) if type == "library" else Color(0, 0, 0, 0.0))
			for k in 4:
				var y := 0.13 + k * 0.19
				_r(0.22, y + 0.16, 0.56, 0.03, wood)
				for b in 5: _r(0.26 + b * 0.09, y + 0.04 + (b % 2) * 0.02, 0.06, 0.12 - (b % 2) * 0.02, Color.from_hsv(fmod(0.08 + b * 0.17 + k * 0.3, 1.0), 0.4, 0.75))
		"table", "big_table":
			_r(0.06, 0.4, 0.88, 0.07, wood if type == "big_table" else Color(0.75, 0.73, 0.69))
			_r(0.14, 0.47, 0.06, 0.38, wood.darkened(0.2)); _r(0.8, 0.47, 0.06, 0.38, wood.darkened(0.2))
		"coffee_table":
			_r(0.1, 0.5, 0.8, 0.06, wood)
			_r(0.18, 0.7, 0.64, 0.04, wood)
			_r(0.16, 0.56, 0.04, 0.26, dark); _r(0.8, 0.56, 0.04, 0.26, dark)
		"lamp":
			_c(0.5, 0.26, 0.22, Color(warm, 0.12))
			_poly([Vector2(0.36, 0.14), Vector2(0.64, 0.14), Vector2(0.7, 0.34), Vector2(0.3, 0.34)], warm)
			_r(0.485, 0.34, 0.03, 0.5, dark)
			_r(0.36, 0.84, 0.28, 0.04, dark)
		"desk_lamp":
			_r(0.28, 0.8, 0.3, 0.05, dark)
			_l(0.42, 0.8, 0.34, 0.5, dark, 0.05); _l(0.34, 0.5, 0.6, 0.32, dark, 0.05)
			_poly([Vector2(0.56, 0.26), Vector2(0.74, 0.22), Vector2(0.82, 0.44), Vector2(0.62, 0.48)], dark.lightened(0.15))
			_c(0.74, 0.5, 0.12, Color(warm, 0.35))
		"door":
			_r(0.28, 0.1, 0.44, 0.8, dark)
			_r(0.33, 0.15, 0.34, 0.75, Color(0.82, 0.78, 0.7))
			_c(0.6, 0.52, 0.03, dark)
		"portal":
			_r(0.2, 0.08, 0.6, 0.84, dark)
			_r(0.27, 0.15, 0.46, 0.77, Color(0.55, 0.65, 1.0))
		"sofa", "armchair":
			var w := 0.84 if type == "sofa" else 0.56
			var x0 := 0.5 - w / 2
			_r(x0 + 0.06, 0.3, w - 0.12, 0.28, fab.darkened(0.1))
			_r(x0, 0.5, w, 0.2, fab)
			_r(x0, 0.4, 0.1, 0.32, fab.lightened(0.05)); _r(x0 + w - 0.1, 0.4, 0.1, 0.32, fab.lightened(0.05))
			if type == "sofa": _l(0.5, 0.52, 0.5, 0.62, fab.darkened(0.25), 0.02)
			_r(x0 + 0.08, 0.7, 0.04, 0.08, wood.darkened(0.3)); _r(x0 + w - 0.12, 0.7, 0.04, 0.08, wood.darkened(0.3))
		"chair":
			_r(0.36, 0.14, 0.05, 0.74, wood); _r(0.36, 0.2, 0.3, 0.12, wood)
			_r(0.36, 0.5, 0.32, 0.06, fab)
			_r(0.62, 0.56, 0.05, 0.32, wood)
		"plant":
			_poly([Vector2(0.34, 0.62), Vector2(0.66, 0.62), Vector2(0.62, 0.88), Vector2(0.38, 0.88)], Color(0.76, 0.47, 0.35))
			for q in [Vector3(0.5, 0.3, 0.16), Vector3(0.36, 0.42, 0.13), Vector3(0.64, 0.42, 0.13), Vector3(0.5, 0.5, 0.12), Vector3(0.42, 0.22, 0.1)]:
				_c(q.x, q.y, q.z, Color(0.3, 0.52, 0.33).lightened(q.y * 0.3))
		"rug":
			_poly([Vector2(0.2, 0.4), Vector2(0.92, 0.4), Vector2(0.8, 0.7), Vector2(0.08, 0.7)], Color(0.82, 0.76, 0.66))
			_poly([Vector2(0.26, 0.45), Vector2(0.82, 0.45), Vector2(0.74, 0.65), Vector2(0.18, 0.65)], Color(0.6, 0.38, 0.32))
		"pouf":
			_r(0.26, 0.42, 0.48, 0.36, Color(0.72, 0.58, 0.42))
			_c(0.5, 0.42, 0.24, Color(0.78, 0.64, 0.48))
			_r(0.26, 0.74, 0.48, 0.05, Color(0.5, 0.38, 0.28))
		"bench":
			_r(0.08, 0.48, 0.84, 0.07, wood)
			_r(0.18, 0.55, 0.05, 0.28, dark); _r(0.77, 0.55, 0.05, 0.28, dark)
		"cushions":
			_c(0.4, 0.58, 0.2, Color(0.82, 0.62, 0.45))
			_c(0.62, 0.48, 0.18, Color(0.5, 0.6, 0.62))
		"wall", "half_wall":
			var h := 0.7 if type == "wall" else 0.34
			_poly([Vector2(0.12, 0.85 - h), Vector2(0.78, 0.85 - h), Vector2(0.88, 0.78 - h), Vector2(0.22, 0.78 - h)], stone.lightened(0.1))
			_r(0.12, 0.85 - h, 0.66, h, stone)
			_poly([Vector2(0.78, 0.85 - h), Vector2(0.88, 0.78 - h), Vector2(0.88, 0.78), Vector2(0.78, 0.85)], stone.darkened(0.15))
			_r(0.12, 0.8, 0.66, 0.05, Color.WHITE if type == "wall" else wood)
		"glass_wall":
			_r(0.12, 0.12, 0.76, 0.76, dark)
			_r(0.16, 0.16, 0.68, 0.68, Color(0.7, 0.88, 0.95, 0.35))
			_l(0.25, 0.6, 0.45, 0.25, Color(1, 1, 1, 0.6), 0.03)
			_l(0.4, 0.7, 0.6, 0.35, Color(1, 1, 1, 0.4), 0.02)
		"column":
			_r(0.3, 0.1, 0.4, 0.07, stone.darkened(0.08)); _r(0.3, 0.83, 0.4, 0.07, stone.darkened(0.08))
			_r(0.38, 0.17, 0.24, 0.66, stone)
			_r(0.43, 0.17, 0.03, 0.66, stone.darkened(0.12)); _r(0.53, 0.17, 0.03, 0.66, stone.darkened(0.12))
		"platform":
			_poly([Vector2(0.08, 0.58), Vector2(0.72, 0.58), Vector2(0.92, 0.48), Vector2(0.28, 0.48)], wood.lightened(0.1))
			_r(0.08, 0.58, 0.64, 0.12, wood.darkened(0.15))
			_poly([Vector2(0.72, 0.58), Vector2(0.92, 0.48), Vector2(0.92, 0.6), Vector2(0.72, 0.7)], wood.darkened(0.3))
		"arch":
			_r(0.14, 0.1, 0.72, 0.8, stone)
			_r(0.32, 0.46, 0.36, 0.44, Color(0.12, 0.13, 0.16))
			_c(0.5, 0.46, 0.18, Color(0.12, 0.13, 0.16))
			_r(0.46, 0.1, 0.08, 0.12, stone.darkened(0.15))
		"railing":
			_r(0.08, 0.3, 0.84, 0.05, wood)
			_r(0.08, 0.3, 0.04, 0.55, dark); _r(0.88, 0.3, 0.04, 0.55, dark)
			for i in 6: _r(0.2 + i * 0.12, 0.35, 0.02, 0.45, dark)
			_r(0.08, 0.76, 0.84, 0.03, dark)
		"ceiling_light":
			_r(0.06, 0.12, 0.88, 0.04, dark)
			_r(0.18, 0.16, 0.64, 0.08, Color(0.95, 0.95, 0.92))
			_poly([Vector2(0.18, 0.24), Vector2(0.82, 0.24), Vector2(0.96, 0.86), Vector2(0.04, 0.86)], Color(warm, 0.18))
		"frame":
			_r(0.14, 0.2, 0.72, 0.58, Color(0.32, 0.24, 0.17))
			_r(0.19, 0.25, 0.62, 0.48, paper)
			_c(0.62, 0.4, 0.09, Color(0.9, 0.6, 0.4))
			_poly([Vector2(0.19, 0.73), Vector2(0.38, 0.45), Vector2(0.55, 0.73)], Color(0.4, 0.55, 0.65))
			_poly([Vector2(0.42, 0.73), Vector2(0.6, 0.55), Vector2(0.81, 0.73)], Color(0.5, 0.65, 0.5))
		"clock":
			_c(0.5, 0.5, 0.36, dark)
			_c(0.5, 0.5, 0.31, paper)
			_l(0.5, 0.5, 0.5, 0.27, dark, 0.035); _l(0.5, 0.5, 0.66, 0.56, dark, 0.045)
			_c(0.5, 0.5, 0.03, dark)
		"vase":
			_c(0.5, 0.64, 0.17, Color(0.42, 0.55, 0.6))
			_r(0.43, 0.38, 0.14, 0.16, Color(0.42, 0.55, 0.6))
			_l(0.48, 0.38, 0.38, 0.16, Color(0.3, 0.45, 0.28), 0.02); _l(0.52, 0.38, 0.62, 0.14, Color(0.3, 0.45, 0.28), 0.02)
			_c(0.38, 0.15, 0.05, Color(0.95, 0.72, 0.55)); _c(0.62, 0.13, 0.05, Color(0.98, 0.82, 0.6))
		"book_stack":
			var cols := [Color(0.55, 0.35, 0.3), Color(0.3, 0.42, 0.55), Color(0.5, 0.55, 0.35), Color(0.65, 0.5, 0.3)]
			for i in 4: _r(0.2 + (i % 2) * 0.05, 0.74 - i * 0.12, 0.56 - (i % 3) * 0.06, 0.11, cols[i])
		"globe":
			_c(0.5, 0.42, 0.26, Color(0.3, 0.5, 0.68))
			_c(0.42, 0.36, 0.08, Color(0.62, 0.68, 0.45)); _c(0.6, 0.5, 0.06, Color(0.62, 0.68, 0.45))
			draw_arc(_p(0.5, 0.42), 0.3 * _k, -1.2, 1.9, 24, Color(0.75, 0.6, 0.35), maxf(1.0, 0.03 * _k), true)
			_r(0.48, 0.7, 0.04, 0.12, wood.darkened(0.3)); _r(0.36, 0.82, 0.28, 0.05, wood.darkened(0.3))
		"sculpture":
			_r(0.3, 0.6, 0.4, 0.3, Color(0.92, 0.91, 0.89))
			draw_arc(_p(0.5, 0.38), 0.15 * _k, 0, TAU, 32, Color(0.66, 0.48, 0.32), maxf(2.0, 0.07 * _k), true)
			_c(0.58, 0.22, 0.06, Color(0.66, 0.48, 0.32))
			_r(0.47, 0.5, 0.06, 0.1, Color(0.66, 0.48, 0.32))
		_:
			_r(0.25, 0.25, 0.5, 0.5, Color(0.6, 0.6, 0.6))

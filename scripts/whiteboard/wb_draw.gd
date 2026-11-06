class_name WBDraw
extends RefCounted
## Dessin partagé des éléments (éditeur, texture 3D, export PNG) : un seul code, même rendu.

const BG := Color("#fbfbf8")
const NOTE := Color("#fff3a6")
const ACCENT := Color("#6965db")


static func font() -> Font:
	return ThemeDB.fallback_font


static func text_size(t: String, fs: int) -> Vector2:
	var f := font()
	var s := f.get_multiline_string_size(t if t != "" else " ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	return Vector2(maxf(s.x, fs * 0.3), maxf(s.y, f.get_height(fs)))


## Tracé « à la main » : rééchantillonne et ajoute un bruit lisse déterministe.
static func roughen(pl: PackedVector2Array, seed: int, amp: float) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := PackedVector2Array()
	var step := 42.0
	var acc := 0.0
	var a := Vector2(rng.randf_range(-amp, amp), rng.randf_range(-amp, amp))
	var b := Vector2(rng.randf_range(-amp, amp), rng.randf_range(-amp, amp))
	for i in pl.size() - 1:
		var p0 := pl[i]
		var p1 := pl[i + 1]
		var l := p0.distance_to(p1)
		var n := maxi(1, int(l / 8.0))
		for k in n:
			out.append(p0.lerp(p1, float(k) / n) + a.lerp(b, smoothstep(0.0, 1.0, acc / step)))
			acc += l / n
			while acc >= step:
				acc -= step
				a = b
				b = Vector2(rng.randf_range(-amp, amp), rng.randf_range(-amp, amp))
	out.append(pl[pl.size() - 1] + a.lerp(b, smoothstep(0.0, 1.0, acc / step)))
	return out


## Polylignes à tracer, en coordonnées monde.
static func strokes(e: Dictionary) -> Array:
	var t: String = e.type
	if t == "text" or t == "note":
		return []
	var base := WBModel.outline(e)
	var out := []
	if base.size() < 2:
		if base.size() == 1:
			out.append(base)
		return out
	var rough: bool = bool(e.rough) and t != "freedraw"
	if rough:
		var amp := clampf(1.0 + float(e.width) * 0.35, 1.0, 4.0)
		out.append(roughen(base, int(e.seed), amp))
		out.append(roughen(base, int(e.seed) + 7919, amp))
	else:
		out.append(base)
	if t == "arrow":
		var tip := base[base.size() - 1]
		var from := base[0]
		for i in range(base.size() - 2, -1, -1):
			if base[i].distance_to(tip) > 1.0:
				from = base[i]
				break
		if from.distance_to(tip) > 1.0:
			var dir := (tip - from).normalized()
			var l := minf(14.0 + float(e.width) * 2.5, from.distance_to(tip) * 0.5)
			out.append(PackedVector2Array([tip - dir.rotated(0.45) * l, tip, tip - dir.rotated(-0.45) * l]))
	return out


static func _map(pl: PackedVector2Array, o: Vector2, z: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pl.size())
	for i in pl.size():
		out[i] = pl[i] * z + o
	return out


static func draw_all(ci: CanvasItem, elements: Array, o: Vector2, z: float, skip_text_id := "") -> void:
	for e in elements:
		draw_element(ci, e, o, z, e.id == skip_text_id)


static func draw_element(ci: CanvasItem, e: Dictionary, o: Vector2, z: float, hide_text := false) -> void:
	var col := Color(str(e.stroke))
	var t: String = e.type
	if t == "text":
		if not hide_text:
			_text(ci, e, Vector2(float(e.x), float(e.y)) * z + o, z, col, -1.0)
		return
	if t == "note":
		var r := Rect2(Vector2(float(e.x), float(e.y)) * z + o, Vector2(float(e.w), float(e.h)) * z)
		ci.draw_rect(Rect2(r.position + Vector2(2, 5) * z, r.size), Color(0, 0, 0, 0.10))
		ci.draw_rect(r, Color(str(e.fill)) if str(e.fill) != "" else NOTE)
		if not hide_text:
			var pad := WBModel.NOTE_PAD * z
			_text(ci, e, r.position + Vector2(pad, pad), z, col, maxf(4.0, r.size.x - pad * 2.0))
		return
	var w := maxf(1.0, float(e.width) * z)
	if t in WBModel.SHAPES and str(e.fill) != "" and absf(float(e.w)) > 1.0 and absf(float(e.h)) > 1.0:
		var poly := _map(WBModel.outline(e), o, z)
		poly.resize(poly.size() - 1)
		ci.draw_colored_polygon(poly, Color(str(e.fill)))
	for pl in strokes(e):
		var sp := _map(pl, o, z)
		if sp.size() >= 2:
			ci.draw_polyline(sp, col, w, true)
			if w >= 3.0:
				ci.draw_circle(sp[0], w / 2.0, col, true, -1.0, true)
				ci.draw_circle(sp[sp.size() - 1], w / 2.0, col, true, -1.0, true)
				if t == "freedraw" and sp.size() < 3000:
					for i in range(1, sp.size() - 1):
						ci.draw_circle(sp[i], w / 2.0, col)
		elif sp.size() == 1:
			ci.draw_circle(sp[0], w / 2.0, col, true, -1.0, true)


static func _text(ci: CanvasItem, e: Dictionary, pos: Vector2, z: float, col: Color, wrap: float) -> void:
	var fsz := roundi(float(e.fs) * z)
	if fsz < 2 or str(e.text) == "":
		return
	var f := font()
	ci.draw_multiline_string(f, pos + Vector2(0, f.get_ascent(fsz)), str(e.text), HORIZONTAL_ALIGNMENT_LEFT, wrap, fsz, -1, col)

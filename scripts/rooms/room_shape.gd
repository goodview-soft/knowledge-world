class_name RoomShape
extends RefCounted
## Forme d'une salle dans le plan XZ, générée depuis ses données (champ optionnel
## `shape`, défaut « rect » = salle historique). Fournit le polygone, les segments de
## murs (portes, fenêtres, find_wall_slot), contains(), un point d'apparition valide,
## la mezzanine (+ escalier) et l'emplacement des fenêtres.

const SHAPES := [["rect", "Rectangle"], ["L", "En L"], ["T", "En T"], ["croix", "Croix"], ["octogone", "Octogone"], ["ronde", "Ronde"], ["alcoves", "Alcôves"]]
const MEZZ_Y := 2.6
const MEZZ_DEPTH := 3.2
const MEZZ_MIN_H := 4.8
const STEP_RUN := 0.3
const STAIR_W := 1.1
const WALL_T := 0.2
static var _cache := {}


static func kind(room: Dictionary) -> String:
	var k := str(room.get("shape", "rect"))
	for s in SHAPES:
		if s[0] == k:
			return k
	return "rect"


static func dims(room: Dictionary) -> Vector3:
	var s: Array = room.get("size", [10.0, 4.0, 10.0])
	return Vector3(float(s[0]), float(s[1]), float(s[2]))


# ------------------------------------------------------------------ polygone & murs

static func polygon(room: Dictionary) -> PackedVector2Array:
	var s := dims(room)
	var k := kind(room)
	var key := "%s|%.3f|%.3f" % [k, s.x, s.z]
	if not _cache.has(key):
		_cache[key] = _make(k, s.x / 2.0, s.z / 2.0)
	return _cache[key]


static func _make(k: String, hw: float, hd: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	match k:
		"L":
			var nx := hw * 0.84
			var nz := hd * 0.84
			p = [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd - nz), Vector2(hw - nx, hd - nz), Vector2(hw - nx, hd), Vector2(-hw, hd)]
		"T":
			var sw := hw * 0.5
			p = [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, 0), Vector2(sw, 0), Vector2(sw, hd), Vector2(-sw, hd), Vector2(-sw, 0), Vector2(-hw, 0)]
		"croix":
			var aw := hw * 0.55
			var ad := hd * 0.55
			p = [Vector2(-aw, -hd), Vector2(aw, -hd), Vector2(aw, -ad), Vector2(hw, -ad), Vector2(hw, ad), Vector2(aw, ad),
				Vector2(aw, hd), Vector2(-aw, hd), Vector2(-aw, ad), Vector2(-hw, ad), Vector2(-hw, -ad), Vector2(-aw, -ad)]
		"octogone":
			var c := 0.3 * minf(hw, hd) * 2.0
			p = [Vector2(-hw + c, -hd), Vector2(hw - c, -hd), Vector2(hw, -hd + c), Vector2(hw, hd - c),
				Vector2(hw - c, hd), Vector2(-hw + c, hd), Vector2(-hw, hd - c), Vector2(-hw, -hd + c)]
		"ronde":
			var n := clampi(roundi(PI * (hw + hd) / 2.6), 12, 32)
			for i in n:
				var a := TAU * (i + 0.5) / n
				p.append(Vector2(hw * sin(a), -hd * cos(a)))
		"alcoves":
			if hw < 4.0:
				return _make("rect", hw, hd)
			var xi := hw - 1.2
			var n := maxi(1, int((2.0 * hd - 2.0) / 4.5))
			var zs := []
			for i in n:
				zs.append(-hd + 2.0 * hd * (i + 0.5) / n)
			p.append(Vector2(-xi, -hd))
			p.append(Vector2(xi, -hd))
			for z in zs:
				p.append_array([Vector2(xi, z - 1.2), Vector2(hw, z - 1.2), Vector2(hw, z + 1.2), Vector2(xi, z + 1.2)])
			p.append(Vector2(xi, hd))
			p.append(Vector2(-xi, hd))
			zs.reverse()
			for z in zs:
				p.append_array([Vector2(-xi, z + 1.2), Vector2(-hw, z + 1.2), Vector2(-hw, z - 1.2), Vector2(-xi, z - 1.2)])
		_:
			p = [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]
	return p


## Segments de murs : {a, b, mid, dir, n (normale vers l'intérieur), len, ext_neg, ext_pos}.
## Repère local d'un mur : x = dir (t ∈ [-len/2, len/2]), z = n ; rotation Y = atan2(n.x, n.y).
static func walls(room: Dictionary) -> Array:
	var poly := polygon(room)
	var key := "w|%s|%d|%.3f|%.3f" % [kind(room), poly.size(), poly[0].x, poly[0].y]
	if _cache.has(key):
		return _cache[key]
	var out := []
	var n := poly.size()
	var area := 0.0
	for i in n:
		area += poly[i].cross(poly[(i + 1) % n])
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var mid := (a + b) / 2.0
		var e := (b - a).normalized()
		var nrm := Vector2(-e.y, e.x)
		if not Geometry2D.is_point_in_polygon(mid + nrm * 0.05, poly):
			nrm = -nrm
		var dir := Vector2(nrm.y, -nrm.x)
		# Prolongement des dalles aux coins saillants (aucun aux coins rentrants).
		var ea := _corner_ext(poly[(i - 1 + n) % n], a, b, area)
		var eb := _corner_ext(a, b, poly[(i + 2) % n], area)
		var a_neg := (a - mid).dot(dir) < 0.0
		out.append({"a": a, "b": b, "mid": mid, "dir": dir, "n": nrm, "len": a.distance_to(b),
			"ext_neg": ea if a_neg else eb, "ext_pos": eb if a_neg else ea, "rot": rad_to_deg(atan2(nrm.x, nrm.y))})
	_cache[key] = out
	return out


static func _corner_ext(p0: Vector2, p1: Vector2, p2: Vector2, area: float) -> float:
	var d1 := (p1 - p0).normalized()
	var d2 := (p2 - p1).normalized()
	if d1.cross(d2) * area <= 0.0:
		return 0.0
	return WALL_T * tan(acos(clampf(d1.dot(d2), -1.0, 1.0)) / 2.0)


static func bounds(room: Dictionary) -> Rect2:
	var s := dims(room)
	return Rect2(-s.x / 2.0, -s.z / 2.0, s.x, s.z)

# ------------------------------------------------------------------ contenance

static func contains(room: Dictionary, p: Vector3, margin := 0.0) -> bool:
	var q := Vector2(p.x, p.z)
	var poly := polygon(room)
	if not Geometry2D.is_point_in_polygon(q, poly):
		return false
	return margin <= 0.0 or boundary_dist(room, p) >= margin


static func boundary_dist(room: Dictionary, p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	var poly := polygon(room)
	var best := INF
	for i in poly.size():
		best = minf(best, Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()]).distance_to(q))
	return best


## Point le plus proche à l'intérieur (au moins `margin` des murs).
static func clamp_inside(room: Dictionary, p: Vector3, margin := 0.5) -> Vector3:
	if contains(room, p, margin):
		return p
	var q := Vector2(p.x, p.z)
	var best := INF
	var bc := Vector2.ZERO
	var bn := Vector2.ZERO
	for w in walls(room):
		var c := Geometry2D.get_closest_point_to_segment(q, w.a, w.b)
		var dd := c.distance_to(q) if Geometry2D.is_point_in_polygon(q, polygon(room)) else c.distance_squared_to(q)
		if dd < best:
			best = dd
			bc = c
			bn = w.n
	var sp := spawn_point(room)
	var cand := bc + bn * (margin + 0.05)
	var target := Vector2(sp.x, sp.z)
	for k in 11:
		var c2 := cand.lerp(target, k / 10.0)
		if contains(room, Vector3(c2.x, 0, c2.y), margin * 0.95):
			return Vector3(c2.x, p.y, c2.y)
	return Vector3(sp.x, p.y, sp.z)


## Point d'apparition valide (historique : près du mur sud, au centre).
static func spawn_point(room: Dictionary) -> Vector3:
	var s := dims(room)
	for c in [Vector3(0, 0.05, s.z / 2.0 - 2.0), Vector3(0, 0.05, 0), Vector3(0, 0.05, s.z / 4.0)]:
		if contains(room, c, 0.8):
			return c
	var best := Vector3(0, 0.05, 0)
	var bd := -1.0
	for i in 9:
		for k in 9:
			var c := Vector3(-s.x / 2.0 + s.x * (i + 0.5) / 9.0, 0.05, -s.z / 2.0 + s.z * (k + 0.5) / 9.0)
			if contains(room, c):
				var dd := boundary_dist(room, c)
				if dd > bd:
					bd = dd
					best = c
	return best


## Intervalles intérieurs le long de la ligne axis=c (axis 0 : x = c → z ; 1 : z = c → x).
static func scanline(room: Dictionary, axis: int, c: float) -> Array:
	var poly := polygon(room)
	var hits := []
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var a0 := a.x if axis == 0 else a.y
		var b0 := b.x if axis == 0 else b.y
		if (a0 <= c and c < b0) or (b0 <= c and c < a0):
			var t := (c - a0) / (b0 - a0)
			hits.append(lerpf(a.y if axis == 0 else a.x, b.y if axis == 0 else b.x, t))
	hits.sort()
	var out := []
	for i in range(0, hits.size() - 1, 2):
		out.append(Vector2(hits[i], hits[i + 1]))
	return out

# ------------------------------------------------------------------ mezzanine

## {} si absente. Sinon {rect (x,z), y, stair (Rect2), dir, x_end, n, sh, gaps{back,left,right}}.
static func mezzanine(room: Dictionary) -> Dictionary:
	var s := dims(room)
	if not bool(room.get("mezzanine", false)) or s.y < MEZZ_MIN_H:
		return {}
	var key := "m|%s|%.2f|%.2f|%s" % [kind(room), s.x, s.z, str(room.get("mezz_side", "droite"))]
	if _cache.has(key):
		return _cache[key]
	var n := ceili(MEZZ_Y / 0.22)
	var run := n * STEP_RUN
	var best := {}
	var bhx := 0.0
	var z0 := -s.z / 2.0
	while z0 <= -s.z / 2.0 + s.z * 0.3:
		var hx := _band_half_width(room, z0, z0 + MEZZ_DEPTH + STAIR_W)
		if hx > bhx + 0.3:
			bhx = hx
			best = {"z0": z0}
		z0 += 0.25
	var out := {}
	if not best.is_empty() and bhx * 2.0 >= run + 1.2:
		var bz: float = best.z0
		var hx := _band_half_width(room, bz, bz + MEZZ_DEPTH)
		var dir := -1.0 if str(room.get("mezz_side", "droite")) == "gauche" else 1.0
		var z1 := bz + MEZZ_DEPTH
		var x_end := dir * bhx
		out = {"rect": Rect2(-hx, bz, hx * 2.0, MEZZ_DEPTH), "y": MEZZ_Y, "n": n, "sh": MEZZ_Y / n, "dir": dir, "x_end": x_end,
			"stair": Rect2(minf(x_end, x_end - dir * run), z1, run, STAIR_W),
			"gaps": {"back": contains(room, Vector3(0, 0, bz - 0.35)), "left": contains(room, Vector3(-hx - 0.35, 0, bz + 1.5)),
				"right": contains(room, Vector3(hx + 0.35, 0, bz + 1.5))}}
	_cache[key] = out
	return out


static func _band_half_width(room: Dictionary, z0: float, z1: float) -> float:
	var s := dims(room)
	var lo := 0.0
	var hi := s.x / 2.0
	for _i in 14:
		var m := (lo + hi) / 2.0
		var ok := true
		for k in 6:
			var z := lerpf(z0, z1, k / 5.0)
			if not (contains(room, Vector3(m, 0, z), 0.04) and contains(room, Vector3(-m, 0, z), 0.04)):
				ok = false
				break
		if ok:
			lo = m
		else:
			hi = m
	return lo


## Zones à garder libres pour les portes (mezzanine + escalier, élargies).
static func reserved(room: Dictionary) -> Array:
	var m := mezzanine(room)
	if m.is_empty():
		return []
	return [(m.rect as Rect2).grow(0.9), (m.stair as Rect2).grow(0.9)]

# ------------------------------------------------------------------ fenêtres

const WINDOW_STYLES := [["aucune", "Aucune"], ["fenetres", "Fenêtres"], ["baies", "Baies vitrées"], ["bandeau", "Bandeau"]]
const WINDOW_WALLS := [["tous", "Tous les murs"], ["nord", "Nord"], ["sud", "Sud"], ["cotes", "Côtés"], ["nord_sud", "Nord + sud"]]


static func _wall_selected(w: Dictionary, which: String) -> bool:
	var nn: Vector2 = w.n
	match which:
		"nord": return nn.y > 0.5
		"sud": return nn.y < -0.5
		"cotes": return absf(nn.x) > 0.5
		"nord_sud": return absf(nn.y) > 0.5
	return true


## Fenêtres : [{wall, t0, t1, y0, y1}] ; évite les objets accrochés près du mur (portes…).
static func window_spans(room: Dictionary, objects: Array = []) -> Array:
	var style := str(room.get("windows", "aucune"))
	var out := []
	if style == "aucune" or (str(room.get("ceiling", "")) == "ouvert" and bool(room.get("parapet", false))):
		return out
	var s := dims(room)
	var which := str(room.get("window_walls", "tous"))
	var width := 1.3
	var spacing := 3.2
	var y0 := 0.9
	var y1 := minf(s.y - 0.6, 2.4)
	match style:
		"baies":
			width = 2.4
			spacing = 3.3
			y0 = 0.06
			y1 = s.y - 0.4
		"bandeau":
			y0 = 1.05
			y1 = minf(1.75, s.y - 0.6)
	var mz := mezzanine(room)
	var ws := walls(room)
	for i in ws.size():
		var w: Dictionary = ws[i]
		if not _wall_selected(w, which):
			continue
		var L: float = w.len
		var blocked := []
		for o in objects:
			var p := World.vec(o.pos)
			var q := Vector2(p.x, p.z) - (w.mid as Vector2)
			var dn := q.dot(w.n)
			var t := q.dot(w.dir)
			if dn > -0.1 and dn < 0.75 and absf(t) < L / 2.0 + 1.0:
				var half: float = ObjectRegistry.get_def(o.type).size.x * World.vec(o.scale).x / 2.0 + 0.35
				blocked.append(Vector2(t - half, t + half))
		var cands := []
		if style == "bandeau":
			if L >= 2.4:
				cands.append(Vector2(-L / 2.0 + 0.6, L / 2.0 - 0.6))
		elif L >= width + 0.9:
			var k := maxi(1, int((L - 0.8) / spacing))
			for j in k:
				var c := (j - (k - 1) / 2.0) * spacing
				cands.append(Vector2(maxf(c - width / 2.0, -L / 2.0 + 0.4), minf(c + width / 2.0, L / 2.0 - 0.4)))
		for c in cands:
			# Découpe du bandeau / rejet des fenêtres par les objets.
			var parts: Array = [c]
			for b in blocked:
				var np := []
				for pc in parts:
					if b.y <= pc.x or b.x >= pc.y:
						np.append(pc)
					elif style == "bandeau":
						if b.x - pc.x > 0.8:
							np.append(Vector2(pc.x, b.x))
						if pc.y - b.y > 0.8:
							np.append(Vector2(b.y, pc.y))
				parts = np
			for pc in parts:
				var top := y1
				if not mz.is_empty():
					var mid2: Vector2 = w.mid + w.dir * ((pc.x + pc.y) / 2.0) + w.n * 0.3
					if (mz.rect as Rect2).grow(0.3).has_point(mid2) and top > MEZZ_Y - 0.35:
						top = minf(top, MEZZ_Y - 0.35)
				if top - y0 > 0.4:
					out.append({"wall": i, "t0": pc.x, "t1": pc.y, "y0": y0, "y1": top})
	return out


## Centres (z) des alcôves (forme « alcoves ») ; x = ±(demi-largeur - 0,6).
static func alcove_centers(room: Dictionary) -> Array:
	var s := dims(room)
	if kind(room) != "alcoves" or s.x < 8.0:
		return []
	var n := maxi(1, int((s.z - 2.0) / 4.5))
	var out := []
	for i in n:
		out.append(-s.z / 2.0 + s.z * (i + 0.5) / n)
	return out

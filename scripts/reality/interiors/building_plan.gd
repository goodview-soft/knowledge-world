class_name BuildingPlan
extends RefCounted
## Plan unique d'un immeuble (source de vérité façade + intérieur), déterministe par graine
## (= id du bâtiment), piloté par data/city/building_patterns.json.
## Repère du plan : x le long de la façade rue (gauche → droite vue de la rue), z = profondeur
## (0 = façade rue, d = façade arrière), y = hauteur depuis le sol de l'étage.
## Façades : front (z=0), right (x=w), back (z=d), left (x=0). Fenêtre : {facade, x (centre le long de la
## façade : x pour front/back, z pour left/right), y (allège), w, h}. Rect = [x, z, w, d].

const PATH := "res://data/city/building_patterns.json"
const FACADES := ["front", "right", "back", "left"]
static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var j = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				_cfg = j
	return _cfg


static func generate(building_id: String, w: float, d: float, floors: int, fh: float, address := "") -> Dictionary:
	var c := cfg()
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(building_id.hash()) + 17
	var cw: float = float(c.corridor_w)
	var cl: float = float(c.core_len)
	var hw: float = float(c.hall_w)
	var pat := _pick_pattern(rng, w, d, c)
	var zs := 0.0
	var rows: Array = []
	var corr: Array = []
	match pat:
		"central", "L":
			zs = snappedf(d * 0.5 - cw * 0.5, 0.1)
			var x1b: float = w - cw if pat == "L" else w
			rows = [{"x0": cl, "x1": w, "z0": 0.0, "z1": zs, "fac": "front"}, {"x0": cl, "x1": x1b, "z0": zs + cw, "z1": d, "fac": "back"}]
			corr = [[cl, zs, w - cl, cw]]
			if pat == "L":
				corr.append([w - cw, zs + cw, cw, d - zs - cw])
		"coursive":
			zs = d - cw
			rows = [{"x0": cl, "x1": w, "z0": 0.0, "z1": zs, "fac": "front"}]
			corr = [[cl, zs, w - cl, cw]]
		_:
			zs = 0.0
			rows = [{"x0": cl, "x1": w, "z0": cw, "z1": d, "fac": "back"}]
			corr = [[cl, 0.0, w - cl, cw]]
	var gallery: bool = pat == "gallery"
	var n: int = ceili(fh * 0.5 / 0.19 - 0.001)
	var tread: float = clampf((cl - 1.2 - 1.3) / float(n), 0.26, 0.3)
	var z0s: float = zs - 1.4
	if z0s < 2.4:
		z0s = 0.0
	if d - (z0s + 3.0) < 2.4:
		z0s = d - 3.0
	var P := {"id": building_id, "address": address, "pattern": pat, "w": w, "d": d, "floors": floors, "fh": fh,
		"entrance": {"x": cl + 1.5, "w": 1.2, "h": 2.3},
		"stair": {"x0": 0.0, "len": cl, "z0": z0s, "w": 3.0, "lane": 1.3, "n": n, "tread": tread, "rise": fh * 0.5 / float(n), "start_x": cl - 1.2},
		"floors_data": [], "apartments": {}, "apartment_ids": [], "rooms": {}, "windows": [],
		"facade_windows": {"front": [], "right": [], "back": [], "left": []}}
	var palette: Array = c.wall_colors
	for f in floors:
		var fd := {"floor": f, "cells": [], "doors": []}
		var cells: Array = fd.cells
		var unit := 0
		# noyau : escalier + locaux ; couloir(s) ; hall au rez-de-chaussée
		_cell(P, fd, "b%s-%d-stair" % [building_id, f], "stair", "Escalier", [0.0, z0s, cl, 3.0], "", [] if fh < 2.8 else [_win("left", z0s + 1.5, fh * 0.5 + 0.1, 1.0, 1.2)])
		if z0s > 2.4:
			_cell(P, fd, "b%s-%d-local-f" % [building_id, f], "local", "Local", [0.0, 0.0, cl, z0s], "", [_win("front", cl * 0.5)] if not gallery else [])
		var bz: float = z0s + 3.0
		if d - bz > 2.4:
			_cell(P, fd, "b%s-%d-local-b" % [building_id, f], "local", "Local", [0.0, bz, cl, d - bz], "", [_win("back", cl * 0.5)])
		var ci := 0
		for cr in corr:
			var cwins: Array = []
			var r: Array = cr
			if ci == 0:
				match pat:
					"central", "L": cwins.append(_win("right", zs + cw * 0.5))
					"coursive": cwins = _strip_windows("back", r, 3.5, -1.0)
					_: cwins = _strip_windows("front", r, 3.5, float(P.entrance.x) if f == 0 else -1.0)
			else:
				cwins.append(_win("back", float(r[0]) + float(r[2]) * 0.5))
			_cell(P, fd, "b%s-%d-corr%d" % [building_id, f, ci], "corridor", "Couloir", r, "", cwins)
			ci += 1
		var x_off := 0.0
		if not gallery and f == 0:
			x_off = hw
			_cell(P, fd, "b%s-0-hall" % building_id, "hall", "Hall", [cl, 0.0, hw, zs], "", [])
			fd.doors.append({"x": cl + hw * 0.5, "z": zs, "w": 1.2, "h": 2.2, "axis": "x"})
			fd.doors.append({"x": cl, "z": clampf(z0s + 0.65, z0s + 0.62, zs - 0.62), "w": 1.2, "h": 2.2, "axis": "z"})
		fd.doors.append({"x": cl, "z": zs + 0.9, "w": 1.2, "h": 2.2, "axis": "z"})
		var ids: Array = []
		for row in rows:
			var rw: Dictionary = row
			var xa: float = float(rw.x0) + (x_off if rw.fac == "front" else 0.0)
			for seg in _segments(rng, float(rw.x1) - xa, c.types):
				unit += 1
				var apt := _apartment(P, rng, fd, f, unit, rw, xa, float(seg[1]), str(seg[0]), palette)
				ids.append(apt.id)
				xa += float(seg[1])
		fd["apartments"] = ids
		P.floors_data.append(fd)
	for fac in FACADES:
		(P.facade_windows[fac] as Array).sort_custom(func(a, b) -> bool: return a.floor < b.floor or (a.floor == b.floor and a.x < b.x))
	return P


static func _pick_pattern(rng: RandomNumberGenerator, w: float, d: float, c: Dictionary) -> String:
	var opts: Array = []
	var tot := 0.0
	for p in c.patterns:
		if w >= float(p.get("min_w", 0)) and d >= float(p.get("min_d", 0)):
			opts.append(p)
			tot += float(p.weight)
	var r := rng.randf() * tot
	for p in opts:
		r -= float(p.weight)
		if r <= 0.0:
			return str(p.id)
	return "gallery"


static func _segments(rng: RandomNumberGenerator, lr: float, types: Dictionary) -> Array:
	var out: Array = []
	var rest := lr
	var guard := 0
	while rest > 0.01 and guard < 8:
		guard += 1
		var opts: Array = []
		for t in ["T1", "T2", "T3"]:
			if float(types[t].min_len) <= rest + 0.001:
				opts.append(t)
		if opts.is_empty():
			if out.is_empty():
				out.append(["T1", rest])
			else:
				out[out.size() - 1][1] = float(out[out.size() - 1][1]) + rest
			break
		var t: String = opts[rng.randi() % opts.size()]
		var ln := minf(rest, float(types[t].min_len) + rng.randf() * 1.5)
		if rest - ln < float(types["T1"].min_len):
			ln = rest
		out.append([t, ln])
		rest -= ln
	return out


static func _win(facade: String, x: float, y := 0.9, w := 1.2, h := 1.4) -> Dictionary:
	return {"facade": facade, "x": snappedf(x, 0.01), "y": y, "w": w, "h": h}


static func _strip_windows(facade: String, r: Array, pitch: float, avoid_x: float) -> Array:
	var out: Array = []
	var n: int = maxi(1, int(float(r[2]) / pitch))
	for i in n:
		var x: float = float(r[0]) + (i + 0.5) * float(r[2]) / float(n)
		if avoid_x >= 0.0 and absf(x - avoid_x) < 2.3:
			continue
		out.append(_win(facade, x))
	return out


## Enregistre une pièce/cellule (et ses fenêtres, avec appartement + pièce) dans le plan.
static func _cell(P: Dictionary, fd: Dictionary, id: String, kind: String, nm: String, rect: Array, apt_id: String, wins: Array, color := "") -> Dictionary:
	var col := color if color != "" else str(cfg().corridor_color)
	var room := {"id": id, "name": nm, "kind": kind, "rect": rect, "windows": wins, "color": col, "floor": int(fd.floor), "apartment_id": apt_id}
	fd.cells.append(room)
	P.rooms[id] = room
	for wn in wins:
		var e: Dictionary = (wn as Dictionary).duplicate()
		e["floor"] = int(fd.floor)
		e["apartment_id"] = apt_id
		e["room_id"] = id
		P.windows.append(e)
		P.facade_windows[str(wn.facade)].append(e)
	return room


static func _apartment(P: Dictionary, rng: RandomNumberGenerator, fd: Dictionary, f: int, unit: int, row: Dictionary, xa: float, ln: float, type: String, palette: Array) -> Dictionary:
	var c := cfg()
	var wc: Dictionary = c.window
	var z0: float = row.z0
	var z1: float = row.z1
	var dd: float = z1 - z0
	var front: bool = row.fac == "front"
	var df: float = minf(float(c.facade_depth), dd - float(c.band_min))
	var bd: float = dd - df
	var fz: float = z0 if front else z1 - df
	var bz: float = z0 + df if front else z0
	var edge_z: float = z1 if front else z0
	var split_z: float = z0 + df if front else z1 - df
	var kw: float = float(c.kitchen_w)
	var bw: float = float(c.bath_w)
	var fw: Array
	var bnd: Array
	match type:
		"T1":
			fw = [["Séjour", "living", ln]]
			bnd = [["Entrée", "entry", ln - bw], ["Salle d'eau", "bath", bw]]
		"T2":
			fw = [["Séjour", "living", ln * 0.55], ["Chambre", "bedroom", ln * 0.45]]
			bnd = [["Cuisine", "kitchen", kw], ["Entrée", "entry", ln - kw - bw], ["Salle d'eau", "bath", bw]]
		_:
			fw = [["Séjour", "living", ln * 0.4], ["Chambre 1", "bedroom", ln * 0.3], ["Chambre 2", "bedroom", ln * 0.3]]
			bnd = [["Cuisine", "kitchen", kw], ["Entrée", "entry", ln - kw - bw], ["Salle d'eau", "bath", bw]]
	if rng.randf() < 0.5:
		fw.reverse()
		bnd.reverse()
	var aid := "%s-%d-%d" % [P.id, f, unit]
	var col := str(palette[rng.randi() % palette.size()])
	var apt := {"id": aid, "building_id": str(P.id), "address": str(P.address), "floor": f, "unit": unit, "type": type, "area_m2": 0.0,
		"rooms": [], "doors": [], "corridor_door": [], "occupants": [], "lights_on": rng.randf() < float(c.ambient_lit)}
	var rooms: Array = []
	var area := 0.0
	for band in 2:
		var specs: Array = fw if band == 0 else bnd
		var x := xa
		var cnt := {}
		for k in specs.size():
			var sp: Array = specs[k]
			var wr: float = float(sp[2]) if k < specs.size() - 1 else xa + ln - x
			var kind: String = sp[1]
			var rid := "%s-%s%d" % [aid, kind, int(cnt.get(kind, 0)) + 1]
			cnt[kind] = int(cnt.get(kind, 0)) + 1
			var rect: Array = [x, fz if band == 0 else bz, wr, df if band == 0 else bd]
			var wins: Array = []
			if band == 0:
				var fac: String = "front" if front else "back"
				if wr >= float(wc.double_min_room):
					wins.append(_win(fac, x + wr * 0.27, float(wc.sill), float(wc.w), float(wc.h)))
					wins.append(_win(fac, x + wr * 0.73, float(wc.sill), float(wc.w), float(wc.h)))
				else:
					wins.append(_win(fac, x + wr * 0.5, float(wc.sill), float(wc.w), float(wc.h)))
			if kind in ["living", "bedroom", "kitchen"] and absf(x + wr - float(P.w)) < 0.01 and float(rect[3]) >= 2.0:
				wins.append(_win("right", float(rect[1]) + float(rect[3]) * 0.5, float(wc.sill), float(wc.w), float(wc.h)))
			var nm: String = sp[0]
			var room := _cell(P, fd, rid, kind, nm, rect, aid, wins, col)
			rooms.append(room)
			area += wr * float(rect[3])
			x += wr
	# portes : pièces de façade -> entrée (sinon pièce du fond la plus recouvrante) ; entrée -> couloir
	var entry: Dictionary = {}
	for r in rooms:
		if r.kind == "entry":
			entry = r
	for r in rooms:
		if float((r.rect as Array)[1]) != fz or r.kind == "entry" or r.kind in ["bath", "kitchen"] and false:
			continue
		if not (r.kind in ["living", "bedroom"]):
			continue
		var best: Dictionary = entry
		var bo := _overlap(r.rect, entry.rect)
		if bo < 1.2:
			for o in rooms:
				if o.kind in ["kitchen", "bath"] and _overlap(r.rect, o.rect) > bo:
					best = o
					bo = _overlap(r.rect, o.rect)
		var lo: float = maxf(float(r.rect[0]), float(best.rect[0]))
		var hi: float = minf(float(r.rect[0]) + float(r.rect[2]), float(best.rect[0]) + float(best.rect[2]))
		apt.doors.append({"x": (lo + hi) * 0.5, "z": split_z, "w": float(c.door_w), "h": float(c.door_h), "axis": "x"})
	var ecx: float = float(entry.rect[0]) + float(entry.rect[2]) * 0.5
	apt.corridor_door = [ecx, edge_z]
	apt.doors.append({"x": ecx, "z": edge_z, "w": float(c.door_w), "h": float(c.door_h), "axis": "x"})
	for dr in apt.doors:
		fd.doors.append(dr)
	apt.area_m2 = snappedf(area, 0.1)
	apt.rooms = rooms
	P.apartments[aid] = apt
	P.apartment_ids.append(aid)
	return apt


static func _overlap(a: Array, b: Array) -> float:
	return minf(float(a[0]) + float(a[2]), float(b[0]) + float(b[2])) - maxf(float(a[0]), float(b[0]))


# --- Requêtes ---

static func window_info(plan: Dictionary, facade: String, index: int) -> Dictionary:
	var l: Array = plan.facade_windows.get(facade, [])
	return l[index] if index >= 0 and index < l.size() else {}


static func windows_of(plan: Dictionary, apartment_id: String) -> Array:
	return (plan.windows as Array).filter(func(wn) -> bool: return wn.apartment_id == apartment_id)


static func room_of_window(plan: Dictionary, win: Dictionary) -> Dictionary:
	return plan.rooms.get(str(win.get("room_id", "")), {})


static func apartment(plan: Dictionary, apartment_id: String) -> Dictionary:
	return plan.apartments.get(apartment_id, {})


## Propriétés complètes de l'appartement ?
static func apartment_ok(a: Dictionary) -> bool:
	for k in ["id", "building_id", "address", "floor", "unit", "type", "area_m2", "rooms", "corridor_door", "occupants", "lights_on"]:
		if not a.has(k):
			return false
	if (a.rooms as Array).is_empty() or (a.corridor_door as Array).size() != 2:
		return false
	for r in a.rooms:
		for k in ["name", "kind", "rect", "windows"]:
			if not r.has(k):
				return false
	return true


## Trajet piéton hall -> dernier étage : points (x, y, z) du plan ; sert à vérifier l'escalier praticable.
static func stair_path(plan: Dictionary) -> Array:
	var s: Dictionary = plan.stair
	var fh: float = plan.fh
	var n: int = s.n
	var rise: float = s.rise
	var tr: float = s.tread
	var out: Array = []
	var za: float = float(s.z0) + float(s.lane) * 0.5
	var zb: float = float(s.z0) + float(s.w) - float(s.lane) * 0.5
	var sx: float = s.start_x
	for f in int(plan.floors) - 1:
		var y0: float = f * fh
		out.append(Vector3(float(s.len) + 0.5, y0, zb))
		out.append(Vector3(sx + 0.5, y0, za))
		for i in n + 1:
			out.append(Vector3(sx - tr * i, y0 + rise * i, za))
		for i in n + 1:
			out.append(Vector3(sx - tr * (n - i), y0 + fh * 0.5 + rise * i, zb))
	return out

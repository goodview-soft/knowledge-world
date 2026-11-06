class_name RoomBuilder
extends RefCounted
## Génère la géométrie d'une salle à partir de ses données. Tous les champs de
## personnalisation sont optionnels (anciennes sauvegardes = salle rectangulaire) :
## couleurs (wall_color, floor_color, ceil_color), floor_mat, wall_mat, light,
## light_energy, shape (RoomShape), ceiling, mezzanine, windows, window_walls, sky,
## horizon, trim, cove, dust, parapet. Aucune salle n'est codée à la main.

const MOOD_COLORS := {"chaude": Color(1.0, 0.86, 0.7), "neutre": Color(1.0, 0.96, 0.9), "froide": Color(0.84, 0.91, 1.0), "tamisee": Color(1.0, 0.76, 0.55)}
const MOOD_ENERGY := {"chaude": 0.8, "neutre": 0.9, "froide": 1.0, "tamisee": 0.4}
## Matériau du sol : rugosité.
const FLOOR_ROUGH := {"bois": 0.55, "beton": 0.35, "moquette": 1.0, "carrelage": 0.25, "marbre": 0.12, "pierre": 0.8, "herbe": 1.0, "uni": 0.6}
const FLOOR_LABELS := [["uni", "Uni"], ["bois", "Parquet"], ["carrelage", "Carrelage"], ["beton", "Béton ciré"], ["moquette", "Moquette"], ["pierre", "Pierre"], ["marbre", "Marbre"], ["herbe", "Herbe"]]
const WALL_ROUGH := {"enduit": 0.95, "bois": 0.6, "brique": 0.9, "beton": 0.85, "marbre": 0.15, "tissu": 1.0, "sombre": 0.5}
const WALL_LABELS := [["enduit", "Enduit"], ["bois", "Panneaux bois"], ["brique", "Brique"], ["beton", "Béton"], ["marbre", "Marbre"], ["tissu", "Tissu acoustique"], ["sombre", "Sombre"]]
const CEILINGS := [["plat", "Plat"], ["voute", "Voûte"], ["coupole", "Coupole"], ["verriere", "Verrière"], ["coupole_vitree", "Coupole vitrée"], ["ouvert", "Ouvert (ciel)"]]
const SKY_LABELS := [["jour", "Jour"], ["coucher", "Coucher de soleil"], ["nuit", "Nuit étoilée"], ["brume", "Brume"], ["espace", "Espace"]]
const HORIZON_LABELS := [["aucun", "Aucun"], ["foret", "Forêt"], ["mer", "Mer"], ["collines", "Collines"]]
## Ciel : couleurs haut/horizon/sol, soleil (élévation°, azimut°, couleur, énergie), étoiles, brume.
const SKIES := {
	"jour": {"top": Color(0.32, 0.52, 0.82), "hor": Color(0.78, 0.86, 0.94), "gnd": Color(0.42, 0.44, 0.42), "elev": 52.0, "az": 25.0, "sun": Color(1.0, 0.95, 0.86), "energy": 1.25, "stars": 0.0, "haze": 0.0, "amb": Color(0.75, 0.82, 0.92), "amb_e": 0.7},
	"coucher": {"top": Color(0.2, 0.24, 0.45), "hor": Color(1.0, 0.6, 0.36), "gnd": Color(0.3, 0.24, 0.24), "elev": 7.0, "az": 20.0, "sun": Color(1.0, 0.62, 0.36), "energy": 1.0, "stars": 0.15, "haze": 0.1, "amb": Color(0.95, 0.72, 0.62), "amb_e": 0.55},
	"nuit": {"top": Color(0.012, 0.02, 0.06), "hor": Color(0.06, 0.09, 0.18), "gnd": Color(0.03, 0.035, 0.05), "elev": 38.0, "az": -30.0, "sun": Color(0.62, 0.72, 1.0), "energy": 0.18, "stars": 1.0, "haze": 0.0, "amb": Color(0.35, 0.42, 0.65), "amb_e": 0.35},
	"brume": {"top": Color(0.62, 0.66, 0.7), "hor": Color(0.82, 0.83, 0.84), "gnd": Color(0.6, 0.62, 0.62), "elev": 30.0, "az": 15.0, "sun": Color(1.0, 0.95, 0.88), "energy": 0.45, "stars": 0.0, "haze": 0.8, "amb": Color(0.82, 0.84, 0.86), "amb_e": 0.7},
	"espace": {"top": Color(0.004, 0.005, 0.012), "hor": Color(0.02, 0.02, 0.05), "gnd": Color(0.004, 0.005, 0.012), "elev": 18.0, "az": 50.0, "sun": Color(1.0, 0.97, 0.92), "energy": 1.1, "stars": 1.4, "haze": 0.0, "amb": Color(0.45, 0.5, 0.7), "amb_e": 0.35},
}
const STYLE_KEYS := ["wall_color", "floor_color", "ceil_color", "floor_mat", "wall_mat", "light", "light_energy", "shape", "ceiling",
	"mezzanine", "mezz_side", "windows", "window_walls", "sky", "horizon", "trim", "cove", "dust", "parapet", "template"]
const SKY_SHADER := """
shader_type sky;
uniform vec3 top_col : source_color;
uniform vec3 hor_col : source_color;
uniform vec3 gnd_col : source_color;
uniform vec3 sun_dir = vec3(0.0, 0.5, 0.8);
uniform vec3 sun_col : source_color;
uniform float stars = 0.0;
uniform float haze = 0.0;
uniform float planet = 0.0;
uniform float ground_stars = 0.0;
float hash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = y > 0.0 ? mix(hor_col, top_col, pow(clamp(y, 0.0, 1.0), 0.45)) : mix(hor_col, gnd_col, clamp(-y * 5.0, 0.0, 1.0));
	vec3 sd = normalize(sun_dir);
	float c = max(dot(d, sd), 0.0);
	col += sun_col * (pow(c, 900.0) * 6.0 + pow(c, 48.0) * 0.35 + pow(c, 6.0) * 0.12) * (1.0 - haze * 0.6);
	if (stars > 0.0 && (y > -0.02 || ground_stars > 0.5)) {
		vec3 q = d * 160.0;
		vec3 id = floor(q);
		float h = hash(id);
		if (h > 0.982) {
			float s = smoothstep(0.5, 0.0, length(fract(q) - 0.5));
			col += vec3(0.85, 0.9, 1.0) * s * stars * (h - 0.982) / 0.018 * 1.6;
		}
		float band = exp(-pow(dot(d, normalize(vec3(0.3, 0.2, 1.0))) * 3.5, 2.0));
		col += vec3(0.08, 0.07, 0.12) * band * stars * (0.6 + 0.4 * hash(floor(d * 40.0)));
	}
	if (planet > 0.0) {
		vec3 pd = normalize(vec3(-0.55, 0.32, -0.75));
		float a = acos(clamp(dot(d, pd), -1.0, 1.0));
		float r = 0.22;
		if (a < r) {
			vec3 side = normalize(d - pd * dot(d, pd));
			float t = a / r;
			float lit = clamp(dot(side * t + pd * sqrt(1.0 - t * t) * 0.3, sd) * 1.4 + 0.25, 0.04, 1.0);
			float bands = 0.5 + 0.5 * sin(d.y * 140.0 + sin(d.x * 30.0) * 2.0);
			vec3 pc = mix(vec3(0.55, 0.42, 0.34), vec3(0.85, 0.72, 0.58), bands);
			col = mix(col, pc * lit, smoothstep(r, r - 0.004, a));
		}
		col += vec3(0.3, 0.45, 0.8) * smoothstep(r + 0.03, r, a) * 0.15;
	}
	col = mix(col, hor_col, haze * (1.0 - abs(y)) * 0.85);
	COLOR = col;
}
"""
static var _tex_cache := {}
static var _sky_shader: Shader
static var _glass_mat: StandardMaterial3D


## Valeurs effectives d'une salle (défauts = salle historique).
static func style_of(room: Dictionary) -> Dictionary:
	var tint := Color(room.get("color", "#cfc8bc"))
	return {
		"wall_color": Color(room.get("wall_color", Color(0.84, 0.82, 0.78).lerp(tint, 0.15).to_html(false))),
		"floor_color": Color(room.get("floor_color", Color(0.36, 0.33, 0.3).lerp(tint, 0.08).to_html(false))),
		"ceil_color": Color(room.get("ceil_color", "#e6e3dc")),
		"floor_mat": str(room.get("floor_mat", "uni")),
		"wall_mat": str(room.get("wall_mat", "enduit")),
		"light": str(room.get("light", "chaude")),
		"light_energy": float(room.get("light_energy", 1.0)),
		"shape": RoomShape.kind(room),
		"ceiling": str(room.get("ceiling", "plat")),
		"windows": str(room.get("windows", "aucune")),
		"window_walls": str(room.get("window_walls", "tous")),
		"sky": str(room.get("sky", "jour")) if SKIES.has(str(room.get("sky", "jour"))) else "jour",
		"horizon": str(room.get("horizon", "aucun")),
		"trim": bool(room.get("trim", true)),
		"cove": bool(room.get("cove", true)),
		"dust": bool(room.get("dust", false)),
		"parapet": bool(room.get("parapet", false)),
		"mezzanine": bool(room.get("mezzanine", false)),
	}


static func light_color(st: Dictionary) -> Color:
	return MOOD_COLORS.get(st.light, MOOD_COLORS.chaude)


static func light_energy(st: Dictionary) -> float:
	return float(MOOD_ENERGY.get(st.light, 0.8)) * float(st.light_energy)


## La salle laisse-t-elle voir l'extérieur (fenêtres, verrière, ciel ouvert) ?
static func has_outside(st: Dictionary) -> bool:
	return st.windows != "aucune" or st.ceiling in ["verriere", "coupole_vitree", "ouvert"]


## Montée du plafond au point (x, z) au-dessus de la hauteur des murs.
static func ceil_rise(st: Dictionary, s: Vector3, x: float, z: float) -> float:
	var hw := s.x / 2.0
	var hd := s.z / 2.0
	match st.ceiling:
		"voute":
			var u := x / hw if s.x <= s.z else z / hd
			return clampf(minf(s.x, s.z) * 0.3, 1.0, 3.5) * sqrt(maxf(0.0, 1.0 - u * u))
		"coupole", "coupole_vitree":
			var r2 := (x / hw) * (x / hw) + (z / hd) * (z / hd)
			return clampf(minf(s.x, s.z) * 0.42, 1.5, 6.0) * sqrt(maxf(0.0, 1.0 - r2))
	return 0.0


## Construit la salle. preview = aperçu de portail (sans soleil ni particules).
static func build(room: Dictionary, is_hub: bool, preview := false) -> Node3D:
	var root := Node3D.new()
	var s := RoomShape.dims(room)
	var w := s.x
	var h := s.y
	var d := s.z
	var st := style_of(room)
	var lc := light_color(st)
	var le := light_energy(st)
	var poly := RoomShape.polygon(room)
	var outside := has_outside(st)
	var wall_m := wall_material(st.wall_mat, st.wall_color)
	var floor_m := floor_material(st.floor_mat, st.floor_color)
	var ceil_m := ObjectRegistry.mat(st.ceil_color, 0.0, 1.0)
	ceil_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Sol : surface exacte du polygone + collision sur le rectangle englobant.
	var fl := MeshInstance3D.new()
	fl.mesh = _flat_mesh(poly, 0.0, true)
	fl.material_override = floor_m
	root.add_child(fl)
	_collider(root, Vector3(w + 0.6, 0.2, d + 0.6), Vector3(0, -0.1, 0))
	# Plafond.
	var ceiling: String = st.ceiling
	match ceiling:
		"plat":
			var c := MeshInstance3D.new()
			c.mesh = _flat_mesh(poly, h, false)
			c.material_override = ceil_m
			root.add_child(c)
			_collider(root, Vector3(w + 0.6, 0.2, d + 0.6), Vector3(0, h + 0.1, 0))
		"voute", "coupole":
			var c := MeshInstance3D.new()
			c.mesh = _curved_mesh(room, st, s)
			c.material_override = ceil_m
			root.add_child(c)
		"verriere":
			var g := MeshInstance3D.new()
			g.mesh = _flat_mesh(poly, h, false)
			g.material_override = glass_material()
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(g)
			_skylight_bars(root, room, h, st.ceil_color.darkened(0.5))
		"coupole_vitree":
			var g := MeshInstance3D.new()
			g.mesh = _curved_mesh(room, st, s)
			g.material_override = glass_material()
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(g)
			_dome_ribs(root, room, st, s)
	# Murs (un nœud par segment, marqué kw_wall : _hide_near_exit des portails).
	var spans := RoomShape.window_spans(room, World.objects_in_room(str(room.get("id", ""))) if room.has("id") else [])
	var ws := RoomShape.walls(room)
	var trim_m := ObjectRegistry.mat(st.wall_color.darkened(0.55), 0.0, 0.6)
	var cove_m := ObjectRegistry.mat(lc, 1.6 * clampf(le / 0.8, 0.2, 2.0))
	for i in ws.size():
		var wd: Dictionary = ws[i]
		var my := spans.filter(func(sp): return sp.wall == i)
		_build_wall(root, wd, st, s, my, wall_m, trim_m, cove_m)
	# Mezzanine + escalier.
	var mz := RoomShape.mezzanine(room)
	if not mz.is_empty():
		_build_mezzanine(root, mz, floor_m, cove_m)
	# Éclairage intérieur : grille de points dans la forme.
	var nx := maxi(1, roundi(w / 7.0))
	var nz := maxi(1, roundi(d / 7.0))
	var day: bool = outside and st.sky in ["jour", "brume"]
	var placed := 0
	for i in nx:
		for k in nz:
			var lp := Vector3(-w / 2 + w / nx * (i + 0.5), h - 0.7, -d / 2 + d / nz * (k + 0.5))
			if not RoomShape.contains(room, lp, 0.3):
				continue
			_omni(root, lp, lc, 0.95 * le * (0.55 if day else 1.0), maxf(w / nx, d / nz) * 1.25 + h * 0.2)
			placed += 1
	if placed == 0:
		var sp := RoomShape.spawn_point(room)
		_omni(root, Vector3(sp.x, h - 0.7, sp.z * 0.5), lc, 0.95 * le, maxf(w, d) * 0.8)
	if is_hub:
		var ring := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 2.6
		cyl.bottom_radius = 2.6
		cyl.height = 0.04
		ring.mesh = cyl
		ring.material_override = ObjectRegistry.mat(st.floor_color.lightened(0.35), 0.0, 0.3)
		ring.position = Vector3(0, 0.02, 1.5)
		root.add_child(ring)
		if ceiling == "plat":
			ObjectRegistry.box(root, Vector3(w * 0.5, 0.02, 0.4), Vector3(0, h - 0.01, 0), ObjectRegistry.mat(lc, 1.2))
	if outside:
		root.add_child(_exterior(room, st, s))
	if st.dust and not preview:
		root.add_child(_dust(s, lc))
	if outside and not preview:
		root.add_child(make_sun(st))
	return root


static func _omni(root: Node3D, p: Vector3, c: Color, e: float, rng: float) -> void:
	var l := OmniLight3D.new()
	l.position = p
	l.light_color = c
	l.light_energy = e
	l.omni_range = rng
	l.omni_attenuation = 0.8
	root.add_child(l)

# ------------------------------------------------------------------ murs

static func _build_wall(root: Node3D, wd: Dictionary, st: Dictionary, s: Vector3, spans: Array, wall_m: Material, trim_m: Material, cove_m: Material) -> void:
	var node := Node3D.new()
	node.set_meta("kw_wall", true)
	var mid: Vector2 = wd.mid
	var nrm: Vector2 = wd.n
	node.position = Vector3(mid.x, 0, mid.y)
	node.rotation.y = atan2(nrm.x, nrm.y)
	root.add_child(node)
	var L: float = wd.len
	var h := s.y
	var t_lo: float = -L / 2.0 - float(wd.ext_neg)
	var t_hi: float = L / 2.0 + float(wd.ext_pos)
	# Hauteur du mur : jusqu'au plafond courbe le plus haut le long du mur.
	var wh := h
	if st.ceiling in ["voute", "coupole", "coupole_vitree"]:
		for k in 11:
			var p2: Vector2 = mid + (wd.dir as Vector2) * lerpf(-L / 2.0, L / 2.0, k / 10.0) + nrm * 0.05
			wh = maxf(wh, h + ceil_rise(st, s, p2.x, p2.y) + 0.05)
	if st.ceiling == "ouvert" and st.parapet:
		_wall_box(node, t_lo, t_hi, 0.0, 1.0, wall_m, true)
		ObjectRegistry.box(node, Vector3(t_hi - t_lo, 0.04, 0.26), Vector3((t_lo + t_hi) / 2.0, 1.02, -0.1), trim_m)
		var g := _wall_box(node, -L / 2.0, L / 2.0, 1.04, 2.2, glass_material(), true, 0.03)
		g.get_child(1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	spans.sort_custom(func(a, b): return a.t0 < b.t0)
	var cur := t_lo
	var frame_m := ObjectRegistry.mat(Color(0.16, 0.17, 0.19), 0.0, 0.4)
	var floor_gaps := []
	for sp in spans:
		var t0: float = sp.t0
		var t1: float = sp.t1
		var y0: float = sp.y0
		var y1: float = sp.y1
		if t0 > cur:
			_wall_box(node, cur, t0, 0.0, wh, wall_m, true)
		if y0 > 0.01:
			_wall_box(node, t0, t1, 0.0, y0, wall_m, true)
		_wall_box(node, t0, t1, y1, wh, wall_m, true)
		var gl := _wall_box(node, t0, t1, y0, y1, glass_material(), true, 0.03)
		gl.get_child(1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Cadre fin et tablette.
		var cx := (t0 + t1) / 2.0
		for fb in [[Vector3(t1 - t0, 0.05, 0.08), Vector3(cx, y0 + 0.025, -0.1)], [Vector3(t1 - t0, 0.05, 0.08), Vector3(cx, y1 - 0.025, -0.1)],
				[Vector3(0.05, y1 - y0, 0.08), Vector3(t0 + 0.025, (y0 + y1) / 2.0, -0.1)], [Vector3(0.05, y1 - y0, 0.08), Vector3(t1 - 0.025, (y0 + y1) / 2.0, -0.1)]]:
			ObjectRegistry.box(node, fb[0], fb[1], frame_m)
		if t1 - t0 > 1.8:
			var nm := int((t1 - t0) / 1.2)
			for m in range(1, nm):
				ObjectRegistry.box(node, Vector3(0.04, y1 - y0, 0.06), Vector3(lerpf(t0, t1, float(m) / nm), (y0 + y1) / 2.0, -0.1), frame_m)
		if y0 > 0.3:
			ObjectRegistry.box(node, Vector3(t1 - t0 + 0.12, 0.03, 0.14), Vector3(cx, y0 - 0.015, 0.05), trim_m)
		else:
			floor_gaps.append(Vector2(t0, t1))
		cur = t1
	if cur < t_hi:
		_wall_box(node, cur, t_hi, 0.0, wh, wall_m, true)
	# Plinthes, corniche, gorge lumineuse.
	if st.trim:
		var segs := [Vector2(-L / 2.0, L / 2.0)]
		for g in floor_gaps:
			var ns := []
			for sg in segs:
				if g.y <= sg.x or g.x >= sg.y:
					ns.append(sg)
				else:
					if g.x > sg.x:
						ns.append(Vector2(sg.x, g.x))
					if g.y < sg.y:
						ns.append(Vector2(g.y, sg.y))
			segs = ns
		for sg in segs:
			if sg.y - sg.x > 0.05:
				ObjectRegistry.box(node, Vector3(sg.y - sg.x, 0.08, 0.02), Vector3((sg.x + sg.y) / 2.0, 0.04, 0.01), trim_m)
		if st.ceiling in ["plat", "voute", "coupole"]:
			ObjectRegistry.box(node, Vector3(L, 0.06, 0.05), Vector3(0, h - 0.03, 0.025), trim_m)
	if st.cove and st.ceiling != "ouvert" and L > 1.0:
		ObjectRegistry.box(node, Vector3(L - 0.6 if L > 1.6 else L * 0.6, 0.03, 0.08), Vector3(0, h - 0.2, 0.06), cove_m)


## Pavé de mur dans le repère local (x = t, z vers l'intérieur ; dalle côté extérieur).
static func _wall_box(node: Node3D, t0: float, t1: float, y0: float, y1: float, m: Material, collide: bool, thick := WALL_T) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 if collide else 0
	body.position = Vector3((t0 + t1) / 2.0, (y0 + y1) / 2.0, -WALL_T / 2.0)
	var size := Vector3(maxf(t1 - t0, 0.01), maxf(y1 - y0, 0.01), thick)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	ObjectRegistry.box(body, size, Vector3.ZERO, m)
	node.add_child(body)
	return body


const WALL_T := 0.2


static func _collider(parent: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	parent.add_child(body)

# ------------------------------------------------------------------ maillages

## Surface plane du polygone (normale vers le haut pour un sol, vers le bas pour un plafond).
static func _flat_mesh(poly: PackedVector2Array, y: float, up: bool) -> ArrayMesh:
	var idx := Geometry2D.triangulate_polygon(poly)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nrm := Vector3.UP if up else Vector3.DOWN
	for i in range(0, idx.size(), 3):
		var tri := [poly[idx[i]], poly[idx[i + 1]], poly[idx[i + 2]]]
		_emit_tri(st, [Vector3(tri[0].x, y, tri[0].y), Vector3(tri[1].x, y, tri[1].y), Vector3(tri[2].x, y, tri[2].y)], [nrm, nrm, nrm], up)
	return st.commit()


## Triangle orienté (Godot : faces avant dans le sens horaire vu de face).
static func _emit_tri(st: SurfaceTool, v: Array, n: Array, up: bool) -> void:
	var cr: Vector3 = (v[1] - v[0]).cross(v[2] - v[0])
	var order := [0, 1, 2]
	if (cr.y > 0.0) == up:
		order = [0, 2, 1]
	for k in order:
		st.set_normal(n[k])
		st.set_uv(Vector2(v[k].x, v[k].z) * 0.5)
		st.add_vertex(v[k])


## Plafond courbe (voûte, coupole) : triangulation de Delaunay du polygone densifié.
static func _curved_mesh(room: Dictionary, st_: Dictionary, s: Vector3) -> ArrayMesh:
	var poly := RoomShape.polygon(room)
	var pts := PackedVector2Array()
	var step := 0.7
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var n := maxi(1, ceili(a.distance_to(b) / step))
		for k in n:
			pts.append(a.lerp(b, float(k) / n))
	var x := -s.x / 2.0 + step / 2.0
	while x < s.x / 2.0:
		var z := -s.z / 2.0 + step / 2.0
		while z < s.z / 2.0:
			if RoomShape.contains(room, Vector3(x, 0, z), 0.2):
				pts.append(Vector2(x, z))
			z += step
		x += step
	var tris := Geometry2D.triangulate_delaunay(pts)
	var sf := SurfaceTool.new()
	sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var e := 0.05
	for i in range(0, tris.size(), 3):
		var a := pts[tris[i]]
		var b := pts[tris[i + 1]]
		var c := pts[tris[i + 2]]
		var cen := (a + b + c) / 3.0
		if not Geometry2D.is_point_in_polygon(cen, poly):
			continue
		var vs := []
		var ns := []
		for p in [a, b, c]:
			var y := s.y + ceil_rise(st_, s, p.x, p.y)
			vs.append(Vector3(p.x, y, p.y))
			var gx := (ceil_rise(st_, s, p.x + e, p.y) - ceil_rise(st_, s, p.x - e, p.y)) / (2.0 * e)
			var gz := (ceil_rise(st_, s, p.x, p.y + e) - ceil_rise(st_, s, p.x, p.y - e)) / (2.0 * e)
			ns.append(Vector3(gx, -1.0, gz).normalized())
		_emit_tri(sf, vs, ns, false)
	return sf.commit()


## Montants de verrière (lignes de la grille, découpées par la forme).
static func _skylight_bars(root: Node3D, room: Dictionary, h: float, col: Color) -> void:
	var s := RoomShape.dims(room)
	var m := ObjectRegistry.mat(col, 0.0, 0.4)
	for axis in 2:
		var span := s.x if axis == 0 else s.z
		var n := maxi(2, roundi(span / 1.6))
		for i in range(1, n):
			var c := -span / 2.0 + span * i / n
			for iv in RoomShape.scanline(room, axis, c):
				var ln: float = iv.y - iv.x
				var mid: float = (iv.x + iv.y) / 2.0
				var b := ObjectRegistry.box(root, Vector3(0.06, 0.1, ln) if axis == 0 else Vector3(ln, 0.1, 0.06),
					Vector3(c, h - 0.05, mid) if axis == 0 else Vector3(mid, h - 0.05, c), m)
				b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Nervures de la coupole vitrée (méridiens + deux anneaux), en un seul maillage.
static func _dome_ribs(root: Node3D, room: Dictionary, st_: Dictionary, s: Vector3) -> void:
	var sf := SurfaceTool.new()
	sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := s.x / 2.0
	var hd := s.z / 2.0
	var lines := []
	for m in 12:
		var a := TAU * m / 12.0
		var pts := []
		for k in 13:
			var r := k / 12.0 * 0.995
			pts.append(Vector2(hw * r * cos(a), hd * r * sin(a)))
		lines.append(pts)
	for rr in [0.45, 0.8]:
		var pts := []
		for k in 49:
			var a := TAU * k / 48.0
			pts.append(Vector2(hw * rr * cos(a), hd * rr * sin(a)))
		lines.append(pts)
	for pts in lines:
		for k in pts.size() - 1:
			var p0: Vector2 = pts[k]
			var p1: Vector2 = pts[k + 1]
			if not (RoomShape.contains(room, Vector3(p0.x, 0, p0.y)) and RoomShape.contains(room, Vector3(p1.x, 0, p1.y))):
				continue
			var side := (p1 - p0).normalized().orthogonal() * 0.045
			var q := [p0 - side, p0 + side, p1 + side, p1 - side]
			var v := []
			for qq in q:
				v.append(Vector3(qq.x, s.y + ceil_rise(st_, s, qq.x, qq.y) - 0.03, qq.y))
			_emit_tri(sf, [v[0], v[1], v[2]], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], false)
			_emit_tri(sf, [v[0], v[2], v[3]], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], false)
	var mi := MeshInstance3D.new()
	mi.mesh = sf.commit()
	var mat := ObjectRegistry.mat(Color(0.14, 0.15, 0.17), 0.0, 0.4)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	root.add_child(mi)

# ------------------------------------------------------------------ mezzanine

static func _build_mezzanine(root: Node3D, mz: Dictionary, floor_m: Material, cove_m: Material) -> void:
	var r: Rect2 = mz.rect
	var y: float = mz.y
	var node := Node3D.new()
	node.name = "Mezzanine"
	root.add_child(node)
	var deck_m := ObjectRegistry.mat(Color(0.86, 0.84, 0.8), 0.0, 0.8)
	_static_box(node, Vector3(r.size.x, 0.06, r.size.y), Vector3(r.get_center().x, y - 0.03, r.get_center().y), floor_m)
	_static_box(node, Vector3(r.size.x, 0.18, r.size.y), Vector3(r.get_center().x, y - 0.15, r.get_center().y), deck_m)
	# Bandeau lumineux sous le nez de la mezzanine.
	ObjectRegistry.box(node, Vector3(r.size.x - 0.2, 0.02, 0.05), Vector3(r.get_center().x, y - 0.25, r.end.y - 0.06), cove_m)
	# Garde-corps vitrés (ouverture en haut de l'escalier).
	var dir: float = mz.dir
	var x_end: float = mz.x_end
	var open0 := minf(x_end, x_end - dir * 1.0)
	var open1 := maxf(x_end, x_end - dir * 1.0)
	var rails := []
	if open0 > r.position.x + 0.1:
		rails.append([Vector2(r.position.x, r.end.y), Vector2(open0, r.end.y)])
	if open1 < r.end.x - 0.1:
		rails.append([Vector2(open1, r.end.y), Vector2(r.end.x, r.end.y)])
	if mz.gaps.back:
		rails.append([Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y)])
	if mz.gaps.left:
		rails.append([Vector2(r.position.x, r.position.y), Vector2(r.position.x, r.end.y)])
	if mz.gaps.right:
		rails.append([Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y)])
	var steel := ObjectRegistry.mat(Color(0.2, 0.21, 0.23), 0.0, 0.35)
	for rl in rails:
		var a: Vector2 = rl[0]
		var b: Vector2 = rl[1]
		var c := (a + b) / 2.0
		var horiz := absf(a.y - b.y) < 0.01
		var ln := a.distance_to(b)
		var sz := Vector3(ln, 1.0, 0.03) if horiz else Vector3(0.03, 1.0, ln)
		var g := _static_box(node, sz, Vector3(c.x, y + 0.5, c.y), glass_material())
		g.get_child(1).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ObjectRegistry.box(node, Vector3(sz.x + 0.02, 0.04, sz.z + 0.04), Vector3(c.x, y + 1.02, c.y), steel)
	# Escalier : blocs pleins de marches ≤ 25 cm (le joueur les gravit sans sauter).
	var stair: Rect2 = mz.stair
	var n: int = mz.n
	var sh: float = mz.sh
	var run: float = RoomShape.STEP_RUN
	var tread := ObjectRegistry.mat(Color(0.55, 0.42, 0.3), 0.0, 0.6)
	for k in n:
		var top := (k + 1) * sh
		var xc := x_end - dir * (n - k - 0.5) * run
		_static_box(node, Vector3(run, top, stair.size.y), Vector3(xc, top / 2.0, stair.get_center().y), tread if k % 2 == 0 else floor_m)
	# Main courante côté vide.
	var zr := stair.end.y - 0.03
	var x0 := x_end - dir * n * run
	var p0 := Vector3(x0, 1.0, zr)
	var p1 := Vector3(x_end, y + 1.0, zr)
	var hr := ObjectRegistry.box(node, Vector3(p0.distance_to(p1), 0.05, 0.05), (p0 + p1) / 2.0, steel)
	hr.rotation.z = atan2(p1.y - p0.y, p1.x - p0.x)


static func _static_box(parent: Node3D, size: Vector3, center: Vector3, m: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = center
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	ObjectRegistry.box(body, size, Vector3.ZERO, m)
	parent.add_child(body)
	return body

# ------------------------------------------------------------------ extérieur & ambiance

static func _exterior(room: Dictionary, st: Dictionary, s: Vector3) -> Node3D:
	var ext := Node3D.new()
	ext.name = "Exterior"
	var sky: Dictionary = SKIES[st.sky]
	var night: bool = st.sky in ["nuit", "espace"]
	var r0 := maxf(s.x, s.z) * 0.75
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(room.get("id", "x")))
	if st.sky == "espace":
		return ext
	var gcol := Color(0.36, 0.42, 0.3) if st.horizon in ["foret", "collines"] else Color(0.5, 0.48, 0.44)
	if st.horizon == "mer":
		gcol = Color(0.78, 0.72, 0.6)
	gcol = gcol.lerp(sky.hor, 0.2)
	if night:
		gcol = gcol.darkened(0.8)
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	var gr := r0 + 14.0 if st.horizon == "mer" else 260.0
	disc.top_radius = gr
	disc.bottom_radius = gr
	disc.height = 0.05
	disc.radial_segments = 48
	ground.mesh = disc
	ground.position.y = -0.06
	ground.material_override = ObjectRegistry.mat(gcol, 0.0, 1.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ext.add_child(ground)
	match st.horizon:
		"mer":
			var sea := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(900, 900)
			sea.mesh = pm
			sea.position.y = -0.35
			var sm := ObjectRegistry.mat(Color(0.12, 0.3, 0.42).lerp(sky.hor, 0.25).darkened(0.7 if night else 0.0), 0.0, 0.08)
			sm.metallic = 0.3
			sea.material_override = sm
			ext.add_child(sea)
		"foret":
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 1.6
			cone.height = 6.0
			cone.radial_segments = 7
			cone.rings = 1
			mm.mesh = cone
			mm.instance_count = 160
			for i in mm.instance_count:
				var a := rng.randf() * TAU
				var dist := r0 + 18.0 + rng.randf() * 70.0
				var sc := rng.randf_range(0.8, 1.9)
				mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(sc, sc * rng.randf_range(0.9, 1.4), sc)), Vector3(cos(a) * dist, 3.0 * sc, sin(a) * dist)))
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = ObjectRegistry.mat(Color(0.16, 0.3, 0.2).lerp(sky.hor, 0.15).darkened(0.75 if night else 0.0), 0.0, 1.0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ext.add_child(mi)
	if st.horizon in ["collines", "foret"]:
		var hm := ObjectRegistry.mat(Color(0.34, 0.44, 0.4).lerp(sky.hor, 0.55).darkened(0.8 if night else 0.0), 0.0, 1.0)
		for i in 7:
			var a := TAU * i / 7.0 + rng.randf() * 0.5
			var hill := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radial_segments = 16
			sp.rings = 8
			hill.mesh = sp
			var dist := 150.0 + rng.randf() * 40.0
			hill.scale = Vector3(rng.randf_range(50, 80), rng.randf_range(14, 26), rng.randf_range(40, 60))
			hill.position = Vector3(cos(a) * dist, -4.0, sin(a) * dist)
			hill.material_override = hm
			hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ext.add_child(hill)
	return ext


static func sun_dir(st: Dictionary) -> Vector3:
	var sky: Dictionary = SKIES[st.sky]
	var el := deg_to_rad(float(sky.elev))
	var az := deg_to_rad(float(sky.az))
	return Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el)).normalized()


static func make_sun(st: Dictionary) -> DirectionalLight3D:
	var sky: Dictionary = SKIES[st.sky]
	var l := DirectionalLight3D.new()
	l.name = "Sun"
	l.transform = Transform3D(Basis.looking_at(-sun_dir(st), Vector3.UP), Vector3.ZERO)
	l.light_color = sky.sun
	l.light_energy = sky.energy
	l.shadow_enabled = true
	l.directional_shadow_max_distance = 45.0
	l.light_cull_mask = 1 # pas les aperçus de portails (calque 2)
	return l


## Ajuste l'environnement (fond, ciel, ambiance, brume) pour la salle.
static func apply_environment(env: Environment, room: Dictionary) -> void:
	var st := style_of(room)
	var lc := light_color(st)
	var amb := Color(0.78, 0.75, 0.7).lerp(lc, 0.6)
	var amb_e := 0.45 * clampf(light_energy(st) / 0.8, 0.35, 1.8)
	env.fog_enabled = false
	if not has_outside(st):
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.05, 0.05, 0.06)
		env.ambient_light_color = amb
		env.ambient_light_energy = amb_e
		return
	var sk: Dictionary = SKIES[st.sky]
	if _sky_shader == null:
		_sky_shader = Shader.new()
		_sky_shader.code = SKY_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = _sky_shader
	sm.set_shader_parameter("top_col", sk.top)
	sm.set_shader_parameter("hor_col", sk.hor)
	sm.set_shader_parameter("gnd_col", sk.gnd)
	sm.set_shader_parameter("sun_dir", sun_dir(st))
	sm.set_shader_parameter("sun_col", sk.sun)
	sm.set_shader_parameter("stars", sk.stars)
	sm.set_shader_parameter("haze", sk.haze)
	sm.set_shader_parameter("planet", 1.0 if st.sky == "espace" else 0.0)
	sm.set_shader_parameter("ground_stars", 1.0 if st.sky == "espace" else 0.0)
	var sky := Sky.new()
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	var open: bool = st.ceiling == "ouvert"
	env.ambient_light_color = amb.lerp(sk.amb, 0.75 if open else 0.45)
	env.ambient_light_energy = lerpf(amb_e, float(sk.amb_e), 0.8 if open else 0.4)
	env.fog_enabled = true
	env.fog_light_color = sk.hor
	env.fog_density = 0.03 if st.sky == "brume" else 0.0025
	env.fog_sky_affect = 0.5 if st.sky == "brume" else 0.0


## Poussière en suspension dans la lumière (discrète).
static func _dust(s: Vector3, lc: Color) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Dust"
	p.amount = int(clampf(s.x * s.z * 0.8, 60, 220))
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.visibility_aabb = AABB(Vector3(-s.x / 2, 0, -s.z / 2), s)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(s.x * 0.42, s.y * 0.4, s.z * 0.42)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.05
	pm.gravity = Vector3(0, 0.004, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.25, Color(1, 1, 1, 1))
	fade.add_point(0.75, Color(1, 1, 1, 1))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	p.position = Vector3(0, s.y * 0.45, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.018, 0.018)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(lc.r, lc.g, lc.b, 0.5)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p

# ------------------------------------------------------------------ matériaux

static func glass_material() -> StandardMaterial3D:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.albedo_color = Color(0.82, 0.9, 0.96, 0.1)
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.roughness = 0.04
		_glass_mat.metallic_specular = 0.9
		_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glass_mat


## Matériau de sol : couleur + rugosité + motif procédural (triplanaire, 1 motif / 2 m).
static func floor_material(kind: String, col: Color) -> StandardMaterial3D:
	var m := ObjectRegistry.mat(col, 0.0, float(FLOOR_ROUGH.get(kind, 0.6)))
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var tex := _pattern(kind)
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	if kind == "marbre":
		m.metallic_specular = 0.7
	if kind == "beton":
		m.metallic_specular = 0.6
	return m


static func wall_material(kind: String, col: Color) -> StandardMaterial3D:
	var c := col.darkened(0.55) if kind == "sombre" else col
	var m := ObjectRegistry.mat(c, 0.0, float(WALL_ROUGH.get(kind, 0.95)))
	var tex := _pattern("w_" + kind)
	if tex:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * (1.0 if kind == "brique" else 0.5)
	if kind == "marbre":
		m.metallic_specular = 0.7
	return m


static func _pattern(kind: String) -> Texture2D:
	if kind == "uni":
		return null
	if _tex_cache.has(kind):
		return _tex_cache[kind]
	var n := 128
	var im := Image.create(n, n, true, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var known := true
	match kind:
		"bois":
			noise.frequency = 0.02
			for y in n:
				var plank := y / 16
				var off := (plank * 37) % n
				for x in n:
					var g := 0.86 + 0.14 * noise.get_noise_2d((x + off) * 0.25, y * 4.0)
					g += 0.05 * sin(float(plank) * 2.3)
					if y % 16 == 0 or (x + off) % n == 0:
						g *= 0.7
					im.set_pixel(x, y, Color(g, g, g))
		"beton":
			noise.frequency = 0.05
			for y in n:
				for x in n:
					var g := 0.9 + 0.08 * noise.get_noise_2d(x, y) + rng.randf_range(-0.015, 0.015)
					im.set_pixel(x, y, Color(g, g, g))
		"moquette":
			for y in n:
				for x in n:
					var g := 0.9 + rng.randf_range(-0.08, 0.08)
					im.set_pixel(x, y, Color(g, g, g))
		"carrelage":
			for y in n:
				for x in n:
					var joint := x % 32 < 1 or y % 32 < 1
					var g := 0.72 if joint else 0.97 - 0.02 * float((x / 32 + y / 32) % 2)
					im.set_pixel(x, y, Color(g, g, g))
		"marbre", "w_marbre":
			noise.frequency = 0.03
			noise.fractal_octaves = 4
			for y in n:
				for x in n:
					var v := absf(sin((x + y) * 0.05 + noise.get_noise_2d(x, y) * 6.0))
					var g := 0.84 + 0.16 * pow(v, 0.3)
					im.set_pixel(x, y, Color(g, g, g))
		"pierre":
			# Dalles irrégulières : Voronoï sur grille 4x4 (jitter), joints sombres.
			var g4 := 4
			var cs := n / g4
			var pts := {}
			for gx in g4:
				for gy in g4:
					pts[Vector2i(gx, gy)] = Vector2(gx * cs + rng.randf_range(4, cs - 4), gy * cs + rng.randf_range(4, cs - 4))
			noise.frequency = 0.08
			for y in n:
				for x in n:
					var d1 := INF
					var d2 := INF
					var ci := Vector2i.ZERO
					var cx := x / cs
					var cy := y / cs
					for ox in [-1, 0, 1]:
						for oy in [-1, 0, 1]:
							var k := Vector2i(cx + ox, cy + oy)
							var wrapk := Vector2i(posmod(k.x, g4), posmod(k.y, g4))
							var pp: Vector2 = pts[wrapk] + Vector2((k.x - wrapk.x) * cs, (k.y - wrapk.y) * cs)
							var dd := Vector2(x, y).distance_to(pp)
							if dd < d1:
								d2 = d1
								d1 = dd
								ci = wrapk
							elif dd < d2:
								d2 = dd
					var g: float = (0.82 + 0.18 * float(absi(hash(ci)) % 100) / 100.0) * (0.93 + 0.07 * noise.get_noise_2d(x, y))
					if d2 - d1 < 1.6:
						g *= 0.6
					im.set_pixel(x, y, Color(g, g, g))
		"herbe":
			noise.frequency = 0.06
			noise.fractal_octaves = 3
			for y in n:
				for x in n:
					var g := 0.8 + 0.15 * noise.get_noise_2d(x, y) + rng.randf_range(-0.12, 0.12)
					im.set_pixel(x, y, Color(g * 0.95, g, g * 0.85))
		"w_enduit":
			noise.frequency = 0.12
			for y in n:
				for x in n:
					var g := 0.965 + 0.035 * noise.get_noise_2d(x, y)
					im.set_pixel(x, y, Color(g, g, g))
		"w_bois":
			# Lames verticales (claustra), fines rainures.
			noise.frequency = 0.03
			for y in n:
				for x in n:
					var slat := x / 16
					var g := 0.84 + 0.12 * noise.get_noise_2d(x * 3.0 + slat * 50, y * 0.3) + 0.04 * sin(slat * 1.9)
					if x % 16 < 1:
						g *= 0.55
					im.set_pixel(x, y, Color(g, g, g))
		"w_brique":
			for y in n:
				var row := y / 16
				var off := 16 if row % 2 == 1 else 0
				for x in n:
					var bx := (x + off) / 32
					var mortar := y % 16 < 2 or (x + off) % 32 < 2
					var t := float(absi(hash(Vector2i(bx, row))) % 1000) / 1000.0
					var g := 1.05 if mortar else 0.62 + 0.25 * t + rng.randf_range(-0.03, 0.03)
					im.set_pixel(x, y, Color(minf(g, 1.0), minf(g * (1.0 if mortar else 0.92), 1.0), minf(g * (1.0 if mortar else 0.88), 1.0)))
		"w_beton":
			noise.frequency = 0.05
			for y in n:
				for x in n:
					var g := 0.88 + 0.08 * noise.get_noise_2d(x, y) + rng.randf_range(-0.02, 0.02)
					if x % 64 < 1 or y % 32 < 1:
						g *= 0.85
					var hole := Vector2(x % 64, y % 64).distance_to(Vector2(32, 16)) < 2.0
					if hole:
						g *= 0.6
					im.set_pixel(x, y, Color(g, g, g))
		"w_tissu":
			for y in n:
				for x in n:
					var g := 0.9 + 0.05 * float((x + y) % 2) + rng.randf_range(-0.04, 0.04)
					if x % 64 < 2:
						g *= 0.7
					im.set_pixel(x, y, Color(g, g, g))
		"w_sombre":
			for y in n:
				for x in n:
					var g := 0.92 + rng.randf_range(-0.02, 0.02)
					if x % 64 < 1:
						g *= 0.6
					im.set_pixel(x, y, Color(g, g, g))
		_:
			known = false
	if not known:
		_tex_cache[kind] = null
		return null
	im.generate_mipmaps()
	var tex := ImageTexture.create_from_image(im)
	_tex_cache[kind] = tex
	return tex

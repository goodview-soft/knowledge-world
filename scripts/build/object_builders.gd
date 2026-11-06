class_name ObjectBuilders
extends RefCounted
## Visuels des objets de mobilier / architecture / décoration (primitives soignées).
## Appelé par ObjectRegistry.build() pour les types qu'il ne construit pas lui-même.
## Origine = bas-centre, face avant = +Z ; s = taille de DEFS (non mise à l'échelle).



static func build(root: Node3D, o: Dictionary, s: Vector3) -> void:
	match str(o.type):
		"sofa": _sofa(root, o, s, 2)
		"armchair": _sofa(root, o, s, 1)
		"chair": _chair(root, o, s)
		"coffee_table": _coffee_table(root, o, s)
		"big_table": _big_table(root, o, s)
		"shelf": _shelf(root, o, s)
		"plant": _plant(root, o, s)
		"rug": _rug(root, o, s)
		"desk_lamp": _desk_lamp(root, o, s)
		"pouf": _pouf(root, o, s)
		"bench": _bench(root, o, s)
		"cushions": _cushions(root, o, s)
		"wall", "half_wall": _wall(root, o, s)
		"glass_wall": _glass_wall(root, o, s)
		"column": _column(root, o, s)
		"platform": _platform(root, o, s)
		"arch": _arch(root, o, s)
		"railing": _railing(root, o, s)
		"ceiling_light": _ceiling_light(root, o, s)
		"frame": _frame(root, o, s)
		"clock": _clock(root, o, s)
		"vase": _vase(root, o, s)
		"book_stack": _book_stack(root, o, s)
		"globe": _globe(root, o, s)
		"sculpture": _sculpture(root, o, s)
		_:
			ObjectRegistry.box(root, s, Vector3(0, s.y / 2, 0), ObjectRegistry.mat(Color(0.6, 0.6, 0.6)))


static func _rng(o: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(o.get("id", "x")))
	return rng


static func _pc(o: Dictionary, def: Color) -> Color:
	return ObjectRegistry.style_color(o, "primary", def)


static func _sc(o: Dictionary, def: Color) -> Color:
	return ObjectRegistry.style_color(o, "secondary", def)


# ------------------------------------------------------------------ mobilier

static func _sofa(root: Node3D, o: Dictionary, s: Vector3, seats: int) -> void:
	var fc := _pc(o, Color(0.43, 0.49, 0.55))
	var fabric := ObjectRegistry.mat(fc, 0.0, 0.95)
	var cushion := ObjectRegistry.mat(fc.lightened(0.08), 0.0, 0.95)
	var legs := ObjectRegistry.mat(_sc(o, Color(0.3, 0.22, 0.16)), 0.0, 0.6)
	var arm := 0.18 if seats > 1 else 0.15
	var leg_h := 0.08
	for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ObjectRegistry.cyl(root, 0.022, 0.016, leg_h, Vector3(p.x * (s.x / 2 - 0.08), leg_h / 2, p.y * (s.z / 2 - 0.08)), legs)
	ObjectRegistry.box(root, Vector3(s.x, 0.22, s.z), Vector3(0, leg_h + 0.11, 0), fabric)
	var inner := s.x - arm * 2
	var cw := inner / seats
	for i in seats:
		var cx := -inner / 2 + cw * (i + 0.5)
		ObjectRegistry.box(root, Vector3(cw - 0.02, 0.13, s.z - 0.28), Vector3(cx, 0.365, 0.1), cushion)
		var bc := ObjectRegistry.box(root, Vector3(cw - 0.04, 0.36, 0.14), Vector3(cx, 0.6, -s.z / 2 + 0.27), cushion)
		bc.rotation_degrees.x = -8
	ObjectRegistry.box(root, Vector3(inner, s.y - 0.3, 0.2), Vector3(0, 0.3 + (s.y - 0.3) / 2, -s.z / 2 + 0.1), fabric)
	for x in [-1, 1]:
		var ax: float = x * (s.x / 2 - arm / 2)
		ObjectRegistry.box(root, Vector3(arm, 0.5, s.z), Vector3(ax, leg_h + 0.25, 0), fabric)
		ObjectRegistry.cyl(root, arm / 2, arm / 2, s.z, Vector3(ax, leg_h + 0.5, 0), fabric, Vector3(90, 0, 0))


static func _chair(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var wood := ObjectRegistry.mat(_pc(o, Color(0.55, 0.42, 0.3)), 0.0, 0.6)
	var seat := ObjectRegistry.mat(_sc(o, Color(0.32, 0.36, 0.4)), 0.0, 0.95)
	var hx := s.x / 2 - 0.03
	var hz := s.z / 2 - 0.04
	for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ObjectRegistry.box(root, Vector3(0.035, 0.44, 0.035), Vector3(p.x * hx, 0.22, p.y * hz), wood)
	ObjectRegistry.box(root, Vector3(s.x, 0.035, s.z - 0.02), Vector3(0, 0.455, 0), wood)
	ObjectRegistry.box(root, Vector3(s.x - 0.04, 0.03, s.z - 0.08), Vector3(0, 0.487, 0.02), seat)
	for x in [-1, 1]:
		ObjectRegistry.box(root, Vector3(0.035, s.y - 0.47, 0.035), Vector3(x * hx, 0.47 + (s.y - 0.47) / 2, -hz), wood)
	ObjectRegistry.box(root, Vector3(s.x - 0.02, 0.16, 0.025), Vector3(0, s.y - 0.12, -hz), wood)
	ObjectRegistry.box(root, Vector3(s.x - 0.06, 0.03, 0.02), Vector3(0, 0.66, -hz), wood)


static func _coffee_table(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var top := ObjectRegistry.mat(_pc(o, Color(0.6, 0.47, 0.34)), 0.0, 0.5)
	var legs := ObjectRegistry.mat(_sc(o, Color(0.2, 0.2, 0.22)), 0.0, 0.5)
	ObjectRegistry.box(root, Vector3(s.x, 0.04, s.z), Vector3(0, s.y - 0.02, 0), top)
	ObjectRegistry.box(root, Vector3(s.x - 0.14, 0.02, s.z - 0.14), Vector3(0, 0.12, 0), top)
	for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ObjectRegistry.cyl(root, 0.018, 0.014, s.y - 0.04, Vector3(p.x * (s.x / 2 - 0.08), (s.y - 0.04) / 2, p.y * (s.z / 2 - 0.08)), legs)


static func _big_table(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var top := ObjectRegistry.mat(_pc(o, Color(0.5, 0.36, 0.25)), 0.0, 0.55)
	var legs := ObjectRegistry.mat(_sc(o, Color(0.42, 0.3, 0.21)), 0.0, 0.6)
	ObjectRegistry.box(root, Vector3(s.x, 0.05, s.z), Vector3(0, s.y - 0.025, 0), top)
	var lh := s.y - 0.05
	for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ObjectRegistry.box(root, Vector3(0.07, lh, 0.07), Vector3(p.x * (s.x / 2 - 0.12), lh / 2, p.y * (s.z / 2 - 0.12)), legs)
	for z in [-1, 1]:
		ObjectRegistry.box(root, Vector3(s.x - 0.3, 0.08, 0.03), Vector3(0, lh - 0.04, z * (s.z / 2 - 0.12)), legs)
	for x in [-1, 1]:
		ObjectRegistry.box(root, Vector3(0.03, 0.08, s.z - 0.3), Vector3(x * (s.x / 2 - 0.12), lh - 0.04, 0), legs)


static func _shelf(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var wood := ObjectRegistry.mat(_pc(o, Color(0.66, 0.52, 0.38)), 0.0, 0.6)
	var metal := ObjectRegistry.mat(_sc(o, Color(0.17, 0.17, 0.19)), 0.0, 0.4)
	for p in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		ObjectRegistry.box(root, Vector3(0.025, s.y, 0.025), Vector3(p.x * (s.x / 2 - 0.0125), s.y / 2, p.y * (s.z / 2 - 0.0125)), metal)
	var rng := _rng(o)
	var n := 5
	for k in n:
		var y := 0.06 + k * (s.y - 0.1) / (n - 1)
		ObjectRegistry.box(root, Vector3(s.x, 0.025, s.z), Vector3(0, y, 0), wood)
		if k == n - 1:
			break
		var x := -s.x / 2 + 0.06
		var kind := rng.randi_range(0, 2)
		if kind == 0: # livres
			for b in rng.randi_range(4, 9):
				var bw := rng.randf_range(0.03, 0.06)
				var bh := rng.randf_range(0.18, 0.28)
				ObjectRegistry.box(root, Vector3(bw, bh, 0.18), Vector3(x + bw / 2, y + 0.0125 + bh / 2, 0), ObjectRegistry.mat(Color.from_hsv(rng.randf(), 0.35, rng.randf_range(0.45, 0.8))))
				x += bw + 0.008
		elif kind == 1: # vase + boîte
			ObjectRegistry.cyl(root, 0.04, 0.06, 0.2, Vector3(s.x * 0.2, y + 0.11, 0), ObjectRegistry.mat(Color.from_hsv(rng.randf(), 0.25, 0.85), 0.0, 0.3))
			ObjectRegistry.box(root, Vector3(0.22, 0.12, 0.2), Vector3(-s.x * 0.2, y + 0.07, 0), ObjectRegistry.mat(Color(0.85, 0.82, 0.75)))
		else: # petite plante
			ObjectRegistry.cyl(root, 0.06, 0.05, 0.1, Vector3(0, y + 0.06, 0), ObjectRegistry.mat(Color(0.75, 0.48, 0.36)))
			ObjectRegistry.sph(root, 0.09, Vector3(0, y + 0.19, 0), ObjectRegistry.mat(Color(0.32, 0.52, 0.33), 0.0, 0.9))


static func _plant(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var pot := ObjectRegistry.mat(_pc(o, Color(0.74, 0.46, 0.34)), 0.0, 0.8)
	var leaf_c := _sc(o, Color(0.3, 0.5, 0.32))
	ObjectRegistry.cyl(root, 0.2, 0.15, 0.36, Vector3(0, 0.18, 0), pot)
	ObjectRegistry.cyl(root, 0.21, 0.21, 0.03, Vector3(0, 0.36, 0), pot)
	ObjectRegistry.cyl(root, 0.19, 0.19, 0.01, Vector3(0, 0.37, 0), ObjectRegistry.mat(Color(0.25, 0.18, 0.13)))
	ObjectRegistry.cyl(root, 0.015, 0.02, 0.45, Vector3(0, 0.58, 0), ObjectRegistry.mat(Color(0.35, 0.28, 0.18)))
	var rng := _rng(o)
	for k in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.02, 0.13)
		var y := rng.randf_range(0.68, 1.02)
		var rad := rng.randf_range(0.12, 0.19)
		var m := ObjectRegistry.mat(leaf_c.darkened(rng.randf_range(0.0, 0.25)), 0.0, 0.9)
		ObjectRegistry.sph(root, rad, Vector3(cos(a) * r, y, sin(a) * r), m, Vector3(1, 0.85, 1))


static func _rug(root: Node3D, o: Dictionary, s: Vector3) -> void:
	ObjectRegistry.box(root, s, Vector3(0, s.y / 2, 0), ObjectRegistry.mat(_sc(o, Color(0.82, 0.76, 0.66)), 0.0, 1.0))
	ObjectRegistry.box(root, Vector3(s.x - 0.16, s.y, s.z - 0.16), Vector3(0, s.y / 2 + 0.001, 0), ObjectRegistry.mat(_pc(o, Color(0.55, 0.36, 0.31)), 0.0, 1.0))
	ObjectRegistry.box(root, Vector3(s.x - 0.5, s.y, s.z - 0.5), Vector3(0, s.y / 2 + 0.002, 0), ObjectRegistry.mat(_pc(o, Color(0.55, 0.36, 0.31)).lightened(0.12), 0.0, 1.0))


static func _desk_lamp(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var body := ObjectRegistry.mat(_pc(o, Color(0.2, 0.22, 0.24)), 0.0, 0.4)
	var lcol := ObjectRegistry.style_color(o, "light_color", Color(1.0, 0.86, 0.66))
	var lpow := ObjectRegistry.style_float(o, "light_energy", 0.6)
	ObjectRegistry.cyl(root, 0.08, 0.09, 0.025, Vector3(0, 0.0125, 0), body)
	ObjectRegistry.cyl(root, 0.01, 0.01, 0.26, Vector3(0, 0.15, 0), body, Vector3(0, 0, -12))
	ObjectRegistry.cyl(root, 0.01, 0.01, 0.2, Vector3(0.0, 0.3, 0.05), body, Vector3(60, 0, 0))
	var shade := ObjectRegistry.cyl(root, 0.035, 0.08, 0.11, Vector3(0, 0.36, 0.11), ObjectRegistry.mat(_sc(o, Color(0.2, 0.22, 0.24)), 0.0, 0.4), Vector3(35, 0, 0))
	shade.name = "Shade"
	ObjectRegistry.sph(root, 0.025, Vector3(0, 0.34, 0.13), ObjectRegistry.mat(lcol, 1.5 + clampf(lpow, 0.0, 3.0)))
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.28, 0.16)
	light.light_color = lcol
	light.light_energy = lpow
	light.omni_range = 2.2
	root.add_child(light)


static func _pouf(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var fc := _pc(o, Color(0.72, 0.58, 0.42))
	ObjectRegistry.cyl(root, s.x / 2 - 0.02, s.x / 2 - 0.03, s.y - 0.06, Vector3(0, (s.y - 0.06) / 2 + 0.01, 0), ObjectRegistry.mat(fc, 0.0, 0.95), Vector3.ZERO, 32)
	ObjectRegistry.sph(root, s.x / 2 - 0.02, Vector3(0, s.y - 0.06, 0), ObjectRegistry.mat(fc.lightened(0.06), 0.0, 0.95), Vector3(1, 0.22, 1))
	ObjectRegistry.cyl(root, s.x / 2 - 0.015, s.x / 2 - 0.015, 0.025, Vector3(0, 0.02, 0), ObjectRegistry.mat(_sc(o, Color(0.45, 0.35, 0.26))), Vector3.ZERO, 32)


static func _bench(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var wood := ObjectRegistry.mat(_pc(o, Color(0.62, 0.47, 0.32)), 0.0, 0.6)
	var legs := ObjectRegistry.mat(_sc(o, Color(0.18, 0.18, 0.2)), 0.0, 0.45)
	for k in 3:
		ObjectRegistry.box(root, Vector3(s.x, 0.035, s.z / 3 - 0.015), Vector3(0, s.y - 0.0175, -s.z / 3 + k * s.z / 3), wood)
	for x in [-1, 1]:
		var lx: float = x * (s.x / 2 - 0.15)
		ObjectRegistry.box(root, Vector3(0.04, s.y - 0.035, 0.04), Vector3(lx, (s.y - 0.035) / 2, -s.z / 2 + 0.05), legs)
		ObjectRegistry.box(root, Vector3(0.04, s.y - 0.035, 0.04), Vector3(lx, (s.y - 0.035) / 2, s.z / 2 - 0.05), legs)
		ObjectRegistry.box(root, Vector3(0.04, 0.04, s.z - 0.06), Vector3(lx, s.y - 0.055, 0), legs)
		ObjectRegistry.box(root, Vector3(0.03, 0.03, s.z - 0.1), Vector3(lx, 0.1, 0), legs)


static func _cushions(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var a := ObjectRegistry.sph(root, 0.2, Vector3(-0.12, 0.09, 0), ObjectRegistry.mat(_pc(o, Color(0.82, 0.62, 0.45)), 0.0, 0.95), Vector3(1.0, 0.42, 0.85))
	a.rotation_degrees.y = 12
	var b := ObjectRegistry.sph(root, 0.18, Vector3(0.14, 0.17, 0.02), ObjectRegistry.mat(_sc(o, Color(0.5, 0.6, 0.62)), 0.0, 0.95), Vector3(1.0, 0.42, 0.85))
	b.rotation_degrees = Vector3(0, -18, 8)

# ------------------------------------------------------------------ architecture

static func _wall(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var plaster := ObjectRegistry.mat(_pc(o, Color(0.86, 0.85, 0.82)), 0.0, 0.95)
	var trim := ObjectRegistry.mat(_sc(o, Color(0.55, 0.42, 0.3) if o.type == "half_wall" else Color(0.95, 0.94, 0.92)), 0.0, 0.6)
	ObjectRegistry.box(root, s, Vector3(0, s.y / 2, 0), plaster)
	ObjectRegistry.box(root, Vector3(s.x + 0.002, 0.09, s.z + 0.02), Vector3(0, 0.045, 0), trim)
	if o.type == "half_wall":
		ObjectRegistry.box(root, Vector3(s.x + 0.04, 0.04, s.z + 0.08), Vector3(0, s.y - 0.02, 0), trim)


static func _glass_wall(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var frame := ObjectRegistry.mat(_sc(o, Color(0.16, 0.17, 0.19)), 0.0, 0.35)
	var g := ObjectRegistry.mat(_pc(o, Color(0.78, 0.9, 0.95)), 0.0, 0.05)
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.albedo_color.a = 0.16
	g.metallic_specular = 0.9
	g.cull_mode = BaseMaterial3D.CULL_DISABLED
	var f := 0.05
	ObjectRegistry.box(root, Vector3(s.x - f * 2, s.y - f * 2, 0.012), Vector3(0, s.y / 2, 0), g)
	ObjectRegistry.box(root, Vector3(f, s.y, s.z), Vector3(-s.x / 2 + f / 2, s.y / 2, 0), frame)
	ObjectRegistry.box(root, Vector3(f, s.y, s.z), Vector3(s.x / 2 - f / 2, s.y / 2, 0), frame)
	ObjectRegistry.box(root, Vector3(s.x, f, s.z), Vector3(0, f / 2, 0), frame)
	ObjectRegistry.box(root, Vector3(s.x, f, s.z), Vector3(0, s.y - f / 2, 0), frame)
	ObjectRegistry.box(root, Vector3(s.x - f * 2, 0.02, s.z * 0.6), Vector3(0, 1.05, 0), frame)


static func _column(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var stone := ObjectRegistry.mat(_pc(o, Color(0.88, 0.86, 0.82)), 0.0, 0.8)
	var base := ObjectRegistry.mat(_sc(o, Color(0.8, 0.78, 0.74)), 0.0, 0.8)
	ObjectRegistry.box(root, Vector3(s.x, 0.1, s.z), Vector3(0, 0.05, 0), base)
	ObjectRegistry.cyl(root, s.x * 0.42, s.x * 0.45, 0.06, Vector3(0, 0.13, 0), base, Vector3.ZERO, 32)
	ObjectRegistry.cyl(root, s.x * 0.36, s.x * 0.4, s.y - 0.32, Vector3(0, 0.16 + (s.y - 0.32) / 2, 0), stone, Vector3.ZERO, 32)
	ObjectRegistry.cyl(root, s.x * 0.45, s.x * 0.38, 0.08, Vector3(0, s.y - 0.13, 0), base, Vector3.ZERO, 32)
	ObjectRegistry.box(root, Vector3(s.x, 0.09, s.z), Vector3(0, s.y - 0.045, 0), base)


static func _platform(root: Node3D, o: Dictionary, s: Vector3) -> void:
	ObjectRegistry.box(root, Vector3(s.x, s.y - 0.02, s.z - 0.03), Vector3(0, (s.y - 0.02) / 2, -0.015), ObjectRegistry.mat(_pc(o, Color(0.6, 0.46, 0.33)).darkened(0.15), 0.0, 0.7))
	ObjectRegistry.box(root, Vector3(s.x, 0.025, s.z), Vector3(0, s.y - 0.0125, 0), ObjectRegistry.mat(_pc(o, Color(0.6, 0.46, 0.33)), 0.0, 0.6))
	ObjectRegistry.box(root, Vector3(s.x, 0.04, 0.04), Vector3(0, s.y - 0.02, s.z / 2 - 0.02), ObjectRegistry.mat(_sc(o, Color(0.35, 0.27, 0.2)), 0.0, 0.6))


static func _arch(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var stone := ObjectRegistry.mat(_pc(o, Color(0.86, 0.84, 0.8)), 0.0, 0.85)
	var key := ObjectRegistry.mat(_sc(o, Color(0.74, 0.7, 0.64)), 0.0, 0.85)
	var post := 0.3
	var r_in := s.x / 2 - post # 0.7
	var y0 := s.y - post - r_in # naissance de l'arc
	for x in [-1, 1]:
		ObjectRegistry.box(root, Vector3(post, y0, s.z), Vector3(x * (s.x / 2 - post / 2), y0 / 2, 0), stone)
		ObjectRegistry.box(root, Vector3(post + 0.06, 0.06, s.z + 0.04), Vector3(x * (s.x / 2 - post / 2), y0 - 0.03, 0), key)
	var n := 11
	var rm := r_in + post / 2
	for i in n:
		var th := PI * (i + 0.5) / n
		var seg := ObjectRegistry.box(root, Vector3(rm * PI / n * 1.08, post, s.z), Vector3(cos(th) * rm, y0 + sin(th) * rm, 0), key if i == 5 else stone)
		seg.rotation.z = th + PI / 2
	# écoinçons : remplissent les angles au-dessus des piliers
	for x in [-1, 1]:
		ObjectRegistry.box(root, Vector3(0.22, 0.4, s.z), Vector3(x * (s.x / 2 - 0.11), s.y - 0.2, 0), stone)


static func _railing(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var metal := ObjectRegistry.mat(_pc(o, Color(0.22, 0.22, 0.24)), 0.0, 0.4)
	var wood := ObjectRegistry.mat(_sc(o, Color(0.5, 0.36, 0.25)), 0.0, 0.5)
	for x in [-1, 1]:
		ObjectRegistry.box(root, Vector3(0.05, s.y - 0.04, 0.05), Vector3(x * (s.x / 2 - 0.025), (s.y - 0.04) / 2, 0), metal)
	ObjectRegistry.cyl(root, 0.03, 0.03, s.x, Vector3(0, s.y - 0.03, 0), wood, Vector3(0, 0, 90), 16)
	ObjectRegistry.box(root, Vector3(s.x - 0.05, 0.025, 0.025), Vector3(0, 0.1, 0), metal)
	var count := int(s.x / 0.12)
	for i in range(1, count):
		var x := -s.x / 2 + i * s.x / count
		ObjectRegistry.cyl(root, 0.008, 0.008, s.y - 0.16, Vector3(x, 0.1 + (s.y - 0.16) / 2, 0), metal, Vector3.ZERO, 8)


static func _ceiling_light(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var lcol := ObjectRegistry.style_color(o, "light_color", Color(1.0, 0.95, 0.88))
	var lpow := ObjectRegistry.style_float(o, "light_energy", 1.0)
	ObjectRegistry.box(root, s, Vector3(0, s.y / 2, 0), ObjectRegistry.mat(_sc(o, Color(0.9, 0.9, 0.9)), 0.0, 0.5))
	ObjectRegistry.box(root, Vector3(s.x - 0.06, 0.01, s.z - 0.06), Vector3(0, -0.004, 0), ObjectRegistry.mat(_pc(o, lcol), 1.2 + clampf(lpow, 0.0, 3.0)))
	var light := OmniLight3D.new()
	light.position = Vector3(0, -0.35, 0)
	light.light_color = lcol
	light.light_energy = lpow
	light.omni_range = 6.0
	light.omni_attenuation = 1.2
	root.add_child(light)

# ------------------------------------------------------------------ décoration

static func _frame(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var fm := ObjectRegistry.mat(_sc(o, Color(0.32, 0.24, 0.17)), 0.0, 0.5)
	var b := 0.04
	ObjectRegistry.box(root, Vector3(s.x, b, s.z), Vector3(0, b / 2, 0), fm)
	ObjectRegistry.box(root, Vector3(s.x, b, s.z), Vector3(0, s.y - b / 2, 0), fm)
	ObjectRegistry.box(root, Vector3(b, s.y, s.z), Vector3(-s.x / 2 + b / 2, s.y / 2, 0), fm)
	ObjectRegistry.box(root, Vector3(b, s.y, s.z), Vector3(s.x / 2 - b / 2, s.y / 2, 0), fm)
	var canvas := _pc(o, Color(0.93, 0.9, 0.84))
	ObjectRegistry.box(root, Vector3(s.x - b * 2, s.y - b * 2, 0.01), Vector3(0, s.y / 2, -s.z / 2 + 0.01), ObjectRegistry.mat(canvas, 0.0, 0.95))
	var rng := _rng(o)
	var hue := rng.randf()
	for k in 5:
		var w := rng.randf_range(0.1, 0.35) * s.x
		var h := rng.randf_range(0.1, 0.4) * s.y
		var cx := rng.randf_range(-0.3, 0.3) * s.x
		var cy := s.y / 2 + rng.randf_range(-0.25, 0.25) * s.y
		var col := Color.from_hsv(fmod(hue + k * 0.13, 1.0), rng.randf_range(0.3, 0.6), rng.randf_range(0.5, 0.9))
		ObjectRegistry.box(root, Vector3(w, h, 0.004), Vector3(cx, cy, -s.z / 2 + 0.017 + k * 0.001), ObjectRegistry.mat(col, 0.0, 0.95))


static func _clock(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var r := s.x / 2
	ObjectRegistry.cyl(root, r, r, s.z, Vector3(0, r, 0), ObjectRegistry.mat(_pc(o, Color(0.2, 0.2, 0.22)), 0.0, 0.4), Vector3(90, 0, 0), 40)
	ObjectRegistry.cyl(root, r - 0.02, r - 0.02, 0.006, Vector3(0, r, s.z / 2), ObjectRegistry.mat(_sc(o, Color(0.96, 0.95, 0.92)), 0.0, 0.8), Vector3(90, 0, 0), 40)
	var ink := ObjectRegistry.mat(Color(0.12, 0.12, 0.13))
	for k in 12:
		var a := TAU * k / 12.0
		var tick := ObjectRegistry.box(root, Vector3(0.008, 0.03 if k % 3 == 0 else 0.016, 0.004), Vector3(sin(a) * (r - 0.045), r + cos(a) * (r - 0.045), s.z / 2 + 0.005), ink)
		tick.rotation.z = -a
	var t := Time.get_time_dict_from_system()
	var ha := TAU * (fmod(float(t.hour), 12.0) + float(t.minute) / 60.0) / 12.0
	var ma := TAU * float(t.minute) / 60.0
	for hand in [[ha, r * 0.5, 0.012], [ma, r * 0.75, 0.008]]:
		var hm := ObjectRegistry.box(root, Vector3(hand[2], hand[1], 0.004), Vector3(sin(hand[0]) * hand[1] / 2, r + cos(hand[0]) * hand[1] / 2, s.z / 2 + 0.009), ink)
		hm.rotation.z = -hand[0]
	ObjectRegistry.cyl(root, 0.012, 0.012, 0.01, Vector3(0, r, s.z / 2 + 0.01), ink, Vector3(90, 0, 0), 12)


static func _vase(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var cer := ObjectRegistry.mat(_pc(o, Color(0.42, 0.55, 0.6)), 0.0, 0.25)
	ObjectRegistry.sph(root, 0.1, Vector3(0, 0.12, 0), cer, Vector3(1, 1.2, 1))
	ObjectRegistry.cyl(root, 0.045, 0.06, 0.12, Vector3(0, 0.27, 0), cer)
	ObjectRegistry.cyl(root, 0.055, 0.045, 0.02, Vector3(0, 0.34, 0), cer)
	var rng := _rng(o)
	var flower := _sc(o, Color(0.95, 0.75, 0.55))
	var stem := ObjectRegistry.mat(Color(0.3, 0.45, 0.28))
	for k in 3:
		var tilt := Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
		var top := Vector3(sin(deg_to_rad(tilt.z)) * -0.06, 0.34 + rng.randf_range(0.05, 0.1), sin(deg_to_rad(tilt.x)) * 0.06)
		ObjectRegistry.cyl(root, 0.004, 0.004, top.y - 0.25, Vector3(top.x / 2, (top.y + 0.25) / 2, top.z / 2), stem, tilt, 6)
		ObjectRegistry.sph(root, 0.025, top, ObjectRegistry.mat(flower.lightened(k * 0.08), 0.0, 0.9))


static func _book_stack(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var rng := _rng(o)
	var y := 0.0
	var base := _pc(o, Color(0.55, 0.35, 0.3))
	var pages := ObjectRegistry.mat(_sc(o, Color(0.93, 0.9, 0.82)), 0.0, 0.95)
	for k in 5:
		var h := rng.randf_range(0.03, 0.05)
		var w := rng.randf_range(0.2, 0.28)
		var d := rng.randf_range(0.15, 0.2)
		var col := Color.from_hsv(fmod(base.h + rng.randf_range(-0.15, 0.15), 1.0), base.s * rng.randf_range(0.6, 1.2), base.v * rng.randf_range(0.7, 1.3))
		var b := ObjectRegistry.box(root, Vector3(w, h, d), Vector3(0, y + h / 2, 0), ObjectRegistry.mat(col, 0.0, 0.8))
		b.rotation_degrees.y = rng.randf_range(-12, 12)
		ObjectRegistry.box(b, Vector3(w - 0.01, h - 0.008, 0.004), Vector3(0, 0, d / 2 + 0.001), pages)
		y += h
		if y > s.y - 0.03:
			break


static func _globe(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var stand := ObjectRegistry.mat(_sc(o, Color(0.42, 0.3, 0.2)), 0.0, 0.5)
	var brass := ObjectRegistry.mat(Color(0.75, 0.6, 0.35), 0.0, 0.3)
	brass.metallic = 0.7
	ObjectRegistry.cyl(root, 0.1, 0.12, 0.03, Vector3(0, 0.015, 0), stand)
	ObjectRegistry.cyl(root, 0.012, 0.015, 0.14, Vector3(0, 0.1, 0), stand)
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.33, 0)
	pivot.rotation_degrees.z = 23.4
	root.add_child(pivot)
	ObjectRegistry.sph(pivot, 0.15, Vector3.ZERO, ObjectRegistry.mat(_pc(o, Color(0.3, 0.5, 0.68)), 0.0, 0.5))
	var rng := _rng(o)
	var land := ObjectRegistry.mat(Color(0.62, 0.68, 0.45), 0.0, 0.8)
	for k in 6:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 0.8), rng.randf_range(-1, 1)).normalized()
		var blob := ObjectRegistry.sph(pivot, rng.randf_range(0.04, 0.07), dir * 0.13, land, Vector3(1, 1, 0.45))
		blob.look_at_from_position(dir * 0.13, dir * 0.13 + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.172
	ring.mesh = tm
	ring.material_override = brass
	ring.rotation_degrees.x = 90
	pivot.add_child(ring)


static func _sculpture(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var plinth := ObjectRegistry.mat(_sc(o, Color(0.92, 0.91, 0.89)), 0.0, 0.7)
	var bronze := ObjectRegistry.mat(_pc(o, Color(0.66, 0.48, 0.32)), 0.0, 0.35)
	bronze.metallic = 0.6
	ObjectRegistry.box(root, Vector3(s.x, 0.5, s.z), Vector3(0, 0.25, 0), plinth)
	ObjectRegistry.box(root, Vector3(s.x + 0.03, 0.03, s.z + 0.03), Vector3(0, 0.515, 0), plinth)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.09
	tm.outer_radius = 0.14
	ring.mesh = tm
	ring.material_override = bronze
	ring.position = Vector3(0, 0.71, 0)
	ring.rotation_degrees = Vector3(80, 25, 0)
	root.add_child(ring)
	ObjectRegistry.sph(root, 0.06, Vector3(0.04, 0.84, 0.02), bronze)
	ObjectRegistry.cyl(root, 0.02, 0.05, 0.14, Vector3(0, 0.6, 0), bronze)

class_name CosmeticFX
extends RefCounted
## Fabrique des particules cosmétiques (aura, traînée de pas, style des portails) à partir des
## `params` du catalogue. Partagée par ParticleFX (monde) et le casier (aperçu).
## Formes : dot (lueur), spark (étincelle), petal (pétale/feuille), flake (flocon), rune (glyphe).

static var _tex := {}
static var _mat := {}


static func texture(shape: String) -> ImageTexture:
	if _tex.has(shape):
		return _tex[shape]
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var segs := _segments(shape)
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, clampf(_alpha(shape, p, segs), 0.0, 1.0)))
	var t := ImageTexture.create_from_image(img)
	_tex[shape] = t
	return t


static func _segments(shape: String) -> Array:
	var s := []
	match shape:
		"flake":
			for k in 6:
				var a := k * PI / 3.0
				var d := Vector2(cos(a), sin(a))
				s.append([Vector2.ZERO, d * 0.85])
				s.append([d * 0.5, d * 0.5 + Vector2(cos(a + 0.8), sin(a + 0.8)) * 0.25])
				s.append([d * 0.5, d * 0.5 + Vector2(cos(a - 0.8), sin(a - 0.8)) * 0.25])
		"rune":
			s = [[Vector2(0, -0.55), Vector2(0, 0.55)], [Vector2(0, -0.2), Vector2(0.35, -0.5)],
				[Vector2(0, 0.05), Vector2(-0.35, -0.25)], [Vector2(0, 0.3), Vector2(0.3, 0.1)]]
	return s


static func _alpha(shape: String, p: Vector2, segs: Array) -> float:
	var d := p.length()
	match shape:
		"spark":
			var star := maxf(exp(-(absf(p.x) * 9.0 + absf(p.y) * 1.6)), exp(-(absf(p.y) * 9.0 + absf(p.x) * 1.6)))
			return (star + pow(maxf(1.0 - d * 2.2, 0.0), 2.0)) * maxf(1.0 - d, 0.0)
		"petal":
			var e := pow(p.x / 0.42, 2.0) + pow(p.y / 0.92, 2.0)
			var edge := clampf((1.0 - e) * 6.0, 0.0, 1.0)
			return edge * (0.75 + 0.25 * (1.0 - absf(p.x) * 2.0))
		"flake", "rune":
			var m := 10.0
			for sg in segs:
				m = minf(m, _seg_dist(p, sg[0], sg[1]))
			var a := clampf(1.0 - m / 0.09, 0.0, 1.0)
			if shape == "rune":
				a = maxf(a, clampf(1.0 - absf(d - 0.8) / 0.07, 0.0, 1.0))
			return maxf(a, pow(maxf(1.0 - d, 0.0), 3.0) * 0.35)
	var g := clampf(1.0 - d, 0.0, 1.0)
	return g * g


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Matériau de particule : additif (lumineux) ou mélangé (pétales, feuilles : `shaded`).
static func material(shape: String, shaded := false) -> StandardMaterial3D:
	var key := shape + ("|mix" if shaded else "|add")
	if _mat.has(key):
		return _mat[key]
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX if shaded else BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = texture(shape)
	mat.disable_receive_shadows = true
	_mat[key] = mat
	return mat


static func mesh(params: Dictionary, fallback_size := 0.04) -> QuadMesh:
	var q := QuadMesh.new()
	var s := float(params.get("size", fallback_size))
	q.size = Vector2(s, s)
	q.material = material(str(params.get("shape", "dot")), bool(params.get("shaded", false)))
	return q


static func colors_of(params: Dictionary, fallback: Color) -> Array:
	var out := []
	for c in params.get("colors", []):
		out.append(Color(str(c)))
	if out.is_empty():
		out.append(fallback)
	return out


## Couleur initiale aléatoire parmi les couleurs données (dégradé échantillonné au hasard).
static func initial_ramp(cols: Array) -> GradientTexture1D:
	var g := Gradient.new()
	if cols.size() == 1:
		g.set_color(0, cols[0])
		g.set_color(1, cols[0])
	else:
		var offs := PackedFloat32Array()
		var cc := PackedColorArray()
		for i in cols.size():
			offs.append(float(i) / float(cols.size() - 1))
			cc.append(cols[i])
		g.offsets = offs
		g.colors = cc
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


## Fondu d'opacité (apparition, plateau, disparition).
static func fade_ramp(peak := 1.0) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.2, Color(1, 1, 1, peak))
	g.add_point(0.7, Color(1, 1, 1, peak * 0.6))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


static func _apply_spin(pm: ParticleProcessMaterial, shape: String) -> void:
	if shape in ["petal", "flake", "spark"]:
		pm.angle_min = -180.0
		pm.angle_max = 180.0
		pm.angular_velocity_min = -60.0
		pm.angular_velocity_max = 60.0


## Aura autour du joueur. tint : couleur imposée (alpha 0 = couleurs de l'item) ; density : multiplicateur.
static func make_aura(params: Dictionary, tint := Color(0, 0, 0, 0), density := 1.0) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.amount = maxi(1, int(round(float(params.get("amount", 36)) * density)))
	e.lifetime = float(params.get("lifetime", 2.6))
	e.local_coords = false
	e.draw_pass_1 = mesh(params, 0.035)
	e.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 4, 6))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	pm.emission_sphere_radius = float(params.get("radius", 0.75))
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.02
	pm.initial_velocity_max = 0.08
	pm.gravity = Vector3(0, float(params.get("rise", 0.05)), 0)
	var orbit := float(params.get("orbit", 0.08))
	pm.orbit_velocity_min = orbit * 0.6
	pm.orbit_velocity_max = orbit * 1.4
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	var shape := str(params.get("shape", "dot"))
	_apply_spin(pm, shape)
	var cols := [tint] if tint.a > 0.0 else colors_of(params, Color(0.75, 0.88, 1.0))
	pm.color_initial_ramp = initial_ramp(cols)
	pm.color_ramp = fade_ramp(float(params.get("peak", 0.5)))
	pm.attractor_interaction_enabled = false # l'aura n'est pas repoussée par le champ du joueur
	e.process_material = pm
	return e


## Traînée de pas : émet au sol tant que le joueur marche (emitting piloté par l'appelant).
static func make_trail(params: Dictionary) -> GPUParticles3D:
	var e := GPUParticles3D.new()
	e.amount = int(params.get("amount", 30))
	e.lifetime = float(params.get("lifetime", 1.8))
	e.local_coords = false
	e.emitting = false
	e.draw_pass_1 = mesh(params, 0.04)
	e.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 4, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.18, 0.02, 0.18)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 50.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.25
	var shape := str(params.get("shape", "dot"))
	pm.gravity = Vector3(0, -0.15 if shape == "petal" else 0.06, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.5
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	_apply_spin(pm, shape)
	pm.color_initial_ramp = initial_ramp(colors_of(params, Color(0.8, 0.9, 1.0)))
	pm.color_ramp = fade_ramp(float(params.get("peak", 0.8)))
	pm.attractor_interaction_enabled = false
	e.process_material = pm
	return e


## Style des émissions de portail : applique forme/couleurs/vitesse au matériau existant.
## room_col sert quand l'item ne fixe pas de couleurs (style « couleur de la salle »).
static func style_portal(e: GPUParticles3D, pm: ParticleProcessMaterial, params: Dictionary, room_col: Color, peak: float, size: float) -> void:
	var p := params.duplicate()
	if not p.has("size"):
		p.size = size
	e.draw_pass_1 = mesh(p, size)
	var spd := float(params.get("speed", 1.0))
	pm.initial_velocity_min *= spd
	pm.initial_velocity_max *= spd
	pm.gravity = Vector3(0, float(params.get("gravity", 0.03)), 0)
	_apply_spin(pm, str(params.get("shape", "dot")))
	pm.color_initial_ramp = initial_ramp(colors_of(params, room_col.lightened(0.35)))
	pm.color_ramp = fade_ramp(peak)

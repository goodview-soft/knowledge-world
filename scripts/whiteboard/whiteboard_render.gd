class_name WhiteboardRender
extends RefCounted
## Rendu 3D d'un tableau blanc (appelé par ObjectRegistry.build).
## Formes ET textes sont dessinés dans une seule texture par le code de l'éditeur (WBDraw)
## via une SubViewport → aucun décalage. En headless : texture rasterisée + Label3D alignés.

const TEX_W := 1400


static func build(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var c := WBModel.migrate(o.get("content", {}))
	var elements: Array = c.elements
	ObjectRegistry.box(root, s, Vector3(0, s.y / 2, 0), ObjectRegistry.mat(Color(0.55, 0.56, 0.58), 0.0, 0.4))
	var fw := s.x - 0.08
	var fh := s.y - 0.08
	var front := s.z / 2.0 + 0.002
	var sc := Vector2.ONE
	var scv = o.get("scale", [1, 1, 1])
	if scv is Array and scv.size() >= 2:
		sc = Vector2(float(scv[0]), float(scv[1]))
	elif scv is Vector3:
		sc = Vector2(scv.x, scv.y)
	var ratio := (fw * maxf(sc.x, 0.01)) / (fh * maxf(sc.y, 0.01))
	var region := WBModel.render_region(elements, ratio)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(fw, fh)
	quad.mesh = qm
	quad.position = Vector3(0, s.y / 2, front)
	root.add_child(quad)
	var m := ObjectRegistry.mat(Color.WHITE, 0.0, 0.6)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	quad.material_override = m
	if elements.is_empty():
		m.albedo_color = WBDraw.BG
	elif DisplayServer.get_name() == "headless":
		m.albedo_texture = raster(elements, region, Vector2i(700, roundi(700 / ratio)))
		_labels(root, elements, region, fw, fh, Vector3(0, s.y / 2, front + 0.002))
	else:
		var snap := WBSnapshot.make(elements, region, Vector2i(TEX_W, maxi(64, roundi(TEX_W / ratio))), func(img: Image):
			img.generate_mipmaps()
			m.albedo_texture = ImageTexture.create_from_image(img))
		snap.on_ready = func(tex: Texture2D): m.albedo_texture = tex
		root.add_child(snap)
	ObjectRegistry.label(root, o.name, Vector3(0, -0.06, s.z / 2), 1.0, 24, Color(0.8, 0.8, 0.8))


## Repli sans rendu GPU : traits rasterisés (sans texte).
static func raster(elements: Array, region: Rect2, px: Vector2i) -> ImageTexture:
	var img := Image.create(px.x, px.y, false, Image.FORMAT_RGBA8)
	img.fill(WBDraw.BG)
	var z := px.x / region.size.x
	var o := -region.position * z
	for e in elements:
		if e.type == "note":
			var r := Rect2(Vector2(float(e.x), float(e.y)) * z + o, Vector2(float(e.w), float(e.h)) * z)
			img.fill_rect(Rect2i(r), Color(str(e.fill)) if str(e.fill) != "" else WBDraw.NOTE)
		var col := Color(str(e.stroke))
		var rad := maxi(0, int(float(e.width) * z / 2.0))
		for pl in WBDraw.strokes(e):
			for i in pl.size():
				var a: Vector2 = pl[i] * z + o
				var b: Vector2 = (pl[i + 1] if i + 1 < pl.size() else pl[i]) * z + o
				var steps := maxi(1, int(a.distance_to(b)))
				for k in steps + 1:
					var q := a.lerp(b, float(k) / steps)
					img.fill_rect(Rect2i(int(q.x) - rad, int(q.y) - rad, rad * 2 + 1, rad * 2 + 1), col)
	return ImageTexture.create_from_image(img)


## Repli : textes en Label3D placés avec la même projection que la texture.
static func _labels(root: Node3D, elements: Array, region: Rect2, fw: float, fh: float, center: Vector3) -> void:
	var mpu := fw / region.size.x
	for e in elements:
		if not (e.type in ["text", "note"]) or str(e.text) == "":
			continue
		var pad := WBModel.NOTE_PAD if e.type == "note" else 0.0
		var wp := Vector2(float(e.x) + pad, float(e.y) + pad) - region.position
		var l := Label3D.new()
		l.text = str(e.text)
		l.font_size = 32
		l.outline_size = 0
		l.pixel_size = float(e.fs) * mpu / 32.0
		l.modulate = Color(str(e.stroke))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		l.double_sided = false
		if e.type == "note":
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.width = (float(e.w) - pad * 2.0) / float(e.fs) * 32.0
		l.position = center + Vector3(-fw / 2.0 + wp.x * mpu, fh / 2.0 - wp.y * mpu, 0)
		root.add_child(l)

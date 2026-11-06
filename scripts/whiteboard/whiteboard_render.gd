class_name WhiteboardRender
extends RefCounted
## Rendu 3D d'un tableau blanc (appelé par ObjectRegistry.build).

static func build(root: Node3D, o: Dictionary, s: Vector3) -> void:
	var c: Dictionary = o.get("content", {})
	var front := s.z / 2.0 + 0.004
	ObjectRegistry.box(root, s, Vector3(0, s.y / 2, 0), ObjectRegistry.mat(Color(0.55, 0.56, 0.58), 0.0, 0.4))
	var face := ObjectRegistry.box(root, Vector3(s.x - 0.08, s.y - 0.08, 0.01), Vector3(0, s.y / 2, s.z / 2), null)
	var fm := ObjectRegistry.mat(Color.WHITE, 0.0, 0.5)
	fm.albedo_texture = whiteboard_texture(c)
	face.material_override = fm
	var fw := s.x - 0.08
	var fh := s.y - 0.08
	for t in c.get("texts", []):
		var tl := ObjectRegistry.label(root, t.t, Vector3(-fw / 2 + t.x / 1000.0 * fw, s.y / 2 + fh / 2 - t.y / 600.0 * fh, front + 0.003), 1.2, 40, Color(t.get("c", "#222222")))
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ObjectRegistry.label(root, o.name, Vector3(0, -0.06, s.z / 2), 1.0, 24, Color(0.8, 0.8, 0.8))


## Rasterise les traits du tableau blanc (canevas logique 1000×600) en texture.
static func whiteboard_texture(c: Dictionary) -> ImageTexture:
	var w := 500
	var h := 300
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.97, 0.97, 0.95))
	for st in c.get("strokes", []):
		var col := Color(st.get("c", "#222222"))
		var r := maxi(1, int(st.get("w", 4)) / 4)
		var p: Array = st.get("p", [])
		if p.size() == 2:
			img.fill_rect(Rect2i(int(p[0] / 2) - r, int(p[1] / 2) - r, r * 2 + 1, r * 2 + 1), col)
		for i in range(0, p.size() - 3, 2):
			var a := Vector2(p[i], p[i + 1]) / 2.0
			var b := Vector2(p[i + 2], p[i + 3]) / 2.0
			var steps := maxi(1, int(a.distance_to(b)))
			for k in steps + 1:
				var q := a.lerp(b, float(k) / steps)
				img.fill_rect(Rect2i(int(q.x) - r, int(q.y) - r, r * 2 + 1, r * 2 + 1), col)
	return ImageTexture.create_from_image(img)

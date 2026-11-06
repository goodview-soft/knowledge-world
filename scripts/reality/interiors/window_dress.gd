class_name WindowDress
## Vue extérieure commune (panorama procédural selon la direction du regard) + habillage de fenêtre.

const PANORAMA := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float hour = 12.0;
float h1(float x) { return fract(sin(x * 12.9898) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h1(i), h1(i + 1.0), f); }
void fragment() {
	vec3 d = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
	float yaw = atan(d.x, d.z) / 6.2831853 + 0.5;
	float el = asin(clamp(d.y, -1.0, 1.0));
	float day = smoothstep(5.5, 7.5, hour) * (1.0 - smoothstep(19.5, 21.0, hour));
	float dusk = max(smoothstep(16.5, 18.8, hour) * (1.0 - smoothstep(19.4, 21.0, hour)), (1.0 - smoothstep(6.0, 8.0, hour)) * smoothstep(4.5, 6.0, hour));
	float sunel = sin((hour - 6.0) / 12.0 * 3.14159) * 0.9 - 0.05;
	float sunaz = (hour - 12.0) * 0.3;
	vec3 sd = vec3(sin(sunaz) * cos(sunel), sin(sunel), cos(sunaz) * cos(sunel));
	vec3 top = mix(vec3(0.02, 0.04, 0.1), vec3(0.38, 0.6, 0.95), day);
	vec3 hor = mix(vec3(0.07, 0.09, 0.17), vec3(0.8, 0.88, 0.96), day);
	hor = mix(hor, vec3(1.0, 0.55, 0.25), dusk * 0.85);
	top = mix(top, vec3(0.35, 0.38, 0.65), dusk * 0.5);
	vec3 c = mix(hor, top, smoothstep(0.0, 0.7, el));
	c += vec3(1.0, 0.8, 0.5) * pow(max(dot(d, sd), 0.0), 24.0) * (0.25 + 0.5 * dusk) * (day + dusk);
	// silhouette : trois plans de bâtiments, bords adoucis (flou de profondeur)
	float a1 = yaw * 140.0;
	float far = 0.02 + 0.07 * n1(yaw * 38.0) + 0.04 * h1(floor(a1 * 0.4));
	float mid = 0.01 + 0.13 * h1(floor(yaw * 60.0) + 7.0);
	float nr = -0.02 + 0.2 * h1(floor(yaw * 22.0) + 31.0);
	vec3 haze = mix(vec3(0.1, 0.12, 0.2), vec3(0.62, 0.7, 0.8), day);
	haze = mix(haze, vec3(0.8, 0.5, 0.35), dusk * 0.6);
	c = mix(c, haze, smoothstep(far + 0.012, far - 0.012, el) * 0.9);
	vec3 mc = haze * 0.72;
	float mm = smoothstep(mid + 0.01, mid - 0.01, el);
	vec2 g = vec2(fract(yaw * 60.0 * 3.0), fract(el * 70.0));
	float lit = step(0.45, h1(floor(yaw * 180.0) * 3.0 + floor(el * 70.0))) * (1.0 - day);
	mc += vec3(1.0, 0.85, 0.5) * lit * smoothstep(0.2, 0.4, g.x) * smoothstep(0.2, 0.4, g.y) * 0.7;
	c = mix(c, mc, mm);
	vec3 nc = haze * 0.5;
	float nm = smoothstep(nr + 0.01, nr - 0.01, el);
	float lit2 = step(0.5, h1(floor(yaw * 66.0) * 5.0 + floor(el * 40.0) * 2.0)) * (1.0 - day);
	nc += vec3(1.0, 0.8, 0.45) * lit2 * 0.6;
	c = mix(c, nc, nm * step(0.2, h1(floor(yaw * 22.0) * 1.7)));
	float ground = smoothstep(-0.06, -0.1, el);
	c = mix(c, mix(vec3(0.08, 0.08, 0.1), vec3(0.34, 0.33, 0.32), day), ground);
	ALBEDO = c;
}
"""

const BLIND := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float rows = 22.0;
uniform float drop = 0.6;
void fragment() {
	float inside = step(UV.y, drop);
	float s = fract(UV.y * rows);
	float slat = smoothstep(0.0, 0.2, s) * smoothstep(1.0, 0.7, s);
	ALBEDO = mix(vec3(0.8, 0.77, 0.7), vec3(0.95, 0.93, 0.88), s);
	ALPHA = inside * (0.35 + 0.65 * slat);
}
"""

const KINDS := ["sheer", "curtains_open", "curtains_half", "blind", "sheer_curtains", "ajar"]

static var _sky_shader: Shader
static var _blind_shader: Shader


static func sky_material(hour: float) -> ShaderMaterial:
	if _sky_shader == null:
		_sky_shader = Shader.new()
		_sky_shader.code = PANORAMA
	var m := ShaderMaterial.new()
	m.shader = _sky_shader
	m.set_shader_parameter("hour", hour)
	return m


static func pick_kind(room_kind: String, key: String) -> String:
	if room_kind == "bath":
		return "frosted"
	var hsh: int = absi(key.hash())
	if room_kind == "bedroom" and hsh % 3 == 0:
		return "curtains_half"
	return KINDS[hsh % KINDS.size()]


static func _flat(parent: Node3D, size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _fabric(col: Color, alpha := 1.0, emit := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 1.0
	if emit > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emit
	return m


static func _curtain(parent: Node3D, x0: float, x1: float, h: float, col: Color) -> void:
	var w: float = x1 - x0
	var n: int = maxi(3, int(w / 0.12))
	var mat := _fabric(col)
	for i in n:
		var sw: float = w / float(n)
		var x: float = x0 + sw * (float(i) + 0.5)
		var z: float = 0.0 if i % 2 == 0 else 0.035
		ObjectRegistry.box(parent, Vector3(sw * 0.95, h, 0.03), Vector3(x, 0.0, 0.12 + z), mat)


## Fenêtre complète : vue (z=0, +z vers l'intérieur) et habillage. `key` rend le choix déterministe.
static func build(w: float, h: float, kind: String, key: String, hour: float) -> Node3D:
	var root := Node3D.new()
	var sky := _flat(root, Vector2(w, h), Vector3.ZERO, sky_material(hour))
	sky.name = "Sky"
	var hs: int = absi(key.hash())
	var pal := [Color(0.82, 0.74, 0.62), Color(0.55, 0.3, 0.3), Color(0.35, 0.45, 0.55), Color(0.6, 0.6, 0.5), Color(0.4, 0.35, 0.45)]
	var col: Color = pal[(hs / 7) % pal.size()]
	match kind:
		"frosted":
			_flat(root, Vector2(w, h), Vector3(0, 0, 0.03), _fabric(Color(0.92, 0.96, 1.0), 0.93, 0.5))
		"sheer", "sheer_curtains":
			_flat(root, Vector2(w * 1.05, h * 1.1), Vector3(0, 0, 0.08), _fabric(Color(1, 1, 0.97), 0.55, 0.25))
			if kind == "sheer_curtains":
				_curtain(root, -w * 0.5 - 0.28, -w * 0.5 + 0.12, h * 1.25, col)
				_curtain(root, w * 0.5 - 0.12, w * 0.5 + 0.28, h * 1.25, col)
		"curtains_open", "curtains_half":
			var cover := 0.3 if kind == "curtains_open" else 0.62
			var left: float = -w * 0.5 - 0.25 + w * cover
			var right: float = w * 0.5 + 0.25 - w * (cover if kind == "curtains_open" else 0.2)
			_curtain(root, -w * 0.5 - 0.25, left, h * 1.25, col)
			_curtain(root, right, w * 0.5 + 0.25, h * 1.25, col)
		"blind":
			if _blind_shader == null:
				_blind_shader = Shader.new()
				_blind_shader.code = BLIND
			var sm := ShaderMaterial.new()
			sm.shader = _blind_shader
			sm.set_shader_parameter("drop", 0.35 + 0.1 * float(hs % 6))
			sm.set_shader_parameter("rows", maxf(10.0, h / 0.05))
			var bl := _flat(root, Vector2(w, h * 1.06), Vector3(0, h * 0.03, 0.06), sm)
			bl.name = "Blind"
		"ajar":
			var pivot := Node3D.new()
			pivot.position = Vector3(-w * 0.5, 0, 0.05)
			pivot.rotation.y = deg_to_rad(-55.0)
			root.add_child(pivot)
			var fr := _fabric(Color(0.92, 0.92, 0.9))
			var lw: float = w * 0.5
			ObjectRegistry.box(pivot, Vector3(lw, 0.05, 0.04), Vector3(lw * 0.5, h * 0.5 - 0.025, 0), fr)
			ObjectRegistry.box(pivot, Vector3(lw, 0.05, 0.04), Vector3(lw * 0.5, -h * 0.5 + 0.025, 0), fr)
			ObjectRegistry.box(pivot, Vector3(0.05, h, 0.04), Vector3(0.025, 0, 0), fr)
			ObjectRegistry.box(pivot, Vector3(0.05, h, 0.04), Vector3(lw - 0.025, 0, 0), fr)
			_flat(pivot, Vector2(lw, h), Vector3(lw * 0.5, 0, 0), _fabric(Color(0.8, 0.9, 1.0), 0.2))
	return root


## Lumière de fenêtre selon l'heure : null la nuit. Renvoie couleur et énergie.
static func light_for(hour: float) -> Vector2:
	var day := smoothstep(5.5, 7.5, hour) * (1.0 - smoothstep(19.5, 21.0, hour))
	return Vector2(day, 0.0)


static func light_color(hour: float) -> Color:
	var dusk := maxf(smoothstep(16.5, 18.8, hour) * (1.0 - smoothstep(19.4, 21.0, hour)), (1.0 - smoothstep(6.0, 8.0, hour)) * smoothstep(4.5, 6.0, hour))
	return Color(0.95, 0.96, 1.0).lerp(Color(1.0, 0.55, 0.25), dusk)

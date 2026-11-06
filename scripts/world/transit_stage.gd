class_name TransitStage
extends Node3D
## L'ENTRE-DEUX — courte cinématique jouée en traversant un portail.
## La matière du portail est aspirée avec nous dans un tunnel de lumière qui
## s'ouvre sur le cosmos, où un colosse de lumière tend la main : on traverse
## sa paume et l'on ressort dans la salle de destination.
## ~4 s ; clic / Espace / E / Échap pour passer. Construit loin au-dessus du monde.

signal finished

const DURATION := 4.2
const ORIGIN := Vector3(0, 3000, 0)
const HAND_LOCAL := Vector3(0, 125, 92)
const GIANT_POS := Vector3(0, -90, -430)

const ETHEREAL := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 col : source_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform float intensity = 1.0;
varying vec3 wpos;
float h(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float n3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.2);
	float n = n3(wpos * 0.06 + vec3(0.0, TIME * 0.4, TIME * 0.2));
	float veins = smoothstep(0.55, 0.9, n3(wpos * 0.15 - vec3(TIME * 0.3)));
	ALBEDO = col.rgb * (fres * 1.6 + 0.08 + 0.22 * n + veins * 0.5) * intensity;
}
"""

const COSMOS := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never;
uniform vec4 tint_a : source_color = vec4(0.25, 0.15, 0.5, 1.0);
uniform vec4 tint_b : source_color = vec4(0.1, 0.35, 0.6, 1.0);
float h(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
float n3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h(i), h(i + vec3(1,0,0)), f.x), mix(h(i + vec3(0,1,0)), h(i + vec3(1,1,0)), f.x), f.y),
			   mix(mix(h(i + vec3(0,0,1)), h(i + vec3(1,0,1)), f.x), mix(h(i + vec3(0,1,1)), h(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void fragment() {
	vec3 d = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	vec3 p = d * 3.0;
	float neb = n3(p) * 0.5 + n3(p * 2.1) * 0.3 + n3(p * 4.3) * 0.2;
	vec3 c = mix(tint_a.rgb, tint_b.rgb, n3(p * 0.7 + 3.0)) * pow(neb, 2.2) * 1.4;
	vec3 g = floor(d * 260.0);
	float s = step(0.9975, h(g)) * (0.6 + 0.4 * sin(TIME * 2.0 + h(g + 1.0) * 30.0));
	ALBEDO = c + vec3(s);
}
"""

var cam: Camera3D
var _t := 0.0
var _playing := false
var _src := Color.WHITE
var _dst := Color.WHITE
var _rings: Array[MeshInstance3D] = []
var _debris: Array = [] # [node, offset, spin]
var _giant: Node3D
var _head: Node3D
var _hand_mat: ShaderMaterial
var _giant_mats: Array[ShaderMaterial] = []
var _flash: ColorRect
var _drone: AudioStreamPlayer
var _stream: GPUParticles3D
var _hand_light: OmniLight3D


static func make(src: Color, dst: Color) -> TransitStage:
	var s := TransitStage.new()
	s._src = src
	s._dst = dst
	return s


func _ready() -> void:
	global_position = ORIGIN
	cam = Camera3D.new()
	cam.fov = 80
	cam.far = 2000.0
	cam.near = 0.1
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_bloom = 0.25
	env.glow_hdr_threshold = 0.7
	cam.environment = env
	add_child(cam)
	_build_cosmos()
	_build_tunnel()
	_build_giant()
	_build_matter()
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(_src.lightened(0.6), 1.0)
	layer.add_child(_flash)
	_drone = AudioStreamPlayer.new()
	_drone.stream = _make_drone()
	_drone.volume_db = -10.0
	add_child(_drone)


func play() -> void:
	_playing = true
	_t = 0.0
	cam.current = true
	_drone.play()
	_update(0.0)


func _input(event: InputEvent) -> void:
	if not _playing:
		return
	var skip: bool = (event is InputEventMouseButton and event.pressed) or \
		(event is InputEventKey and event.pressed and event.keycode in [KEY_SPACE, KEY_E, KEY_ESCAPE, KEY_ENTER])
	if skip and _t > 0.25:
		_t = DURATION - 0.3
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _playing:
		return
	_t += delta
	_update(delta)
	if _t >= DURATION:
		_playing = false
		finished.emit()

# ------------------------------------------------------------------ séquence

func _update(delta: float) -> void:
	var t := _t
	var col := _src.lerp(_dst, clampf((t - 1.2) / 2.5, 0.0, 1.0))
	# Trajectoire : tunnel (accélération) puis vol vers la paume du colosse.
	var hand := GIANT_POS + HAND_LOCAL
	var p: Vector3
	var look: Vector3
	if t < 1.6:
		var k := ease(t / 1.6, 2.4)
		p = Vector3(0, 0, -150.0 * k)
		look = p + Vector3(sin(t * 3.0) * 0.6, 0.2, -10)
	else:
		var k := ease((t - 1.6) / (DURATION - 1.6), 1.8)
		var start := Vector3(0, 0, -150)
		var mid := Vector3(-30, 20, -260)
		p = start.lerp(mid, k).lerp(mid.lerp(hand + Vector3(0, 0, 6), k), k)
		look = p.lerp(hand, 0.5) + Vector3(0, 0, -40.0 * (1.0 - k))
		look = hand if k > 0.6 else look
	cam.position = p
	if not p.is_equal_approx(look):
		cam.look_at(global_position + look, Vector3.UP)
	cam.rotate_object_local(Vector3.FORWARD, sin(t * 1.3) * 0.08)
	cam.fov = 80.0 + 25.0 * clampf(1.0 - absf(t - 1.2) / 0.6, 0.0, 1.0) + 20.0 * clampf((t - DURATION + 0.8) / 0.8, 0.0, 1.0)
	# Anneaux du tunnel.
	for i in _rings.size():
		var r := _rings[i]
		r.rotate_z(delta * (0.6 + i * 0.05))
		(r.material_override as StandardMaterial3D).emission = col
	# Matière aspirée : débris qui nous accompagnent en spiralant.
	for d in _debris:
		var n: Node3D = d[0]
		var off: Vector3 = d[1]
		var a := t * (1.4 + off.z * 0.1)
		var rad := off.x * (1.0 + t * 0.35)
		n.position = p + Vector3(cos(a + off.y) * rad, sin(a + off.y) * rad * 0.7, -4.0 - off.z)
		n.rotate(Vector3(0.3, 1, 0.2).normalized(), delta * d[2])
	_stream.global_position = global_position + p + Vector3(0, 0, -30)
	# Le colosse : apparaît, tourne la tête vers nous, sa paume s'illumine.
	var reveal := clampf((t - 1.3) / 1.2, 0.0, 1.0)
	for m in _giant_mats:
		m.set_shader_parameter("intensity", reveal)
		m.set_shader_parameter("col", col.lightened(0.2))
	_head.rotation.y = lerpf(0.5, 0.0, reveal) + sin(t * 0.8) * 0.05
	_head.rotation.x = lerpf(0.0, 0.18, reveal)
	var glow := clampf((t - 2.2) / (DURATION - 2.4), 0.0, 1.0)
	_hand_mat.set_shader_parameter("intensity", reveal + glow * 4.0)
	_hand_light.light_energy = 2.0 + glow * 30.0
	_hand_light.light_color = col
	# Fondus : entrée (lumière du portail) et sortie (lumière de la paume).
	var fin := clampf(1.0 - t / 0.45, 0.0, 1.0)
	var fout := clampf((t - (DURATION - 0.45)) / 0.4, 0.0, 1.0)
	_flash.color = Color((_src if fin > 0.0 else _dst).lightened(0.6), maxf(fin, fout))

# ------------------------------------------------------------------ construction

func _build_cosmos() -> void:
	var sky := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1500.0
	sm.height = 3000.0
	sky.mesh = sm
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = COSMOS
	m.shader = sh
	m.set_shader_parameter("tint_a", Color.from_hsv(_src.h, maxf(_src.s, 0.65), 0.55))
	m.set_shader_parameter("tint_b", Color.from_hsv(_dst.h, maxf(_dst.s, 0.7), 0.6))
	sky.material_override = m
	add_child(sky)


func _build_tunnel() -> void:
	for i in 14:
		var r := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 7.0
		tm.outer_radius = 7.35
		tm.rings = 48
		r.mesh = tm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.BLACK
		m.emission_enabled = true
		m.emission = _src
		m.emission_energy_multiplier = 3.0
		r.material_override = m
		r.position = Vector3(0, 0, -8.0 - i * 10.0)
		r.rotation.x = PI / 2
		add_child(r)
		_rings.append(r)


func _ethereal_mat(intensity := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = ETHEREAL
	m.shader = sh
	m.set_shader_parameter("col", _dst)
	m.set_shader_parameter("intensity", intensity)
	_giant_mats.append(m)
	return m


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _ethereal_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


## Le Gardien : silhouette humaine colossale faite de lumière.
func _build_giant() -> void:
	_giant = Node3D.new()
	_giant.position = GIANT_POS
	add_child(_giant)
	_part(_giant, _capsule(24, 95), Vector3(0, 70, 0))                       # torse
	_part(_giant, _capsule(9, 20), Vector3(0, 118, 0))                       # cou
	_part(_giant, _capsule(10, 70), Vector3(-34, 85, 0), Vector3(0, 0, -0.12)) # bras gauche (baissé)
	_part(_giant, _capsule(9, 46), Vector3(30, 112, 22), Vector3(-1.1, 0, 0.35))  # bras droit (levé vers nous)
	_part(_giant, _capsule(8, 44), Vector3(14, 122, 62), Vector3(-1.45, 0, 0.6))  # avant-bras
	_head = Node3D.new()
	_head.position = Vector3(0, 140, 0)
	_giant.add_child(_head)
	_part(_head, _sphere(16), Vector3.ZERO)
	for x in [-5.5, 5.5]:
		var eye := _part(_head, _sphere(1.8), Vector3(x, 2, 14.5))
		eye.material_override.set_shader_parameter("intensity", 0.0)
	# Main ouverte, paume tournée vers nous.
	var hand := Node3D.new()
	hand.position = HAND_LOCAL
	_giant.add_child(hand)
	var palm := _part(hand, _sphere(9), Vector3.ZERO)
	_hand_mat = palm.material_override as ShaderMaterial
	for i in 5:
		var a := -0.9 + i * 0.45
		_part(hand, _capsule(1.8, 13), Vector3(sin(a) * 10, cos(a) * 10 + 2, -1), Vector3(0, 0, -a))
	_hand_light = OmniLight3D.new()
	_hand_light.omni_range = 120.0
	_hand_light.position = Vector3(0, 0, 12)
	hand.add_child(_hand_light)


func _build_matter() -> void:
	# Fragments du portail emportés avec nous.
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 26:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3.ONE * rng.randf_range(0.06, 0.22)
		mi.mesh = b
		var m := StandardMaterial3D.new()
		m.albedo_color = _src.darkened(0.3)
		m.emission_enabled = true
		m.emission = _src.lightened(0.2)
		m.emission_energy_multiplier = rng.randf_range(0.6, 1.8)
		mi.material_override = m
		add_child(mi)
		_debris.append([mi, Vector3(rng.randf_range(1.2, 4.0), rng.randf_range(0, TAU), rng.randf_range(0, 6)), rng.randf_range(1.0, 5.0)])
	# Flux de poussière lumineuse (traînées).
	_stream = GPUParticles3D.new()
	_stream.amount = 700
	_stream.lifetime = 2.5
	_stream.local_coords = false
	_stream.visibility_aabb = AABB(Vector3(-60, -60, -200), Vector3(120, 120, 400))
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.6)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	qm.vertex_color_use_as_albedo = true
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = qm
	_stream.draw_pass_1 = q
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 0, 1)
	pm.emission_ring_radius = 9.0
	pm.emission_ring_inner_radius = 1.5
	pm.emission_ring_height = 40.0
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 4.0
	pm.initial_velocity_min = 30.0
	pm.initial_velocity_max = 70.0
	pm.gravity = Vector3.ZERO
	var g := Gradient.new()
	g.set_color(0, Color(_src.lightened(0.4), 0.0))
	g.add_point(0.3, Color(_src.lightened(0.4), 0.9))
	g.set_color(g.get_point_count() - 1, Color(_dst.lightened(0.4), 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_stream.process_material = pm
	add_child(_stream)


## Nappe sonore grave (deux sinus désaccordés + souffle), enveloppe montante.
func _make_drone() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * DURATION)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var k := float(i) / n
		lp += (rng.randf_range(-1, 1) - lp) * (0.02 + 0.1 * k)
		var v := 0.35 * sin(TAU * 55.0 * t) + 0.25 * sin(TAU * 82.6 * t + sin(t * 0.7)) + 0.15 * sin(TAU * 110.3 * t) + lp * 0.8
		var env := clampf(k * 3.0, 0.0, 1.0) * clampf((1.0 - k) * 6.0, 0.0, 1.0)
		data.encode_s16(i * 2, int(clampf(v * env * 0.6, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

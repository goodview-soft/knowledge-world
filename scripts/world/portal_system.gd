class_name PortalSystem
extends Node3D
## Portails « vivants » : on voit la salle de destination à travers les portes et
## portails (caméra virtuelle rendue dans une SubViewport, échantillonnée en espace
## écran), et on les traverse en marchant, sans écran noir, avec un effet de passage.
## Les salles de destination sont reconstruites en « aperçu » loin sous le monde.

const MAX_LIVE := 3
const LIVE_DIST := 18.0
const PREVIEW_SPACING := 400.0
const RES_SCALE := 0.6
const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D view_tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float live = 0.0;
uniform float near_f = 0.0;
uniform float is_portal = 1.0;
void fragment() {
	vec2 c = UV - 0.5;
	float edge = smoothstep(0.3, 0.5, max(abs(c.x), abs(c.y)));
	float t = TIME;
	vec2 wob = vec2(sin(UV.y * 24.0 + t * 1.6), cos(UV.x * 20.0 + t * 1.3)) * (0.0015 + 0.006 * near_f) * (0.25 + edge) * is_portal;
	vec3 scene = texture(view_tex, SCREEN_UV + wob).rgb;
	vec3 idle = tint.rgb * (0.85 + 0.15 * sin(t * 1.5 + UV.y * 6.0));
	vec3 col = mix(idle, scene, live);
	col += tint.rgb * edge * (0.25 + 0.75 * near_f) * (0.4 + 0.6 * is_portal) * 0.9;
	col += tint.rgb * is_portal * live * 0.05 * sin(UV.y * 90.0 - t * 4.0);
	ALBEDO = col;
}
"""

var main: Node
var entries: Array[Entry] = []
var _shader: Shader
var _cooldown := 0.0
var _flash: ColorRect
var _sound: AudioStreamPlayer
var _refresh_pending := false


class Entry:
	var obj_id := ""
	var target := ""
	var exit_obj := ""
	var exit_xf := Transform3D.IDENTITY # dans le repère de la salle de destination
	var offset := Vector3.ZERO
	var inner := Vector2.ONE
	var inner_y := 1.0
	var zf := 0.02
	var color := Color.WHITE
	var preview: Node3D
	var vp: SubViewport
	var cam: Camera3D
	var quad: MeshInstance3D
	var mat: ShaderMaterial
	var live := false


func _ready() -> void:
	_shader = Shader.new()
	_shader.code = SHADER_CODE
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	layer.add_child(_flash)
	_sound = AudioStreamPlayer.new()
	_sound.stream = _make_whoosh()
	_sound.volume_db = -8.0
	add_child(_sound)

# ------------------------------------------------------------------ construction

func clear() -> void:
	for e in entries:
		for n in [e.preview, e.vp, e.quad]:
			if is_instance_valid(n):
				n.queue_free()
	entries.clear()


func request_refresh() -> void:
	if not _refresh_pending:
		_refresh_pending = true
		refresh.call_deferred()


func refresh() -> void:
	_refresh_pending = false
	clear()
	var room_id: String = main.current_room
	var i := 0
	for id in main.nodes:
		var o: Dictionary = World.data.objects.get(id, {})
		if o.is_empty() or not o.type in ["door", "portal"]:
			continue
		var target: String = o.params.get("target_room", "")
		if target == "" or target == room_id or not World.data.rooms.has(target):
			continue
		i += 1
		entries.append(_make_entry(o, target, Vector3(0, -PREVIEW_SPACING * i, 0)))


func _make_entry(o: Dictionary, target: String, offset: Vector3) -> Entry:
	var e := Entry.new()
	e.obj_id = o.id
	e.target = target
	e.offset = offset
	var scl := World.vec(o.scale)
	var s: Vector3 = ObjectRegistry.get_def(o.type).size * scl
	var post: float = 0.12 if o.type == "door" else 0.22
	e.inner = Vector2(s.x - post * scl.x * 2.0, s.y - post * scl.y)
	e.inner_y = e.inner.y / 2.0
	e.zf = 0.016 * scl.z
	var room: Dictionary = World.data.rooms[target]
	e.color = Color(room.color)
	# Sortie : la porte de la salle cible qui ramène ici, sinon le point d'apparition.
	var exit_found := false
	for t in World.objects_in_room(target):
		if t.type in ["door", "portal"] and t.params.get("target_room", "") == main.current_room:
			e.exit_obj = t.id
			e.exit_xf = Transform3D(Basis.from_euler(World.vec(t.rot) * PI / 180.0), World.vec(t.pos))
			exit_found = true
			break
	if not exit_found:
		e.exit_xf = Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, float(room.size[2]) / 2.0 - 2.0))
	# Aperçu de la salle cible.
	e.preview = Node3D.new()
	add_child(e.preview)
	e.preview.global_position = offset
	var geo := RoomBuilder.build(room, target == World.data.hub)
	e.preview.add_child(geo)
	if exit_found:
		_hide_near_exit(geo, e.exit_xf)
	for t in World.objects_in_room(target):
		if t.id != e.exit_obj:
			var n := KWObject.new()
			e.preview.add_child(n)
			n.setup(t.id)
	# Caméra virtuelle.
	e.vp = SubViewport.new()
	e.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(e.vp)
	e.cam = Camera3D.new()
	e.cam.near = 0.05
	e.cam.far = 120.0
	var env: Environment = main.env.duplicate()
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	e.cam.environment = env
	e.vp.add_child(e.cam)
	e.cam.current = true
	# Surface du passage.
	e.quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = e.inner
	e.quad.mesh = qm
	e.quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	e.mat = ShaderMaterial.new()
	e.mat.shader = _shader
	e.mat.set_shader_parameter("view_tex", e.vp.get_texture())
	e.mat.set_shader_parameter("tint", e.color.lightened(0.15))
	e.mat.set_shader_parameter("is_portal", 1.0 if o.type == "portal" else 0.35)
	e.quad.material_override = e.mat
	add_child(e.quad)
	return e


## Retire de l'aperçu le mur (et les moulures) derrière la porte de sortie,
## pour que la caméra virtuelle, placée « derrière » la porte, voie la salle.
func _hide_near_exit(geo: Node3D, exit_xf: Transform3D) -> void:
	var n := exit_xf.basis.z
	for c in geo.get_children():
		if c is Node3D and not c is Light3D:
			var p: Vector3 = (c as Node3D).position
			var size := Vector3.ZERO
			if c is StaticBody3D:
				for cs in c.get_children():
					if cs is CollisionShape3D and cs.shape is BoxShape3D:
						size = cs.shape.size
			if absf((p - exit_xf.origin).dot(n)) < 0.4 and (size == Vector3.ZERO or absf(size.dot(n.abs())) < 0.5):
				(c as Node3D).visible = false
				if c is StaticBody3D:
					c.collision_layer = 0

# ------------------------------------------------------------------ mise à jour

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if entries.is_empty():
		return
	var cam: Camera3D = main.player.cam
	var pp: Vector3 = main.player.global_position
	var vsize := Vector2i((get_viewport().get_visible_rect().size * RES_SCALE).max(Vector2(64, 64)))
	# Choix des passages rendus en direct : les plus proches, vus de face.
	var cands := []
	for e in entries:
		var node = main.nodes.get(e.obj_id)
		if node == null or not is_instance_valid(node):
			continue
		var ta: Transform3D = node.global_transform
		var local := ta.affine_inverse() * pp
		var dist := local.length()
		e.quad.global_transform = ta * Transform3D(Basis(), Vector3(0, e.inner_y, e.zf))
		e.mat.set_shader_parameter("near_f", clampf(1.0 - (dist - 0.5) / 3.0, 0.0, 1.0))
		if local.z > 0.05 and dist < LIVE_DIST:
			cands.append([dist, e])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var live_set := {}
	for k in mini(MAX_LIVE, cands.size()):
		live_set[cands[k][1]] = true
	for e in entries:
		var on: bool = live_set.has(e) and not main._travelling
		if on != e.live:
			e.live = on
			e.vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
			e.mat.set_shader_parameter("live", 1.0 if on else 0.0)
		if on:
			if e.vp.size != vsize:
				e.vp.size = vsize
			var ta: Transform3D = main.nodes[e.obj_id].global_transform
			e.cam.global_transform = _mapping(e, ta, true) * cam.global_transform
			e.cam.fov = cam.fov


## Transformation qui envoie un point devant le passage d'entrée vers la sortie.
func _mapping(e: Entry, ta: Transform3D, to_preview: bool) -> Transform3D:
	var exit := e.exit_xf
	if to_preview:
		exit = Transform3D(Basis(), e.offset) * exit
	return exit * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO) * ta.affine_inverse()


func _physics_process(_delta: float) -> void:
	if _cooldown > 0.0 or main.panel != null or main._travelling or main.build.active:
		return
	var p: KWPlayer = main.player
	for e in entries:
		var node = main.nodes.get(e.obj_id)
		if node == null:
			continue
		var ta: Transform3D = node.global_transform
		var local := ta.affine_inverse() * p.global_position
		var vel_local := ta.basis.inverse() * p.velocity
		if absf(local.x) < e.inner.x / 2.0 - 0.05 and local.z < 0.45 and local.z > -0.4 and local.y < 1.0 and vel_local.z < -0.3:
			_traverse(e, ta)
			return


func _traverse(e: Entry, ta: Transform3D) -> void:
	var p: KWPlayer = main.player
	var m := _mapping(e, ta, false)
	var xf := m * p.global_transform
	var local := e.exit_xf.affine_inverse() * xf.origin
	local.z = maxf(local.z, 0.75)
	local.y = 0.05
	var pos := e.exit_xf * local
	var yaw := xf.basis.get_euler().y
	var pitch := p.head.rotation.x
	var vel := m.basis * p.velocity
	var color := e.color
	var target := e.target
	var from: String = main.current_room
	_cooldown = 0.8
	main.enter_room(target, from)
	p.global_position = pos
	p.rotation = Vector3(0, yaw, 0)
	p.head.rotation.x = pitch
	p.velocity = vel
	play_effect(color)

# ------------------------------------------------------------------ effet « wow »

func play_effect(color: Color) -> void:
	var cam: Camera3D = main.player.cam
	var base := float(KWSettings.get_value("fov"))
	cam.fov = base + 24.0
	var tw := create_tween()
	tw.tween_property(cam, "fov", base, 0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_flash.color = Color(color.lightened(0.5), 0.6)
	var tf := create_tween()
	tf.tween_property(_flash, "color:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if _sound.stream != null:
		_sound.play()


## Souffle doux procédural (bruit filtré, balayage de fréquence, enveloppe).
func _make_whoosh() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.9)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / n
		var cutoff := 0.02 + 0.25 * sin(t * PI)
		lp += (rng.randf_range(-1.0, 1.0) - lp) * cutoff
		lp2 += (lp - lp2) * cutoff
		var env := pow(sin(t * PI), 1.6) * (1.0 - t * 0.4)
		var v := int(clampf(lp2 * env * 2.2, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

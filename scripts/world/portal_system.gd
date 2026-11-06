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
render_mode cull_disabled, shadows_disabled, specular_schlick_ggx;
uniform sampler2D view_tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.6, 0.8, 1.0, 1.0);
uniform float live = 0.0;
uniform float near_f = 0.0;
uniform float is_portal = 1.0;
uniform vec3 player_local = vec3(0.0, 0.0, 5.0);
uniform float absorb = 0.0;
varying float v_disp;
varying vec2 v_grad;
void vertex() {
	// Surface liquide : creux qui « aspire » vers le joueur proche + ondes concentriques.
	vec2 q = VERTEX.xy - player_local.xy;
	float r2 = dot(q, q);
	float w = 0.16 + 0.22 * is_portal;
	float well = exp(-r2 / w);
	float ripple = sin(sqrt(r2) * 22.0 - TIME * 7.0) * 0.014 * exp(-r2 * 1.2);
	float idle = sin(VERTEX.x * 6.0 + TIME * 1.3) * sin(VERTEX.y * 5.0 - TIME * 1.1) * 0.006 * is_portal;
	float d = -absorb * 0.24 * well + absorb * ripple + idle;
	VERTEX.z += d;
	v_disp = d;
	v_grad = (2.0 * q / w) * well * absorb * 0.24;
	NORMAL = normalize(vec3(-v_grad.x, -v_grad.y, 1.0));
}
void fragment() {
	vec2 c = UV - 0.5;
	float edge = smoothstep(0.3, 0.5, max(abs(c.x), abs(c.y)));
	float t = TIME;
	vec2 wob = vec2(sin(UV.y * 24.0 + t * 1.6), cos(UV.x * 20.0 + t * 1.3)) * (0.0015 + 0.006 * near_f) * (0.25 + edge) * is_portal;
	vec2 refr = v_grad * 0.02 + vec2(v_disp) * 0.05;
	vec3 scene = texture(view_tex, SCREEN_UV + wob + refr).rgb;
	vec3 idle_c = tint.rgb * (0.85 + 0.15 * sin(t * 1.5 + UV.y * 6.0));
	vec3 col = mix(idle_c, scene, live);
	col += tint.rgb * edge * (0.25 + 0.75 * near_f) * (0.4 + 0.6 * is_portal) * 0.9;
	col += tint.rgb * is_portal * live * 0.012 * sin(UV.y * 90.0 - t * 4.0);
	col += tint.rgb * absorb * 0.5 * exp(-dot(v_grad, v_grad) * 0.5) * clamp(-v_disp * 6.0, 0.0, 1.0);
	// Verre : l'image traverse, les reflets (SSR + lumières) apparaissent selon l'angle.
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = vec3(0.015);
	METALLIC = 0.0;
	ROUGHNESS = 0.03;
	SPECULAR = 0.75;
	EMISSION = col * (1.0 - fres * 0.6);
}
"""

var main: Node
var entries: Array[Entry] = []
var _shader: Shader
var _cooldown := 0.0
var _flash: ColorRect
var _sound: AudioStreamPlayer
var _refresh_pending := false
var _swirl: ColorRect
var _swirl_mat: ShaderMaterial
var _swirl_t := 0.0 # effet de sortie (décroît)
var _approach := 0.0 # aspiration à l'approche
var _attractors := {} # Entry -> GPUParticlesAttractorSphere3D

const SWIRL_CODE := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;
uniform vec4 tint : source_color = vec4(0.7, 0.85, 1.0, 1.0);
void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float r = length(c);
	float a = amount;
	float ang = a * 2.6 * (1.0 - smoothstep(0.0, 0.75, r));
	vec2 rc = vec2(c.x * cos(ang) - c.y * sin(ang), c.x * sin(ang) + c.y * cos(ang));
	vec2 suv = 0.5 + rc * (1.0 - a * 0.3 * (1.0 - r));
	vec3 col = vec3(0.0);
	for (int i = 0; i < 6; i++) {
		float k = float(i) / 6.0 * a * 0.09;
		col.r += texture(screen_tex, suv - c * k * 1.25).r;
		col.g += texture(screen_tex, suv - c * k).g;
		col.b += texture(screen_tex, suv - c * k * 0.75).b;
	}
	col /= 6.0;
	col = mix(col, tint.rgb, a * 0.4 * smoothstep(0.15, 0.85, r));
	COLOR = vec4(col, 1.0);
}
"""


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
	# Distorsion plein écran (aspiration / éjection) : tourbillon + aberration chromatique.
	_swirl_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SWIRL_CODE
	_swirl_mat.shader = sh
	_swirl = ColorRect.new()
	_swirl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_swirl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swirl.material = _swirl_mat
	_swirl.visible = false
	var under_ui := CanvasLayer.new()
	under_ui.layer = 0 # sous l'interface (layer 1) : seule la 3D est déformée
	add_child(under_ui)
	under_ui.add_child(_swirl)
	# Reflets dans les portails : réflexions en espace écran.
	if main != null and main.env != null:
		main.env.ssr_enabled = true
		main.env.ssr_max_steps = 48
		main.env.ssr_fade_in = 0.15
		main.env.ssr_fade_out = 2.0
		main.env.ssr_depth_tolerance = 0.2

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
		e.exit_xf = Transform3D(Basis(Vector3.UP, PI), RoomShape.spawn_point(room) - Vector3(0, 0.05, 0))
	# Aperçu de la salle cible.
	e.preview = Node3D.new()
	add_child(e.preview)
	e.preview.global_position = offset
	var geo := RoomBuilder.build(room, target == World.data.hub, true)
	e.preview.add_child(geo)
	if exit_found:
		_hide_near_exit(geo, e.exit_xf)
	for t in World.objects_in_room(target):
		if t.id != e.exit_obj:
			var n := KWObject.new()
			e.preview.add_child(n)
			n.setup(t.id)
	_set_layer(e.preview) # hors du soleil de la salle courante
	# Caméra virtuelle.
	e.vp = SubViewport.new()
	e.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(e.vp)
	e.cam = Camera3D.new()
	e.cam.near = 0.05
	e.cam.far = 120.0
	var env: Environment = main.env.duplicate()
	RoomBuilder.apply_environment(env, room)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = false
	e.cam.environment = env
	e.vp.add_child(e.cam)
	e.cam.current = true
	# Surface du passage.
	e.quad = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = e.inner
	qm.subdivide_width = 28
	qm.subdivide_depth = 40
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


## Retire de l'aperçu les murs (nœuds kw_wall de RoomBuilder) situés derrière le plan de
## la porte de sortie, pour que la caméra virtuelle, placée « derrière », voie la salle.
func _hide_near_exit(geo: Node3D, exit_xf: Transform3D) -> void:
	var n := exit_xf.basis.z
	for c in geo.get_children():
		if c is Node3D and c.has_meta("kw_wall"):
			var p: Vector3 = (c as Node3D).position
			if (p - exit_xf.origin).dot(n) < 0.35:
				(c as Node3D).visible = false
				for b in c.get_children():
					if b is StaticBody3D:
						b.collision_layer = 0


static func _set_layer(n: Node) -> void:
	if n is VisualInstance3D:
		(n as VisualInstance3D).layers = 2
	for c in n.get_children():
		_set_layer(c)

# ------------------------------------------------------------------ mise à jour

func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	if entries.is_empty():
		_update_swirl(delta, 0.0)
		return
	var cam: Camera3D = main.player.cam
	var pp: Vector3 = main.player.global_position
	var vsize := Vector2i((get_viewport().get_visible_rect().size * RES_SCALE).max(Vector2(64, 64)))
	# Choix des passages rendus en direct : les plus proches, vus de face.
	var cands := []
	var approach := 0.0
	for k in _attractors.keys():
		if not k in entries:
			_attractors[k].queue_free()
			_attractors.erase(k)
	for e in entries:
		var node = main.nodes.get(e.obj_id)
		if node == null or not is_instance_valid(node):
			continue
		var ta: Transform3D = node.global_transform
		var local := ta.affine_inverse() * pp
		var dist := local.length()
		e.quad.global_transform = ta * Transform3D(Basis(), Vector3(0, e.inner_y, e.zf))
		e.mat.set_shader_parameter("near_f", clampf(1.0 - (dist - 0.5) / 3.0, 0.0, 1.0))
		# Aspiration : surface qui se creuse vers le joueur, particules attirées.
		var ql := e.quad.global_transform.affine_inverse() * cam.global_position
		var inside := absf(ql.x) < e.inner.x * 0.75 and ql.y > -e.inner.y * 0.6 and ql.y < e.inner.y * 0.6
		var ab := clampf(1.0 - (ql.z - 0.35) / 1.6, 0.0, 1.0) if inside and ql.z > -0.2 else 0.0
		e.mat.set_shader_parameter("player_local", ql)
		e.mat.set_shader_parameter("absorb", ab)
		approach = maxf(approach, ab)
		var at: GPUParticlesAttractorSphere3D = _attractors.get(e)
		if at == null:
			at = GPUParticlesAttractorSphere3D.new()
			at.radius = 2.2
			at.attenuation = 1.2
			add_child(at)
			_attractors[e] = at
		at.global_position = e.quad.global_transform * Vector3(0, 0, -0.3)
		at.strength = 4.0 + 10.0 * ab
		if local.z > 0.05 and dist < LIVE_DIST:
			cands.append([dist, e])
	_update_swirl(delta, approach)
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
			if on and e.cam.environment != null:
				e.cam.environment.ssr_enabled = false
				e.cam.environment.ssil_enabled = false
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
	if _cooldown > 0.0 or main.panel != null or main._travelling or main.build.placing != "" or main.build.grabbing:
		return
	var p: KWPlayer = main.player
	# Intention de déplacement (la vitesse réelle tombe à 0 contre le mur derrière le passage).
	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if p.active() else Vector2.ZERO
	var wish := p.global_transform.basis * Vector3(iv.x, 0, iv.y)
	for e in entries:
		var node = main.nodes.get(e.obj_id)
		if node == null:
			continue
		var ta: Transform3D = node.global_transform
		var local := ta.affine_inverse() * p.global_position
		var vel_local := ta.basis.inverse() * p.velocity
		var wish_local := ta.basis.inverse() * wish
		var pushing := vel_local.z < -0.3 or wish_local.z < -0.3
		if absf(local.x) < e.inner.x / 2.0 - 0.1 and local.z < 0.6 and local.z > -0.4 and local.y < 1.2 and pushing:
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
	if _cinematic_for(e):
		# L'entre-deux : cinématique de traversée (passable), puis arrivée.
		main._travelling = true
		p.enabled = false
		main.hud.visible = false
		var src_col := Color(World.data.rooms[from].color) if World.data.rooms.has(from) else color
		var stage := TransitStage.make(src_col, color)
		add_child(stage)
		stage.play()
		await stage.finished
		p.cam.make_current()
		stage.queue_free()
		main.hud.visible = true
		p.enabled = main.panel == null
		main._travelling = false
		vel = vel * 0.3
		_cooldown = 1.0
	main.enter_room(target, from)
	p.global_position = pos
	p.rotation = Vector3(0, yaw, 0)
	p.head.rotation.x = pitch
	p.velocity = vel
	play_effect(color)

## Cinématique seulement pour les portails (pas les portes), désactivable,
## jamais en test automatique.
func _cinematic_for(e: Entry) -> bool:
	if "--kw-test" in OS.get_cmdline_user_args():
		return false
	var v = KWSettings.get_value("portal_cinematic")
	if v != null and not bool(v):
		return false
	var o: Dictionary = World.data.objects.get(e.obj_id, {})
	return o.get("type", "") == "portal"

# ------------------------------------------------------------------ effet « wow »

func _update_swirl(delta: float, approach: float) -> void:
	_swirl_t = maxf(0.0, _swirl_t - delta * 1.1)
	_approach = lerpf(_approach, approach, 1.0 - exp(-6.0 * delta))
	var a := maxf(_swirl_t, _approach * _approach * 0.12)
	_swirl.visible = a > 0.005
	if _swirl.visible:
		_swirl_mat.set_shader_parameter("amount", a)


func play_effect(color: Color) -> void:
	var cam: Camera3D = main.player.cam
	_swirl_t = 1.0
	_swirl_mat.set_shader_parameter("tint", color.lightened(0.3))
	cam.rotation.z = 0.12
	create_tween().tween_property(cam, "rotation:z", 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var base := float(KWSettings.get_value("fov"))
	cam.fov = base + 24.0
	var tw := create_tween()
	tw.tween_property(cam, "fov", base, 0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_flash.color = Color(color.lightened(0.5), 0.35)
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

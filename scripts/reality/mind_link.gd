class_name MindLink
extends Node
## Machine d'états réalité ↔ palais mental.
## Maj (appui court < 0,25 s, sans déplacement) : entrer / sortir. Maj maintenu = sprint (inchangé).
## Entrer : le personnage s'assoit, une bulle de pensée montre le palais en direct (SubViewport),
## la caméra vole dans la bulle. Sortir : l'inverse. Transitions ~1,5 s, passables (clic).
## Sauvegarde : World.data.reality = {pos, yaw (réalité, relatifs à l'origine), palace_room, palace_pos, palace_yaw}.

enum S { REALITY, TO_PALACE, PALACE, TO_REALITY }
const TAP_MS := 250
const BUBBLE_FPS := 15.0
const BUBBLE_RES := Vector2i(384, 240)
const BUBBLE_SIZE := Vector2(1.9, 1.2)
const BUBBLE_H := 2.5

const BUBBLE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_linear;
uniform float alpha = 1.0;
uniform float fill = 0.0;
uniform float s = 1.0;
void vertex() {
	VERTEX *= s;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float d = length((UV - 0.5) * 2.0);
	float m = mix(1.0 - smoothstep(0.84, 1.0, d), 1.0, fill);
	vec3 c = texture(tex, UV).rgb;
	float rim = smoothstep(0.8, 0.9, d) * (1.0 - fill);
	ALBEDO = mix(c, vec3(0.9, 0.95, 1.0), rim * 0.6);
	ALPHA = m * alpha;
}
"""

var main: Node
var state: S = S.REALITY
var reality: RealityWorld
var ghost: KWAvatar
var fly: Camera3D
var _palace_env: Environment
var _vp: SubViewport
var _vcam: Camera3D
var _bubble_root: Node3D
var _bubble: MeshInstance3D
var _bmat: ShaderMaterial
var _dots: Array = []
var _tw: Tween
var _finish_cb: Callable
var _bubble_on := false
var _bubble_acc := 0.0
var _shift_down := false
var _shift_ok := false
var _shift_t0 := 0
var _store_acc := 0.0
var _palace_room := ""
var _palace_pos := Vector3.ZERO
var _palace_yaw := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reality = RealityWorld.new()
	main.add_child(reality)
	_palace_env = main.env.duplicate()
	fly = Camera3D.new()
	fly.near = 0.05
	main.add_child(fly)
	_vp = SubViewport.new()
	_vp.size = BUBBLE_RES
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_vp)
	_vcam = Camera3D.new()
	_vcam.far = 150.0
	_vcam.environment = _palace_env
	_vp.add_child(_vcam)
	_vcam.make_current()
	_bubble_root = Node3D.new()
	_bubble_root.visible = false
	reality.add_child(_bubble_root)
	_bubble = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = BUBBLE_SIZE
	_bubble.mesh = qm
	var sh := Shader.new()
	sh.code = BUBBLE_SHADER
	_bmat = ShaderMaterial.new()
	_bmat.shader = sh
	_bmat.set_shader_parameter("tex", _vp.get_texture())
	_bubble.material_override = _bmat
	_bubble.position.y = BUBBLE_H
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble_root.add_child(_bubble)
	for i in 3:
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.05 + 0.03 * i
		sm.height = sm.radius * 2.0
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.92, 0.96, 1.0, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		d.mesh = sm
		d.material_override = m
		d.position.y = 1.5 + 0.2 * i
		d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_bubble_root.add_child(d)
		_dots.append(d)


## Initialise (ou réinitialise) l'état : dans la réalité (jeu normal) ou dans le palais (tests, captures).
func begin(in_palace: bool) -> void:
	if _tw:
		_tw.kill()
	_hide_bubble()
	if ghost:
		ghost.queue_free()
		ghost = null
	var pl: KWPlayer = main.player
	var r: Dictionary = World.data.get("reality", {})
	if World.data.rooms.has(r.get("palace_room", "")) and r.has("palace_pos"):
		if main.current_room != r.palace_room:
			main.enter_room(r.palace_room)
		pl.teleport(World.vec(r.palace_pos), float(r.get("palace_yaw", 0.0)))
	_palace_room = main.current_room
	_palace_pos = pl.global_position
	_palace_yaw = pl.rotation.y
	var rpos := RealityWorld.ORIGIN + (World.vec(r.pos) if r.has("pos") else Vector3(0, 0.05, 3))
	var ryaw := float(r.get("yaw", 0.0))
	pl.avatar.visible = true
	if in_palace:
		_spawn_ghost(rpos, ryaw, true)
		_enter_palace_state()
	else:
		pl.teleport(rpos, ryaw)
		_enter_reality_state()


func _enter_palace_state() -> void:
	state = S.PALACE
	main.in_palace = true
	reality.apply_env(main.env, false, _palace_env)
	var pl: KWPlayer = main.player
	pl.set_third_person(bool(KWSettings.get_value("third_person")), false)
	pl.avatar.visible = true
	pl.enabled = main.title == null
	pl.cam.make_current() if not pl.third_person else pl.cam3.make_current()


func _enter_reality_state() -> void:
	state = S.REALITY
	main.in_palace = false
	reality.apply_env(main.env, true, _palace_env)
	var pl: KWPlayer = main.player
	pl.set_third_person(true, false)
	pl.avatar.visible = true
	pl.enabled = main.title == null


func toggle() -> void:
	if state == S.REALITY:
		enter_palace()
	elif state == S.PALACE:
		exit_palace()


# ------------------------------------------------------------------ transitions

func enter_palace() -> void:
	if state != S.REALITY:
		return
	var pl: KWPlayer = main.player
	state = S.TO_PALACE
	main.in_palace = false
	pl.enabled = false
	_store()
	_spawn_ghost(pl.global_position, pl.rotation.y, false)
	var cam0: Transform3D = pl.active_camera().global_transform
	pl.avatar.visible = false
	_show_bubble(Transform3D(Basis(Vector3.UP, _palace_yaw), _palace_pos + Vector3(0, 1.6, 0)))
	var b := _bubble_center()
	var end_pos := b + _flat_dir(cam0.origin - b) * _fit_dist()
	var tgt := Transform3D(Basis.looking_at(b - end_pos, Vector3.UP), end_pos)
	_start_fly(cam0)
	_set_bubble(0.0, 0.15, 0.0)
	_finish_cb = _finish_palace
	_tw = create_tween()
	_tw.tween_callback(func(): MeditationPose.sit(ghost, 0.6))
	_tw.parallel().tween_method(func(t: float): _set_bubble(t, lerpf(0.15, 1.0, t), 0.0), 0.0, 1.0, 0.6)
	_tw.tween_method(func(t: float):
		fly.global_transform = cam0.interpolate_with(tgt, t)
		_set_bubble(1.0, 1.0, smoothstep(0.55, 1.0, t)), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_callback(_finish_palace)


func exit_palace() -> void:
	if state != S.PALACE:
		return
	var pl: KWPlayer = main.player
	if main.build.active:
		main.build.toggle()
	main.build.cancel()
	main.close_panel()
	_palace_room = main.current_room
	_palace_pos = pl.global_position
	_palace_yaw = pl.rotation.y
	var eye: Transform3D = pl.cam.global_transform
	state = S.TO_REALITY
	main.in_palace = false
	pl.enabled = false
	_store()
	if ghost == null:
		_spawn_ghost(RealityWorld.ORIGIN + Vector3(0, 0.05, 3), 0.0, true)
	var gp := ghost.global_position
	var gy := ghost.rotation.y
	pl.teleport(gp, gy)
	pl.set_third_person(true, false)
	pl.avatar.visible = false
	reality.apply_env(main.env, true, _palace_env)
	_show_bubble(eye)
	var b := _bubble_center()
	var t_pos := gp + Basis(Vector3.UP, gy) * Vector3(0.45, 1.72, 2.3)
	var s_pos := b + _flat_dir(t_pos - b) * _fit_dist()
	var start := Transform3D(Basis.looking_at(b - s_pos, Vector3.UP), s_pos)
	var end := Transform3D(Basis.looking_at(gp + Vector3(0, 1.0, 0) - t_pos, Vector3.UP), t_pos)
	_start_fly(start)
	_set_bubble(1.0, 1.0, 1.0)
	_finish_cb = _finish_reality
	_tw = create_tween()
	_tw.tween_method(func(t: float):
		fly.global_transform = start.interpolate_with(end, t)
		_set_bubble(1.0, 1.0, 1.0 - smoothstep(0.0, 0.45, t)), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tw.tween_callback(func(): MeditationPose.stand(ghost, 0.5))
	_tw.parallel().tween_method(func(t: float): _set_bubble(1.0 - t, lerpf(1.0, 0.1, t), 0.0), 0.0, 1.0, 0.6)
	_tw.tween_callback(_finish_reality)


func _finish_palace() -> void:
	_hide_bubble()
	var pl: KWPlayer = main.player
	pl.teleport(_palace_pos, _palace_yaw)
	_enter_palace_state()


func _finish_reality() -> void:
	_hide_bubble()
	if ghost:
		ghost.queue_free()
		ghost = null
	_enter_reality_state()


## Passe la transition en cours (clic).
func skip() -> void:
	if state != S.TO_PALACE and state != S.TO_REALITY:
		return
	if _tw:
		_tw.kill()
	_finish_cb.call()


# ------------------------------------------------------------------ bulle / fantôme

func _spawn_ghost(pos: Vector3, yaw: float, seated: bool) -> void:
	if ghost:
		ghost.queue_free()
	ghost = KWAvatar.new()
	reality.add_child(ghost)
	ghost.global_position = pos
	ghost.rotation.y = yaw
	var cm = main.get_node_or_null("/root/Cosmetics")
	if cm:
		ghost.apply_look(cm.look())
	if seated:
		MeditationPose.sit(ghost, 0.0, true)


func _bubble_center() -> Vector3:
	return ghost.global_position + Vector3(0, BUBBLE_H, 0)


## Distance caméra → bulle pour que la bulle remplisse l'écran (recadrage vertical ~18 %).
func _fit_dist() -> float:
	return BUBBLE_SIZE.y * 0.5 * 0.82 / tan(deg_to_rad(fly.fov) * 0.5)


func _flat_dir(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized() if v.length() > 0.01 else Vector3.BACK


func _start_fly(from: Transform3D) -> void:
	fly.fov = main.player.cam.fov
	fly.global_transform = from
	fly.make_current()


func _show_bubble(eye: Transform3D) -> void:
	_vcam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(main.player.cam.fov) * 0.5) / 0.82))
	_vcam.global_transform = eye
	_bubble_root.global_position = ghost.global_position
	_bubble_root.visible = true
	_bubble_on = true
	_bubble_acc = 0.0
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _hide_bubble() -> void:
	_bubble_on = false
	_bubble_root.visible = false


func _set_bubble(a: float, sc: float, fill: float) -> void:
	_bmat.set_shader_parameter("alpha", a)
	_bmat.set_shader_parameter("s", sc)
	_bmat.set_shader_parameter("fill", fill)
	for i in _dots.size():
		var k := clampf(a * 1.6 - 0.2 * i, 0.0, 1.0) * (1.0 - fill)
		_dots[i].scale = Vector3.ONE * k + Vector3.ONE * 0.001


# ------------------------------------------------------------------ entrées / boucle

func _can_toggle() -> bool:
	return (state == S.REALITY or state == S.PALACE) and main.title == null and main.panel == null \
		and not main.chat.is_open and main.player.active()


func _moving() -> bool:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.1


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and (state == S.TO_PALACE or state == S.TO_REALITY):
		skip()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey) or event.echo:
		return
	if event.keycode == KEY_SHIFT:
		if event.pressed:
			_shift_down = true
			_shift_t0 = Time.get_ticks_msec()
			_shift_ok = _can_toggle() and not _moving()
		else:
			var ok := _shift_down and _shift_ok and Time.get_ticks_msec() - _shift_t0 < TAP_MS and not _moving()
			_shift_down = false
			if ok:
				toggle()
	elif event.pressed:
		_shift_ok = false


func _process(delta: float) -> void:
	if _shift_down and _moving():
		_shift_ok = false
	if _bubble_on:
		_bubble_acc += delta
		if _bubble_acc >= 1.0 / BUBBLE_FPS:
			_bubble_acc = 0.0
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_store_acc += delta
	if _store_acc > 1.0:
		_store_acc = 0.0
		if state == S.REALITY or state == S.PALACE:
			_store()
	# Filet de sécurité réalité : chute hors du sol.
	var pl: KWPlayer = main.player
	if state == S.REALITY and pl.global_position.y < -5.0 and not (pl.global_position.y > -520.0 and pl.global_position.y < -480.0):
		pl.teleport(RealityWorld.ORIGIN + Vector3(0, 0.05, 3), 0.0)


func _store() -> void:
	var r: Dictionary = World.data.get("reality", {})
	var pl: KWPlayer = main.player
	if state == S.PALACE:
		_palace_room = main.current_room
		_palace_pos = pl.global_position
		_palace_yaw = pl.rotation.y
	elif state == S.REALITY or state == S.TO_PALACE:
		r["pos"] = _arr(pl.global_position - RealityWorld.ORIGIN)
		r["yaw"] = pl.rotation.y
	r["palace_room"] = _palace_room
	r["palace_pos"] = _arr(_palace_pos)
	r["palace_yaw"] = _palace_yaw
	World.data["reality"] = r


static func _arr(v: Vector3) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001), snappedf(v.z, 0.001)]

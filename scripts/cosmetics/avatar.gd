class_name KWAvatar
extends Node3D
## Avatar stylisé « blocky » (BoxMesh) : tête, torse, bras, jambes + accessoires (tête, dos/cou).
## Animation procédurale (marche, arrêt, saut, accroupi, respiration) pilotée par les champs
## speed / on_floor / crouch / pitch, et emotes par Tween (wave, sit, dance, bow).
## Face vers -Z, pieds en y = 0, ~1,75 m.

const LEG_H := 0.66
const TORSO_H := 0.66
const HEAD := 0.44

var speed := 0.0      # vitesse horizontale (m/s)
var on_floor := true
var crouch := 0.0     # 0 debout → 1 accroupi
var pitch := 0.0      # inclinaison du regard (rad, + = vers le haut)
var shadow_only := false

var body_root: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var head_acc: Node3D
var back_acc: Node3D
var _hair: Array = []
var _phase := 0.0
var _t := 0.0
var _emote: Tween
var _emote_name := ""
var _halo: Node3D
var _wings: Array = []
var _scarf_tail: Node3D


func _init() -> void:
	body_root = _pivot(self, Vector3.ZERO)
	leg_l = _pivot(body_root, Vector3(-0.11, LEG_H, 0))
	leg_r = _pivot(body_root, Vector3(0.11, LEG_H, 0))
	torso = _pivot(body_root, Vector3(0, LEG_H, 0))
	head = _pivot(torso, Vector3(0, TORSO_H, 0))
	arm_l = _pivot(torso, Vector3(-0.33, TORSO_H - 0.04, 0))
	arm_r = _pivot(torso, Vector3(0.33, TORSO_H - 0.04, 0))
	head_acc = _pivot(head, Vector3.ZERO)
	back_acc = _pivot(torso, Vector3.ZERO)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


static func _mat(c: Color, emissive := 0.0, alpha := 1.0, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c, alpha)
	m.roughness = 0.85
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _clear(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D or c.has_meta("acc"):
			n.remove_child(c)
			c.queue_free()


## Reconstruit l'apparence : look = {skin: params, head: params, back: params} (voir Cosmetics.look()).
func apply_look(look: Dictionary) -> void:
	for n in [leg_l, leg_r, torso, head, arm_l, arm_r, head_acc, back_acc]:
		_clear(n)
	_hair.clear()
	_wings.clear()
	_halo = null
	_scarf_tail = null
	var s: Dictionary = look.get("skin", {})
	var skin := _mat(Color(s.get("skin", "#e2b894")))
	var shirt := _mat(Color(s.get("shirt", "#5b7cfa")))
	var pants := _mat(Color(s.get("pants", "#2e3440")))
	var shoes := _mat(Color(s.get("shoes", "#1d1f24")))
	var hair := _mat(Color(s.get("hair", "#4a3426")))
	var eye_col := Color(s.get("eyes", "#22252b"))
	var eyes := _mat(eye_col, 1.5 if s.has("glow") else 0.0)
	for leg in [leg_l, leg_r]:
		_box(leg, Vector3(0.21, 0.5, 0.22), Vector3(0, -0.25, 0), pants)
		_box(leg, Vector3(0.22, 0.16, 0.24), Vector3(0, -0.58, -0.01), shoes)
	_box(torso, Vector3(0.44, TORSO_H, 0.22), Vector3(0, TORSO_H / 2.0, 0), shirt)
	if s.has("glow"):
		_box(torso, Vector3(0.45, 0.04, 0.23), Vector3(0, 0.12, 0), _mat(Color(s.glow), 2.0))
	for arm in [arm_l, arm_r]:
		_box(arm, Vector3(0.2, 0.38, 0.2), Vector3(0, -0.15, 0), shirt)
		_box(arm, Vector3(0.19, 0.28, 0.19), Vector3(0, -0.48, 0), skin)
	_box(head, Vector3(HEAD, HEAD, HEAD), Vector3(0, HEAD / 2.0, 0), skin)
	_hair.append(_box(head, Vector3(0.46, 0.1, 0.46), Vector3(0, HEAD - 0.03, 0), hair))
	_hair.append(_box(head, Vector3(0.46, 0.28, 0.06), Vector3(0, 0.28, 0.205), hair))
	for x in [-0.1, 0.1]:
		_box(head, Vector3(0.07, 0.07, 0.02), Vector3(x, 0.21, -0.222), eyes)
	_build_head_acc(look.get("head", {}))
	_build_back_acc(look.get("back", {}))
	set_shadow_only(shadow_only)


func _acc_root(parent: Node3D) -> Node3D:
	var n := Node3D.new()
	n.set_meta("acc", true)
	parent.add_child(n)
	return n


func _build_head_acc(p: Dictionary) -> void:
	var col := Color(p.get("color", "#ffffff"))
	var r := _acc_root(head_acc)
	match str(p.get("model", "")):
		"beanie":
			_box(r, Vector3(0.48, 0.16, 0.48), Vector3(0, HEAD + 0.04, 0), _mat(col))
			_box(r, Vector3(0.49, 0.06, 0.49), Vector3(0, HEAD - 0.04, 0), _mat(col.darkened(0.2)))
			_box(r, Vector3(0.1, 0.1, 0.1), Vector3(0, HEAD + 0.17, 0), _mat(col.lightened(0.5)))
		"halo":
			var t := MeshInstance3D.new()
			var tm := TorusMesh.new()
			tm.inner_radius = 0.15
			tm.outer_radius = 0.19
			t.mesh = tm
			t.material_override = _mat(col, 3.0, 0.9, true)
			t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			t.position = Vector3(0, HEAD + 0.18, 0)
			r.add_child(t)
			_halo = t
		"helmet":
			for h in _hair:
				h.visible = false
			_box(r, Vector3(0.5, 0.5, 0.5), Vector3(0, HEAD / 2.0 + 0.02, 0), _mat(col))
			var vm := _mat(Color(p.get("visor", "#2b3a55")))
			vm.metallic = 0.8
			vm.roughness = 0.15
			_box(r, Vector3(0.42, 0.17, 0.02), Vector3(0, 0.22, -0.255), vm)
		"crown":
			var gold := _mat(col, 0.35)
			gold.metallic = 0.9
			gold.roughness = 0.3
			var y := HEAD + 0.05
			_box(r, Vector3(0.46, 0.08, 0.04), Vector3(0, y, -0.21), gold)
			_box(r, Vector3(0.46, 0.08, 0.04), Vector3(0, y, 0.21), gold)
			_box(r, Vector3(0.04, 0.08, 0.46), Vector3(-0.21, y, 0), gold)
			_box(r, Vector3(0.04, 0.08, 0.46), Vector3(0.21, y, 0), gold)
			for i in 3:
				var x := -0.15 + i * 0.15
				_box(r, Vector3(0.06, 0.1, 0.04), Vector3(x, y + 0.08, -0.21), gold)
				_box(r, Vector3(0.06, 0.1, 0.04), Vector3(x, y + 0.08, 0.21), gold)
			_box(r, Vector3(0.05, 0.05, 0.02), Vector3(0, y, -0.235), _mat(Color("#e0405a"), 1.0))


func _build_back_acc(p: Dictionary) -> void:
	var col := Color(p.get("color", "#ffffff"))
	var r := _acc_root(back_acc)
	match str(p.get("model", "")):
		"scarf":
			var m := _mat(col)
			var y := TORSO_H - 0.03
			_box(r, Vector3(0.5, 0.1, 0.07), Vector3(0, y, -0.14), m)
			_box(r, Vector3(0.5, 0.1, 0.07), Vector3(0, y, 0.14), m)
			_box(r, Vector3(0.07, 0.1, 0.3), Vector3(-0.24, y, 0), m)
			_box(r, Vector3(0.07, 0.1, 0.3), Vector3(0.24, y, 0), m)
			_scarf_tail = _pivot(r, Vector3(0.12, y - 0.03, 0.17))
			_box(_scarf_tail, Vector3(0.12, 0.34, 0.05), Vector3(0, -0.17, 0), _mat(col.darkened(0.1)))
		"wings":
			var wm := _mat(col, 1.2, 0.5, true)
			for side in [-1.0, 1.0]:
				var w := _pivot(r, Vector3(0.07 * side, TORSO_H - 0.16, 0.13))
				var a := _box(w, Vector3(0.55, 0.36, 0.02), Vector3(0.28 * side, 0.08, 0), wm)
				a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				var b := _box(w, Vector3(0.38, 0.22, 0.02), Vector3(0.24 * side, -0.18, 0.01), wm)
				b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				w.set_meta("side", side)
				_wings.append(w)


## Vue première personne : l'avatar ne projette plus que son ombre.
func set_shadow_only(on: bool) -> void:
	shadow_only = on
	_set_shadow(self, on)


func _set_shadow(n: Node, on: bool) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c.mesh is BoxMesh) and not (c.material_override is StandardMaterial3D and (c.material_override as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if on else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		elif c is MeshInstance3D:
			c.visible = not on
		_set_shadow(c, on)

# ------------------------------------------------------------------ animation

func _process(delta: float) -> void:
	_t += delta
	var move := clampf(speed / 3.0, 0.0, 1.6)
	if _emote_name != "" and (move > 0.2 or not on_floor or crouch > 0.3):
		stop_emote()
	# Accessoires vivants.
	if _halo:
		_halo.position.y = HEAD + 0.18 + sin(_t * 2.0) * 0.015
		_halo.rotation.y += delta * 0.6
	for w in _wings:
		var side: float = w.get_meta("side")
		w.rotation.y = side * (-0.35 - sin(_t * (1.6 + move * 2.0)) * 0.22)
	if _scarf_tail:
		_scarf_tail.rotation.x = lerpf(_scarf_tail.rotation.x, 0.15 + move * 0.5 + sin(_t * 5.0) * 0.06 * move, 1.0 - exp(-6.0 * delta))
	if _emote_name != "":
		return
	var k := 1.0 - exp(-12.0 * delta)
	var la := 0.0
	var ll := 0.0
	var bob := 0.0
	if not on_floor:
		la = 0.6
		ll = 0.35
	elif move > 0.05:
		_phase += delta * (4.0 + speed * 1.7)
		ll = sin(_phase) * 0.65 * minf(move, 1.2)
		la = -ll * 0.8
		bob = absf(cos(_phase)) * 0.035 * minf(move, 1.0)
	var breathe := sin(_t * 1.6) * 0.03
	var c := smoothstep(0.0, 1.0, crouch)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, ll, k)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, -ll if on_floor else -ll * 0.4, k)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, (la if on_floor else la) + breathe, k)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, (-la if on_floor else la) - breathe, k)
	arm_l.rotation.z = lerpf(arm_l.rotation.z, -0.05 - (0.35 if not on_floor else 0.0), k)
	arm_r.rotation.z = lerpf(arm_r.rotation.z, 0.05 + (0.35 if not on_floor else 0.0), k)
	# Accroupi : jambes tassées, buste penché en avant.
	var leg_s := 1.0 - 0.5 * c
	leg_l.scale.y = leg_s
	leg_r.scale.y = leg_s
	torso.position.y = LEG_H * leg_s + bob
	torso.rotation.x = lerpf(torso.rotation.x, -0.55 * c - move * 0.06, k)
	torso.rotation.z = 0.0
	body_root.position = body_root.position.lerp(Vector3.ZERO, k)
	body_root.rotation = Vector3.ZERO
	head.rotation.x = lerpf(head.rotation.x, clampf(pitch * 0.6, -0.6, 0.6) + 0.55 * c * 0.6, k)
	head.rotation.y = lerpf(head.rotation.y, 0.0, k)


func is_emoting() -> bool:
	return _emote_name != ""


func stop_emote() -> void:
	if _emote:
		_emote.kill()
	_emote = null
	_emote_name = ""


## Joue une emote : "wave", "sit", "dance", "bow". Interrompue dès que le joueur bouge.
func play_emote(anim: String) -> void:
	stop_emote()
	_reset_pose()
	_emote_name = anim
	var tw := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_emote = tw
	match anim:
		"wave":
			tw.tween_property(arm_r, "rotation", Vector3(0, 0, 2.7), 0.35)
			for i in 3:
				tw.tween_property(arm_r, "rotation:z", 2.3, 0.22)
				tw.tween_property(arm_r, "rotation:z", 2.8, 0.22)
			tw.tween_property(arm_r, "rotation", Vector3.ZERO, 0.35)
		"sit":
			tw.set_parallel()
			tw.tween_property(body_root, "position:y", -(LEG_H - 0.12), 0.6)
			tw.tween_property(leg_l, "rotation:x", 1.5, 0.6)
			tw.tween_property(leg_r, "rotation:x", 1.45, 0.6)
			tw.tween_property(arm_l, "rotation:x", 0.7, 0.6)
			tw.tween_property(arm_r, "rotation:x", 0.7, 0.6)
			tw.tween_property(head, "rotation:x", 0.15, 0.6)
			tw.chain().tween_interval(9999.0) # reste assis jusqu'au prochain mouvement
		"dance":
			for i in 4:
				var s := 1.0 if i % 2 == 0 else -1.0
				tw.set_parallel()
				tw.tween_property(body_root, "rotation:z", 0.1 * s, 0.75)
				tw.tween_property(body_root, "rotation:y", 0.35 * s, 0.75)
				tw.tween_property(arm_l, "rotation:z", -1.2 - 0.5 * s, 0.75)
				tw.tween_property(arm_r, "rotation:z", 1.2 - 0.5 * s, 0.75)
				tw.tween_property(head, "rotation:y", -0.25 * s, 0.75)
				tw.tween_property(leg_l, "rotation:x", 0.15 * s, 0.75)
				tw.tween_property(leg_r, "rotation:x", -0.15 * s, 0.75)
				tw.set_parallel(false)
				tw.tween_interval(0.0)
			tw.set_parallel()
			tw.tween_property(body_root, "rotation", Vector3.ZERO, 0.5)
			tw.tween_property(arm_l, "rotation:z", 0.0, 0.5)
			tw.tween_property(arm_r, "rotation:z", 0.0, 0.5)
			tw.tween_property(head, "rotation:y", 0.0, 0.5)
		"bow":
			tw.set_parallel()
			tw.tween_property(torso, "rotation:x", -0.8, 0.6)
			tw.tween_property(arm_r, "rotation:x", 0.9, 0.6)
			tw.tween_property(arm_l, "rotation:z", -0.5, 0.6)
			tw.chain().tween_interval(0.8)
			tw.chain().tween_property(torso, "rotation:x", 0.0, 0.6)
			tw.parallel().tween_property(arm_r, "rotation:x", 0.0, 0.6)
			tw.parallel().tween_property(arm_l, "rotation:z", 0.0, 0.6)
	tw.finished.connect(func():
		if _emote == tw:
			_emote = null
			_emote_name = "")


func _reset_pose() -> void:
	for n in [leg_l, leg_r, arm_l, arm_r, torso, head, body_root]:
		n.rotation = Vector3.ZERO
	leg_l.scale = Vector3.ONE
	leg_r.scale = Vector3.ONE
	body_root.position = Vector3.ZERO
	torso.position.y = LEG_H

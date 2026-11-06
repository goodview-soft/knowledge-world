class_name KWPlayer
extends CharacterBody3D
## Joueur à la première personne : ZQSD (touches physiques), souris, RayCast3D d'interaction,
## saut (Espace), accroupi (Ctrl gauche maintenu seul, ou C en bascule), petites marches,
## léger balancement de tête (KWSettings "head_bob").

const SPEED := 3.0
const SPRINT := 5.5
const CROUCH_SPEED := 1.4
const JUMP_VELOCITY := 3.7 # ≈ 0,7 m
const GRAVITY := 9.8
const STAND_H := 1.75
const CROUCH_H := 1.1
const EYE_STAND := 1.6
const EYE_CROUCH := 1.0
const STEP_H := 0.25 # marche franchie sans sauter (estrade 20 cm)
const RADIUS := 0.32
const BASE_SENSITIVITY := 0.0022
var sensitivity := 0.0022
var speed_mult := 1.0
var invert_y := false
var head_bob := true
var enabled := true
var force_active := false # tests headless
var head: Node3D
var cam: Camera3D
var ray: RayCast3D
var shape: CollisionShape3D
var capsule: CapsuleShape3D
var up_cast: ShapeCast3D
## État accroupi : bascule (C) ; is_crouched reflète l'état réel (y compris bloqué sous un obstacle).
var crouch_toggled := false
var is_crouched := false
var _crouch_t := 0.0 # 0 debout → 1 accroupi
var _ctrl_held := 0.0
var _ctrl_combo := false # Ctrl utilisé pour un raccourci (Ctrl+S, Ctrl+D…) : pas d'accroupi
var _jump_buffer := 0.0
var _coyote := 0.0
var _bob := 0.0
var _bob_amp := 0.0
var _step_offset := 0.0


func _init() -> void:
	collision_layer = 4
	collision_mask = 3
	shape = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = STAND_H
	shape.shape = capsule
	shape.position.y = STAND_H / 2.0
	add_child(shape)
	up_cast = ShapeCast3D.new()
	var sph := SphereShape3D.new()
	sph.radius = RADIUS - 0.04
	up_cast.shape = sph
	up_cast.position.y = CROUCH_H - RADIUS
	up_cast.target_position = Vector3(0, STAND_H - CROUCH_H + 0.04, 0)
	up_cast.collision_mask = 3
	up_cast.enabled = false
	add_child(up_cast)
	head = Node3D.new()
	head.position.y = EYE_STAND
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 72
	cam.near = 0.05
	head.add_child(cam)
	ray = RayCast3D.new()
	ray.collision_mask = 11 # murs, objets, passages (portes/portails)
	cam.add_child(ray)
	set_reach(3.5)
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50)


func _ready() -> void:
	_setup_actions()


## Actions créées en code (touches physiques : même position en AZERTY / QWERTY).
static func _setup_actions() -> void:
	var defs := {"jump": [KEY_SPACE], "crouch": [KEY_CTRL], "crouch_toggle": [KEY_C]}
	for a in defs:
		if InputMap.has_action(a):
			continue
		InputMap.add_action(a)
		for k in defs[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			if k == KEY_CTRL:
				ev.location = KEY_LOCATION_LEFT
			InputMap.action_add_event(a, ev)


## Applique les paramètres globaux (KWSettings).
func apply_settings() -> void:
	sensitivity = BASE_SENSITIVITY * float(KWSettings.get_value("sensitivity"))
	speed_mult = float(KWSettings.get_value("speed"))
	invert_y = bool(KWSettings.get_value("invert_y"))
	head_bob = bool(KWSettings.get_value("head_bob"))
	cam.fov = float(KWSettings.get_value("fov"))


func active() -> bool:
	return enabled and (force_active or OS.has_feature("mobile") or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


func set_reach(r: float) -> void:
	ray.target_position = Vector3(0, 0, -r)


func teleport(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	_step_offset = 0.0


## Demande de saut (tampon court : appui juste avant d'atterrir accepté).
func request_jump() -> void:
	_jump_buffer = 0.15


## Peut-on se relever ? (rien au-dessus de la tête jusqu'à la hauteur debout)
func can_stand() -> bool:
	up_cast.force_shapecast_update()
	return not up_cast.is_colliding()


func _input(event: InputEvent) -> void:
	# Ctrl seul = accroupi ; Ctrl + une touche = raccourci (Ctrl+S, Ctrl+D…) qui annule l'accroupi.
	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode != KEY_CTRL:
		if _ctrl_held < 0.15 or event.keycode in [KEY_S, KEY_D]:
			_ctrl_combo = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and active():
		rotate_y(-event.relative.x * sensitivity)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sensitivity * (-1.0 if invert_y else 1.0), -1.45, 1.45)
	elif event is InputEventKey and event.pressed and not event.echo and active() and not event.ctrl_pressed:
		if event.is_action("jump"):
			request_jump()
		elif event.is_action("crouch_toggle"):
			crouch_toggled = not crouch_toggled


func _physics_process(delta: float) -> void:
	var act := active()
	# --- accroupi
	var ctrl := act and Input.is_action_pressed("crouch")
	if ctrl:
		_ctrl_held += delta
	else:
		_ctrl_held = 0.0
		_ctrl_combo = false
	var want := crouch_toggled or (ctrl and not _ctrl_combo and _ctrl_held >= 0.12)
	if not want and _crouch_t > 0.0 and not can_stand():
		want = true
	is_crouched = want
	_crouch_t = move_toward(_crouch_t, 1.0 if want else 0.0, delta / 0.18)
	var e := smoothstep(0.0, 1.0, _crouch_t)
	capsule.height = lerpf(STAND_H, CROUCH_H, e)
	shape.position.y = capsule.height / 2.0
	# --- déplacement
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if act else Vector2.ZERO
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var spd := SPRINT if (Input.is_action_pressed("sprint") and not want) else SPEED
	spd = lerpf(spd, CROUCH_SPEED, e)
	var target := dir * spd * speed_mult
	var on_floor := is_on_floor()
	var k := 1.0 - exp(-(10.0 if on_floor else 2.0) * delta) # contrôle en l'air réduit
	velocity.x = lerpf(velocity.x, target.x, k)
	velocity.z = lerpf(velocity.z, target.z, k)
	_coyote = 0.1 if on_floor else maxf(_coyote - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if _jump_buffer > 0.0 and _coyote > 0.0 and not want:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0 # pas de double saut
	elif on_floor:
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta
	if on_floor and velocity.y <= 0.0:
		_try_step(delta)
	move_and_slide()
	# --- caméra : hauteur des yeux, marche lissée, balancement
	_step_offset = move_toward(_step_offset, 0.0, delta * 1.5)
	head.position.y = lerpf(EYE_STAND, EYE_CROUCH, e) + _step_offset
	var hs := Vector2(velocity.x, velocity.z).length()
	var moving := head_bob and is_on_floor() and hs > 0.4
	_bob_amp = move_toward(_bob_amp, clampf(hs / SPEED, 0.0, 1.4) if moving else 0.0, delta * 3.0)
	if _bob_amp > 0.0:
		_bob += delta * (5.0 + hs * 1.6)
	cam.position = Vector3(cos(_bob) * 0.008, absf(sin(_bob)) * 0.022 - 0.011, 0) * _bob_amp


## Petites marches (estrade) : si on bute devant mais que la voie est libre STEP_H plus haut, on monte.
func _try_step(delta: float) -> void:
	var horiz := Vector3(velocity.x, 0, velocity.z) * delta
	if horiz.length() < 0.001:
		return
	var probe := horiz.normalized() * maxf(horiz.length(), 0.05)
	if not test_move(global_transform, probe):
		return
	var up := Vector3(0, STEP_H, 0)
	if test_move(global_transform, up):
		return
	var raised := global_transform.translated(up)
	if test_move(raised, probe):
		return
	var col := KinematicCollision3D.new()
	var moved := raised.translated(probe)
	if test_move(moved, Vector3(0, -STEP_H, 0), col):
		var dy: float = STEP_H - col.get_travel().length()
		if dy > 0.02 and dy <= STEP_H and col.get_normal().y > 0.7:
			global_position.y += dy + 0.01
			_step_offset -= dy

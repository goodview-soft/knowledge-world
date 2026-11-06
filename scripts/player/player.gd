class_name KWPlayer
extends CharacterBody3D
## Joueur à la première personne : ZQSD (touches physiques), souris, RayCast3D d'interaction.

const SPEED := 3.0
const SPRINT := 5.5
var sensitivity := 0.0022
var enabled := true
var force_active := false # tests headless
var head: Node3D
var cam: Camera3D
var ray: RayCast3D


func _init() -> void:
	collision_layer = 4
	collision_mask = 3
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.75
	cs.shape = cap
	cs.position.y = 0.875
	add_child(cs)
	head = Node3D.new()
	head.position.y = 1.6
	add_child(head)
	cam = Camera3D.new()
	cam.fov = 72
	cam.near = 0.05
	head.add_child(cam)
	ray = RayCast3D.new()
	ray.collision_mask = 3
	cam.add_child(ray)
	set_reach(3.5)


func active() -> bool:
	return enabled and (force_active or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


func set_reach(r: float) -> void:
	ray.target_position = Vector3(0, 0, -r)


func teleport(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0, yaw, 0)
	head.rotation = Vector3.ZERO
	velocity = Vector3.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and active():
		rotate_y(-event.relative.x * sensitivity)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * sensitivity, -1.45, 1.45)


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if active() else Vector2.ZERO
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var target := dir * (SPRINT if Input.is_action_pressed("sprint") else SPEED)
	var k := 1.0 - exp(-10.0 * delta)
	velocity.x = lerpf(velocity.x, target.x, k)
	velocity.z = lerpf(velocity.z, target.z, k)
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()

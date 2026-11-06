class_name HingedDoor
extends Node3D
## Vraie porte : battant 3D pivotant sur une charnière (montant gauche), dans un encadrement.
## Origine = centre bas de l'ouverture, +Z = côté d'où l'on ouvre ; le battant s'ouvre vers -Z.

const OPEN_ANGLE := deg_to_rad(95.0)
const OPEN_TIME := 0.6

static var _snd_open: AudioStreamWAV
static var _snd_shut: AudioStreamWAV

var width := 0.9
var height := 2.1
var thick := 0.06
var auto_close := 5.0          # 0 = reste ouverte
var angle := 0.0 : set = _set_angle
var is_open := false           # état voulu (l'animation peut être en cours)
var pivot: Node3D
var silent := false
var _tw: Tween
var _left := 0.0
var _player: AudioStreamPlayer3D


func setup(w: float, h: float, t: float, leaf_col: Color, frame_col: Color, frame_depth := 0.2) -> HingedDoor:
	width = w
	height = h
	thick = t
	var fm := StandardMaterial3D.new()
	fm.albedo_color = frame_col
	var lm := StandardMaterial3D.new()
	lm.albedo_color = leaf_col
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color(0.8, 0.7, 0.3)
	hm.metallic = 0.8
	for sx in [-1.0, 1.0]:
		_add(Vector3(0.08, h + 0.1, frame_depth), Vector3(sx * (w * 0.5 + 0.04), (h + 0.1) * 0.5, 0), fm, self)
	_add(Vector3(w + 0.16, 0.1, frame_depth), Vector3(0, h + 0.05, 0), fm, self)
	pivot = Node3D.new()
	pivot.position = Vector3(-w * 0.5, 0, 0)
	add_child(pivot)
	_add(Vector3(w, h, t), Vector3(w * 0.5, h * 0.5, 0), lm, pivot)
	for sz in [-1.0, 1.0]: # poignée des deux côtés
		_add(Vector3(0.12, 0.04, 0.05), Vector3(w - 0.12, h * 0.48, sz * (t * 0.5 + 0.025)), hm, pivot)
	_player = AudioStreamPlayer3D.new()
	_player.max_distance = 18.0
	_player.unit_size = 4.0
	_player.volume_db = -14.0
	add_child(_player)
	return self


func _add(sz: Vector3, pos: Vector3, mat: Material, parent: Node3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _set_angle(a: float) -> void:
	angle = a
	if pivot != null:
		pivot.rotation.y = a


func openness() -> float:
	return angle / OPEN_ANGLE


func swing(open: bool, instant := false) -> void:
	if open == is_open and not instant:
		return
	is_open = open
	if _tw != null:
		_tw.kill()
		_tw = null
	_left = auto_close if open else 0.0
	if instant:
		angle = OPEN_ANGLE if open else 0.0
		return
	_play(open)
	_tw = create_tween()
	_tw.tween_property(self, "angle", OPEN_ANGLE if open else 0.0, OPEN_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func toggle() -> void:
	swing(not is_open)


## Se referme dans `sec` secondes (le joueur vient de passer).
func close_in(sec: float) -> void:
	_left = sec


func is_closed() -> bool:
	return not is_open and angle < 0.01


func _process(dt: float) -> void:
	if is_open and auto_close > 0.0 and _left > 0.0 and (_tw == null or not _tw.is_running()):
		_left -= dt
		if _left <= 0.0:
			swing(false)


func _play(open: bool) -> void:
	if silent or _player == null or not is_inside_tree():
		return
	if _snd_open == null:
		_snd_open = _make_snd(true)
		_snd_shut = _make_snd(false)
	_player.stream = _snd_open if open else _snd_shut
	_player.play()


## Clenche + léger grincement, procéduraux.
static func _make_snd(open: bool) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.55)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if open else 9
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var s := 0.0
		var click_t := 0.0 if open else 0.42
		var dt := t - click_t
		if dt >= 0.0 and dt < 0.04:
			s += (rng.randf() * 2.0 - 1.0) * exp(-dt * 120.0) * 0.8
		var env := sin(clampf(t / 0.5, 0.0, 1.0) * PI) * 0.12
		ph += TAU * (160.0 + 60.0 * sin(t * 9.0) + t * 40.0) / rate
		s += sin(ph) * env * (1.0 if open else 0.5) * (0.6 + 0.4 * rng.randf())
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

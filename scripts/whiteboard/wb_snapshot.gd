class_name WBSnapshot
extends SubViewport
## Rend une fois des éléments dans une SubViewport puis livre l'Image (après 2 frames dessinées).
## on_ready(tex: ViewportTexture) permet d'afficher la texture vivante en attendant.

var on_done: Callable
var on_ready: Callable
var _frames := 0


static func make(elements: Array, region: Rect2, px: Vector2i, done: Callable) -> WBSnapshot:
	var s := WBSnapshot.new()
	s.size = px
	s.disable_3d = true
	s.transparent_bg = false
	s.render_target_update_mode = SubViewport.UPDATE_ONCE
	var v := WBView.new()
	v.elements = elements
	v.region = region
	v.size = Vector2(px)
	s.add_child(v)
	s.on_done = done
	return s


func _ready() -> void:
	if on_ready.is_valid():
		on_ready.call(get_texture())
	RenderingServer.frame_post_draw.connect(_tick)


func _tick() -> void:
	_frames += 1
	if _frames < 2:
		return
	RenderingServer.frame_post_draw.disconnect(_tick)
	var img := get_texture().get_image()
	if img == null or img.is_empty():
		return  # on garde la texture vivante
	if on_done.is_valid():
		on_done.call(img)
	queue_free()

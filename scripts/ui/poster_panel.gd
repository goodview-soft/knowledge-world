class_name PosterPanel
extends KWPanel
## Choix de l'image d'un poster : copiée dans user://images/ (le monde reste autonome).
## Le format de l'objet suit le ratio de l'image.

var id: String
var name_edit: LineEdit
var frame_chk: CheckBox
var preview: TextureRect


func _init(obj_id: String) -> void:
	id = obj_id
	var o: Dictionary = World.data.objects[id]
	super("Poster", Vector2(720, 620))
	name_edit = line(body, o.name, "Titre")
	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.texture = PosterView.texture_for(str(o.content.get("image", "")))
	body.add_child(preview)
	var row := hbox(body)
	primary(row, "Choisir une image…", _pick)
	frame_chk = CheckBox.new()
	frame_chk.text = "Cadre"
	frame_chk.button_pressed = o.content.get("frame", true)
	frame_chk.toggled.connect(func(_b): _save())
	row.add_child(frame_chk)
	spacer(row)
	danger(row, "Supprimer", func(): World.delete_object(id); closed.emit())
	dim(body, "Astuce : en mode construction, PgUp/PgDn change la taille.")


func _pick() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	fd.file_selected.connect(set_image)
	add_child(fd)
	fd.popup_centered(Vector2i(900, 600))


func set_image(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		main.hud.toast("Image illisible.")
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://images"))
	var dest := "user://images/%s.%s" % [id, path.get_extension().to_lower()]
	DirAccess.copy_absolute(path, ProjectSettings.globalize_path(dest))
	PosterView._cache.erase(dest)
	var o: Dictionary = World.data.objects[id]
	var c: Dictionary = o.content.duplicate()
	c.image = dest
	# Ratio de l'image : hauteur conservée, largeur adaptée.
	var base: Vector3 = ObjectRegistry.get_def("poster").size
	var scl := World.vec(o.scale)
	var aspect := float(img.get_width()) / maxf(1.0, img.get_height())
	scl.x = scl.y * aspect * base.y / base.x
	World.update_object(id, {"content": c, "scale": scl})
	preview.texture = PosterView.texture_for(dest)
	if name_edit.text == "Poster (image)":
		name_edit.text = path.get_file().get_basename()
	_save()


func _save() -> void:
	if not World.data.objects.has(id):
		return
	var c: Dictionary = World.data.objects[id].content.duplicate()
	c.frame = frame_chk.button_pressed
	World.update_object(id, {"name": name_edit.text, "content": c})


func on_close() -> void:
	_save()

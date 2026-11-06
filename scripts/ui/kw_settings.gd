class_name KWSettings
extends RefCounted
## Paramètres utilisateur globaux (hors monde) : user://settings.json.
## En test (--kw-save=…), un fichier voisin de la sauvegarde de test est utilisé.

const DEFAULTS := {"sensitivity": 1.0, "fov": 72.0, "speed": 1.0, "invert_y": false, "ui_scale": 1.0,
	"head_bob": true, "hotbar": ["note", "postit", "card", "whiteboard", "kanban", "desk", "library", "table", "lamp", "door"]}
static var data := {}
static var path := "user://settings.json"


static func load_settings() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kw-save="):
			path = a.substr(10).get_base_dir().path_join("settings_test.json")
	data = DEFAULTS.duplicate(true)
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			for k in DEFAULTS:
				if parsed.has(k) and typeof(parsed[k]) == typeof(DEFAULTS[k]):
					data[k] = parsed[k]
				elif parsed.has(k) and DEFAULTS[k] is float and parsed[k] is int:
					data[k] = float(parsed[k])


static func save_settings() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


static func get_value(key: String):
	if data.is_empty():
		load_settings()
	return data.get(key, DEFAULTS.get(key))


static func set_value(key: String, value) -> void:
	if data.is_empty():
		load_settings()
	data[key] = value

extends Node
## UPDATER (premier autoload) — mises à jour légères depuis les releases GitHub.
## Au démarrage (_init, AVANT les autres autoloads) : charge user://update.pck s'il est
## plus récent que la version intégrée, pour que tous les scripts mis à jour s'appliquent.
## check() lit version.json de la dernière release ; download() récupère le .pck
## (même moteur requis, SHA-256 vérifié) ; sinon on ouvre la page de téléchargement.

signal status(text: String, action: String) # action : "" | "update" | "download" | "restart"

const REPO := "goodview-soft/knowledge-world"
const UPDATE_URL := "https://github.com/" + REPO + "/releases/latest/download/version.json"
const RELEASES_URL := "https://github.com/" + REPO + "/releases/latest"
const PCK := "user://update.pck"
const CFG := "user://update.cfg"

var version: String = preload("res://version.gd").VERSION
var info := {}
var _http: HTTPRequest


func _init() -> void:
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(PCK) and cfg.load(CFG) == OK:
		var v: String = cfg.get_value("update", "version", "0")
		if newer(v, version) and ProjectSettings.load_resource_pack(PCK):
			version = v
			print("Mise à jour chargée : ", v)
		else:
			DirAccess.remove_absolute(PCK) # obsolète (programme plus récent) ou illisible


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 20
	add_child(_http)


static func newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := pa[i].to_int() if i < pa.size() else 0
		var y := pb[i].to_int() if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func check() -> void:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	status.emit("Recherche de mises à jour…", "")
	_http.request_completed.connect(_on_version, CONNECT_ONE_SHOT)
	_http.request(UPDATE_URL)


func _on_version(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status.emit("À jour" if code == 404 else "Hors ligne", "")
		return
	var j = JSON.parse_string(body.get_string_from_utf8())
	if not j is Dictionary or not j.has("version") or not newer(str(j.version), version):
		status.emit("À jour (v%s)" % version, "")
		return
	info = j
	var vi := Engine.get_version_info()
	var same_engine: bool = str(j.get("godot", "")) == "%d.%d.%d" % [vi.major, vi.minor, vi.patch]
	if same_engine and j.has("pck"):
		status.emit("v%s disponible" % j.version, "update")
	else:
		status.emit("v%s disponible (nouveau programme)" % j.version, "download")


func download() -> void:
	if info.is_empty():
		return
	status.emit("Téléchargement…", "")
	_http.download_file = "user://update.tmp"
	_http.request_completed.connect(_on_pck, CONNECT_ONE_SHOT)
	_http.request(str(info.pck))


func _on_pck(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_http.download_file = ""
	var tmp := "user://update.tmp"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or FileAccess.get_sha256(tmp) != str(info.get("sha256", "")):
		DirAccess.remove_absolute(tmp)
		status.emit("Échec du téléchargement, réessayer.", "update")
		return
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PCK))
	var c := ConfigFile.new()
	c.set_value("update", "version", str(info.version))
	c.save(CFG)
	status.emit("v%s installée — redémarrer pour l'appliquer" % info.version, "restart")


func open_releases() -> void:
	OS.shell_open(RELEASES_URL)


func restart() -> void:
	World.save_world()
	OS.set_restart_on_exit(true)
	get_tree().quit()

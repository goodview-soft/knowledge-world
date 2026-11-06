extends Node
## COSMETICS (autoload) — catalogue, droits d'usage (EntitlementProvider), équipement et tenues.
## Persistance : user://cosmetics.json (en test : <sauvegarde de test>.cosmetics.json).
## Touche K : ouvre / ferme le casier (LockerPanel). Purement cosmétique, aucun avantage en jeu.

signal changed ## l'équipement (ou les réglages d'aura) a changé
signal entitlements_changed

const SLOTS := ["skin", "head", "back", "aura", "trail", "portal", "emote"]
const MAX_PRESETS := 8

var catalog: CosmeticCatalog
var provider: EntitlementProvider
var equipped := {}      # slot -> item id ("" = rien)
var aura_density := 1.0 # réglage libre de l'aura (0.3 – 2.0)
var aura_tint := ""     # "" = couleurs de l'item, sinon "#rrggbb"
var presets := []       # [{name, equip{}, aura_density, aura_tint}]
var granted := []       # ids accordés localement (voir LocalEntitlements)
var path := "user://cosmetics.json"


func _ready() -> void:
	var test := KWSettings.test_save_path()
	if test != "":
		path = test + ".cosmetics.json"
	catalog = CosmeticCatalog.new().load_all()
	load_state()
	provider = _make_provider()
	provider.entitlements_changed.connect(func():
		_validate()
		entitlements_changed.emit()
		changed.emit())
	_validate()


## Point de branchement d'un futur backend boutique (StoreEntitlements, Steam, itch, serveur…).
func _make_provider() -> EntitlementProvider:
	var p := LocalEntitlements.new()
	p.granted = granted
	return p.setup(catalog)


func owns(id: String) -> bool:
	return provider.owns(id)


func get_equipped(slot: String) -> String:
	return equipped.get(slot, "")


func item(id: String) -> Dictionary:
	return catalog.get_item(id)


## Paramètres visuels de l'item équipé dans un emplacement ({} si rien).
func params_of(slot: String) -> Dictionary:
	var it := catalog.get_item(get_equipped(slot))
	return it.get("params", {})


## Équipe un item possédé. Renvoie false si verrouillé ou inconnu.
func equip(id: String) -> bool:
	var it := catalog.get_item(id)
	if it.is_empty() or not owns(id):
		return false
	equipped[it.category] = id
	_commit()
	return true


## Retire l'item d'un emplacement (les emplacements obligatoires reviennent au défaut).
func unequip(slot: String) -> void:
	var c := catalog.category(slot)
	equipped[slot] = "" if c.get("optional", false) else str(catalog.defaults.get(slot, ""))
	_commit()


func set_aura_tuning(density: float, tint: String) -> void:
	aura_density = clampf(density, 0.3, 2.0)
	aura_tint = tint
	_commit()


## Apparence de l'avatar pour un équipement donné (par défaut : l'équipement courant).
func look(equip_override := {}) -> Dictionary:
	var src := equipped.duplicate()
	src.merge(equip_override, true)
	var out := {}
	for s in ["skin", "head", "back"]:
		var it := catalog.get_item(str(src.get(s, "")))
		out[s] = it.get("params", {})
	return out

# ------------------------------------------------------------------ tenues (presets)

func save_preset(preset_name: String) -> void:
	preset_name = preset_name.strip_edges()
	if preset_name == "":
		preset_name = "Tenue %d" % (presets.size() + 1)
	var p := {"name": preset_name, "equip": equipped.duplicate(), "aura_density": aura_density, "aura_tint": aura_tint}
	for i in presets.size():
		if presets[i].name == preset_name:
			presets[i] = p
			_commit()
			return
	if presets.size() >= MAX_PRESETS:
		presets.pop_front()
	presets.append(p)
	_commit()


## Applique une tenue ; les items qui ne sont plus possédés sont ignorés.
func apply_preset(i: int) -> void:
	if i < 0 or i >= presets.size():
		return
	var p: Dictionary = presets[i]
	for slot in p.get("equip", {}):
		var id: String = p.equip[slot]
		if id == "" or owns(id):
			equipped[slot] = id
	aura_density = float(p.get("aura_density", 1.0))
	aura_tint = str(p.get("aura_tint", ""))
	_validate()
	_commit()


func delete_preset(i: int) -> void:
	if i >= 0 and i < presets.size():
		presets.remove_at(i)
		_commit()

# ------------------------------------------------------------------ persistance

func load_state() -> void:
	equipped = catalog.defaults.duplicate()
	if not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	var d: Dictionary = parsed
	var eq: Dictionary = d.get("equipped", {})
	for s in SLOTS:
		if eq.has(s) and eq[s] is String:
			equipped[s] = eq[s]
	aura_density = float(d.get("aura_density", 1.0))
	aura_tint = str(d.get("aura_tint", ""))
	var pr = d.get("presets", [])
	presets = pr if pr is Array else []
	var gr = d.get("granted", [])
	granted = gr if gr is Array else []


func save_state() -> void:
	var d := {"version": 1, "equipped": equipped, "aura_density": aura_density, "aura_tint": aura_tint,
		"presets": presets, "granted": granted}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	DirAccess.rename_absolute(tmp, path)


## Tout item non possédé ou inconnu revient au défaut de son emplacement.
func _validate() -> void:
	for s in SLOTS:
		var id: String = equipped.get(s, "")
		if id == "" and catalog.category(s).get("optional", false):
			continue
		var it := catalog.get_item(id)
		if it.is_empty() or it.category != s or (provider != null and not provider.owns(id)):
			equipped[s] = str(catalog.defaults.get(s, ""))


func _commit() -> void:
	save_state()
	changed.emit()

# ------------------------------------------------------------------ touche K

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_K):
		return
	if event.ctrl_pressed or event.alt_pressed:
		return
	var m := get_tree().current_scene
	if m == null or not ("panel" in m) or not m.has_method("open_panel"):
		return
	if m.panel is LockerPanel:
		m.close_panel()
	elif m.panel == null:
		m.open_panel(LockerPanel.new())
	else:
		return
	get_viewport().set_input_as_handled()
